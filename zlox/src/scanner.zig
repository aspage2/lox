const std = @import("std");
const value = @import("value.zig");
const inst = @import("inst.zig");

const testing = std.testing;

const Scanner = @This();

pub const Token = struct {
    type: TokenType,
    data: []const u8,
    line: u32,

    pub fn inferIdentifierType(self: *Token) void {
        switch (self.data[0]) {
            'a' => return self.checkKeyword(1, "nd", .And),
            'c' => return self.checkKeyword(1, "lass", .Class),
            'e' => return self.checkKeyword(1, "lse", .Else),
            'i' => return self.checkKeyword(1, "f", .If),
            'n' => return self.checkKeyword(1, "il", .Nil),
            'o' => return self.checkKeyword(1, "r", .Or),
            'p' => return self.checkKeyword(1, "rint", .Print),
            'r' => return self.checkKeyword(1, "eturn", .Return),
            's' => return self.checkKeyword(1, "uper", .Super),
            'v' => return self.checkKeyword(1, "ar", .Var),
            'w' => return self.checkKeyword(1, "hile", .While),
            'f' => if (self.data.len > 1) {
                switch (self.data[1]) {
                    'a' => return self.checkKeyword(2, "lse", .False),
                    'o' => return self.checkKeyword(2, "r", .For),
                    'u' => return self.checkKeyword(2, "n", .Fun),
                    else => {
                        self.type = .Ident;
                    },
                }
            },
            't' => if (self.data.len > 1) {
                switch (self.data[1]) {
                    'h' => return self.checkKeyword(2, "is", .This),
                    'r' => return self.checkKeyword(2, "ue", .True),
                    else => {
                        self.type = .Ident;
                    },
                }
            },
            else => {
                self.type = .Ident;
            },
        }
    }

    fn checkKeyword(self: *Token, pos: usize, rest: []const u8, typ: TokenType) void {
        if (std.mem.eql(u8, self.data[pos..], rest)) {
            self.type = typ;
        } else {
            self.type = .Ident;
        }
    }
};

pub const TokenType = enum(u8) {
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,
    Bang,
    BangEqual,
    Equal,
    DoubleEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    Ident,
    String,
    Number,
    And,
    Class,
    Else,
    False,
    For,
    Fun,
    If,
    Nil,
    Or,
    Print,
    Return,
    Super,
    This,
    True,
    Var,
    While,
    Error,
    Eof,
};

source: []const u8,
start: usize,
pos: usize,
line: u32,

pub fn init(source: []const u8) Scanner {
    return .{
        .source = source,
        .start = 0,
        .pos = 0,
        .line = 1,
    };
}

/// Detect and consume an arbitrary token from the input.
pub fn scanToken(self: *Scanner) Token {
    self.start = self.pos;
    self.skipWhitespace();
    if (self.advance()) |c| {
        if (std.ascii.isAlphabetic(c)) {
            return self.ident();
        }
        if (std.ascii.isDigit(c)) {
            return self.number();
        }
        switch (c) {
            '(' => return self.emit(.LeftParen),
            ')' => return self.emit(.RightParen),
            '{' => return self.emit(.LeftBrace),
            '}' => return self.emit(.RightBrace),
            ';' => return self.emit(.Semicolon),
            ',' => return self.emit(.Comma),
            '.' => return self.emit(.Dot),
            '-' => return self.emit(.Minus),
            '+' => return self.emit(.Plus),
            '/' => return self.emit(.Slash),
            '*' => return self.emit(.Star),
            '!' => return self.emit(if (self.match('=')) .BangEqual else .Bang),
            '=' => return self.emit(if (self.match('=')) .DoubleEqual else .Equal),
            '>' => return self.emit(if (self.match('=')) .GreaterEqual else .Greater),
            '<' => return self.emit(if (self.match('=')) .LessEqual else .Less),
            '"' => {
                self.discardToken(); // Discard "
                return self.string();
            },
            else => {},
        }
        return self.err("unexpected character");
    } else {
        return self.emit(.Eof);
    }
}

fn emit(self: *Scanner, typ: TokenType) Token {
    return .{
        .type = typ,
        .data = self.source[self.start..self.pos],
        .line = self.line,
    };
}

fn err(self: *Scanner, msg: []const u8) Token {
    return .{
        .type = .Error,
        .data = msg,
        .line = self.line,
    };
}

/// Drop the working span without emitting a token value.
fn discardToken(self: *Scanner) void {
    self.start = self.pos;
}

fn ident(self: *Scanner) Token {
    while (self.peek()) |c| {
        if (!std.ascii.isAlphanumeric(c))
            break;
        self.step();
    }
    var tok = self.emit(.Ident);
    tok.inferIdentifierType();
    return tok;
}

fn number(self: *Scanner) Token {
    while (self.peek()) |c| {
        if (std.ascii.isDigit(c)) {
            _ = self.advance();
        } else {
            break;
        }
    }

    if (self.peek()) |c| {
        if (self.peekNext()) |c2| {
            if (c == '.' and std.ascii.isDigit(c2)) {
                _ = self.advance();
                while (self.peek()) |d| {
                    if (std.ascii.isDigit(d)) {
                        _ = self.advance();
                    } else break;
                }
            }
        }
    }
    return self.emit(.Number);
}

/// If it exists, return the value at pos. Returns null
/// if at the end of the source (EOI)
fn peek(self: *Scanner) ?u8 {
    if (self.isAtEnd()) return null;
    return self.source[self.pos];
}

/// If exists, return the value at `pos + 1`, one past the current pos.
/// Otherwise return null.
fn peekNext(self: *Scanner) ?u8 {
    if (self.pos >= self.source.len - 1) return null;
    return self.source[self.pos + 1];
}

inline fn step(self: *Scanner) void {
    if (self.pos < self.source.len)
        self.pos += 1;
}

pub fn string(self: *Scanner) Token {
    const line = self.line;
    while (true) {
        if (self.peek()) |c| {
            switch (c) {
                '"' => {
                    var tok = self.emit(.String);
                    tok.line = line;
                    self.step();
                    self.discardToken(); // Discard ending "
                    return tok;
                },
                '\n' => self.line += 1,
                else => {},
            }
            self.step();
        } else {
            return self.err("Unterminated string");
        }
    }
}

pub fn match(self: *Scanner, exp: u8) bool {
    if (self.isAtEnd()) {
        return false;
    }
    if (self.source[self.pos] != exp) {
        return false;
    }
    self.pos += 1;
    return true;
}

pub fn skipWhitespace(self: *Scanner) void {
    mainblk: while (self.peek()) |c| {
        switch (c) {
            ' ', '\r', '\t' => self.step(),
            '\n' => {
                self.step();
                self.line += 1;
            },
            '/' => {
                if (self.peekNext()) |cn| {
                    if (cn != '/') break :mainblk;
                    while (self.peek()) |ca| {
                        if (ca == '\n')
                            break;
                        self.step();
                    }
                }
            },
            else => break :mainblk,
        }
    }
    self.discardToken();
}

inline fn isAtEnd(self: *Scanner) bool {
    return self.pos >= self.source.len;
}

fn advance(self: *Scanner) ?u8 {
    if (self.pos >= self.source.len)
        return null;
    const ret = self.source[self.pos];
    self.pos += 1;
    return ret;
}

fn expectTokenValue(
    tok: Token,
    typ: TokenType,
    lineNo: usize,
    content: []const u8,
) !void {
    try testing.expectEqual(typ, tok.type);
    try testing.expectEqual(lineNo, tok.line);
    try testing.expectEqualStrings(content, tok.data);
}

// NUMBER token tests
test "basic number" {
    const source = "3.1415";
    var sc: Scanner = .init(source);

    const tok = sc.number();

    try expectTokenValue(tok, .Number, 1, "3.1415");
}

test "bare number" {
    const source = "1337; hello";
    var sc: Scanner = .init(source);

    const tok = sc.number();
    try expectTokenValue(tok, .Number, 1, "1337");
}

test "no bare dot" {
    const source = "444.";
    var sc: Scanner = .init(source);

    const tok = sc.number();

    try expectTokenValue(tok, .Number, 1, "444");
}

// String token
test "simple string" {
    const source = "hello, world\"";
    var sc: Scanner = .init(source);

    const tok = sc.string();
    try expectTokenValue(tok, .String, 1, "hello, world");
}

test "multiline string" {
    const source =
        \\Hello, world
        \\this is my string"
    ;
    var sc: Scanner = .init(source);

    try expectTokenValue(sc.string(), .String, 1, "Hello, world\nthis is my string");
    try testing.expectEqual(2, sc.line);
}

test "string then ws" {
    const source = "foobar\"     ";
    var sc: Scanner = .init(source);
    try expectTokenValue(sc.string(), .String, 1, "foobar");
}

test "string then nl" {
    const source = "foobarz\"\n";
    var sc: Scanner = .init(source);
    try expectTokenValue(sc.string(), .String, 1, "foobarz");
}

test "skipWhitespace" {
    const source = " \t\n\rabc";
    var sc: Scanner = .init(source);
    sc.skipWhitespace();
    try testing.expectEqual(4, sc.pos);
}

test "skipWhitespace comment" {
    const source =
        \\// hello, world
        \\this is actual code
    ;
    var sc: Scanner = .init(source);
    sc.skipWhitespace();
    try testing.expectEqual(16, sc.pos);
}

test "skipWhitespace not comment" {
    const source = " / my_value";
    var sc: Scanner = .init(source);
    sc.skipWhitespace();
    try testing.expectEqual(1, sc.pos);
}

test "ident" {
    const tcs = [_]struct { source: []const u8, typ: TokenType }{
        .{ .source = "and", .typ = .And },
        .{ .source = "class", .typ = .Class },
        .{ .source = "else", .typ = .Else },
        .{ .source = "false", .typ = .False },
        .{ .source = "for", .typ = .For },
        .{ .source = "fun", .typ = .Fun },
        .{ .source = "if", .typ = .If },
        .{ .source = "nil", .typ = .Nil },
        .{ .source = "or", .typ = .Or },
        .{ .source = "print", .typ = .Print },
        .{ .source = "return", .typ = .Return },
        .{ .source = "super", .typ = .Super },
        .{ .source = "this", .typ = .This },
        .{ .source = "true", .typ = .True },
        .{ .source = "var", .typ = .Var },
        .{ .source = "while", .typ = .While },
        .{ .source = "ugh", .typ = .Ident },
        .{ .source = "foo2", .typ = .Ident },
    };

    for (tcs) |tc| {
        var sc: Scanner = .init(tc.source);
        const tok = sc.ident();
        try expectTokenValue(tok, tc.typ, 1, tc.source);
    }
}

test "scanner" {
    const source =
        \\class MyClass {
        \\  constructor() {
        \\    this.x = 33.0 + 45;
        \\    this.y = "Hello, world";
        \\  }
        \\}
        \\
    ;
    var sc: Scanner = .init(source);

    try expectTokenValue(sc.scanToken(), .Class, 1, "class");
    try expectTokenValue(sc.scanToken(), .Ident, 1, "MyClass");
    try expectTokenValue(sc.scanToken(), .LeftBrace, 1, "{");
    try expectTokenValue(sc.scanToken(), .Ident, 2, "constructor");
    try expectTokenValue(sc.scanToken(), .LeftParen, 2, "(");
    try expectTokenValue(sc.scanToken(), .RightParen, 2, ")");
    try expectTokenValue(sc.scanToken(), .LeftBrace, 2, "{");
    try expectTokenValue(sc.scanToken(), .This, 3, "this");
    try expectTokenValue(sc.scanToken(), .Dot, 3, ".");
    try expectTokenValue(sc.scanToken(), .Ident, 3, "x");
    try expectTokenValue(sc.scanToken(), .Equal, 3, "=");
    try expectTokenValue(sc.scanToken(), .Number, 3, "33.0");
    try expectTokenValue(sc.scanToken(), .Plus, 3, "+");
    try expectTokenValue(sc.scanToken(), .Number, 3, "45");
    try expectTokenValue(sc.scanToken(), .Semicolon, 3, ";");
    try expectTokenValue(sc.scanToken(), .This, 4, "this");
    try expectTokenValue(sc.scanToken(), .Dot, 4, ".");
    try expectTokenValue(sc.scanToken(), .Ident, 4, "y");
    try expectTokenValue(sc.scanToken(), .Equal, 4, "=");
    try expectTokenValue(sc.scanToken(), .String, 4, "Hello, world");
    try expectTokenValue(sc.scanToken(), .Semicolon, 4, ";");
    try expectTokenValue(sc.scanToken(), .RightBrace, 5, "}");
    try expectTokenValue(sc.scanToken(), .RightBrace, 6, "}");
    try expectTokenValue(sc.scanToken(), .Eof, 7, "");
}
