
const std = @import("std");
const value = @import("value.zig");
const Heap = @import("heap.zig");

const Value = value.Value;
const NativeResult = value.NativeResult;

pub fn clock(io: std.Io, _: *Heap, _: u8, _: [*]Value) anyerror!NativeResult {
    const val = std.Io.Clock.now(.real, io);
    return .{ .success = .{.Number = @floatFromInt(val.toSeconds()) } };
}

pub fn toString(_: std.Io, heap: *Heap, argc: u8, argv: [*]Value) anyerror!NativeResult {
    if (argc != 1) return .{
        .failure = try heap.strings.make("incorrect arity"),
    };
    const v = argv[0];
    switch (v) {
        .Number => |f| {
            var buf: [128]u8 = undefined;
            const rendered = try std.fmt.float.render(&buf, f, .{});
            const ret = try heap.allocateString(rendered);
            return .{.success = ret.asValue()};
        },
        .Bool => |b| {
            const ret = try heap.allocateString(if (b) "true" else "false");
            return .{.success = ret.asValue()};
        },
        .Nil => {
            const ret = heap.allocateString("NIL")
                catch @panic("out of memory");
            return .{.success = ret.asValue()};
        },
        .Obj => |o| {
            switch (o.inst) {
                .String => return .{.success = argv[0]},
                .Func => |f| {
                    if (f.name) |n| {
                        var buf: [256]u8 = undefined;
                        var wr = std.Io.Writer.fixed(&buf);
                        try wr.print("<function {s}>", .{n});
                        const ret = try heap.allocateString(wr.buffered());
                        return .{.success = ret.asValue()};
                    } else {
                        const ret = try heap.allocateString("<script>");
                        return .{.success = ret.asValue()};
                    }
                },
                .NativeFn => {
                    const ret = try heap.allocateString("<native function>");
                    return .{.success = ret.asValue()};
                },
            }
        },
    }
}
