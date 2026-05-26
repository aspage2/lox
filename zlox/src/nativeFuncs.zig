
const std = @import("std");
const value = @import("value.zig");

const Value = value.Value;

pub fn clock(io: std.Io, _: u8, _: [*]Value) Value {
    const val = std.Io.Clock.now(.real, io);
    return .{ .Number = @floatFromInt(val.toSeconds()) };
}

