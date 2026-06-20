/// The compiler holds state related to function data & scopes.
const std = @import("std");

const scanner = @import("scanner.zig");
const Token = scanner.Token;
const value = @import("value.zig");

const Compiler = @This();

pub const UpValue = struct {
    index: u8,
    isLocal: bool,
};

/// A stack entry.
pub const Local = struct {
    /// The token where this name was first seen
    name: Token,
    /// Scopedepth where this field was defined.
    /// uninitialized locals have a null depth to begin.
    depth: ?usize,
    /// Local is captured by a closure upvalue.
    isCaptured: bool,
};

/// Nested compilers all the way down.
enclosing: ?*Compiler,

/// Local stack
/// In lox, the behavior of locals in a scope is stack-like.
/// The locals ArrayList tracks locals as they enter and leave
/// a scope. The location of a local entry in the local stack
/// magically corresponds to the location in the operand stack
/// where that local will exist during run time.
///
/// The book has us using a fixed buffer for the stack.
localBuffer: [std.math.maxInt(u8)]Local = undefined,
locals: std.ArrayList(Local) = undefined,
upvalueBuffer: [std.math.maxInt(u8)]UpValue = undefined,
upvalues: std.ArrayList(UpValue) = undefined,

/// Scope depth of 0 represents the global scope.
scopeDepth: usize = 0,

function: *value.FuncObj = undefined,
funcType: FuncType,

pub const FuncType = enum { Script, Func };

pub fn init(compiler: *Compiler, funcType: FuncType, func: *value.FuncObj, enclosing: ?*Compiler) void {
    compiler.funcType = funcType;
    compiler.enclosing = enclosing;
    compiler.locals = .initBuffer(&compiler.localBuffer);
    compiler.upvalues = .initBuffer(&compiler.upvalueBuffer);
    compiler.scopeDepth = 0;
    compiler.function = func;

    const local = compiler.locals.addOneAssumeCapacity();
    local.depth = 0;
    local.name = .{ .data = "", .type = .Error, .line = 1 };
    local.isCaptured = false;
}

/// After a local's initializer is parsed, it is marked "initialized"
/// by the parser.
pub fn markInitialized(self: *Compiler) void {
    if (self.scopeDepth == 0) return;
    const l = self.locals.items.len;
    self.locals.items[l - 1].depth = self.scopeDepth;
}

/// Enter a scope
pub fn beginScope(self: *Compiler) void {
    self.scopeDepth += 1;
}

/// Exit a scope, calculating how many locals need to be popped from
/// the value stack on return.
pub fn endScope(self: *Compiler) Dropper {
    return .{ 
        .locals = &self.locals,
        .scopeDepth = self.scopeDepth
    };
}

// Iterator pattern for dropping locals
pub const Dropper = struct {
    locals: *std.ArrayList(Local),
    scopeDepth: usize,

    pub fn dropNext(self: *Dropper) ?bool {
        const local = self.locals.getLastOrNull() 
            orelse return null;
        const done = if (local.depth) |d| d <= self.scopeDepth else false;
        if (done) return null;
        _ = self.locals.pop();
        return local.isCaptured;
    }
};

/// Define a single, uninitialized local on the top of the stack.
pub fn addLocal(self: *Compiler, name: Token) std.mem.Allocator.Error!void {
    const local = try self.locals.addOneBounded();
    local.name = name;
    local.depth = null;
    local.isCaptured = false;
}

/// Determine the position in the value stack where this local will sit.
/// If the incoming name is for an uninitialized local, an error is returned
/// indicating that the code is invalid (self-referential)
pub fn resolveLocal(self: *Compiler, name: Token) error{SelfReferentialLocal}!?u8 {
    var i = self.locals.items.len;
    while (i > 0) : (i -= 1) {
        const pos = i - 1;
        const local = self.locals.items[pos];
        if (std.mem.eql(u8, name.data, local.name.data)) {
            // capture var a = a;
            _ = local.depth orelse
                return error.SelfReferentialLocal;

            return @intCast(pos);
        }
    }
    return null;
}

pub fn resolveUpValue(self: *Compiler, name: Token) !?u8 {
    const parentCompiler = self.enclosing orelse return null;
    if (try parentCompiler.resolveLocal(name)) |local| {
        const l = &parentCompiler.locals.items[local];
        l.isCaptured = true;
        return try self.addUpValue(local, true);
    }
    if (try parentCompiler.resolveUpValue(name)) |uv| {
        return try self.addUpValue(uv, false);
    }
    return null;
}

pub fn addUpValue(self: *Compiler, loc: u8, isLocal: bool) !u8 {
    // First, check for an existing upvalue for this local.
    for (self.upvalues.items, 0..) |uv, i| {
        if (uv.index == loc and uv.isLocal == isLocal)
            return @intCast(i);
    }
    const l = self.upvalues.items.len;
    const u = try self.upvalues.addOneBounded();
    self.function.upvalueCount += 1;
    u.index = loc;
    u.isLocal = isLocal;
    // Return index of new upvalue
    return @intCast(l);
}

pub fn printLocals(self: *Compiler) void {
    std.debug.print("--- LOCALS {s} ---\n", .{self.function.name orelse "<script>"});
    for (self.locals.items) |l| {
        if (l.depth) |d| {
            std.debug.print("{s} {d}\n", .{l.name.data, d});
        } else {
            std.debug.print("{s} <uninitialized>\n", .{l.name.data});
        }
    }
}
