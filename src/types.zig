const std = @import("std");

pub const Opcode = enum(u8){
    OP_RETURN
};

pub const Chunk = std.ArrayList(Opcode);
