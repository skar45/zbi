const std = @import("std");
const Value = @import("values.zig").Value;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Opcode = enum(u8){
    RETURN,
    PRINT,
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
    POP,
    DEFINE_GLOBAL,
    GET_GLOBAL,
    SET_GLOBAL,
    _
};

pub const Chunks = struct {
    code: ArrayList(Opcode),
    values: ArrayList(Value),
    lines: ArrayList(usize),
    _arena: ArenaAllocator,

    inline fn allocatorError(err: std.mem.Allocator.Error) void {
        std.debug.print("{}", .{err});
        std.process.exit(70);
    }

    pub fn init() Chunks {
        var arena = ArenaAllocator.init(std.heap.page_allocator);
        const allocator = arena.allocator();
        const code = ArrayList(Opcode).initCapacity(allocator, 2048) catch |e| allocatorError(e);
        const values_list = ArrayList(Value).initCapacity(allocator, 1024) catch |e| allocatorError(e);
        const lines = ArrayList(usize).initCapacity(allocator, 256) catch |e| allocatorError(e);

        return Chunks {
            .code = code,
            .values = values_list,
            .lines = lines,
            ._arena = arena
        };
    }

    pub fn writeChunk(self: *Chunks,  code: Opcode, line: usize) void {
        self.lines.append(line) catch |e| allocatorError(e);
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
