
const std = @import("std");
const value = @import("value.zig");


pub const OpCode = enum(u8) {
    OP_CONSTANT,
    OP_RETURN,
};

/// A chunk contains compiled lox code and information
/// needed to reconstruct the source.
pub const Chunk = struct {
    alloc: std.mem.Allocator,
    code: std.ArrayList(u8),
    constants: value.ValueArray,
    lines: std.ArrayList(usize),

    pub fn init(alloc: std.mem.Allocator) !Chunk {
        return .{
            .alloc = alloc,
            .code = try .initCapacity(alloc, 8),
            .constants = try .init(alloc),
            .lines = try .initCapacity(alloc, 8),
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.alloc);
        self.lines.deinit(self.alloc);
        self.constants.deinit();
    }

    /// Number of bytes in the code chunk
    pub inline fn len(self: *const Chunk) usize {
        return self.code.items.len;
    }

    /// Put an arbitrary byte in the code block
    pub fn put(self: *Chunk, val: u8, line: usize) !void {
        try self.lines.append(self.alloc, line);
        return self.code.append(self.alloc, val);
    }

    /// Write a single opcode to the code block
    pub fn putOpCode(self: *Chunk, code: OpCode, line: usize) !void {
        return self.put(@intFromEnum(code), line);
    }
    
    /// Append a constant value to this chunk
    /// return the index of that chunk for use in
    /// an OP_CONSTANT instruction
    pub fn addConstant(self: *Chunk, val: value.Value) !usize {
        try self.constants.put(val);
        return self.constants.len() - 1;
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
        if (
            offset > 0 and self.lines.items[offset] == self.lines.items[offset-1]
        ) {
            std.debug.print("   | ", .{});
        } else {
            std.debug.print("{d:>4} ", .{self.lines.items[offset]});
        }
        const inst = self.code.items[offset];
        switch (inst) {
            @intFromEnum(OpCode.OP_RETURN) => 
                return simpleInstruction("OP_RETURN", offset),
            @intFromEnum(OpCode.OP_CONSTANT) =>
                return constantInstruction("OP_CONSTANT", self, offset),
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
    std.debug.print("{s:<16} {d:>4} ", .{name, valueLoc});
    std.debug.print("{d}\n", .{chunk.constants.values.items[valueLoc]});
    return offset + 2;
}

