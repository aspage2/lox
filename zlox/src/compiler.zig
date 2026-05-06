const Chunk = @import("inst.zig").Chunk;
const Scanner = @import("scanner.zig");
const Parser = @import("parser.zig");

pub fn compile(source: []const u8, chunk: *Chunk) !void {
    var sc: Scanner = .init(source);
    var parser: Parser = .init(&sc, chunk);

    parser.advance();

    try parser.expression();

    try parser.end();
}
