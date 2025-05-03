const std = @import("std");
const types = @import("types.zig");
const debug = @import("debug.zig");
const VM = @import("vm.zig").VM;

const Opcode = types.Opcode;



pub fn main() !void {
    var chunks = try types.Chunks.init();
    defer chunks.deinit() catch |e| {
        std.debug.print("Error {}", .{e});
    };
    var constant = try chunks.addConstant(3.4);
    try chunks.writeChunk(Opcode.OP_CONSTANT, 123);
    try chunks.writeChunk(constant, 123);

    constant = try chunks.addConstant(1.2);
    try chunks.writeChunk(Opcode.OP_CONSTANT, 123);
    try chunks.writeChunk(constant, 123);

    try chunks.writeChunk(Opcode.OP_ADD, 123);

    constant = try chunks.addConstant(5.6);
    try chunks.writeChunk(Opcode.OP_CONSTANT, 123);
    try chunks.writeChunk(constant, 123);

    try chunks.writeChunk(Opcode.OP_DIVIDE, 123);
    try chunks.writeChunk(Opcode.OP_NEGATE, 123);
    try chunks.writeChunk(Opcode.OP_RETURN, 123);
    var vm = VM.init(chunks);
    _ = try vm.run();
}

test "Chunk Test" {
    try std.testing.expectEqual(2 + 2, 4);
}
