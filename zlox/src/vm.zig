const std = @import("std");

const inst = @import("inst.zig");
const value = @import("value.zig");
const Heap = @import("heap.zig");

const parser = @import("parser.zig");

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
    closurePtr: *value.Obj,
    closure: *value.ClosureObj,
    ip: usize,
    slots: [*]value.Value,

    fn take_operand(self: *CallFrame, comptime T: type) T {
        const chunk = self.closure.function.chunk;
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
                return constants.items.ptr[idx].Obj.instance.String;
            },
            *value.FuncObj => {
                self.ip += 1;
                const idx = code.items.ptr[self.ip];
                return constants.items.ptr[idx].Obj.instance.Func;
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

    stack: [StackMax]value.Value = undefined,
    stackTop: [*]value.Value = undefined,
    stackBottom: [*]value.Value = undefined,

    openUpvalues: ?*value.UpvalueObj,

    heap: *Heap,

    globals: std.array_hash_map.String(value.Value),

    pub fn init(alloc: std.mem.Allocator, io: std.Io) !*VM {
        const ret = try alloc.create(VM);
        ret.* = .{
            .io = io,
            .alloc = alloc,
            .globals = try .init(alloc, &.{}, &.{}),
            .heap = try .init(alloc),
            .openUpvalues = null,
        };
        ret.frames = .initBuffer(&ret.frameBuf);
        ret.stackTop = &ret.stack;
        ret.stackBottom = &ret.stack;
        try ret.defineNative("clock", nativeFns.clock);
        try ret.defineNative("toString", nativeFns.toString);
        return ret;
    }

    pub fn stackPush(self: *VM, val: value.Value) !void {
        self.stackTop[0] = val;
        self.stackTop += 1;
    }

    fn stackPeek(self: *VM, depth: usize) ?value.Value {
        var st = self.stackTop - depth;
        if (st == self.stackBottom)
            return null;
        st -= 1;
        return st[0];
    }

    pub fn stackPop(self: *VM) RuntimeError!value.Value {
        if (self.stackTop == self.stackBottom)
            return error.StackEmpty;
        self.stackTop -= 1;
        return self.stackTop[0];
    }

    fn stackReset(self: *VM) void {
        self.stackTop = self.stackBottom;
    }

    fn stackDrop(self: *VM, n: usize) void {
        if (self.stackTop - self.stackBottom < n) {
            self.stackTop = self.stackBottom;
        } else {
            self.stackTop -= n;
        }
    }

    pub fn deinit(self: *VM) void {
        self.globals.deinit(self.alloc);
        self.heap.deinit();
        self.alloc.destroy(self.heap);
        self.alloc.destroy(self);
    }

    /// Compile and run the provided source code.
    pub fn interpret(self: *VM, source: []const u8) !InterpretResult {
        const func = try parser.compile(self.alloc, source, self.heap) orelse return .CompileError;

        if (build_opts.lox_debug) {
            std.debug.print("\x1b[2;37m", .{});
            self.heap.strings.pprint();
            std.debug.print("\x1b[0m", .{});
        }

        try self.stackPush(func.asValue());

        const frame = self.frames.addOneAssumeCapacity();
        const closure = try self.heap.newClosure(func.instance.Func);
        // Pop function obj
        _ = try self.stackPop();
        try self.stackPush(closure.asValue());
        frame.closurePtr = closure;
        frame.closure = closure.instance.Closure;
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
        var frame = &self.frames.items[self.frames.items.len - 1];
        var codePtr: [*]u8 = frame.closure.function.chunk.code.items.ptr;

        while (frame.ip < frame.closure.function.chunk.len()) {
            if (comptime build_opts.lox_debug) {
                std.debug.print("\x1b[2;37m", .{});
                std.debug.print("          ", .{});
                var ptr: [*]value.Value = &self.stack;
                while (ptr != self.stackTop) : (ptr += 1) {
                    std.debug.print("[ ", .{});
                    value.printValue(ptr[0]);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
                _ = try frame.closure.function.chunk.disassembleInstruction(frame.ip);
                std.debug.print("\x1b[0m", .{});
            }
            switch (codePtr[frame.ip]) {
                @intFromEnum(inst.OpCode.Return) => {
                    const result = try self.stackPop();
                    self.closeUpvalues(self.frames.items[self.frames.items.len - 1].slots);
                    const df = self.frames.pop().?;
                    if (self.frames.items.len == 0) {
                        _ = try self.stackPop();
                        return .Ok;
                    }
                    self.stackTop = df.slots;
                    try self.stackPush(result);
                    frame = &self.frames.items[self.frames.items.len - 1];
                    codePtr = frame.closure.function.chunk.code.items.ptr;
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.Constant) => {
                    const vLoc: usize = @intCast(frame.take_operand(u8));
                    const val = frame.closure.function.chunk.constants.items[vLoc];
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
                            const boType = std.meta.activeTag(bo.instance);
                            const aoType = std.meta.activeTag(ao.instance);
                            if (boType != aoType or boType != .String) {
                                self.runtimeError("Operands for concat must be strings", .{});
                                return InterpretResult.RuntimeError;
                            }
                            self.stackDrop(2);
                            const newData = try std.mem.concat(
                                self.alloc,
                                u8,
                                &.{ ao.instance.String, bo.instance.String },
                            );
                            const s = try self.heap.takeString(self.alloc, newData);
                            try self.stackPush(s.asValue());
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
                    // Calling convention for expression: my_func(arg1, arg2, arg3);
                    // when my_func is a closure (i.e. a function definition)
                    //
                    // PUSH my_func closure object
                    // {evaluate arg1 expression}
                    // {evaluate arg2 expression}
                    // {evaluate arg3 expression}
                    // CALL 3
                    //
                    // At the point that the VM reads CALL 3, the stack looks like this:
                    // +-----+---------+------+------+------+
                    // | ... | my_func | arg1 | arg2 | arg3 |
                    // +-----+---------+------+------+------+
                    //
                    // The VM will first load the implementation of my_func from the stack.
                    //
                    // --- if the implementation is a LOX CLOSURE OBJECT ---
                    // * Lox creates a new call frame in its own call stack.
                    // * The closure object is just the `my_func` object on the stack.
                    // * The frame's stack window starts at the position of `my_func` in the stack
                    //
                    // Afterwards, the VM operates from the new frame and the stack looks like this:
                    // +---------+------+------+------+
                    // | my_func | arg1 | arg2 | arg3 |
                    // +---------+------+------+------+
                    //
                    // The closure object is pre-populated with local refs for each argument.
                    // During compilation, each variable expression which corresponds to a
                    // function parameter is referenced as that particular local.
                    //
                    // --- if the implementation is a NATIVE ZIG FUNCTION ---
                    // The function implementation is invoked with the raw parameter list.
                    // no stack entry is created because the function runs right here and now.
                    const argCount = frame.take_operand(u8);
                    const val = self.stackPeek(argCount).?;
                    switch (val) {
                        .Obj => |o| switch (o.instance) {
                            .Closure => |c| {
                                if (!self.call(c, argCount)) {
                                    return .RuntimeError;
                                }
                                frame = &self.frames.items[self.frames.items.len - 1];
                                codePtr = frame.closure.function.chunk.code.items.ptr;
                                break :blk;
                            },
                            .NativeFn => |n| {
                                const result = n.impl(
                                    self.io,
                                    self.heap,
                                    argCount,
                                    self.stackTop - argCount,
                                ) catch |e| {
                                    self.runtimeError("{any}", .{e});
                                    return .RuntimeError;
                                };
                                switch (result) {
                                    .success => |v| {
                                        self.stackTop -= argCount + 1;
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
                @intFromEnum(inst.OpCode.Closure) => {
                    // Push a closure object onto the stack.
                    //
                    // The closure object receives the function definition
                    // from the chunk constants. Then, it resolves the pointer
                    // references to the correct upvalues.
                    const f = frame.take_operand(*value.FuncObj);
                    const c = try self.heap.newClosure(f);
                    try self.stackPush(c.asValue());
                    for (c.instance.Closure.upvalues.items) |*uv| {
                        const isLocal = frame.take_operand(u8) == 1;
                        const index = frame.take_operand(u8);
                        if (isLocal) {
                            uv.* = try self.captureUpvalue(frame.slots + index);
                        } else {
                            uv.* = frame.closure.upvalues.items[index];
                        }
                    }
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.GetUpValue) => {
                    const slot = frame.take_operand(u8);
                    const v = frame.closure.upvalues.items[slot].location.*;
                    try self.stackPush(v);
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.SetUpValue) => {
                    const slot = frame.take_operand(u8);
                    frame.closure.upvalues.items[slot].location.* =
                        self.stackPeek(0) orelse {
                            self.runtimeError("FATAL: empty stack", .{});
                            return .RuntimeError;
                        };
                    frame.ip += 1;
                },
                @intFromEnum(inst.OpCode.CloseUpvalue) => {
                    self.closeUpvalues(self.stackTop - 1);
                    _ = try self.stackPop();
                },
                else => {},
            }
        }
        return InterpretResult.RuntimeError;
    }

    fn closeUpvalues(self: *VM, loc: [*]value.Value) void {
        while (self.openUpvalues) |openUV| {
            const openLoc: [*]value.Value = @ptrCast(openUV.location);
            if (openLoc - self.stackBottom < loc - self.stackBottom) break;
            // Copy the stack value to the closure slot
            openUV.closedValue = openUV.location.*;
            openUV.location = &openUV.closedValue;
            self.openUpvalues = openUV.next;
        }
    }

    fn captureUpvalue(self: *VM, v: [*]value.Value) !*value.UpvalueObj {
        const vLoc = v - self.stackBottom;
        var prev: ?*value.UpvalueObj = null;
        var maybeUv: ?*value.UpvalueObj = self.openUpvalues;
        while (maybeUv) |uv| {
            const uvLoc = uv.location - self.stackBottom;
            if (uvLoc <= vLoc) break;
            prev = maybeUv;
            maybeUv = uv.next;
        }
        if (maybeUv) |uv| {
            const loc: [*]value.Value = @ptrCast(uv.location);
            if (loc == v) return uv;
        }

        const created = try self.heap.newUpvalue(@ptrCast(v));
        const uv = created.instance.Upvalue;
        created.instance.Upvalue.next = maybeUv;
        if (prev) |yesPrev| {
            yesPrev.next = uv;
        } else {
            self.openUpvalues = uv;
        }
        return uv;
    }

    /// Set up the interpreter to execute the provided closure definition.
    fn call(self: *VM, closure: *value.ClosureObj, argCount: u8) bool {
        if (argCount != closure.function.arity) {
            self.runtimeError("Expect {d} args, got {d}", .{ closure.function.arity, argCount });
            return false;
        }

        if (self.frames.items.len == FramesMax) {
            self.runtimeError("Stack overflow", .{});
        }
        const newFrame = self.frames.addOneAssumeCapacity();
        newFrame.closure = closure;
        newFrame.ip = 0;
        newFrame.slots = self.stackTop - argCount - 1;

        return true;
    }

    fn runtimeError(self: *VM, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(fmt, args);
        var i = self.frames.items.len;
        while (i > 0) : (i -= 1) {
            const frame = &self.frames.items[i - 1];
            const chunk = frame.closure.function.chunk;

            var l: u32 = 0;
            if (chunk.getLine(frame.ip)) |line| {
                l = line;
            } else |e| {
                std.debug.print("err getting line: {any}\n", .{e});
            }
            std.debug.print("\n[line {d}] in ", .{l});
            if (frame.closure.function.name) |n| {
                std.debug.print("in {s}\n", .{n});
            } else {
                std.debug.print("script\n", .{});
            }
        }
        self.stackReset();
    }

    pub fn defineNative(self: *VM, comptime name: []const u8, comptime func: value.NativeObj.Impl) !void {
        const no = try self.heap.newNative(name, func);
        const val: value.Value = no.asValue();
        try self.stackPush(val);
        try self.globals.put(self.alloc, name, val);
        _ = try self.stackPop();
    }
};

const testing = std.testing;

fn simpleScript() !struct { machine: *VM, scriptClosure: *value.ClosureObj } {
    const m: *VM = try .init(testing.allocator, testing.io);
    const fo = try m.heap.newFunction();
    const co = try m.heap.newClosure(fo);
    const f = m.frames.addOneAssumeCapacity();
    f.closure = co;
    f.ip = 0;
    f.slots = m.stackBottom;
    return .{ .scriptClosure = co, .machine = m };
}

test "stack push and pop" {
    const m: *VM = try .init(testing.allocator, testing.io);
    defer m.deinit();

    try m.stackPush(.{ .Number = 1 });
    try m.stackPush(.{ .Number = 2 });
    try m.stackPush(.{ .Number = 3 });

    inline for ([_]f32{ 3, 2, 1 }) |x| {
        const v = try m.stackPop();
        try testing.expect(v.equals(.{ .Number = x }));
    }
}

test "stack push and peek" {
    const m: *VM = try .init(testing.allocator, testing.io);
    defer m.deinit();

    try m.stackPush(.{ .Number = 2 });
    try m.stackPush(.{ .Number = 1 });
    try m.stackPush(.{ .Number = 0 });

    inline for ([_]f32{ 0, 1, 2 }) |x| {
        const v = m.stackPeek(x) orelse
            return error.UnexpectedValue;

        try testing.expect(v.equals(.{ .Number = x }));
    }
}

test "global get and set" {
    const tuple = try simpleScript();
    const m = tuple.machine;
    defer m.deinit();

    const chunk = &tuple.scriptClosure.function.chunk;

    const cloc = try chunk.addConstant(.{ .Number = 67 });
    try chunk.putOpCode(.Constant, 1);
    try chunk.put(@intCast(cloc), 1);

    const gn = try m.heap.allocateString("myGlobal");
    const gnLoc = try chunk.addConstant(.{ .Obj = .{ .String = gn } });
    try chunk.putOpCode(.DefineGlobal, 1);
    try chunk.put(@intCast(gnLoc), 1);

    try chunk.putOpCode(.GetGlobal, 1);
    try chunk.put(@intCast(gnLoc), 1);

    _ = try m.run();

    const g = m.globals.get("myGlobal") orelse return error.KeyError;
    try testing.expect(g.equals(.{ .Number = 67 }));
    try testing.expectEqual(m.stackTop - m.stackBottom, 1);
    const v = m.stackPeek(0) orelse return error.UnexpectedNull;
    try testing.expect(v.equals(.{ .Number = 67 }));
}

test "number addition" {
    const tuple = try simpleScript();
    const vm = tuple.machine;
    defer vm.deinit();

    const chunk = &tuple.scriptClosure.function.chunk;

    try vm.stackPush(.{ .Number = 64 });
    try vm.stackPush(.{ .Number = 3 });

    try chunk.putOpCode(.Add, 1);

    _ = try vm.run();

    const v = vm.stackPeek(0) orelse return error.UnexpectedNull;
    try testing.expect(v.equals(.{ .Number = 67 }));
}

test "string addition" {
    const tuple = try simpleScript();
    const vm = tuple.machine;
    defer vm.deinit();

    const chunk = &tuple.scriptClosure.function.chunk;

    const s1 = try vm.heap.allocateString("hello");
    const s2 = try vm.heap.allocateString(" world");
    const s3 = try vm.heap.allocateString("hello world");

    try vm.stackPush(.{ .Obj = .{ .String = s1 } });
    try vm.stackPush(.{ .Obj = .{ .String = s2 } });

    try chunk.putOpCode(.Add, 1);

    _ = try vm.run();

    const v = vm.stackPeek(0) orelse return error.UnexpectedNull;
    try testing.expect(v.equals(.{ .Obj = .{ .String = s3 } }));
}
