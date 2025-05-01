const std = @import("std");
const types = @import("types.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var chunks = try std.ArrayList(types.Opcode).initCapacity(allocator, 4096);
    defer chunks.deinit();
    try chunks.append(types.Opcode.OP_RETURN);
    try debug.disassembleChunk(chunks, "test chunk");
}

test "simple test" {
    try std.testing.expectEqual(2 + 2, 4);
}
