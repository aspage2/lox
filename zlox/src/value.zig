const std = @import("std");

pub const Value = f64;

pub fn printValue(val: Value) void {
    std.debug.print("{any}", .{val});
}

pub const ValType = enum {
    Bool,
    Number,
    String,
};

pub const Val = union(ValType) {
    Bool: bool,
    Number: f32,
    String: []const u8,
    Nil: void,
};
