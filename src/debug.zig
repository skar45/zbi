const std = @import("std");
const config = @import("config");
const c = @import("chunks.zig");
const values = @import("values.zig");
const errors = @import("errors.zig");

const OpCode = c.OpCode;
const Chunks = c.Chunks;


pub const ENABLE_LOGGING = config.DEBUG;
pub const Writer = std.io.Writer(std.fs.File, std.posix.WriteError, std.fs.File.write);

pub const DebugCode = struct {
    segment: usize,
    offset: usize,
    chunks: *Chunks,
    stdout: Writer,

    pub fn init(segment: usize, offset: usize, chunks: *Chunks) DebugCode {
        const writer = std.io.getStdOut().writer();
        return DebugCode {
            .segment = segment,
            .offset = offset,
            .chunks = chunks,
            .stdout = writer
        };
    }

    inline fn print(self: *DebugCode, comptime format: []const u8, args: anytype) void {
        self.stdout.print(format, args) catch {
            std.debug.print("fuckoff ", .{});
        };
    }

    inline fn getLine(self: *DebugCode, offset: usize) usize {
        return self.chunks.lines.items[offset];
    }

    inline fn getOpCode(self: *DebugCode, offset: usize) OpCode {
        return self.chunks.code_list.items[self.segment].items[offset];
    }

    inline fn getOpCodeInt(self: *DebugCode, offset: usize) usize {
        return @intFromEnum(self.getOpCode(offset));
    }

    fn simpleInstruction(self: *DebugCode, comptime name: []const u8) usize {
        self.print("{s:<16} \n", .{name});
        return self.offset + 1;
    }

    fn defineTableInstruction(self: *DebugCode, comptime name: []const u8) usize {
        const args = self.getOpCodeInt(self.offset + 1);
        const idx  = self.getOpCodeInt(self.offset + 2);
        self.print("{s:<16} {d:5} ", .{name, idx});
        const value = self.chunks.values.items[idx];
        values.printValue(value) catch unreachable;
        self.print("({d})\n", .{args});
        return self.offset + 3;
    }

    fn callInstruction(self: *DebugCode, comptime name: []const u8) usize {
        const args = self.getOpCodeInt(self.offset + 1);
        self.print("{s:<16} {d:5} ({d}) \n", .{name, self.segment, args});
        return self.offset + 2;
    }

    fn jumpInstruction(self: *DebugCode, comptime name: []const u8, sign: isize) usize {
        var jump = self.getOpCodeInt(self.offset + 1) << 8;
        jump |= self.getOpCodeInt(self.offset + 2);
        const index = self.getOpCodeInt(self.offset + 1);
        const ioffset: isize = @intCast(self.offset);
        const ijump: isize = @intCast(jump);
        const target = ioffset + 3 + sign * ijump;
        self.print("{s:<16} {d:0>3} -> {d}\n", .{name, index, target});
        return self.offset + 3;
    }

    fn defineGlobalInstruction(self: *DebugCode, comptime name: []const u8) usize {
        const index = self.getOpCodeInt(self.offset + 1);
        self.print("{s:<16} {d:5}\n", .{name, index});
        return self.offset + 2;
    }

    fn byteInstruction(self: *DebugCode, comptime name: []const u8) usize {
        const index = self.getOpCodeInt(self.offset + 1);
        self.print("{s:<16} {d:0>3}\n", .{name, index});
        return self.offset + 2;
    }

    fn constantInstruction(self: *DebugCode, comptime name: []const u8) usize {
        const index = self.getOpCodeInt(self.offset + 1);
        self.print("{s:<16} {d:5} ", .{name, index});
        values.printValue(self.chunks.values.items[index]) catch unreachable;
        self.print("\n", .{});
        return self.offset + 2;
    }

    pub fn disassembleInstruction(self: *DebugCode) !usize {
        self.print("{d:0>4} ", .{self.offset});
        if (self.offset > 0 and self.getLine(self.offset) == self.getLine(self.offset - 1)) {
            self.print("   | ", .{});
        } else {
            self.print("{d:4} ", .{self.getLine(self.offset)});
        }

        const instruction: OpCode = self.getOpCode(self.offset);
        return switch (instruction) {
            .RETURN =>  self.simpleInstruction("OP_RETURN"),
            .RETURN_NIL => self.simpleInstruction("OP_RETURN_NIL"),
            .PRINT => self.simpleInstruction("OP_PRINT"),
            .CONSTANT =>self.constantInstruction("OP_CONSTANT"),
            .NIL => self.simpleInstruction("OP_NIL"),
            .TRUE => self.simpleInstruction("OP_TRUE"),
            .FALSE => self.simpleInstruction("OP_FALSE"),
            .NOT => self.simpleInstruction("OP_NOT"),
            .EQUAL => self.simpleInstruction("OP_EQUAL"),
            .GREATER => self.simpleInstruction("OP_GREATER"),
            .LESS => self.simpleInstruction("OP_LESS"),
            .ADD => self.simpleInstruction("OP_ADD"),
            .SUBTRACT => self.simpleInstruction("OP_SUBTRACT"),
            .MULTIPLY => self.simpleInstruction("OP_MULTIPLY"),
            .DIVIDE => self.simpleInstruction("OP_DIVIDE"),
            .NEGATE => self.simpleInstruction("OP_NEGATE"),
            .POP => self.simpleInstruction("OP_POP"),
            .GET_LOCAL => self.byteInstruction("OP_GET_LOCAL"),
            .SET_LOCAL => self.byteInstruction("OP_SET_LOCAL"),
            .DEFINE_GLOBAL => self.defineGlobalInstruction("OP_DEFINE_GLOBAL"),
            .GET_GLOBAL => self.constantInstruction("OP_GET_GLOBAL"),
            .SET_GLOBAL => self.constantInstruction("OP_SET_GLOBAL"),
            .DEFINE_TABLE => self.defineTableInstruction("OP_DEFINE_TABLE"),
            .TABLE_GET => self.byteInstruction("OP_TABLE_GET"),
            .TABLE_SET => self.byteInstruction("OP_TABLE_SET"),
            .JUMP => self.jumpInstruction("OP_JUMP", 1),
            .JUMP_IF_FALSE => self.jumpInstruction("OP_JUMP_IF_ELSE", 1),
            .LOOP => self.jumpInstruction("OP_LOOP", -1),
            .CALL => self.callInstruction("OP_CALL"),
            _ => error.UnknownOpcode
        };
    }

    pub fn disassembleChunk(self: *DebugCode, name: []const u8) !void {
        self.print("== {s} ==\n", .{name});
        self.offset = 0;
        for (0..self.chunks.code_list.items.len) |idx| {
            std.debug.print("\n", .{});
            std.debug.print("=== {d} ===\n", .{idx});
            self.offset = 0;
            while (self.offset < self.chunks.code_list.items[idx].items.len){
                self.offset = try self.disassembleInstruction();
            }
        }
    }
};
