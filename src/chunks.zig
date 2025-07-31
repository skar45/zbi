const std = @import("std");
const Value = @import("values.zig").Value;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const OpCode = enum(usize){
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
    LOOP,
    JUMP,
    JUMP_IF_FALSE,
    DEFINE_GLOBAL,
    GET_LOCAL,
    SET_LOCAL,
    GET_GLOBAL,
    SET_GLOBAL,
    CALL,
    RETURN,
    RETURN_NIL,
    _
};

pub const Chunks = struct {
    code_list: ArrayList(ArrayList(OpCode)),
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
        var code_list = ArrayList(ArrayList(OpCode)).initCapacity(allocator, 4096) catch |e| allocatorError(e);

        const init_frame = ArrayList(OpCode).initCapacity(allocator, 4096) catch |e| allocatorError(e);
        code_list.append(init_frame) catch |e| allocatorError(e);

        const values_list = ArrayList(Value).initCapacity(allocator, 1024) catch |e| allocatorError(e);
        const lines = ArrayList(usize).initCapacity(allocator, 256) catch |e| allocatorError(e);

        return Chunks {
            .code_list = code_list,
            .values = values_list,
            .lines = lines,
            ._arena = arena
        };
    }

    pub inline fn addCodeSegment(self: *Chunks) void {
        const allocator = self._arena.allocator();
        const code = ArrayList(OpCode).initCapacity(allocator, 4096) catch |e| allocatorError(e);
        self.code_list.append(code) catch |e| allocatorError(e);
    }

    pub inline fn writeChunk(self: *Chunks, frame_idx: usize, code: OpCode, line: usize) void {
        self.code_list.items[frame_idx].append(code) catch |e| allocatorError(e);
        self.lines.append(line) catch |e| allocatorError(e);
    }

    pub inline fn addConstant(self: *Chunks, value: Value) OpCode {
        self.values.append(value) catch |e| allocatorError(e);
        // TODO: account for overflow
        return @enumFromInt(self.values.items.len - 1);
    }

    pub fn deinit(self: *Chunks) void {
        self._arena.deinit();
    }
};
