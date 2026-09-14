const std = @import("std");
const value = @import("value.zig");
const Heap = @import("heap.zig");

const Value = value.Value;
const NativeResult = value.NativeObj.NativeResult;

pub fn clock(io: std.Io, _: *Heap, _: u8, _: [*]Value) anyerror!NativeResult {
    const val = std.Io.Clock.now(.real, io);
    return .{ .success = .{ .Number = @floatFromInt(val.toSeconds()) } };
}

pub fn toString(_: std.Io, heap: *Heap, argc: u8, argv: [*]Value) anyerror!NativeResult {
    if (argc != 1) {
        const s: value.StringObj = "incorrect arity";
        const o = try heap.allocateString(s);
        return .{
            .failure = o.instance.String,
        };
    }
    const v = argv[0];
    switch (v) {
        .Number => |f| {
            var buf: [128]u8 = undefined;
            const rendered = try std.fmt.float.render(&buf, f, .{});
            const ret = try heap.allocateString(rendered);
            return .{ .success = ret.asValue() };
        },
        .Bool => |b| {
            const ret = try heap.allocateString(if (b) "true" else "false");
            return .{ .success = ret.asValue() };
        },
        .Nil => {
            const ret = heap.allocateString("NIL") catch @panic("out of memory");
            return .{ .success = ret.asValue() };
        },
        .Obj => |o| {
            switch (o.instance) {
                .String => return .{ .success = argv[0] },
                .Func => |f| {
                    if (f.name) |n| {
                        var buf: [256]u8 = undefined;
                        var wr = std.Io.Writer.fixed(&buf);
                        try wr.print("<function {s}>", .{n});
                        const ret = try heap.allocateString(wr.buffered());
                        return .{ .success = ret.asValue() };
                    } else {
                        const ret = try heap.allocateString("<script>");
                        return .{ .success = ret.asValue() };
                    }
                },
                .Closure => |c| {
                    const f = c.function;
                    if (f.name) |n| {
                        var buf: [256]u8 = undefined;
                        var wr = std.Io.Writer.fixed(&buf);
                        try wr.print("<function {s}>", .{n});
                        const ret = try heap.allocateString(wr.buffered());
                        return .{ .success = ret.asValue() };
                    } else {
                        const ret = try heap.allocateString("<script>");
                        return .{ .success = ret.asValue() };
                    }
                },
                .Upvalue => {
                    const ret = try heap.allocateString("<upvalue>");
                    return .{ .success = ret.asValue() };
                },
                .NativeFn => {
                    const ret = try heap.allocateString("<native function>");
                    return .{ .success = ret.asValue() };
                },
            }
        },
    }
}
