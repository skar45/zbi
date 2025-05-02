const std = @import("std");
const Value = @import("values.zig").Value;

pub const Opcode = enum(u8){
    OP_RETURN,
    OP_CONSTANT,
    OP_NEGATE,
    _
};

pub const Chunks = struct {
    code: std.ArrayList(u8),
    values: std.ArrayList(Value),
    lines: std.ArrayList(usize),
    _arena:  std.heap.ArenaAllocator,

    pub fn init() !Chunks {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const allocator = arena.allocator();
        const code = try std.ArrayList(u8).initCapacity(allocator, 2048);
        const values_list = try std.ArrayList(Value).initCapacity(allocator, 1024);
        const lines = try std.ArrayList(usize).initCapacity(allocator, 256);

        return Chunks {
            .code = code,
            .values = values_list,
            .lines = lines,
            ._arena = arena
        };
    }

    pub fn writeChunk(self: *Chunks,  code: Opcode, line: usize) !void {
        try self.lines.append(line);
        try self.code.append(@intFromEnum(code));
    }

    pub fn addConstant(self: *Chunks, value: Value) !usize {
        try self.values.append(value);
        return self.values.items.len - 1;
    }

    pub fn deinit(self: *Chunks) !void {
        self._arena.deinit();
    }
};
