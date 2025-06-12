const std = @import("std");
const expect = @import("std").testing.expect;
const c = @import("chunks.zig");
const debug = @import("debug.zig");
const values = @import("values.zig");
const compiler = @import("compiler.zig");

const Allocator = std.mem.Allocator;
const printValue = values.printValue;
const Value = values.Value;
const Chunks = c.Chunks;
const OpCode = c.Opcode;

const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

const VmError = error{
    InvalidArithmeticOp,
    OperandMustBeNumber
};

const STACK_SIZE = 256;

pub fn interpret(source: []u8, allocator: *const Allocator) InterpretResult {
    var chunks = Chunks.init();
    defer chunks.deinit();
    if (!compiler.compile(source, &chunks)) {
        return InterpretResult.INTERPRET_COMPILE_ERROR;
    }
    var vm = VM.init(&chunks, allocator);
    return vm.run();
}

pub const VM = struct {
    chunks: *Chunks,
    code_ptr: [*]OpCode,
    stack: [STACK_SIZE]Value,
    stack_idx: usize,
    _allocator: Allocator,

    pub fn init(chunks: *Chunks, allocator: *const Allocator) VM {
        return VM {
            .chunks = chunks,
            .code_ptr = chunks.code.items.ptr,
            .stack = [_]Value{Value.setNil()} ** STACK_SIZE,
            .stack_idx = 0,
            ._allocator = allocator.*,
        };
    }

    fn debug_vm(self: *VM) !void {
        for (self.stack) |v| {
            switch (v) {
                .nil => break,
                else => {
                    std.debug.print("[ ", .{});
                    printValue(v) catch unreachable;
                    std.debug.print(" ]", .{});
                }
            }

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

    inline fn binaryOp(self: *VM, comptime op: []const u8) !void {
        const b: f64 = switch (self.pop()) {
            .number => |v| v,
            else => return error.InvalidArithmeticOp
        };
        const a: f64 = switch (self.pop()) {
            .number => |v| v,
            else => return error.InvalidArithmeticOp
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

    fn run_vm(self: *VM) !void {
        while (true) {
            if (comptime debug.ENABLE_LOGGING) {
                try self.debug_vm();
            }
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
                .GREATER => try self.binaryOp(">"),
                .LESS => try self.binaryOp("<"),
                .ADD => try self.binaryOp("+"),
                .SUBTRACT => try self.binaryOp("-"),
                .MULTIPLY => try self.binaryOp("*"),
                .DIVIDE => try self.binaryOp("/"),
                .NOT => self.push(Value.setBool(VM.isFalsy(self.pop()))),
                .NEGATE => {
                    try switch (try self.peek(1)) {
                        .number => {
                            const num = -self.pop().number;
                            self.push(Value.setNumber(num));
                        },
                        else => error.OperandMustBeNumber
                    };
                },
                .RETURN => return,
                _ => continue
            }
        }

    }

    pub fn run(self: *VM) InterpretResult {
        const stdout = std.io.getStdOut().writer();
        self.run_vm() catch |err| {
            switch (err) {
                error.OperandMustBeNumber => self.runtimeError("Operand must be a number."),
                error.InvalidArithmeticOp => self.runtimeError("Can only do arithmetic operations on numbers."),
                else => self.runtimeError("Unknown error.")
            }
            return InterpretResult.INTERPRET_RUNTIME_ERROR;
        };
        printValue(self.pop()) catch unreachable;
        stdout.print("\n", .{}) catch unreachable;
        return InterpretResult.INTERPRET_OK;
    }

    inline fn resetStack(self: *VM) void {
        self.stack_idx = 0;
        self.stack = [_]Value{Value.setNil()} ** STACK_SIZE;
    }

    inline fn peek(self: *VM, distance: usize) !Value {
        return self.stack[self.stack_idx - distance];
    }

    inline fn push(self: *VM, value: Value) void {
        self.stack[self.stack_idx] = value;
        self.stack_idx += 1;
    }

    inline fn pop(self: *VM) Value {
        self.stack_idx -= 1;
        return self.stack[self.stack_idx];
    }
};
