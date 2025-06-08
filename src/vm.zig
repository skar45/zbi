const std = @import("std");
const expect = @import("std").testing.expect;
const c = @import("chunks.zig");
const debug = @import("debug.zig");
const values = @import("values.zig");
const compiler = @import("compiler.zig");

const printValue = values.printValue;
const Value = values.Value;
const Chunks = c.Chunks;
const OpCode = c.Opcode;

const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

const MAX_STACK = 256;

pub fn interpret(source: []u8) InterpretResult {
    var chunks = Chunks.init();
    defer chunks.deinit();
    if (!compiler.compile(source, &chunks)) {
        return InterpretResult.INTERPRET_COMPILE_ERROR;
    }
    std.debug.print("lines length {d} \n", .{chunks.lines.items.len});
    var vm = VM.init(&chunks);
    return vm.run() catch {
        std.debug.print("vm error", .{});
        return InterpretResult.INTERPRET_RUNTIME_ERROR;
    };
}

pub const VM = struct {
    chunks: *Chunks,
    code_ptr: [*]OpCode,
    stack: [MAX_STACK]Value,
    stack_ptr: [*]Value,

    pub fn init(chunks: *Chunks) VM {
        return VM {
            .chunks = chunks,
            .code_ptr = chunks.code.items.ptr,
            .stack = undefined,
            .stack_ptr = undefined,
        };
    }

    fn debug_vm(self: *VM) !void {
        var slot = @intFromPtr(&self.stack);
        const stack_top = @intFromPtr(self.stack_ptr);
        while (slot < stack_top) {
            std.debug.print("[ ", .{});
            printValue(self.stack[0]) catch unreachable;
            std.debug.print(" ]", .{});
            slot += 8;
        }
        std.debug.print("\n", .{});
        const off: usize = @intFromPtr(self.code_ptr) - @intFromPtr(self.chunks.code.items.ptr);
        _ = try debug.disassembleInstruction(self.chunks, off);
    }

    fn runtimeError(self: *VM, format: []const u8) void {
        std.debug.print("{s} \n", .{format});
        const instruction: usize  = @intFromPtr(self.code_ptr) - @intFromPtr(self.chunks.code.items.ptr) - 1;
        const line: usize = self.chunks.lines.items[instruction];
        std.debug.print("[line {d}] in script\n", .{line});
        self.resetStack();
    }

    inline fn isFalsy(value: Value) bool {
        return switch(value) {
            .boolean => |v| !v,
            .nil => true,
            else => false
        };
    }

    inline fn valuesEqual(a: Value, b: Value) bool {
        return switch (a) {
            .boolean => |v| {
                return switch (b) {
                    .boolean => |s| s == v,
                    else => false
                };
            },
            .nil => {
                return switch (b) {
                    .nil => true,
                    else => false
                };
            },
            .number => |v| {
                return switch(b) {
                    .number => |s| s == v,
                    else => false
                };
            }
        };
    }

    inline fn binaryOp(self: *VM, comptime op: []const u8) void {
        const a: f64 = switch (self.pop()) {
            .number => |v| v,
            else => return self.runtimeError("can only do arithmetic operations on numbers")
        };
        const b: f64 = switch (self.pop()) {
            .number => |v| v,
            else => return self.runtimeError("can only do arithmentic operations on numbers")
        };
        switch (op[0]) {
            '+' => self.push(Value.setNumber(a + b)),
            '-' => self.push(Value.setNumber(a - b)),
            '*' => self.push(Value.setNumber(a * b)),
            '/' => self.push(Value.setNumber(a / b)),
            '>' => self.push(Value.setBool(a > b)),
            '<' => self.push(Value.setBool(a < b)),
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
                .CONSTANT => {
                    const i = @intFromEnum(self.code_ptr[0]);
                    self.code_ptr += 1;
                    self.push(self.chunks.values.items[i]);
                },
                .NIL => self.push(Value.setNil()),
                .TRUE => self.push(Value.setBool(true)),
                .FALSE => self.push(Value.setBool(false)),
                .EQUAL => {
                    const a = self.pop();
                    const b = self.pop();
                    self.push(Value.setBool(valuesEqual(a, b)));
                },
                .GREATER => self.binaryOp(">"),
                .LESS => self.binaryOp("<"),
                .ADD => self.binaryOp("+"),
                .SUBTRACT => self.binaryOp("-"),
                .MULTIPLY => self.binaryOp("*"),
                .DIVIDE => self.binaryOp("/"),
                .NOT => self.push(Value.setBool(VM.isFalsy(self.pop()))),
                .NEGATE => {
                    switch (self.peek(1)) {
                        .number => {
                            const num = -self.pop().number;
                            self.push(Value.setNumber(num));
                        },
                        else => {
                            self.runtimeError("Operand must be a number.");
                            return InterpretResult.INTERPRET_RUNTIME_ERROR;
                        }
                    }
                },
                .RETURN => {
                    try printValue(self.pop());
                    try stdout.print("\n", .{});
                    return InterpretResult.INTERPRET_OK;
                },
                _ => continue
            }
        }
    }

    inline fn resetStack(self: *VM) void {
        self.stack_ptr = &self.stack;
    }

    inline fn peek(self: *VM, distance: usize) Value {
        return self.stack_ptr[distance];
    }

    inline fn push(self: *VM, value: Value) void {
        self.stack_ptr[0] = value;
        self.stack_ptr += 1;
    }

    inline fn pop(self: *VM) Value {
        self.stack_ptr -= 1;
        return self.stack_ptr[0];
    }
};
