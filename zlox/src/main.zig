const std = @import("std");
const Io = std.Io;

const zlox = @import("zlox");

const inst = @import("inst.zig");
const vm  = @import("vm.zig");


pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});


    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    var c: inst.Chunk = try .init(arena);
    defer c.deinit();

    var machine: vm.VM = try .init(arena);
    defer machine.deinit();

    const valIndex = try c.addConstant(1.11);

    try c.putOpCode(inst.OpCode.OP_CONSTANT, 1);
    try c.put(@intCast(valIndex), 1);

    try c.putOpCode(inst.OpCode.OP_RETURN, 1);

    _ = try c.disassemble("My Chunk");

    std.debug.print("Running Interpreter\n", .{});
    const res = try machine.interpret(&c);

    std.debug.print("{}\n", .{res});
}

