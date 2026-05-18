const std = @import("std");

const Scanner = @import("scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const Chunk = inst.Chunk;
const value = @import("value.zig");
const build_options = @import("build_options");

const inst = @import("inst.zig");

pub const Compiler = struct {
    locals: [std.math.maxInt(u8)]Local = undefined,
    count: usize = 0,
    scopeDepth: isize = 0,
    parser: *Parser = undefined,

    pub const Error = error{
        TooManyLocals,
        SelfReferentialLocal,
    };

    pub fn markInitialized(self: *Compiler) void {
        self.locals[self.count - 1].depth = self.scopeDepth;
    }

    pub fn beginScope(self: *Compiler) void {
        self.scopeDepth += 1;
    }

    pub fn endScope(self: *Compiler) u8 {
        const currCount = self.count;
        self.scopeDepth -= 1;
        while (self.count > 0 and
            self.locals[self.count - 1].depth > self.scopeDepth) : (self.count -= 1)
        {}

        return @intCast(currCount - self.count);
    }

    pub fn addLocal(self: *Compiler, name: Token) Compiler.Error!void {
        if (self.count == std.math.maxInt(u8))
            return Compiler.Error.TooManyLocals;
        const ind = self.count;
        self.count += 1;
        self.locals[ind].name = name;
        self.locals[ind].depth = -1;
    }

    pub fn resolveLocal(self: *Compiler, name: Token) Compiler.Error!?u8 {
        var i = self.count;
        while (i > 0) : (i -= 1) {
            const pos = i - 1;
            const local = self.locals[pos];
            if (std.mem.eql(u8, name.data, local.name.data)) {
                // capture var a = a;
                if (local.depth == -1)
                    return Compiler.Error.SelfReferentialLocal;
                return @intCast(pos);
            }
        }
        return null;
    }
};

pub const Local = struct {
    name: Token,
    depth: isize,
};

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
    ruleEntry(.LeftParen, grouping, null, .None),
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
compilingChunk: *Chunk,
stringTable: *value.StringTable,
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
    chunk: *inst.Chunk,
    tbl: *value.StringTable,
    compiler: *Compiler,
) Parser {
    return .{
        .alloc = alloc,
        .sc = sc,
        .compilingChunk = chunk,
        .stringTable = tbl,
        .compiler = compiler,
    };
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
    if (self.match(.Var)) {
        try self.varDeclaration();
    } else {
        try self.statement();
    }

    if (self.panicMode) self.synchronize();
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

    try self.declareVariable();
    if (self.compiler.scopeDepth > 0) return 0;

    return try self.identifierConstant(self.previous);
}

fn identifierConstant(self: *Parser, tok: Token) !u8 {
    const sobj = try self.stringTable.make(tok.data);
    const o = try self.alloc.create(value.Obj);
    o.inst.String = sobj;
    return try self.makeConstant(.{ .Obj = o });
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

fn declareVariable(self: *Parser) !void {
    // We handle globals differently than locally-scoped values
    if (self.compiler.scopeDepth == 0)
        return;
    // Detect redefined variables in the same scope
    var i = self.compiler.count;
    while (i > 0) : (i -= 1) {
        const l = self.compiler.locals[i - 1];
        if (l.depth != -1 and l.depth < self.compiler.scopeDepth) {
            break;
        }
        if (identifiersEqual(self.previous, l.name)) {
            self.err("Cannot re-define varialbe in the same scope");
        }
    }
    self.compiler.addLocal(self.previous) catch {
        self.err("Too many locals defined.");
        return;
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
    } else if (self.match(.While)) {
        try self.whileStatement();
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
    std.mem.writeInt(u16, @ptrCast(self.currentChunk().code.items[ip-2..ip]), @intCast(offset), .little);
}

/// Patches the current chunk pointer to the provided index.
fn patchJump(self: *Parser, offset: usize) void {
    var chunk = self.currentChunk();
    const jump = chunk.len() - offset - 2;
    if (jump > std.math.maxInt(u16))
        self.err("Too much code to jump over");
    std.mem.writeInt(
        u16, @ptrCast(chunk.code.items[offset..offset + 2]), @intCast(jump), .little,
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
    const sobj = try self.stringTable.make(self.previous.data);
    const o = try self.alloc.create(value.Obj);
    o.inst.String = sobj;
    try self.emitConstant(.{ .Obj = o });
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
    } else |e| switch (e) {
        Compiler.Error.SelfReferentialLocal => self.err("can't self-reference a local in its own declaration."),
        else => unreachable,
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
    return self.compilingChunk;
}

fn emitByte(self: *Parser, b: u8) !void {
    try self.currentChunk().put(b, self.previous.line);
}

fn emitOpCode(self: *Parser, code: inst.OpCode) !void {
    std.debug.print("Emit opcode {any} line {d}\n", .{code, self.previous.line});
    try self.currentChunk().putOpCode(code, @intCast(self.previous.line));
}

fn emitTwo(self: *Parser, code: inst.OpCode, b: u8) !void {
    std.debug.print("Emit opcode {any} value {d} line {d}\n", .{code, b, self.previous.line});
    var c = self.currentChunk();
    try c.putOpCode(code, @intCast(self.previous.line));
    try c.put(b, @intCast(self.previous.line));
}

pub fn end(self: *Parser) !void {
    // try self.emitOpCode(.Return);
    if (build_options.lox_debug and !self.hadError) {
        try self.currentChunk().disassemble("code");
    }
}

pub fn compile(
    alloc: std.mem.Allocator,
    source: []const u8,
    chunk: *Chunk,
    st: *value.StringTable,
) !bool {
    var sc: Scanner = .init(source);
    var comp: Compiler = .{};
    var parser: Parser = .init(alloc, &sc, chunk, st, &comp);

    parser.advance();

    while (!parser.match(.Eof)) {
        try parser.declaration();
    }

    try parser.end();
    return parser.hadError;
}
