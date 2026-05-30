const std = @import("std");

const Compiler = @import("compiler.zig");
const Scanner = @import("scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const Chunk = inst.Chunk;
const value = @import("value.zig");
const build_options = @import("build_options");
const Heap = @import("heap.zig");

const inst = @import("inst.zig");

const Parser = @This();

// Parser method which consumes tokens and
// emits data and opcodes. the bool argument is
// true until a binary or unary expression is encountered.
// this information is passed forward through the parser
// to determine whether an equals token `=` should be
// considered invalid or an assignment operator.
const ParseFn = *const fn (*Parser, bool) anyerror!void;

const Entry = @Tuple(&.{ TokenType, ?ParseFn, ?ParseFn, Precedence });

fn makeRuleTable(comptime N: usize, comptime entries: []Entry) [N]ParseRule {
    var ret: [N]ParseRule = undefined;
    for (entries) |entry| {
        const n = @intFromEnum(entry[0]);
        ret[n].prefix = entry[1];
        ret[n].infix = entry[2];
        ret[n].precedence = entry[3];
    }
    return ret;
}

fn ruleEntry(
    comptime typ: TokenType,
    comptime prefix: ?ParseFn,
    comptime infix: ?ParseFn,
    comptime prec: Precedence,
) Entry {
    return .{ typ, prefix, infix, prec };
}

const maxRuleSize = std.math.maxInt(@typeInfo(TokenType).@"enum".tag_type);

// TABLE
const ents = [_]Entry{
    ruleEntry(.LeftParen, grouping, call, .Call),
    ruleEntry(.RightParen, null, null, .None),
    ruleEntry(.LeftBrace, null, null, .None),
    ruleEntry(.RightBrace, null, null, .None),
    ruleEntry(.Comma, null, null, .None),
    ruleEntry(.Dot, null, null, .None),
    ruleEntry(.Minus, unary, binary, .Term),
    ruleEntry(.Plus, null, binary, .Term),
    ruleEntry(.Semicolon, null, null, .None),
    ruleEntry(.Slash, null, binary, .Factor),
    ruleEntry(.Star, null, binary, .Factor),
    ruleEntry(.Bang, unary, null, .None),
    ruleEntry(.BangEqual, null, binary, .Equality),
    ruleEntry(.Equal, null, null, .None),
    ruleEntry(.DoubleEqual, null, binary, .Equality),
    ruleEntry(.Greater, null, binary, .Comparison),
    ruleEntry(.GreaterEqual, null, binary, .Comparison),
    ruleEntry(.Less, null, binary, .Comparison),
    ruleEntry(.LessEqual, null, binary, .Comparison),
    ruleEntry(.Ident, variable, null, .None),
    ruleEntry(.String, string, null, .None),
    ruleEntry(.Number, number, null, .None),
    ruleEntry(.And, null, and_, .And),
    ruleEntry(.Class, null, null, .None),
    ruleEntry(.Else, null, null, .None),
    ruleEntry(.False, literal, null, .None),
    ruleEntry(.For, null, null, .None),
    ruleEntry(.Fun, null, null, .None),
    ruleEntry(.If, null, null, .None),
    ruleEntry(.Nil, literal, null, .None),
    ruleEntry(.Or, null, or_, .Or),
    ruleEntry(.Print, null, null, .None),
    ruleEntry(.Return, null, null, .None),
    ruleEntry(.Super, null, null, .None),
    ruleEntry(.This, null, null, .None),
    ruleEntry(.True, literal, null, .None),
    ruleEntry(.Var, null, null, .None),
    ruleEntry(.While, null, null, .None),
    ruleEntry(.Error, null, null, .None),
    ruleEntry(.Eof, null, null, .None),
};

const parseRules: [maxRuleSize]ParseRule =
    makeRuleTable(maxRuleSize, @constCast(&ents));

const ParseRule = struct { prefix: ?ParseFn, infix: ?ParseFn, precedence: Precedence };

fn getRule(op: TokenType) *const ParseRule {
    return &parseRules[@intFromEnum(op)];
}

alloc: std.mem.Allocator,
sc: *Scanner,
compiler: *Compiler,
heap: *Heap,
previous: Token = undefined,
current: Token = undefined,
hadError: bool = false,
panicMode: bool = false,

const Precedence = enum(u8) {
    None,
    Assignment,
    Or,
    And,
    Equality,
    Comparison,
    Term,
    Factor,
    Unary,
    Call,
    Primary,

    fn succ(self: Precedence) ?Precedence {
        return switch (self) {
            .None => .Assignment,
            .Assignment => .Or,
            .Or => .And,
            .And => .Equality,
            .Equality => .Comparison,
            .Comparison => .Term,
            .Term => .Factor,
            .Factor => .Unary,
            .Unary => .Call,
            .Call => .Primary,
            .Primary => null,
        };
    }

    fn prev(self: Precedence) ?Precedence {
        return switch (self) {
            .None => null,
            .Assignment => .None,
            .Or => .Assignment,
            .And => .Or,
            .Equality => .And,
            .Comparison => .Equality,
            .Term => .Comparison,
            .Factor => .Term,
            .Unary => .Factor,
            .Call => .Unary,
            .Primary => .Call,
        };
    }
};

pub fn init(
    alloc: std.mem.Allocator,
    sc: *Scanner,
    heap: *Heap,
    compiler: *Compiler,
) Parser {
    return .{
        .alloc = alloc,
        .sc = sc,
        .heap = heap,
        .compiler = compiler,
    };
}

fn call(self: *Parser, _: bool) !void {
    const argCount = try self.argList();
    try self.emitTwo(.Call, argCount);
}

fn argList(self: *Parser) !u8 {
    var count: u8 = 0;
    if (!self.check(.RightParen)) {
        while (true) {
            try self.expression();
            if (count == 255) {
                self.err("argcount cannot exceed 255");
            } else {
                count += 1;
            }
            if (!self.match(.Comma)) break;
        }
    }
    self.consume(.RightParen, "call params must end with ')'");
    return count;
}

pub fn advance(self: *Parser) void {
    self.previous = self.current;
    while (true) {
        self.current = self.sc.scanToken();
        if (self.current.type != .Error) break;
        self.errorAtCurrent(self.current.data);
    }
}

/// Indicate that an error occurred at the current token
fn errorAtCurrent(self: *Parser, msg: []const u8) void {
    self.errorAt(&self.current, msg);
}

/// Indicate that an error occurred on the previous consumed token
fn err(self: *Parser, msg: []const u8) void {
    self.errorAt(&self.previous, msg);
}

fn errorAt(self: *Parser, tok: *const Token, msg: []const u8) void {
    if (self.panicMode) return;
    self.panicMode = true;
    std.debug.print("[Line {d}] Error", .{tok.line});
    switch (tok.type) {
        .Eof => std.debug.print(" at EOF", .{}),
        .Error => {},
        else => std.debug.print(" {s}", .{tok.data}),
    }
    std.debug.print(": {s}\n", .{msg});
    self.hadError = true;
}

pub fn declaration(self: *Parser) !void {
    if (self.match(.Fun)) {
        try self.funDeclaration();
    } else if (self.match(.Var)) {
        try self.varDeclaration();
    } else {
        try self.statement();
    }

    if (self.panicMode) self.synchronize();
}

fn funDeclaration(self: *Parser) anyerror!void {
    const global = try self.parseVariable("Expect a function name");
    self.compiler.markInitialized();
    try self.function(.Func);
    try self.defineVariable(global);
}

fn function(self: *Parser, typ: Compiler.FuncType) !void {
    const compilingFunc = try self.heap.newFunction();
    var newCompiler: Compiler = try .init(typ, compilingFunc, self.compiler);
    self.compiler = &newCompiler;

    // Assign the name of the function
    if (typ != .Script) {
        self.compiler.function.name = try self.heap.strings.make(self.previous.data);
    }

    newCompiler.beginScope();

    self.consume(.LeftParen, "Function parameters must be enclosed by ( )");
    if (!self.check(.RightParen)) {
        while (true) {
            self.compiler.function.arity += 1;
            if (self.compiler.function.arity > 255) {
                self.errorAtCurrent("Can't have more than 255 params");
            }
            const paramName = try self.parseVariable("Expect parameter name");
            try self.defineVariable(paramName);

            if (!self.match(.Comma)) break;
        }
    }
    self.consume(.RightParen, "Missing closing ')'");
    self.consume(.LeftBrace, "Function body must be enclosed by { }");
    try self.block();

    const func = try self.endCompiler();
    const f = try self.makeConstant(.{ .Obj = .{ .Func = func } });
    try self.emitTwo(.Constant, f);
}

fn varDeclaration(self: *Parser) !void {
    const global = try self.parseVariable("Expect varname");
    if (self.match(.Equal)) {
        try self.expression();
    } else {
        try self.emitOpCode(.Nil);
    }
    self.consumeSemicolon();
    try self.defineVariable(global);
}

fn parseVariable(self: *Parser, comptime errMsg: []const u8) !u8 {
    self.consume(.Ident, errMsg);

    self.declareVariable();
    if (self.compiler.scopeDepth > 0) return 0;

    return try self.identifierConstant(self.previous);
}

fn identifierConstant(self: *Parser, tok: Token) !u8 {
    const sobj = try self.heap.allocateString(tok.data);
    return try self.makeConstant(.{ .Obj = .{ .String = sobj } });
}

fn defineVariable(self: *Parser, loc: u8) !void {
    // Local-depth (>0) cases are already defined
    // at this point, so we can skip
    if (self.compiler.scopeDepth > 0) {
        self.compiler.markInitialized();
        return;
    }
    try self.emitTwo(.DefineGlobal, loc);
}

fn declareVariable(self: *Parser) void {
    // We handle globals differently than locally-scoped values
    if (self.compiler.scopeDepth == 0)
        return;
    // Detect redefined variables in the same scope
    var i = self.compiler.locals.items.len;
    while (i > 0) : (i -= 1) {
        const l = self.compiler.locals.items[i - 1];
        const done = if (l.depth) |d| d < self.compiler.scopeDepth else true;
        if (done) break;
        if (identifiersEqual(self.previous, l.name)) {
            self.err("Cannot re-define varialbe in the same scope");
        }
    }
    self.compiler.addLocal(self.previous) catch {
        self.err("too many locals");
    };
}

inline fn identifiersEqual(a: Token, b: Token) bool {
    return std.mem.eql(u8, a.data, b.data);
}

inline fn consumeSemicolon(self: *Parser) void {
    self.consume(.Semicolon, "expect statement to end with ';'");
}

fn synchronize(self: *Parser) void {
    self.panicMode = false;

    while (self.current.type != .Eof) {
        if (self.previous.type == .Semicolon) return;

        switch (self.current.type) {
            .Class, .Fun, .Var, .For, .If, .While, .Print, .Return => return,
            else => {},
        }
        self.advance();
    }
}

pub fn statement(self: *Parser) anyerror!void {
    if (self.match(.Print)) {
        try self.printStatement();
    } else if (self.match(.If)) {
        try self.ifStatement();
    } else if (self.match(.Return)) {
        try self.returnStatement();
    }else if (self.match(.While)) {
        try self.whileStatement();
    } else if (self.match(.For)) {
        try self.forStatement();
    } else if (self.match(.LeftBrace)) {
        self.compiler.beginScope();
        try self.block();
        const numLocals = self.compiler.endScope();
        for (0..numLocals) |_| {
            try self.emitOpCode(.Pop);
        }
    } else {
        try self.expressionStatement();
    }
}

fn returnStatement(self: *Parser) !void {
    if (self.compiler.funcType == .Script) {
        self.err("Can't return from toplevel code");
    }
    if (self.match(.Semicolon)) {
        try self.emitReturn();
    } else {
        try self.expression();
        self.consumeSemicolon();
        try self.emitOpCode(.Return);
    }
}

fn forStatement(self: *Parser) !void {
    // Scope out any loop parameters
    self.compiler.beginScope();
    self.consume(.LeftParen, "For header must be enclosed with ( )");

    // Parse initializer
    if (self.match(.Semicolon)) {} else if (self.match(.Var)) {
        try self.varDeclaration();
    } else {
        try self.expressionStatement();
    }
    var loopStart = self.currentChunk().len();
    var exitJump: ?usize = null;
    if (!self.match(.Semicolon)) {
        try self.expression();
        self.consume(.Semicolon, "expect semicolon after conditional in for loop");
        exitJump = try self.emitJump(.conditional);
        try self.emitOpCode(.Pop);
    }

    if (!self.match(.RightParen)) {
        const bodyJump = try self.emitJump(.always);
        const incrementStatement = self.currentChunk().len();
        try self.expression();
        try self.emitOpCode(.Pop);

        self.consume(.RightParen, "expect ')' at close of for condition");

        try self.emitLoop(@intCast(loopStart));
        loopStart = incrementStatement;
        self.patchJump(bodyJump);
    }

    try self.statement();
    try self.emitLoop(@intCast(loopStart));
    if (exitJump) |loc| {
        self.patchJump(loc);
        try self.emitOpCode(.Pop);
    }
    const numLocals = self.compiler.endScope();
    for (0..numLocals) |_| {
        try self.emitOpCode(.Pop);
    }
}

fn whileStatement(self: *Parser) !void {
    const loopStart = self.currentChunk().len();
    self.consume(.LeftParen, "the while condition must be contained by ( )");
    try self.expression();
    self.consume(.RightParen, "While loop condition not closed with `)`");

    const exitJump = try self.emitJump(.conditional);
    try self.emitOpCode(.Pop);
    try self.statement();
    try self.emitLoop(@intCast(loopStart));

    self.patchJump(exitJump);
    try self.emitOpCode(.Pop);
}

fn ifStatement(self: *Parser) !void {
    self.consume(.LeftParen, "if condition must be contained by ( )");
    try self.expression();
    self.consume(.RightParen, "no closing ')'");

    const jumpThen = try self.emitJump(.conditional);
    // The POP opcode is necessary because the jump
    // command doesn't pop the conditional result.
    try self.emitOpCode(.Pop);
    try self.statement();

    const elseJump = try self.emitJump(.always);

    self.patchJump(jumpThen);
    // We must put the POP opcode here as well
    // in the case that we DID jump.
    try self.emitOpCode(.Pop);

    if (self.match(.Else)) try self.statement();
    self.patchJump(elseJump);
}

/// Insert a JMP operation, which is one of the jump opcodes
/// plus a short representing the jump offset. Returns the
/// index in the code block of the short operand for patching
/// later.
fn emitJump(self: *Parser, comptime when: enum { conditional, always }) !usize {
    try self.emitOpCode(switch (when) {
        .conditional => .JumpIfFalse,
        .always => .Jump,
    });
    try self.emitByte(0xff);
    try self.emitByte(0xff);
    return self.currentChunk().len() - 2;
}

fn emitLoop(self: *Parser, loopStart: u16) !void {
    try self.emitOpCode(.Loop);

    const offset = self.currentChunk().len() - loopStart + 2;
    if (offset > std.math.maxInt(u16))
        self.err("Loop body too large");
    try self.emitByte(0);
    try self.emitByte(0);
    const ip = self.currentChunk().len();
    std.mem.writeInt(u16, @ptrCast(self.currentChunk().code.items[ip - 2 .. ip]), @intCast(offset), .little);
}

/// Patches the current chunk pointer to the provided index.
fn patchJump(self: *Parser, offset: usize) void {
    var chunk = self.currentChunk();
    const jump = chunk.len() - offset - 2;
    if (jump > std.math.maxInt(u16))
        self.err("Too much code to jump over");
    std.mem.writeInt(
        u16,
        @ptrCast(chunk.code.items[offset .. offset + 2]),
        @intCast(jump),
        .little,
    );
}

fn block(self: *Parser) !void {
    while (!self.check(.RightBrace) and !self.check(.Eof)) {
        try self.declaration();
    }
    self.consume(.RightBrace, "unterminated block");
}

pub fn printStatement(self: *Parser) !void {
    try self.expression();
    try self.emitOpCode(.Print);
    self.consumeSemicolon();
}

fn expressionStatement(self: *Parser) !void {
    try self.expression();
    self.consumeSemicolon();
    try self.emitOpCode(.Pop);
}

pub fn expression(self: *Parser) !void {
    try self.parsePrecedence(.Assignment);
}

fn number(self: *Parser, _: bool) !void {
    const val: f32 = try std.fmt.parseFloat(f32, self.previous.data);
    try self.emitConstant(.{ .Number = val });
}

fn grouping(self: *Parser, _: bool) !void {
    try self.expression();
    self.consume(.RightParen, "Expect ')' after expression");
}

fn string(self: *Parser, _: bool) !void {
    const sobj = try self.heap.allocateString(self.previous.data);
    try self.emitConstant(.{ .Obj = .{ .String = sobj } });
}

fn variable(self: *Parser, canParse: bool) !void {
    return self.namedVariable(self.previous, canParse);
}

fn namedVariable(self: *Parser, name: Token, canParse: bool) !void {
    var getOp: inst.OpCode = undefined;
    var setOp: inst.OpCode = undefined;
    var arg: u8 = undefined;
    if (self.compiler.resolveLocal(name)) |maybe_a| {
        if (maybe_a) |a| {
            arg = a;
            getOp = .GetLocal;
            setOp = .SetLocal;
        } else {
            arg = try self.identifierConstant(name);
            getOp = .GetGlobal;
            setOp = .SetGlobal;
        }
    } else |_| {
        self.err("Attempt to define a variable in terms of itself");
        return;
    }
    if (canParse and self.match(.Equal)) {
        try self.expression();
        try self.emitTwo(setOp, arg);
    } else {
        try self.emitTwo(getOp, arg);
    }
}

fn binary(self: *Parser, _: bool) !void {
    const typ: TokenType = self.previous.type;
    const rule = getRule(typ);
    try self.parsePrecedence(rule.precedence.succ().?);

    switch (typ) {
        .Plus => try self.emitOpCode(.Add),
        .Minus => try self.emitOpCode(.Subtract),
        .Star => try self.emitOpCode(.Multiply),
        .Slash => try self.emitOpCode(.Divide),
        .BangEqual => {
            try self.emitOpCode(.Equal);
            try self.emitOpCode(.Not);
        },
        .DoubleEqual => try self.emitOpCode(.Equal),
        .Greater => try self.emitOpCode(.Greater),
        .Less => try self.emitOpCode(.Less),
        .GreaterEqual => {
            try self.emitOpCode(.Less);
            try self.emitOpCode(.Not);
        },
        .LessEqual => {
            try self.emitOpCode(.Greater);
            try self.emitOpCode(.Not);
        },
        else => unreachable,
    }
}

fn parsePrecedence(self: *Parser, prec: Precedence) !void {
    const pi = @intFromEnum(prec);
    const canAssign = pi <= @intFromEnum(Precedence.Assignment);
    self.advance();
    const f = getRule(self.previous.type);
    if (f.prefix) |pf| {
        try pf(self, canAssign);
    } else {
        self.err("Expect an expression");
        return;
    }
    while (pi <= @intFromEnum(getRule(self.current.type).precedence)) {
        self.advance();
        const ifRule = getRule(self.previous.type).infix.?;
        try ifRule(self, canAssign);
    }
    if (canAssign and self.match(.Equal)) {
        self.err("Invalid assignment target");
        return;
    }
}

fn unary(self: *Parser, _: bool) !void {
    const typ = self.previous.type;

    try self.parsePrecedence(.Unary);

    switch (typ) {
        .Minus => try self.emitOpCode(.Negate),
        .Bang => try self.emitOpCode(.Not),
        else => return,
    }
}

fn consume(self: *Parser, typ: TokenType, comptime errMsg: []const u8) void {
    if (self.current.type == typ) {
        self.advance();
    } else {
        self.errorAt(&self.current, errMsg);
    }
}

fn emitConstant(self: *Parser, val: value.Value) !void {
    try self.emitTwo(.Constant, try self.makeConstant(val));
}

fn and_(self: *Parser, _: bool) !void {
    const jumpInd = try self.emitJump(.conditional);
    try self.emitOpCode(.Pop);
    try self.parsePrecedence(.And);
    self.patchJump(jumpInd);
}

fn or_(self: *Parser, _: bool) !void {
    try self.emitOpCode(.Not);

    const jumpInd = try self.emitJump(.conditional);
    try self.emitOpCode(.Pop);

    try self.parsePrecedence(.Or);
    try self.emitOpCode(.Not);

    self.patchJump(jumpInd);
    try self.emitOpCode(.Not);
}

fn literal(self: *Parser, _: bool) !void {
    switch (self.previous.type) {
        .Nil => try self.emitOpCode(.Nil),
        .True => try self.emitOpCode(.True),
        .False => try self.emitOpCode(.False),
        else => unreachable,
    }
}

fn makeConstant(self: *Parser, val: value.Value) !u8 {
    const valLoc = try self.currentChunk().addConstant(val);
    if (valLoc > std.math.maxInt(u8)) {
        self.err("too many constants in one chunk");
        return 0;
    }
    return @intCast(valLoc);
}

inline fn check(self: *Parser, typ: TokenType) bool {
    return self.current.type == typ;
}

pub fn match(self: *Parser, typ: TokenType) bool {
    if (!self.check(typ)) return false;
    self.advance();
    return true;
}

fn currentChunk(self: *Parser) *inst.Chunk {
    return &self.compiler.function.chunk;
}

fn emitByte(self: *Parser, b: u8) !void {
    try self.currentChunk().put(b, self.previous.line);
}

fn emitOpCode(self: *Parser, code: inst.OpCode) !void {
    try self.currentChunk().putOpCode(code, @intCast(self.previous.line));
}

fn emitTwo(self: *Parser, code: inst.OpCode, b: u8) !void {
    var c = self.currentChunk();
    try c.putOpCode(code, @intCast(self.previous.line));
    try c.put(b, @intCast(self.previous.line));
}

fn emitReturn(self: *Parser) !void {
    try self.emitOpCode(.Nil);
    try self.emitOpCode(.Return);
}

pub fn endCompiler(self: *Parser) !*value.FuncObj {
    try self.emitReturn();
    
    const f = self.compiler.function;
    if (build_options.lox_debug and !self.hadError) {
        try self.currentChunk().disassemble(f.name orelse "<script>");
    }
    if (self.compiler.enclosing) |e| self.compiler = e;
    return f;
}

pub fn compile(
    alloc: std.mem.Allocator,
    source: []const u8,
    heap: *Heap,
) !?*value.FuncObj {
    var sc: Scanner = .init(source);
    const func = try heap.newFunction();
    var comp: Compiler = try .init(.Script, func, null);
    var parser: Parser = .init(alloc, &sc, heap, &comp);

    parser.advance();

    while (!parser.match(.Eof)) {
        try parser.declaration();
    }

    const f = try parser.endCompiler();
    return if (parser.hadError) null else f;
}
