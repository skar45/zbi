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

const Context = struct {
    pub fn hash(_: *const Context, k: []const u8) u32 {
        var h: u32 = 2166136261;
        for (k) |s| {
            h ^= s;
            h *%= 1677619;
        }
        return h;
    }

    pub fn eql(_: *const Context, key1: []const u8, key2: []const u8, _: usize) bool {
        for (key1, 0..) |k, i| {
            if (key2[i] != k) return false;
        }
        return true;
    }
};

const GlobalDeclMap = std.ArrayHashMap([]const u8, Value, Context, true);

const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

const VmError = error{
    InvalidArithmeticOp,
    OperandMustBeNumber,
    VarNameMustBeString,
    VarUndefined
};

const STACK_SIZE = 256;

pub fn interpret(source: []u8, allocator: *const Allocator) InterpretResult {
    // @compileLog("size of 'Value'", @sizeOf(Value));
    var chunks = Chunks.init();
    defer chunks.deinit();
    if (!compiler.compile(source, &chunks, allocator)) {
        return InterpretResult.INTERPRET_COMPILE_ERROR;
    }
    var vm = VM.init(&chunks, allocator);
    return vm.run();
}

pub const VM = struct {
    chunks: *Chunks,
    code: []OpCode,
    code_idx: usize,
    stack: [STACK_SIZE]Value,
    stack_idx: usize,
    globals: GlobalDeclMap,
    _allocator: *const Allocator,

    pub fn init(chunks: *Chunks, allocator: *const Allocator) VM {
        const globals = GlobalDeclMap.init(allocator.*);
        return VM {
            .chunks = chunks,
            .code = chunks.code.items,
            .code_idx = 0,
            .stack = [_]Value{Value.setVoid()} ** STACK_SIZE,
            .stack_idx = 0,
            .globals = globals,
            ._allocator = allocator,
        };
    }

    pub fn deinit(self: *VM) void {
        self.globals.deinit();
    }

    fn debug_vm(self: *VM) !void {
        for (self.stack) |v| {
            switch (v) {
                .void => break,
                else => {
                    std.debug.print("[ ", .{});
                    printValue(v) catch unreachable;
                    std.debug.print(" ]", .{});
                }
            }

        }
        std.debug.print("\n", .{});
        const off: usize = self.code_idx;
        _ = try debug.disassembleInstruction(self.chunks, off);
    }

    fn runtimeError(self: *VM, format: []const u8) void {
        std.debug.print("{s} \n", .{format});
        const instruction: usize  = self.code_idx;
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
            },
            .string => |v| {
                return switch(b) {
                    .string => |s| v.compare(s.str),
                    else => false
                };
            },
            else => false
        };
    }

    inline fn binaryOp(self: *VM, comptime op: []const u8) !void {
        const b: f64 = switch (self.pop()) {
            .number => |v| v,
            .string => |v| {
                if (op[0] != '+') return error.InvalidArithmeticOp;
                try switch (try self.peek(0)) {
                    .string => {
                        const str = self.pop();
                        switch (str) {
                            .string => |s| {
                                const value = Value.concatString(s.str, v.str, s._allocator);
                                self.push(value);
                                return;
                            },
                            else => return error.InvalidArithmeticOp
                        }
                    },
                    else =>  return error.InvalidArithmeticOp
                };
            },
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

    inline fn read_val_from_chunk(self: *VM) Value {
        const i = @intFromEnum(self.code[self.code_idx]);
        self.code_idx += 1;
        return self.chunks.values.items[i];
    }

    /// jump offset is encoded in 2 bytes of instructions
    inline fn get_jump_offset(self: *VM) usize {
        const offset: usize = @intFromEnum(self.code[self.code_idx]) << 8
                            | @intFromEnum(self.code[self.code_idx + 1]);
        return offset;
    }

    fn run_vm(self: *VM) !void {
        while (self.code.len > self.code_idx) {
            if (comptime debug.ENABLE_LOGGING) {
                try self.debug_vm();
            }
            const instruction = self.code[self.code_idx];
            self.code_idx += 1;
            switch (instruction) {
                .CONSTANT => {
                    const val = self.read_val_from_chunk();
                    self.push(val);
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
                    switch (try self.peek(0)) {
                        .number => {
                            const num = -self.pop().number;
                            self.push(Value.setNumber(num));
                        },
                        else => return error.OperandMustBeNumber
                    }
                },
                .PRINT => {
                    const stdout = std.io.getStdOut();
                    try printValue(self.pop());
                    _ = try stdout.writer().write("\n");
                },
                .DEFINE_GLOBAL => {
                    const name = self.read_val_from_chunk();
                    switch (name) {
                        .string => |s| {
                            try self.globals.put(s.str, try self.peek(0));
                            _ = self.pop();
                        },
                        else => return error.VarNameMustBeString
                    }
                },
                .GET_LOCAL => {
                    const i = @intFromEnum(self.code[self.code_idx]);
                    self.code_idx += 1;
                    self.push(self.stack[i]);
                },
                .SET_LOCAL => {
                    const i = @intFromEnum(self.code[self.code_idx]);
                    self.code_idx += 1;
                    self.stack[i] = try self.peek(0);
                },
                .GET_GLOBAL => {
                    const name = self.read_val_from_chunk();
                    switch (name) {
                        .string => |s| {
                            if (self.globals.get(s.str)) |val| {
                                self.push(val);
                            } else {
                                var buf: [256]u8 = undefined;
                                _ = std.fmt.bufPrint(buf[0..], "Variable not defined: {s}", .{s.str}) catch {
                                    std.debug.print("Could not format error variable", .{});
                                    std.process.exit(64);
                                };
                                self.runtimeError(&buf);
                                return error.VarUndefined;
                            }
                        },
                        else => return error.VarNameMustBeString
                    }
                },
                .SET_GLOBAL => {
                    const name = self.read_val_from_chunk();
                    switch (name) {
                        .string => |s| {
                            self.globals.put(s.str, try self.peek(0)) catch {
                                var buf: [256]u8 = undefined;
                                _ = std.fmt.bufPrint(buf[0..], "Variable not defined: {s}", .{s.str}) catch {
                                    std.debug.print("Could not format error variable", .{});
                                    std.process.exit(64);
                                };
                                self.runtimeError(&buf);
                                return error.VarUndefined;
                            };
                        },
                        else => {
                            return error.VarNameMustBeString;
                        }
                    }
                },
                .JUMP => {
                    const offset = self.get_jump_offset();
                    self.code_idx += offset;
                },
                .JUMP_IF_FALSE => {
                    const offset = self.get_jump_offset();
                    self.code_idx += 2;
                    if (isFalsy(try self.peek(0))) {
                        self.code_idx += offset;
                    }
                },
                .LOOP => {
                    const offset = self.get_jump_offset();
                    self.code_idx -= offset;
                },
                .POP => {
                    _ = self.pop();
                },
                .RETURN => continue,
                _ => break
            }
        }

    }

    pub fn run(self: *VM) InterpretResult {
        self.run_vm() catch |err| {
            switch (err) {
                error.OperandMustBeNumber => self.runtimeError("Operand must be a number."),
                error.InvalidArithmeticOp => self.runtimeError("Can only do arithmetic operations on numbers."),
                error.VarNameMustBeString => self.runtimeError("Variable names must be string"),
                error.VarUndefined => {},
                else => self.runtimeError("Unknown error.")
            }
            return InterpretResult.INTERPRET_RUNTIME_ERROR;
        };
        return InterpretResult.INTERPRET_OK;
    }

    inline fn resetStack(self: *VM) void {
        self.stack_idx = 0;
        self.stack = [_]Value{Value.setVoid()} ** STACK_SIZE;
    }

    inline fn peek(self: *VM, distance: usize) !Value {
        return self.stack[self.stack_idx - distance - 1];
    }

    inline fn push(self: *VM, value: Value) void {
        self.stack[self.stack_idx] = value;
        self.stack_idx += 1;
    }

    inline fn pop(self: *VM) Value {
        self.stack_idx -= 1;
        const value = self.stack[self.stack_idx];
        self.stack[self.stack_idx] = Value.setVoid();
        return value;
    }
};
