const std = @import("std");

const inst = @import("inst.zig");
const value = @import("value.zig");

const compiler = @import("compiler.zig");

const build_opts = @import("build_options");

pub const InterpretResult = enum(u8) {
    Ok,
    CompileError,
    RuntimeError,
};

const StackMax: usize = 256;

pub const VM = struct {
    alloc: std.mem.Allocator,
    chunk: *inst.Chunk,
    ip: usize,

    stack: [StackMax]value.Value,
    stackSize: usize,

    pub fn init(alloc: std.mem.Allocator) !VM {
        return .{
            .alloc = alloc,
            .chunk = undefined,
            .ip = undefined,
            .stackSize = 0,
            .stack = undefined,
        };
    }

    pub fn stackPush(self: *VM, val: value.Value) !void {
        self.stack[self.stackSize] = val;
        self.stackSize += 1;
    }

    pub fn stackPop(self: *VM) !value.Value {
        const ret = self.stack[self.stackSize - 1];
        self.stackSize -= 1;
        return ret;
    }

    pub fn deinit(_: *VM) void {
    }

    pub fn interpret(self: *VM, source: []const u8) !InterpretResult {
        var chunk: inst.Chunk = try .init(self.alloc);
        defer chunk.deinit();

        try compiler.compile(source, &chunk);

        self.chunk = &chunk;
        self.ip = 0;
        if (build_opts.lox_debug) {
            std.debug.print("--- RUNNING ---\n", .{});
        }
        return self.run();
    }

    fn run(self: *VM) !InterpretResult {
        const codePtr: [*]u8 = self.chunk.code.items.ptr;

        while (self.ip < self.chunk.len()) : (self.ip += 1) {
            if (comptime build_opts.lox_debug) {
                std.debug.print("          ", .{});
                for (0..self.stackSize) |i| {
                    std.debug.print("[ ", .{});
                    value.printValue(self.stack[i]);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
                _ = try self.chunk.disassembleInstruction(self.ip);
            }
            switch (codePtr[self.ip]) {
                @intFromEnum(inst.OpCode.Return) => {
                    // FixMe: Implement return semantics
                    std.debug.print("Returning value: ", .{});
                    value.printValue(try self.stackPop());
                    std.debug.print("\n", .{});
                    return InterpretResult.Ok;
                },
                @intFromEnum(inst.OpCode.Constant) => {
                    self.ip += 1;
                    const vLoc: usize = @intCast(codePtr[self.ip]);
                    const val = self.chunk.constants.items[vLoc];
                    try self.stackPush(val);
                },
                @intFromEnum(inst.OpCode.Negate) => {
                    const val = try self.stackPop();
                    try self.stackPush(-val);
                },
                @intFromEnum(inst.OpCode.Add) => {
                    const b = try self.stackPop();
                    const a = try self.stackPop();
                    try self.stackPush(a + b);
                },
                @intFromEnum(inst.OpCode.Subtract) => {
                    const b = try self.stackPop();
                    const a = try self.stackPop();
                    try self.stackPush(a - b);
                },
                @intFromEnum(inst.OpCode.Multiply) => {
                    const b = try self.stackPop();
                    const a = try self.stackPop();
                    try self.stackPush(a * b);
                },
                @intFromEnum(inst.OpCode.Divide) => {
                    const b = try self.stackPop();
                    const a = try self.stackPop();
                    try self.stackPush(a / b);
                },
                else => {},
            }
        }
        return InterpretResult.RuntimeError;
    }
};
