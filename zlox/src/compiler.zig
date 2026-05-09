const std = @import("std");
const Chunk = @import("inst.zig").Chunk;
const Scanner = @import("scanner.zig");
const Parser = @import("parser.zig");
const StringTable = @import("value.zig").StringTable;

pub fn compile(
    alloc: std.mem.Allocator,
    source: []const u8,
    chunk: *Chunk,
    st: *StringTable,
) !void {
    var sc: Scanner = .init(source);
    var parser: Parser = .init(alloc, &sc, chunk, st);

    parser.advance();

    try parser.expression();

    try parser.end();
}
