const std = @import("std");
const types = @import("types.zig");
const debug = @import("debug.zig");
const values = @import("values.zig");
const Value = values.Value;
const printValue = values.printValue;

const Chunks = types.Chunks;
const OpCode = types.Opcode;

const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

const MAX_STACK = 256;


const VM = struct {
    chunks: Chunks,
    code_ptr: [*]OpCode,
    stack: [MAX_STACK]Value,
    stack_ptr: [*]Value,

    pub fn init(chunks: Chunks) VM {
        var stack: [MAX_STACK]Value =  undefined;
        return VM {
            .chunks = chunks,
            .code_ptr = &(chunks.code),
            .stack = stack,
            .stack_ptr = &stack,
        };
    }

    pub fn run(self: *VM) InterpretResult {
        while (1) {
            comptime if (debug.ENABLE_LOGGING) {
                var slot = self.stack_ptr;
                std.debug.print("          ", .{});
                while (slot < &self.stack) {
                    std.debug.print("[ ", .{});
                    std.debug.print("{d}", .{slot.*});
                    std.debug.print(" ]", .{});
                    slot += 1;
                }
                std.debug.print("\n", .{});
                const off: usize = self.code_ptr - self.chunks;
                debug.disassembleInstruction(self.chunks, off);
            };
            const stdout = std.io.getStdOut().writer();
            const instruction = self.code_ptr[0];
            self.code_ptr += 1;
            switch (instruction) {
                .OP_CONSTANT => {
                    const i = self.code_ptr[0];
                    self.code_ptr += 1;
                    self.chunks.values.items[i];
                },
                .OP_NEGATE => {
                    self.push(self.pop());
                    break;
                },
                .OP_RETURN => {
                    printValue(self.pop());
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
        self.stack_ptr.* = value;
        self.stack_ptr += 1;
    }

    pub fn pop(self: *VM) Value {
        self.stack_ptr -= 1;
        return self.stack_ptr.*;
    }
};
