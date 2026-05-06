const std = @import("std");

const compiler = @import("compiler.zig");
const Scanner = @import("scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const Chunk = inst.Chunk;
const value = @import("value.zig");
const build_options = @import("build_options");

const inst = @import("inst.zig");

const Parser = @This();

const ParseFn = *const fn(*Parser) anyerror!void;

const Entry = @Tuple(&.{TokenType, ?ParseFn, ?ParseFn, Precedence});

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
    return .{typ, prefix, infix, prec};
}

const maxRuleSize = std.math.maxInt(@typeInfo(TokenType).@"enum".tag_type);

const ents = [_]Entry{
    ruleEntry(.LeftParen, Parser.grouping, null, .None),
    ruleEntry(.RightParen, null, null, .None),
    ruleEntry(.LeftBrace, null, null, .None),
    ruleEntry(.RightBrace, null, null, .None),
    ruleEntry(.Comma, null, null, .None),
    ruleEntry(.Dot, null, null, .None),
    ruleEntry(.Minus, Parser.unary, Parser.binary, .Term),
    ruleEntry(.Plus, null, Parser.binary, .Term),
    ruleEntry(.Semicolon, null, null, .None),
    ruleEntry(.Slash, null, Parser.binary, .Factor),
    ruleEntry(.Star, null, Parser.binary, .Factor),
    ruleEntry(.Bang, null, null, .None),
    ruleEntry(.BangEqual, null, null, .None),
    ruleEntry(.Equal, null, null, .None),
    ruleEntry(.DoubleEqual, null, null, .None),
    ruleEntry(.Greater, null, null, .None),
    ruleEntry(.GreaterEqual, null, null, .None),
    ruleEntry(.Less, null, null, .None),
    ruleEntry(.LessEqual, null, null, .None),
    ruleEntry(.Ident, null, null, .None),
    ruleEntry(.String, null, null, .None),
    ruleEntry(.Number, Parser.number, null, .None),
    ruleEntry(.And, null, null, .None),
    ruleEntry(.Class, null, null, .None),
    ruleEntry(.Else, null, null, .None),
    ruleEntry(.False, null, null, .None),
    ruleEntry(.For, null, null, .None),
    ruleEntry(.Fun, null, null, .None),
    ruleEntry(.If, null, null, .None),
    ruleEntry(.Nil, null, null, .None),
    ruleEntry(.Or, null, null, .None),
    ruleEntry(.Print, null, null, .None),
    ruleEntry(.Return, null, null, .None),
    ruleEntry(.Super, null, null, .None),
    ruleEntry(.This, null, null, .None),
    ruleEntry(.True, null, null, .None),
    ruleEntry(.Var, null, null, .None),
    ruleEntry(.While, null, null, .None),
    ruleEntry(.Error, null, null, .None),
    ruleEntry(.Eof, null, null, .None),
};

const parseRules: [maxRuleSize]ParseRule =
    makeRuleTable(maxRuleSize, @constCast(&ents));

sc: *Scanner,
compilingChunk: *Chunk,
previous: Token = undefined,
current: Token = undefined,
hadError: bool = false,
panicMode: bool = false,

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence
};


fn getRule(op: TokenType) *const ParseRule { 
    return &parseRules[@intFromEnum(op)];
}

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
        return switch(self) {
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
        return switch(self) {
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

pub fn init(sc: *Scanner, chunk: *inst.Chunk) Parser {
    return .{.sc = sc, .compilingChunk = chunk};
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

pub fn expression(self: *Parser) !void {
    try self.parsePrecedence(.Assignment);
}

fn number(self: *Parser) !void {
    const val: value.Value = try std.fmt.parseFloat(value.Value, self.previous.data);
    try self.emitConstant(val);
}

fn grouping(self: *Parser) !void {
    try self.expression();
    self.consume(.RightParen, "Expect ')' after expression");
}

fn binary(self: *Parser) !void {
    const typ: TokenType = self.previous.type;
    const rule = getRule(typ);
    try self.parsePrecedence(rule.precedence.succ().?);

    try self.emitOpCode(switch(typ) {
        .Plus => .Add,
        .Minus => .Subtract,
        .Star => .Multiply,
        .Slash => .Divide,
        else => unreachable,
    });
}

fn parsePrecedence(self: *Parser, prec: Precedence) !void {
    self.advance();
    const f = getRule(self.previous.type);
    if (f.prefix) |pf| {
        try pf(self);
    } else {
        self.err("Expect an expression");
        return;
    }

    while (@intFromEnum(prec) <= @intFromEnum(getRule(self.current.type).precedence)) {
        self.advance();
        const ifRule = getRule(self.previous.type).infix.?;
        try ifRule(self);
    }
}

fn unary(self: *Parser) !void {
    const typ = self.previous.type;

    try self.parsePrecedence(.Unary);

    switch(typ) {
    .Minus => try self.emitOpCode(.Negate),
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

fn makeConstant(self: *Parser, val: value.Value) !u8 {
    const valLoc = try self.currentChunk().addConstant(val);
    if (valLoc > std.math.maxInt(u8)) {
        self.err("too many constants in one chunk");
        return 0;
    }
    return @intCast(valLoc);
}
fn currentChunk(self: *Parser) *inst.Chunk {
    return self.compilingChunk;
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

pub fn end(self: *Parser) !void {
    try self.emitOpCode(.Return);
    if (build_options.lox_debug and !self.hadError) {
        try self.currentChunk().disassemble("code");
    }
}
