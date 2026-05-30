const std = @import("std");

const inst = @import("inst.zig");
const value = @import("value.zig");
const Heap = @import("heap.zig");

const compile = @import("parser.zig").compile;

const nativeFns = @import("nativeFuncs.zig");

const build_opts = @import("build_options");

pub const InterpretResult = enum(u8) {
    Ok,
    CompileError,
    RuntimeError,
};

pub const RuntimeError = error{
    StackEmpty,
};

/// Max depth of the call stack (max recursion depth)
const FramesMax: usize = 64;

/// Max depth of the VM operation stack
const StackMax: usize = (std.math.maxInt(u8) + 1) * 64;

const CallFrame = struct {
    function: *value.FuncObj,
    ip: usize,
    slots: [*]value.Value,
    
    fn take_operand(self: *CallFrame, comptime T: type) T {
        const chunk = self.function.chunk;
        const code = chunk.code;
        const constants = chunk.constants;
        switch (T) {
            u8 => {
                self.ip += 1;
                return code.items.ptr[self.ip];
            },
            u16 => {
                self.ip += 2;
                const x = code.items[self.ip - 1 .. self.ip + 1];
                return std.mem.readInt(u16, @ptrCast(x), .little);
            },
            value.Value => {
                self.ip += 1;
                const idx = code.items.ptr[self.ip];
                return constants.items.ptr[idx];
            },
            value.StringObj => {
                self.ip += 1;
                const idx = code.items.ptr[self.ip];
                return constants.items.ptr[idx].Obj.String;
            },
            else => @panic("unsupported type"),
        }
    }
};

pub const VM = struct {
    alloc: std.mem.Allocator,
    io: std.Io,

    frameBuf: [FramesMax]CallFrame = undefined,
    frames: std.ArrayList(CallFrame) = undefined,

    stack: [StackMax]value.Value,
    stackSize: usize,

    heap: *Heap,

    globals: std.array_hash_map.String(value.Value),

    pub fn init(alloc: std.mem.Allocator, io: std.Io) !*VM {
        const ret = try alloc.create(VM);
        ret.* = .{
            .io = io,
            .alloc = alloc,
            .stackSize = 0,
            .stack = undefined,
            .globals = try .init(alloc, &.{}, &.{}),
            .heap = try .init(alloc),
        };
        ret.frames = .initBuffer(&ret.frameBuf);
        try ret.defineNative("clock", nativeFns.clock);
        try ret.defineNative("toString", nativeFns.toString);
        return ret;
    }

    pub fn stackPush(self: *VM, val: value.Value) !void {
        self.stack[self.stackSize] = val;
        self.stackSize += 1;
    }

    pub fn stackPop(self: *VM) RuntimeError!value.Value {
        if (self.stackSize == 0) return error.StackEmpty;
        const ret = self.stack[self.stackSize - 1];
        self.stackSize -= 1;
        return ret;
    }

    fn stackReset(self: *VM) void {
        self.stackSize = 0;
    }

    fn stackDrop(self: *VM, n: usize) void {
        if (self.stackSize < n) self.stackSize = 0;
        self.stackSize -= n;
    }

    pub fn deinit(self: *VM) void {
        self.globals.deinit(self.alloc);
        self.heap.deinit();
        self.alloc.destroy(self.heap);
        self.alloc.destroy(self);
    }

    pub fn interpret(self: *VM, source: []const u8) !InterpretResult {

        const func = try compile(self.alloc, source, self.heap)
            orelse return .CompileError;

        if (build_opts.lox_debug) {
            std.debug.print("\x1b[2;37m", .{});
            self.heap.strings.pprint();
            std.debug.print("\x1b[0m", .{});
        }

        try self.stackPush(.{ .Obj = .{ .Func = func } });

        const frame = self.frames.addOneAssumeCapacity();
        frame.function = func;
        frame.ip = 0;
        frame.slots = &self.stack;

        if (build_opts.lox_debug) {
            std.debug.print("\x1b[2;37m--- RUNNING ---\n\x1b[0m", .{});
        }
        const res = self.run();
        if (build_opts.lox_debug) {
            std.debug.print("\x1b[2;37m", .{});
            self.heap.strings.pprint();
            std.debug.print("\x1b[0m", .{});
        }
        return res;
    }


    fn run(self: *VM) !InterpretResult {
        var frame = &self.frames.items[self.frames.items.len-1];
        var codePtr: [*]u8 = frame.function.chunk.code.items.ptr;

        while (frame.ip < frame.function.chunk.len()) {
            if (comptime build_opts.lox_debug) {
                std.debug.print("\x1b[2;37m", .{});
                std.debug.print("          ", .{});
                for (0..self.stackSize) |i| {
                    std.debug.print("[ ", .{});
                    value.printValue(self.stack[i]);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
                _ = try frame.function.chunk.disassembleInstruction(frame.ip);
                std.debug.print("\x1b[0m", .{});
            }
            switch (codePtr[frame.ip]) {
                @intFromEnum(inst.OpCode.Return) => {
                    const result = try self.stackPop();
                    const df = self.frames.pop().?;
                    if (self.frames.items.len == 0) {
                        _ = try self.stackPop();
                        return .Ok;
                    }
                    self.stackSize -= df.function.arity + 1;
                    try self.stackPush(result);
                    frame = &self.frames.items[self.frames.items.len - 1];
                    codePtr = frame.function.chunk.code.items.ptr;
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Constant) => {
                    const vLoc: usize = @intCast(frame.take_operand(u8));
                    const val = frame.function.chunk.constants.items[vLoc];
                    try self.stackPush(val);
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Negate) => {
                    const val = self.stackPeek(0).?;
                    switch (val) {
                        .Number => |n| {
                            _ = try self.stackPop();
                            try self.stackPush(.{ .Number = -n });
                        },
                        else => {
                            self.runtimeError("Operand must be a number.", .{});
                            return InterpretResult.RuntimeError;
                        },
                    }
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Add) => {
                    const b = self.stackPeek(0).?;
                    switch (b) {
                        .Number => |bn| {
                            const an = self.stackPeek(1).?.expectType(.Number) orelse {
                                self.runtimeError("Operands must be numbers", .{});
                                return InterpretResult.RuntimeError;
                            };
                            self.stackDrop(2);
                            try self.stackPush(.{ .Number = an + bn });
                        },
                        .Obj => |bo| {
                            const ao = self.stackPeek(1).?.expectType(.Obj) orelse {
                                self.runtimeError("Operands for concat must be strings", .{});
                                return InterpretResult.RuntimeError;
                            };
                            const boType = std.meta.activeTag(bo);
                            const aoType = std.meta.activeTag(ao);
                            if (boType != aoType or boType != .String) {
                                self.runtimeError("Operands for concat must be strings", .{});
                                return InterpretResult.RuntimeError;
                            }
                            self.stackDrop(2);
                            const newData = try std.mem.concat(
                                self.alloc,
                                u8,
                                &.{ ao.String, bo.String },
                            );
                            defer self.alloc.free(newData);
                            const s = try self.heap.takeString(self.alloc, newData);
                            try self.stackPush(.{.Obj = .{ .String = s } });
                        },
                        else => unreachable,
                    }
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Subtract) => {
                    const b = self.stackPeek(0).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    const a = self.stackPeek(1).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    self.stackDrop(2);
                    try self.stackPush(.{ .Number = a - b });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Multiply) => {
                    const b = self.stackPeek(0).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    const a = self.stackPeek(1).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    self.stackDrop(2);
                    try self.stackPush(.{ .Number = a * b });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Divide) => {
                    const b = self.stackPeek(0).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    const a = self.stackPeek(1).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    self.stackDrop(2);
                    try self.stackPush(.{ .Number = a / b });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Nil) => {
                    try self.stackPush(.Nil);
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.True) => {
                    try self.stackPush(.{ .Bool = true });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.False) => {
                    try self.stackPush(.{ .Bool = false });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Not) => {
                    const v = try self.stackPop();
                    try self.stackPush(.{ .Bool = v.isFalsey() });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Equal) => {
                    const a = try self.stackPop();
                    const b = try self.stackPop();
                    try self.stackPush(.{ .Bool = a.equals(b) });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Less) => {
                    const b = self.stackPeek(0).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    const a = self.stackPeek(1).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    self.stackDrop(2);
                    try self.stackPush(.{ .Bool = a < b });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Greater) => {
                    const b = self.stackPeek(0).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    const a = self.stackPeek(1).?.expectType(.Number) orelse {
                        self.runtimeError("Operands must be numbers", .{});
                        return InterpretResult.RuntimeError;
                    };
                    self.stackDrop(2);
                    try self.stackPush(.{ .Bool = a > b });
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Print) => {
                    const v = try self.stackPop();
                    value.printValue(v);
                    std.debug.print("\n", .{});
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Pop) => {
                    _ = try self.stackPop();
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.DefineGlobal) => {
                    const globalName = frame.take_operand(value.StringObj);
                    const val = self.stackPeek(0).?;
                    try self.globals.put(self.alloc, globalName, val);
                    self.stackDrop(1);
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.GetGlobal) => {
                    const name = frame.take_operand(value.StringObj);

                    if (self.globals.get(name)) |val| {
                        try self.stackPush(val);
                    } else {
                        self.runtimeError("Undefined variable: {s}", .{name});
                        return .RuntimeError;
                    }
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.SetGlobal) => {
                    const name = frame.take_operand(value.StringObj);
                    if (self.globals.getEntry(name)) |ent| {
                        ent.value_ptr.* = self.stackPeek(0).?;
                    } else {
                        self.runtimeError("Undefined variable: {s}", .{name});
                        return .RuntimeError;
                    }
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.SetLocal) => {
                    const slot = frame.take_operand(u8);
                    frame.slots[slot] = self.stackPeek(0).?;
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.GetLocal) => {
                    const slot = frame.take_operand(u8);
                    try self.stackPush(frame.slots[slot]);
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.JumpIfFalse) => {
                    const offset = frame.take_operand(u16);
                    const top = self.stackPeek(0).?;
                    if (top.isFalsey()) {
                        frame.ip += offset;
                    }
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Jump) => {
                    const offset = frame.take_operand(u16);
                    frame.ip += offset;
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Loop) => {
                    const offset = frame.take_operand(u16);
                    frame.ip -= offset;
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Call) => blk: {
                    const argCount = frame.take_operand(u8);
                    const val = self.stackPeek(argCount).?;
                    switch (val) {
                        .Obj => |o| switch(o) {
                            .Func => |f| {
                                if (!self.call(f, argCount)) {
                                    return .RuntimeError;
                                }
                                frame = &self.frames.items[self.frames.items.len-1];
                                codePtr = frame.function.chunk.code.items.ptr;
                                break :blk;
                            },
                            .NativeFn => |n| {
                                const result = n.impl(
                                    self.io,
                                    self.heap,
                                    argCount, 
                                    @as([*]value.Value, &self.stack) + self.stackSize - argCount,
                                ) catch |e| {
                                    self.runtimeError("{any}", .{e});
                                    return .RuntimeError;
                                };
                                switch (result) {
                                    .success => |v| {
                                        self.stackSize -= argCount + 1;
                                        try self.stackPush(v);
                                    },
                                    .failure => |msg| {
                                        self.runtimeError("Error during native call: {s}", .{msg});
                                        return .RuntimeError;
                                    },
                                }
                                frame.ip += 1;
                                break :blk;
                            },
                            else => {},
                        },
                        else => {},
                    }

                    self.runtimeError("Attempt to call non-function value {any}", .{val});
                    return .RuntimeError;
                },
                else => {},
            }
        }
        return InterpretResult.RuntimeError;
    }

    fn call(self: *VM, func: *value.FuncObj, argCount: u8) bool {
        if (argCount != func.arity) {
            self.runtimeError("Expect {d} args, got {d}", .{func.arity, argCount});
            return false;
        }

        if (self.frames.items.len == FramesMax) {
            self.runtimeError("Stack overflow", .{});
        }
        const newFrame = self.frames.addOneAssumeCapacity();
        newFrame.function = func;
        newFrame.ip = 0;
        newFrame.slots = @as([*]value.Value, &self.stack) + (self.stackSize - 1 - argCount);

        return true;
    }

    fn stackPeek(self: *VM, depth: usize) ?value.Value {
        if (self.stackSize <= depth) return null;
        return self.stack[self.stackSize - 1 - depth];
    }

    fn runtimeError(self: *VM, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(fmt, args);
        var i = self.frames.items.len;
        while (i > 0) : (i -= 1) {
            const frame = &self.frames.items[i-1];
            const chunk = frame.function.chunk;

            var l: u32 = 0;
            if (chunk.getLine(frame.ip)) |line| {
                l = line;
            } else |e| {
                std.debug.print("err getting line: {any}\n", .{e});
            }
            std.debug.print("\n[line {d}] in ", .{l});
            if (frame.function.name) |n| {
                std.debug.print("in {s}\n", .{n});
            } else {
                std.debug.print("script\n", .{});
            }

        }
        self.stackReset();
    }

    pub fn defineNative(self: *VM, comptime name: []const u8, comptime func: value.NativeObj.Impl) !void {
        const no = value.Obj{.NativeFn = try self.heap.newNative(name, func)};
        const val: value.Value = no.asValue();
        try self.stackPush(val);
        try self.globals.put(self.alloc, name, val);
        _ = try self.stackPop();
    }
};

