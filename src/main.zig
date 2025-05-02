const std = @import("std");
const types = @import("types.zig");
const debug = @import("debug.zig");
const vm = @import("vm.zig");

pub fn main() !void {
    var chunks = try types.Chunks.init();
    defer chunks.deinit() catch |e| {
        std.debug.print("Error {}", .{e});
    };
}

test "Chunk Test" {
    try std.testing.expectEqual(2 + 2, 4);
    var chunks = try types.Chunks.init();
    defer chunks.deinit() catch |e| {
        std.debug.print("Error {}", .{e});
    };
    const constant: types.Opcode = @enumFromInt(try chunks.addConstant(1.2));
    try chunks.writeChunk(types.Opcode.OP_CONSTANT, 123);
    try chunks.writeChunk(constant, 123);
    try chunks.writeChunk(types.Opcode.OP_NEGATE, 123);
    try chunks.writeChunk(types.Opcode.OP_RETURN, 123);
    try debug.disassembleChunk(chunks, "test chunk");
}
