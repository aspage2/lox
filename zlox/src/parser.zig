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

const ParseFn = *const fn (*Parser) anyerror!void;

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
    ruleEntry(.GreaterEqual, null, binary, .Equality),
    ruleEntry(.Less, null, binary, .Equality),
    ruleEntry(.LessEqual, null, binary, .Equality),
    ruleEntry(.Ident, null, null, .None),
    ruleEntry(.String, string, null, .None),
    ruleEntry(.Number, number, null, .None),
    ruleEntry(.And, null, null, .None),
    ruleEntry(.Class, null, null, .None),
    ruleEntry(.Else, null, null, .None),
    ruleEntry(.False, literal, null, .None),
    ruleEntry(.For, null, null, .None),
    ruleEntry(.Fun, null, null, .None),
    ruleEntry(.If, null, null, .None),
    ruleEntry(.Nil, literal, null, .None),
    ruleEntry(.Or, null, null, .None),
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

pub fn init(alloc: std.mem.Allocator, sc: *Scanner, chunk: *inst.Chunk, tbl: *value.StringTable) Parser {
    return .{ 
        .alloc = alloc,
        .sc = sc,
        .compilingChunk = chunk,
        .stringTable = tbl,
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

pub fn expression(self: *Parser) !void {
    try self.parsePrecedence(.Assignment);
}

fn number(self: *Parser) !void {
    const val: f32 = try std.fmt.parseFloat(f32, self.previous.data);
    try self.emitConstant(.{ .Number = val });
}

fn grouping(self: *Parser) !void {
    try self.expression();
    self.consume(.RightParen, "Expect ')' after expression");
}

fn string(self: *Parser) !void {
    const sobj = try self.stringTable.make(self.previous.data);
    const o = try self.alloc.create(value.Obj);
    o.inst.String = sobj;
    try self.emitConstant(.{.Obj = o});
}

fn binary(self: *Parser) !void {
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

fn literal(self: *Parser) !void {
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
