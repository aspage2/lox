
const std = @import("std");
const value = @import("value.zig");
const Heap = @import("heap.zig");

const Value = value.Value;

pub fn clock(io: std.Io, _: *Heap, _: u8, _: [*]Value) Value {
    const val = std.Io.Clock.now(.real, io);
    return .{ .Number = @floatFromInt(val.toSeconds()) };
}

pub fn toString(_: std.Io, heap: *Heap, argc: u8, argv: [*]Value) Value {
    if (argc != 1) @panic("expect 1 arg");
    const v = argv[0];
    switch (v) {
        .Number => |f| {
            var buf: [128]u8 = undefined;
            const rendered = std.fmt.float.render(&buf, f, .{})
                catch @panic("given too small a buffer");
            const ret = heap.allocateString(rendered) 
                catch @panic("out of memory.");
            return ret.asValue();
        },
        .Bool => |b| {
            const ret = heap.allocateString(if (b) "true" else "false")
                catch @panic("out of memory");
            return ret.asValue();
        },
        .Nil => {
            const ret = heap.allocateString("NIL")
                catch @panic("out of memory");
            return ret.asValue();
        },
        .Obj => |o| {
            switch (o.inst) {
                .String => return argv[0],
                .Func => |f| {
                    if (f.name) |n| {
                        var buf: [256]u8 = undefined;
                        var wr = std.Io.Writer.fixed(&buf);
                        wr.print("<function {s}>", .{n})
                            catch @panic("buffer to small");
                        const ret = heap.allocateString(wr.buffered())
                            catch @panic("out of memory");
                        return ret.asValue();
                    } else {
                        const ret = heap.allocateString("<script>")
                            catch @panic("out of memory");
                        return ret.asValue();
                    }
                },
                .NativeFn => {
                    const ret = heap.allocateString("<native function>")
                        catch @panic("out of memory");
                    return ret.asValue();
                },
            }
        },
    }
}
