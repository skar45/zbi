const std = @import("std");
const expect = @import("std").testing.expect;
const chunks = @import("chunks.zig");
const debug = @import("debug.zig");
const values = @import("values.zig");
const compiler = @import("compiler.zig");

const printValue = values.printValue;
const Value = values.Value;
const Chunks = chunks.Chunks;
const OpCode = chunks.Opcode;

const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

const MAX_STACK = 256;

pub fn interpret(source: []u8) InterpretResult {
    compiler.compile(source);
    return InterpretResult.INTERPRET_OK;
}

pub const VM = struct {
    chunks: Chunks,
    code_ptr: [*]OpCode,
    stack: [MAX_STACK]Value,
    stack_ptr: [*]Value,

    pub fn init(c: Chunks) VM {
        return VM {
            .chunks = c,
            .code_ptr = c.code.items.ptr,
            .stack = undefined,
            .stack_ptr = undefined,
        };
    }

    fn debug_vm(self: *VM) !void {
        var slot = @intFromPtr(&self.stack);
        const stack_top = @intFromPtr(self.stack_ptr);
        std.debug.print("          ", .{});
        while (slot < stack_top) {
            std.debug.print("[ ", .{});
            const value: *f64 = @ptrFromInt(slot);
            std.debug.print("{d}", .{value.*});
            std.debug.print(" ]", .{});
            slot += 8;
        }
        std.debug.print("\n", .{});
        const off: usize = @intFromPtr(self.code_ptr) - @intFromPtr(self.chunks.code.items.ptr);
        _ = try debug.disassembleInstruction(self.chunks, off);
    }

    inline fn binary_op(self: *VM, comptime op: []const u8) void {
        const a = self.pop();
        const b = self.pop();
        switch (op[0]) {
            '+' => self.push(a + b),
            '-' => self.push(a - b),
            '*' => self.push(a * b),
            '/' => self.push(a / b),
            else => unreachable
        }
    }

    pub fn run(self: *VM) !InterpretResult {
        self.stack_ptr = &self.stack;
        while (true) {
            if (comptime debug.ENABLE_LOGGING) {
                try self.debug_vm();
            }
            const stdout = std.io.getStdOut().writer();
            const instruction = self.code_ptr[0];
            self.code_ptr += 1;
            switch (instruction) {
                .OP_CONSTANT => {
                    const i = @intFromEnum(self.code_ptr[0]);
                    self.code_ptr += 1;
                    self.push(self.chunks.values.items[i]);
                },
                .OP_ADD => self.binary_op("+"),
                .OP_SUBTRACT => self.binary_op("-"),
                .OP_MULTIPLY => self.binary_op("*"),
                .OP_DIVIDE => self.binary_op("/"),
                .OP_NEGATE => {
                    self.push(-self.pop());
                },
                .OP_RETURN => {
                    try printValue(self.pop());
                    try stdout.print("\n", .{});
                    return InterpretResult.INTERPRET_OK;
                },
                _ => continue
            }
        }
    }

    pub fn resetStack(self: *VM) void {
        self.stack_ptr = &self.stack;
    }

    pub fn push(self: *VM, value: Value) void {
        self.stack_ptr[0] = value;
        self.stack_ptr += 1;
    }

    pub fn pop(self: *VM) Value {
        self.stack_ptr -= 1;
        return self.stack_ptr[0];
    }
};
