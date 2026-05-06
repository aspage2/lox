const std = @import("std");

pub const ValType = enum {
    Bool,
    Number,
    String,
    Nil,
};

pub const ValueError = error{
    UnexpectedType,
};

pub const Value = union(ValType) {
    Bool: bool,
    Number: f32,
    String: []const u8,
    Nil: void,

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
            else => false,
        };
    }
};

pub fn printValue(val: Value) void {
    switch (val) {
        .Nil => std.debug.print("NIL", .{}),
        .String => |s| std.debug.print("\"{s}\"", .{s}),
        .Number => |n| std.debug.print("{d}", .{n}),
        .Bool => |b| std.debug.print("{any}", .{b}),
    }
}
