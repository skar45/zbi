const std = @import("std");
const types = @import("types.zig");
const values = @import("values.zig");
const errors = @import("errors.zig");

pub const ENABLE_LOGGING = true;

fn simpleInstruction(name: []const u8, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s} \n", .{name});
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunks: types.Chunks, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    const index = @intFromEnum(chunks.code.items[offset + 1]);
    try stdout.print("{s} {d:4} ", .{name, index});
    try values.printValue(chunks.values.items[index]);
    try stdout.print("\n", .{});
    return offset + 2;

}

pub fn disassembleInstruction(chunks: types.Chunks, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{d:0>4} ", .{offset});
    if (offset > 0 and chunks.lines.items[offset] == chunks.lines.items[offset - 1]) {
        try stdout.print("   | ", .{});
    } else {
        try stdout.print("{d:4} ", .{chunks.lines.items[offset]});
    }

    const instruction: types.Opcode = chunks.code.items[offset];
    return switch (instruction) {
        .OP_RETURN => try simpleInstruction("OP_RETURN", offset),
        .OP_CONSTANT => try constantInstruction("OP_CONSTANT", chunks, offset),
        .OP_ADD => try simpleInstruction("OP_ADD", offset),
        .OP_SUBTRACT => try simpleInstruction("OP_SUBTRACT", offset),
        .OP_MULTIPLY => try simpleInstruction("OP_MULTIPLY", offset),
        .OP_DIVIDE => try simpleInstruction("OP_DIVIDE", offset),
        .OP_NEGATE => try simpleInstruction("OP_NEGATE", offset),
        else => error.UnknownOpcode
    };
}

pub fn disassembleChunk(chunks: types.Chunks, name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunks.code.items.len){
        offset = try disassembleInstruction(chunks, offset);
    }
}
