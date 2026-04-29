
const std = @import("std");
const inst = @import("inst.zig");

pub const InterpretResult = enum(u8) {
    Ok,
    CompileError,
    RuntimeError,
};

pub const VM = struct {
    alloc: std.mem.Allocator,
    chunk: *inst.Chunk,
    ip: usize,

    pub fn init(alloc: std.mem.Allocator) !VM {
        return .{
            .alloc = alloc,
            .chunk = undefined,
            .ip = undefined,
        };
    }

    pub fn deinit(_: *VM) void { }

    pub fn interpret(self: *VM, chunk: *inst.Chunk) !InterpretResult {
        self.chunk = chunk;
        self.ip = 0;
        return self.run();
    }

    fn run(self: *VM) !InterpretResult {
        const codePtr: [*]u8 = self.chunk.code.items.ptr;

        while (self.ip < self.chunk.len()) : (self.ip += 1) {
            switch (codePtr[self.ip]) {
                @intFromEnum(inst.OpCode.OP_RETURN) => 
                    return InterpretResult.Ok,
                @intFromEnum(inst.OpCode.OP_CONSTANT) => {
                    self.ip += 1;
                    const vLoc: usize = @intCast(codePtr[self.ip]);
                    const val = self.chunk.constants.values.items[vLoc];

                    std.debug.print("CONST: {d}\n", .{val});
                },
                else => {},
            }
        }
        return InterpretResult.RuntimeError;
    }
};
