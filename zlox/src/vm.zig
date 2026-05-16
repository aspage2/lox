const std = @import("std");

const inst = @import("inst.zig");
const value = @import("value.zig");
const compile = @import("parser.zig").compile;

const build_opts = @import("build_options");

pub const InterpretResult = enum(u8) {
    Ok,
    CompileError,
    RuntimeError,
};

pub const RuntimeError = error{
    StackEmpty,
};

const StackMax: usize = 256;

pub const VM = struct {
    alloc: std.mem.Allocator,
    chunk: *inst.Chunk,
    ip: usize,

    stack: [StackMax]value.Value,
    stackSize: usize,

    objList: ?*value.Obj,

    strings: value.StringTable,

    globals: std.array_hash_map.String(value.Value),

    pub fn init(alloc: std.mem.Allocator) !VM {
        return .{
            .alloc = alloc,
            .chunk = undefined,
            .ip = undefined,
            .stackSize = 0,
            .stack = undefined,
            .objList = undefined,
            .strings = try .init(alloc),
            .globals = try .init(alloc, &.{}, &.{}),
        };
    }

    pub fn allocateObject(self: *VM) !*value.Obj {
        const obj = try self.alloc.create(value.Obj);
        obj.next = self.objList;
        self.objList = obj;
        return obj;
    }

    pub fn allocateString(self: *VM, data: []const u8) !*value.Obj {
        const o = try self.allocateObject();
        o.inst.String = try self.strings.make(data);
        return o;
    }

    pub fn freeObject(self: *VM) void {
        var maybeO = self.objList;
        while (maybeO) |obj| {
            maybeO = obj.next;
            switch (obj.inst) {
                .String => |s| {
                    self.alloc.free(s.data);
                    self.alloc.destroy(s);
                },
            }
            self.alloc.destroy(obj);
        }
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
    }

    pub fn interpret(self: *VM, source: []const u8) !InterpretResult {
        var chunk: inst.Chunk = try .init(self.alloc);
        defer chunk.deinit();

        self.strings = try .init(self.alloc);
        defer self.strings.deinit();

        const hadError = try compile(self.alloc, source, &chunk, &self.strings);
        if (hadError) return .CompileError;
        if (build_opts.lox_debug) {
            std.debug.print("\x1b[2;37m", .{});
            self.strings.pprint();
            std.debug.print("\x1b[0m", .{});
        }

        self.chunk = &chunk;
        self.ip = 0;
        if (build_opts.lox_debug) {
            std.debug.print("\x1b[2;37m--- RUNNING ---\n\x1b[0m", .{});
        }
        const res = self.run();
        if (build_opts.lox_debug) {
            std.debug.print("\x1b[2;37m", .{});
            self.strings.pprint();
            std.debug.print("\x1b[0m", .{});
        }
        return res;
    }

    inline fn take_operand(self: *VM) u8 {
        self.ip += 1;
        return self.chunk.code.items.ptr[self.ip];
    }

    fn run(self: *VM) !InterpretResult {
        const codePtr: [*]u8 = self.chunk.code.items.ptr;

        while (self.ip < self.chunk.len()) : (self.ip += 1) {
            if (comptime build_opts.lox_debug) {
                std.debug.print("\x1b[2;37m", .{});
                std.debug.print("          ", .{});
                for (0..self.stackSize) |i| {
                    std.debug.print("[ ", .{});
                    value.printValue(self.stack[i]);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
                _ = try self.chunk.disassembleInstruction(self.ip);
                std.debug.print("\x1b[0m", .{});
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
                    const vLoc: usize = @intCast(self.take_operand());
                    const val = self.chunk.constants.items[vLoc];
                    try self.stackPush(val);
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
                            const boType = std.meta.activeTag(bo.inst);
                            const aoType = std.meta.activeTag(ao.inst);
                            if (boType != aoType or boType != .String) {
                                self.runtimeError("Operands for concat must be strings", .{});
                                return InterpretResult.RuntimeError;
                            }
                            self.stackDrop(2);
                            const newData = try std.mem.concat(
                                self.alloc,
                                u8,
                                &.{ ao.inst.String.data, bo.inst.String.data },
                            );
                            defer self.alloc.free(newData);
                            try self.stackPush(.{ .Obj = try self.allocateString(newData) });
                        },
                        else => unreachable,
                    }
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
                },
                @intFromEnum(inst.OpCode.Nil) => try self.stackPush(.Nil),
                @intFromEnum(inst.OpCode.True) => try self.stackPush(.{ .Bool = true }),
                @intFromEnum(inst.OpCode.False) => try self.stackPush(.{ .Bool = false }),
                @intFromEnum(inst.OpCode.Not) => {
                    const v = try self.stackPop();
                    try self.stackPush(.{ .Bool = v.isFalsey() });
                },
                @intFromEnum(inst.OpCode.Equal) => {
                    const a = try self.stackPop();
                    const b = try self.stackPop();
                    try self.stackPush(.{ .Bool = a.equals(b) });
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
                },
                @intFromEnum(inst.OpCode.Print) => {
                    const v = try self.stackPop();
                    value.printValue(v);
                    std.debug.print("\n", .{});
                },
                @intFromEnum(inst.OpCode.Pop) => {
                    _ = try self.stackPop();
                },
                @intFromEnum(inst.OpCode.DefineGlobal) => {
                    const globalName = self.take_operand_as_val().Obj.inst.String;
                    const val = self.stackPeek(0).?;
                    try self.globals.put(self.alloc, globalName.data, val);
                    self.stackDrop(1);
                },
                @intFromEnum(inst.OpCode.GetGlobal) => {
                    const name = self.take_operand_as_val().Obj.inst.String;

                    if (self.globals.get(name.data)) |val| {
                        try self.stackPush(val);
                    } else {
                        self.runtimeError("Undefined variable: {s}", .{name.data});
                        return .RuntimeError;
                    }
                },
                @intFromEnum(inst.OpCode.SetGlobal) => {
                    const name = self.take_operand_as_val().Obj.inst.String;
                    if (self.globals.getEntry(name.data)) |ent| {
                        ent.value_ptr.* = self.stackPeek(0).?;
                    } else {
                        self.runtimeError("Undefined variable: {s}", .{name.data});
                        return .RuntimeError;
                    }
                },
                @intFromEnum(inst.OpCode.SetLocal) => {
                    const slot = self.take_operand();
                    self.stack[slot] = self.stackPeek(0).?;
                },
                @intFromEnum(inst.OpCode.GetLocal) => {
                    const slot = self.take_operand();
                    try self.stackPush(self.stack[slot]);
                },
                else => {},
            }
        }
        return InterpretResult.RuntimeError;
    }

    fn take_operand_as_val(self: *VM) value.Value {
        const loc: usize = @intCast(self.take_operand());
        return self.chunk.constants.items[loc];
    }

    fn stackPeek(self: *VM, depth: usize) ?value.Value {
        if (self.stackSize <= depth) return null;
        return self.stack[self.stackSize - 1 - depth];
    }

    fn runtimeError(self: *VM, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(fmt, args);
        var l: u32 = 0;
        if (self.chunk.getLine(self.ip)) |line| {
            l = line;
        } else |e| {
            std.debug.print("err getting line: {any}\n", .{e});
        }
        std.debug.print("\n[line {d}] in script\n", .{l});
        self.stackReset();
    }
};
