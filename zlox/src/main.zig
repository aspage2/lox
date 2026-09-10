const std = @import("std");
const Io = std.Io;

const zlox = @import("zlox");

const inst = @import("inst.zig");
const vm = @import("vm.zig");
const Heap = @import("heap.zig");
const build_opts = @import("build_options");

test {
    std.testing.refAllDecls(@This());
}

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives
    // as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    const argv = try init.minimal.args.toSlice(arena);

    var machine: *vm.VM = try .init(arena, init.io);
    defer machine.deinit();

    switch (argv.len) {
        1 => try repl(arena, machine, init.io),
        2 => try runFile(
            arena,
            machine,
            try std.Io.Dir.cwd().openFile(init.io, argv[1], .{ .mode = .read_only }),
            init.io,
        ),
        3 => {
            if (std.mem.eql(u8, argv[1], "compile")) {
                const file = try std.Io.Dir.cwd().openFile(init.io, argv[2], .{ .mode = .read_only });
                var buf: [1024]u8 = undefined;
                var rd = file.reader(init.io, buf[0..]);
                const fileSize = try file.length(init.io);
                const source = try rd.interface.readAlloc(arena, fileSize);
                const hp: *Heap = try .init(arena);
                const func = try @import("parser.zig").compile(arena, source, hp) orelse std.process.exit(1);
                try func.chunk.disassemble("Script");
                hp.strings.pprint();
            } else {
                std.debug.print("Usage: ./lox compile [FNAME]", .{});
                std.process.exit(1);
            }
        },

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
        _ = machine.interpret(line) catch |err| blk: {
            switch (err) {
                vm.RuntimeError.StackEmpty => std.debug.print("ERROR: attempt to pop from an empty stack", .{}),
                else => return err,
            }
            break :blk vm.InterpretResult.RuntimeError;
        };
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
    switch (try machine.interpret(source)) {
        .CompileError => std.debug.print("Compiler error", .{}),
        .RuntimeError => std.debug.print("Runtime error", .{}),
        .Ok => {},
    }
}
