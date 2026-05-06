const std = @import("std");
const Io = std.Io;

const zlox = @import("zlox");

const inst = @import("inst.zig");
const vm = @import("vm.zig");
const compiler = @import("compiler.zig");

test {
    std.testing.refAllDecls(@This());
}

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives
    // as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    const argv = try init.minimal.args.toSlice(arena);

    var machine: vm.VM = try .init(arena);
    defer machine.deinit();

    switch (argv.len) {
        1 => try repl(arena, &machine, init.io),
        2 => try runFile(
            arena,
            &machine,
            try std.Io.Dir.cwd().openFile(init.io, argv[1], .{ .mode = .read_only }),
            init.io,
        ),

        else => {
            std.debug.print("Usage: ./main [file]", .{});
            std.process.exit(1);
        },
    }
}

fn repl(_: std.mem.Allocator, machine: *vm.VM, io: std.Io) !void {
    const stdin = std.Io.File.stdin();
    var lineBuf: [1024]u8 = undefined;
    var rd = stdin.readerStreaming(io, lineBuf[0..]);
    std.debug.print("> ", .{});
    while (try rd.interface.takeDelimiter('\n')) |line| {
        if (std.mem.eql(u8, line, "exit")) {
            return;
        }
        _ = try machine.interpret(line);
        std.debug.print("> ", .{});
    }
}

fn runFile(
    alloc: std.mem.Allocator,
    machine: *vm.VM,
    file: std.Io.File,
    io: std.Io,
) !void {
    var buf: [1024]u8 = undefined;
    var rd = file.reader(io, buf[0..]);

    const fileSize = try file.length(io);
    const source = try rd.interface.readAlloc(alloc, fileSize);
    defer alloc.free(source);
    _ = try machine.interpret(source);
}
