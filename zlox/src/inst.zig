const std = @import("std");
const value = @import("value.zig");

pub const OpCode = enum(u8) {
    // Load a constant into the stack
    // size: 2
    Constant,
    // Return from a function call.
    // Pop the top of the stack
    // size: 1
    Return,
    // Negate the top of the stack
    // size: 1
    Negate,
    // Add the top two values of the stack
    // and push the result.
    // size: 1
    Add,
    // Subtract the top of the stack from the next top
    // and push the result.
    // size: 1
    Subtract,
    // Subtract the top two stack entries
    // and push the result.
    // size: 1
    Multiply,
    // Divide the top of the stack from the next top
    // and push the result.
    // size: 1
    Divide,
};

pub const InstructionError = error{
    OutOfBounds,
};

/// A chunk contains compiled lox code and information
/// needed to reconstruct the source.
pub const Chunk = struct {
    alloc: std.mem.Allocator,
    code: std.ArrayList(u8),
    constants: std.ArrayList(value.Value),

    // Lines uses a simple run-length encoding scheme
    // to represent what lines go with what instruction.
    // The MSB of a line number is set to indicate that
    // more than one instruction is associated with a
    // particular line, in which case the next entry
    // encodes the run length. If the MSB is zero,
    // the next number is the next line number.
    lines: std.ArrayList(u32),
    currentLineHasRLE: bool,

    pub fn init(alloc: std.mem.Allocator) !Chunk {
        return .{
            .alloc = alloc,
            .code = try .initCapacity(alloc, 8),
            .constants = try .initCapacity(alloc, 8),
            .lines = try .initCapacity(alloc, 8),
            .currentLineHasRLE = false,
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.alloc);
        self.lines.deinit(self.alloc);
        self.constants.deinit(self.alloc);
    }

    /// Number of bytes in the code chunk
    pub inline fn len(self: *const Chunk) usize {
        return self.code.items.len;
    }

    /// Put an arbitrary byte in the code block
    pub fn put(self: *Chunk, val: u8, line: u32) !void {
        try self.putLine(line);
        return self.code.append(self.alloc, val);
    }

    fn putLine(self: *Chunk, line: u32) !void {
        if (self.lines.items.len == 0) {
            return self.lines.append(self.alloc, line & 0x7fffffff);
        }

        const linesTop = if (self.currentLineHasRLE)
            self.lines.items.len - 2
        else
            self.lines.items.len - 1;

        const curLine = self.lines.items[linesTop] & 0x7fffffff;
        if (curLine != line) {
            self.currentLineHasRLE = false;
            return self.lines.append(self.alloc, line & 0x7fffffff);
        }
        if (!self.currentLineHasRLE) {
            self.currentLineHasRLE = true;
            self.lines.items[self.lines.items.len - 1] |= 1 << 31;
            return self.lines.append(self.alloc, 1);
        }
        self.lines.items[linesTop + 1] += 1;
    }

    fn getLine(self: *const Chunk, codeIdx: usize) InstructionError!u32 {
        if (codeIdx >= self.code.items.len) {
            return InstructionError.OutOfBounds;
        }
        var idx: usize = 0;
        var currLine: usize = 0;
        while (currLine < self.lines.items.len) {
            const l = self.lines.items[currLine];
            // Check for RLE
            if (l & 0x7fffffff != 0) {
                idx += 1 + self.lines.items[currLine + 1];
                currLine += 2;
            } else {
                idx += 1;
                currLine += 1;
            }

            // We contain the target
            if (idx > codeIdx)
                return l & 0x7fffffff;
        }
        return InstructionError.OutOfBounds;
    }

    /// Write a single opcode to the code block
    pub fn putOpCode(self: *Chunk, code: OpCode, line: u32) !void {
        return self.put(@intFromEnum(code), line);
    }

    /// Append a constant value to this chunk
    /// return the index of that chunk for use in
    /// an OP_CONSTANT instruction
    pub fn addConstant(self: *Chunk, val: value.Value) !usize {
        try self.constants.append(self.alloc, val);
        return self.constants.items.len - 1;
    }

    pub fn disassemble(self: *const Chunk, name: []const u8) !void {
        std.debug.print("== {s} ==\n", .{name});
        var offset: usize = 0;
        while (offset < self.len()) {
            offset = try self.disassembleInstruction(offset);
        }
    }

    pub fn disassembleInstruction(self: *const Chunk, offset: usize) !usize {
        std.debug.print("{:0>4} ", .{offset});
        const line = try self.getLine(offset);
        if (offset > 0 and line == try self.getLine(offset - 1)) {
            std.debug.print("   | ", .{});
        } else {
            std.debug.print("{d:>4} ", .{line});
        }
        const inst = self.code.items[offset];
        switch (inst) {
            @intFromEnum(OpCode.Return) => return simpleInstruction("OP_RETURN", offset),
            @intFromEnum(OpCode.Negate) => return simpleInstruction("OP_NEGATE", offset),
            @intFromEnum(OpCode.Constant) => return constantInstruction("OP_CONSTANT", self, offset),
            @intFromEnum(OpCode.Add) => return simpleInstruction("OP_ADD", offset),
            @intFromEnum(OpCode.Subtract) => return simpleInstruction("OP_SUBTRACT", offset),
            @intFromEnum(OpCode.Multiply) => return simpleInstruction("OP_MULTIPLY", offset),
            @intFromEnum(OpCode.Divide) => return simpleInstruction("OP_DIVIDE", offset),
            else => {
                std.debug.print("Unknown opcode: {d}\n", .{inst});
                return offset + 1;
            },
        }
    }
};

fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const valueLoc: usize = @intCast(chunk.code.items[offset + 1]);
    std.debug.print("{s:<16} {d:>4} ", .{ name, valueLoc });
    std.debug.print("{d}\n", .{chunk.constants.items[valueLoc]});
    return offset + 2;
}
