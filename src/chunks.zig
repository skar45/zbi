const std = @import("std");
const Value = @import("values.zig").Value;

pub const Opcode = enum(u8){
    RETURN,
    CONSTANT,
    NIL,
    TRUE,
    FALSE,
    EQUAL,
    GREATER,
    LESS,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    NEGATE,
    NOT,
    _
};

pub const Chunks = struct {
    code: std.ArrayList(Opcode),
    values: std.ArrayList(Value),
    lines: std.ArrayList(usize),
    _arena:  std.heap.ArenaAllocator,

    inline fn allocatorError(err: std.mem.Allocator.Error) void {
        std.debug.print("{}", .{err});
        std.process.exit(70);
    }

    pub fn init() Chunks {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const allocator = arena.allocator();
        const code = std.ArrayList(Opcode).initCapacity(allocator, 2048) catch |e| allocatorError(e);
        const values_list = std.ArrayList(Value).initCapacity(allocator, 1024) catch |e| allocatorError(e);
        const lines = std.ArrayList(usize).initCapacity(allocator, 256) catch |e| allocatorError(e);

        return Chunks {
            .code = code,
            .values = values_list,
            .lines = lines,
            ._arena = arena
        };
    }

    pub fn writeChunk(self: *Chunks,  code: Opcode, line: usize) void {
        self.lines.append(line) catch |e| allocatorError(e);
        std.debug.print("write chunk added total length: {d} \n", .{self.lines.items.len});
        self.code.append(code) catch |e| allocatorError(e);
    }

    pub fn addConstant(self: *Chunks, value: Value) Opcode {
        self.values.append(value) catch |e| allocatorError(e);
        // TODO: account for overflow
        return @enumFromInt(self.values.items.len - 1);
    }

    pub fn deinit(self: *Chunks) void {
        self._arena.deinit();
    }
};
