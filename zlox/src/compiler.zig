/// The compiler holds state related to function data & scopes.
const std = @import("std");

const scanner = @import("scanner.zig");
const Token = scanner.Token;
const value = @import("value.zig");

const Compiler = @This();

/// A stack entry.
pub const Local = struct {
    /// The token where this name was first seen
    name: Token,
    /// Scopedepth where this field was defined.
    /// uninitialized locals have a null depth to begin.
    depth: ?usize,
};

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

/// Scope depth of 0 represents the global scope.
scopeDepth: usize = 0,

function: *value.FuncObj = undefined,
funcType: FuncType,

const FuncType = enum { Script, Func };

pub fn init(alloc: std.mem.Allocator, funcType: FuncType) !Compiler {
    var ret: Compiler = .{.funcType = funcType};
    ret.locals = .initBuffer(&ret.localBuffer);
    ret.scopeDepth = 0;
    ret.function = try value.FuncObj.sentinelFunction(alloc);

    const local = ret.locals.addOneAssumeCapacity();
    local.depth = 0;
    local.name = .{ .data = "", .type = .Error, .line = 1 };
    return ret;
}

/// After a local's initializer is parsed, it is marked "initialized"
/// by the parser.
pub fn markInitialized(self: *Compiler) void {
    const l = self.locals.items.len;
    self.locals.items[l - 1].depth = self.scopeDepth;
}

/// Enter a scope
pub fn beginScope(self: *Compiler) void {
    self.scopeDepth += 1;
}

/// Exit a scope, calculating how many locals need to be popped from
/// the value stack on return.
pub fn endScope(self: *Compiler) u8 {
    var numDropped: u8 = 0;
    self.scopeDepth -= 1;
    while (self.locals.getLastOrNull()) |l| {
        const done = if (l.depth) |d| d <= self.scopeDepth else false;
        if (done) break;
        numDropped += 1;
        _ = self.locals.pop();
    }
    return numDropped;
}

/// Define a single, uninitialized local on the top of the stack.
pub fn addLocal(self: *Compiler, name: Token) std.mem.Allocator.Error!void {
    const local = try self.locals.addOneBounded();
    local.name = name;
    local.depth = null;
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
