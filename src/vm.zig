const std = @import("std");
const expect = @import("std").testing.expect;
const c = @import("chunks.zig");
const debug = @import("debug.zig");
const values = @import("values.zig");
const compiler = @import("compiler.zig");
const async_ = @import("async.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const printValue = values.printValue;
const Value = values.Value;
const Table = values.Table;
const Chunks = c.Chunks;
const OpCode = c.OpCode;
const DebugCode = debug.DebugCode;
const Future = async_.Future;

const STACK_SIZE = 256;
const MAX_CALL_STACK = 256;
const MAX_GLOBALS = 256;
const MAX_TABLES = 256;

const TOTAL_TABLE_SIZE: comptime_int = @sizeOf(Table) * 256 / 8;

const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

const VmError = error{
    InvalidArithmeticOp,
    OperandMustBeNumber,
    VarNameMustBeString,
    VarUndefined,
    InvalidCall,
    ArgsMismatch,
    InvalidTableOp
};

pub fn interpret(source: []u8, allocator: *const Allocator) InterpretResult {
    // @compileLog("size of 'Value'", @sizeOf(Value));
    var chunks = Chunks.init();
    defer chunks.deinit();
    if (!compiler.compile(source, &chunks, allocator)) {
        return InterpretResult.INTERPRET_COMPILE_ERROR;
    }
    var vm = VM.init(&chunks, allocator);
    defer vm.deinit();
    return vm.run();
}

pub const CallFrame = struct {
    base_ptr: usize,
    ret_ip: usize,
    ret_code: *const []OpCode,

    pub fn init() CallFrame {
        return CallFrame {
            .base_ptr = 0,
            .ret_ip = 0,
            .ret_code= undefined
        };
    }
};

pub const VM = struct {
    chunks: *Chunks,
    instructions: []OpCode,
    ip: usize,
    stack: [STACK_SIZE]Value,
    stack_ptr: usize,
    call_stack: [MAX_CALL_STACK]CallFrame,
    call_stack_ptr: usize,
    globals: [MAX_GLOBALS]Value,
    tables: ArrayList(Table),
    _allocator: *const Allocator,
    _fba_buf: [TOTAL_TABLE_SIZE]u8,
    _fba_alloc: Allocator,

    pub fn init(chunks: *Chunks, allocator: *const Allocator) VM {
        var buf: [TOTAL_TABLE_SIZE]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const fba_alloc = fba.allocator();
        const table_list = ArrayList(Table).initCapacity(fba_alloc, 32) catch unreachable;
        return VM {
            .chunks = chunks,
            .instructions = chunks.code_list.items[0].items,
            .ip = 0,
            .stack = [_]Value{Value.setVoid()} ** STACK_SIZE,
            .stack_ptr = 0,
            .call_stack = [_]CallFrame{CallFrame.init()} ** MAX_CALL_STACK,
            .call_stack_ptr = 0,
            .globals = [_]Value{Value.setVoid()} ** MAX_GLOBALS,
            .tables = table_list,
            ._allocator = allocator,
            ._fba_buf = buf,
            ._fba_alloc = fba_alloc
        };
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
        var segment: usize = 0;
        for (0..self.chunks.code_list.items.len) |i| {
            if (@intFromPtr(self.chunks.code_list.items[i].items.ptr) == 
                @intFromPtr(self.instructions.ptr)
            ) {
                segment = i;
                break;
            }
        }

        std.debug.print("\n", .{});
//         std.debug.print("constants: ", .{});
//         for (self.chunks.values.items) |v| {
//             std.debug.print("[ ", .{});
//             printValue(v) catch unreachable;
//             std.debug.print(" ]", .{});
//         }
// 
//         std.debug.print("\n", .{});
        const off: usize = self.ip;
        var debug_trace = DebugCode.init(segment, off, self.chunks);
        _ = try debug_trace.disassembleInstruction();
    }

    fn runtimeError(self: *VM, format: []const u8) void {
        std.debug.print("{s} \n", .{format});
        const instruction: usize  = self.ip;
        const line: usize = self.chunks.lines.items[instruction];
        std.debug.print("[line {d}] in script\n", .{line});
        self.reset();
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

    inline fn readValFromChunk(self: *VM) Value {
        const i = @intFromEnum(self.instructions[self.ip]);
        self.ip += 1;
        return self.chunks.values.items[i];
    }

    /// jump offset is encoded in 2 bytes of instructions
    inline fn getJumpOffset(self: *VM) usize {
        const offset: usize = @intFromEnum(self.instructions[self.ip]) << 8
                            | @intFromEnum(self.instructions[self.ip + 1]);
        return offset;
    }

    inline fn getFnOpcode(self: *VM, segment: usize) []OpCode {
        return self.chunks.code_list.items[segment].items;
    }

    fn runVM(self: *VM) !void {
        while (self.instructions.len > self.ip) {
            if (comptime debug.ENABLE_LOGGING) {
                try self.debug_vm();
            }
            const instruction = self.instructions[self.ip];
            self.ip += 1;
            switch (instruction) {
                .CONSTANT => {
                    const val = self.readValFromChunk();
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
                    const global_index: usize = @intFromEnum(self.instructions[self.ip]);
                    self.ip += 1;
                    const value = try self.peek(0);
                    self.globals[global_index] = value;
                },
                .GET_LOCAL => {
                    const i = @intFromEnum(self.instructions[self.ip]);
                    self.ip += 1;
                    const ptr = self.call_stack[self.call_stack_ptr].base_ptr;
                    self.push(self.stack[ptr + i]);
                },
                .SET_LOCAL => {
                    const i = @intFromEnum(self.instructions[self.ip]);
                    self.ip += 1;
                    const ptr = self.call_stack[self.call_stack_ptr].base_ptr;
                    self.stack[ptr + i] = try self.peek(0);
                },
                .GET_GLOBAL => {
                    const global_index: usize = @intFromEnum(self.instructions[self.ip]);
                    self.ip += 1;
                    const global_value = self.globals[global_index];
                    switch (global_value) {
                        .void => {
                            return error.VarUndefined;
                        },
                        else => self.push(global_value)
                    }
                },
                .SET_GLOBAL => {
                    const global_index: usize = @intFromEnum(self.instructions[self.ip]);
                    self.ip += 1;
                    const value = try self.peek(0);
                    switch (self.globals[global_index]) {
                        .void => {
                            return error.VarUndefined;
                        },
                        else => self.globals[global_index] = value
                    }
                },
                // TARGET TARGET
                .JUMP => {
                    const offset = self.getJumpOffset();
                    self.ip += (offset + 2);
                },
                .JUMP_IF_FALSE => {
                    const offset = self.getJumpOffset();
                    self.ip += 2;
                    if (isFalsy(try self.peek(0))) {
                        self.ip += offset;
                    }
                },
                .LOOP => {
                    const offset = self.getJumpOffset();
                    self.ip -= offset;
                },
                .POP => {
                    _ = self.pop();
                },
                // ARGLEN FN
                .CALL => {
                    self.call_stack_ptr += 1;
                    var call_frame = CallFrame.init();
                    const airity = @intFromEnum(self.instructions[self.ip]);

                    self.ip += 1;
                    call_frame.base_ptr = self.stack_ptr - airity;
                    call_frame.ret_ip = self.ip;
                    self.call_stack[self.call_stack_ptr] = call_frame;

                    const procedure = try self.peek(airity);
                    switch (procedure) {
                        .function => |f| {
                            if (airity != f.airity) {
                                var buf: [256]u8 = undefined;
                                _ = try std.fmt.bufPrint(buf[0..], "Expected {d} args", .{airity});
                                self.runtimeError(&buf);
                                return error.ArgsMismatch;
                            }
                            self.ip = 0;
                            self.instructions = self.getFnOpcode(f.fn_segment);
                        },
                        .closure => |_| unreachable,
                        else => return error.InvalidCall
                    }
                },
                // VAL RET
                .RETURN => {
                    const call_stack = self.call_stack[self.call_stack_ptr];
                    const ret_val = self.pop();
                    for (0..(self.stack_ptr - call_stack.base_ptr)) |_| {
                        _ = self.pop();
                    }
                    // Remove callee from the stack
                    _ = self.pop();
                    self.push(ret_val);
                    self.call_stack_ptr -= 1;
                    self.ip = call_stack.ret_ip;
                    self.instructions = self.getFnOpcode(self.call_stack_ptr);
                },
                .RETURN_NIL => {
                    const call_stack = self.call_stack[self.call_stack_ptr];
                    for (0..(self.stack_ptr - call_stack.base_ptr)) |_| {
                        _ = self.pop();
                    }
                    // Remove callee from the stack
                    _ = self.pop();
                    self.push(Value.setNil());
                    self.call_stack_ptr -= 1;
                    self.ip = call_stack.ret_ip;
                    self.instructions = self.getFnOpcode(self.call_stack_ptr);
                },
                // ARGLEN TABLE
                .DEFINE_TABLE => {
                    const assign_count = @intFromEnum(self.instructions[self.ip]);
                    self.ip += 1;
                    var table = Table.init(self._allocator);
                    for (0..assign_count) |_| {
                        const val = self.pop();
                        const key = self.pop();
                        table.insert(key, val);
                    }
                    self.tables.append(table) catch unreachable;
                    const ptr = @constCast(&self.tables.getLast());
                    self.push(Value.initTable(ptr));
                },
                .TABLE_GET => {
                    const key = self.pop();
                    const table = self.pop();
                    switch(table) {
                        .table => |t| {
                            if (t.*.map.get(key)) |v| {
                                self.push(v);
                            } else {
                                self.push(Value.setNil());
                            }
                        },
                        else => return error.InvalidTableOp
                    }
                },
                .TABLE_SET => {
                    const value = self.pop();
                    const key = self.pop();
                    const table_val = self.pop();
                    switch(table_val) {
                        .table => |t| {
                            t.*.insert(key, value);
                        },
                        else => return error.InvalidTableOp
                    }
                },
                _ => break
            }
        }

    }

    pub fn run(self: *VM) InterpretResult {
        self.runVM() catch |err| {
            switch (err) {
                error.OperandMustBeNumber => self.runtimeError("Operand must be a number."),
                error.InvalidArithmeticOp => self.runtimeError("Can only do arithmetic operations on numbers."),
                error.InvalidCall => self.runtimeError("Can only call functions"),
                error.VarUndefined => {},
                error.ArgsMismatch => {},
                else => self.runtimeError("Unknown error.")
            }
            return InterpretResult.INTERPRET_RUNTIME_ERROR;
        };
        return InterpretResult.INTERPRET_OK;
    }

    pub fn deinit(self: *VM) void {
        for (&self.stack) |*v| {
            v.deinit();
        }
    }

    inline fn reset(self: *VM) void {
        self.stack_ptr = 0;
        self.call_stack_ptr = 0;
        for (0..self.stack_ptr) |i| {
            self.stack[i] = Value.setVoid();
        }
        for (0..self.call_stack_ptr) |i| {
            self.call_stack[i] = CallFrame.init();
        }
    }

    inline fn peek(self: *VM, distance: usize) !Value {
        return self.stack[self.stack_ptr - distance - 1];
    }

    inline fn push(self: *VM, value: Value) void {
        self.stack[self.stack_ptr] = value;
        self.stack_ptr += 1;
    }

    inline fn pop(self: *VM) Value {
        self.stack_ptr -= 1;
        const value = self.stack[self.stack_ptr];
        self.stack[self.stack_ptr] = Value.setVoid();
        return value;
    }
};
