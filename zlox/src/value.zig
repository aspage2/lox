
const std = @import("std");

pub const Value = f64;

pub const ValueArray = struct {
    alloc: std.mem.Allocator,
    values: std.ArrayList(Value),

    pub fn init(alloc: std.mem.Allocator) !ValueArray {
        return .{
            .alloc = alloc,
            .values = try .initCapacity(alloc, 8),
        };
    }

    pub fn deinit(self: *ValueArray) void {
        self.values.deinit(self.alloc);
    }

    pub fn put(self: *ValueArray, val: Value) !void {
        return self.values.append(self.alloc, val);
    }

    pub inline fn len(self: *ValueArray) usize {
        return self.values.items.len;
    }
};
