const std = @import("std");
const types = @import("types.zig");

pub fn simpleInstruction(name: []const u8, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s} \n", .{name});
    return offset + 1;
}

pub fn disassembleInstruction(chunks: types.Chunk, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{d:4} ", .{offset});

    const instruction = chunks.items[offset];
    return switch (instruction) {
        .OP_RETURN => try simpleInstruction("OP_RETURN", offset),
        // else => try stdout.print("Unknown Op Code {d}\n", .{offset})
    };
}

pub fn disassembleChunk(chunks: types.Chunk, name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunks.items.len){
        offset = try disassembleInstruction(chunks, offset);
    }
}


