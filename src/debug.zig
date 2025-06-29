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

fn constantInstruction(name: []const u8, c: *Chunks, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    const index = @intFromEnum(c.code.items[offset + 1]);
    try stdout.print("{s} {d:4} ", .{name, index});
    try values.printValue(c.values.items[index]);
    try stdout.print("\n", .{});
    return offset + 2;

}

pub fn disassembleInstruction(c: *Chunks, offset: usize) !usize {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{d:0>4} ", .{offset});
    if (offset > 0 and c.lines.items[offset] == c.lines.items[offset - 1]) {
        try stdout.print("   | ", .{});
    } else {
        try stdout.print("{d:4} ", .{c.lines.items[offset]});
    }

    const instruction: Opcode = c.code.items[offset];
    return switch (instruction) {
        .RETURN => try simpleInstruction("OP_RETURN", offset),
        .PRINT => try simpleInstruction("OP_PRINT", offset),
        .CONSTANT => try constantInstruction("OP_CONSTANT", c, offset),
        .NIL => try simpleInstruction("OP_NIL", offset),
        .TRUE => try simpleInstruction("OP_TRUE", offset),
        .FALSE => try simpleInstruction("OP_FALSE", offset),
        .EQUAL => try simpleInstruction("OP_EQUAL", offset),
        .GREATER => try simpleInstruction("OP_GREATER", offset),
        .LESS => try simpleInstruction("OP_LESS", offset),
        .ADD => try simpleInstruction("OP_ADD", offset),
        .SUBTRACT => try simpleInstruction("OP_SUBTRACT", offset),
        .MULTIPLY => try simpleInstruction("OP_MULTIPLY", offset),
        .DIVIDE => try simpleInstruction("OP_DIVIDE", offset),
        .NEGATE => try simpleInstruction("OP_NEGATE", offset),
        .POP => try simpleInstruction("OP_POP", offset),
        .DEFINE_GLOBAL => try constantInstruction("OP_DEFINE_GLOBAL", c, offset),
        .GET_GLOBAL => try constantInstruction("OP_GET_GLOBAL", c, offset),
        .SET_GLOBAL => try constantInstruction("OP_SET_GLOBAL", c, offset),
        else => error.UnknownOpcode
    };
}

pub fn disassembleChunk(c: *Chunks, name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < c.code.items.len){
        offset = try disassembleInstruction(c, offset);
    }
}
