const inst = @import("inst.zig");
const Heap = @import("heap.zig");
const std = @import("std");

const ValType = enum {
    Bool,
    Number,
    Nil,
    Obj,
};

pub const Value = union(ValType) {
    Bool: bool,
    Number: f32,
    Nil: void,
    Obj: Obj,

    pub fn expectType(self: Value, comptime typ: ValType) ?std.meta.fieldInfo(Value, typ).type {
        return switch (self) {
            inline else => |val, t| {
                if (t == typ) return val;
                return null;
            },
        };
    }

    pub fn isFalsey(self: Value) bool {
        return switch (self) {
            .Nil => true,
            .Bool => |b| !b,
            else => false,
        };
    }

    pub fn equals(self: Value, other: Value) bool {
        const myType = std.meta.activeTag(self);
        const otherType = std.meta.activeTag(other);

        if (myType != otherType) return false;

        return switch (myType) {
            .Bool => self.Bool == other.Bool,
            .Nil => true,
            .Number => self.Number == other.Number,
            .Obj => self.Obj.equals(other.Obj),
        };
    }
};

pub fn printValue(val: Value) void {
    switch (val) {
        .Nil => std.debug.print("NIL", .{}),
        .Number => |n| std.debug.print("{d}", .{n}),
        .Bool => |b| std.debug.print("{any}", .{b}),
        .Obj => |o| printObject(o),
    }
}

pub fn printObject(obj: Obj) void {
    switch (obj.inst) {
        .String => |s| std.debug.print("\"{s}\"", .{s}),
        .Func => |f| f.print(),
        .NativeFn => |n| std.debug.print("<native {s}>", .{n.name}),
    }
}

/// Obj is a wrapper type for heap-allocated objects.
pub const Obj = union(Obj.Type) {
    const Type = enum(u8) {
        String,
        Func,
        NativeFn,
    };
    String: StringObj,
    Func: *FuncObj,
    NativeFn: *NativeObj,

    fn equals(self: Obj, other: Obj) bool {
        switch (self.inst) {
            .String => |s| return std.mem.eql(u8, s, other.inst.String),
            else => return false,
        }
    }

    pub fn asValue(self: *Obj) Value {
        return .{ .Obj = self };
    }
};

/// As Zig has native support for slices, a stringobj
/// from the book is just a u8 slice.
pub const StringObj = []const u8;

/// A FuncObj represents a callable subroutine in a lox
/// program.
pub const FuncObj = struct {
    arity: u8,
    chunk: inst.Chunk,
    name: ?StringObj,

    pub fn sentinelFunction(alloc: std.mem.Allocator) !*FuncObj {
        return FuncObj.init(alloc, null, 0);
    }

    pub fn init(alloc: std.mem.Allocator, name: ?StringObj, arity: u8) !*FuncObj {
        const ret = try alloc.create(FuncObj);
        ret.arity = arity;
        ret.name = name;
        ret.chunk = try .init(alloc);
        return ret;
    }

    pub fn deinit(self: *FuncObj) void {
        self.chunk.deinit();
    }

    fn print(self: *FuncObj) void {
        if (self.name) |n| {
            std.debug.print("<func {s}>", .{n});
        } else {
            std.debug.print("<script>", .{});
        }
    }
};

pub const NativeObj = struct {
    name: []const u8 = "???",
    impl: Impl,

    pub const NativeResult = union(enum) {
        success: Value, failure: StringObj,
    };

    /// A NativeFn is a lox callable implemented in Zig.
    pub const Impl = *const fn(
        io: std.Io, heap: *Heap, argCount: u8, args: [*]Value,
    ) anyerror!NativeResult;
};

