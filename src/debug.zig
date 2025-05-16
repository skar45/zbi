const std = @import("std");
const chunks = @import("chunks.zig");
const values = @import("values.zig");
const errors = @import("errors.zig");

const Opcode = chunks.Opcode;
const Chunks = chunks.Chunks;



pub const ENABLE_LOGGING = true;

fn simpleInstruction(name: []const u8, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s} \n", .{name});
    return offset + 1;
}

fn constantInstruction(name: []const u8, c: Chunks, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    const index = @intFromEnum(c.code.items[offset + 1]);
    try stdout.print("{s} {d:4} ", .{name, index});
    try values.printValue(c.values.items[index]);
    try stdout.print("\n", .{});
    return offset + 2;

}

pub fn disassembleInstruction(c: Chunks, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{d:0>4} ", .{offset});
    if (offset > 0 and c.lines.items[offset] == c.lines.items[offset - 1]) {
        try stdout.print("   | ", .{});
    } else {
        try stdout.print("{d:4} ", .{c.lines.items[offset]});
    }

    const instruction: Opcode = c.code.items[offset];
    return switch (instruction) {
        .OP_RETURN => try simpleInstruction("OP_RETURN", offset),
        .OP_CONSTANT => try constantInstruction("OP_CONSTANT", c, offset),
        .OP_ADD => try simpleInstruction("OP_ADD", offset),
        .OP_SUBTRACT => try simpleInstruction("OP_SUBTRACT", offset),
        .OP_MULTIPLY => try simpleInstruction("OP_MULTIPLY", offset),
        .OP_DIVIDE => try simpleInstruction("OP_DIVIDE", offset),
        .OP_NEGATE => try simpleInstruction("OP_NEGATE", offset),
        else => error.UnknownOpcode
    };
}

pub fn disassembleChunk(c: Chunks, name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < c.code.items.len){
        offset = try disassembleInstruction(c, offset);
    }
}
