const std = @import("std");
const lexer = @import("scanner.zig");
const c = @import("chunks.zig");
const parserule = @import("parserule.zig");
const debug = @import("debug.zig");
const values = @import("values.zig");

const Scanner = lexer.Scanner;
const TokenType = lexer.TokenType;
const Token = lexer.Token;
const Chunks = c.Chunks;
const Opcode = c.Opcode;
const Precedence = parserule.Precedence;
const ParseRule = parserule.ParseRule;
const Value = values.Value;
const LOGGING  = debug.ENABLE_LOGGING;
const rules = parserule.rules;



pub const Parser = struct {
    compilingChunk: Chunks,
    current: *const Token,
    previous: *const Token,
    scanner: Scanner,
    hadError: bool,
    panicMode: bool,

    pub fn init(scanner: Scanner, chunks: Chunks) Parser {
        return Parser {
            .compilingChunk = chunks,
            .current = undefined,
            .previous = undefined,
            .scanner = scanner,
            .hadError = false,
            .panicMode = false
        };
    }

    inline fn errorAt(self: *Parser, token: *const Token, message: []const u8) void {
        if (self.panicMode) return;
        self.panicMode = true;
        const stdErr = std.io.getStdErr().writer();
        stdErr.print("[line {d}] Error", .{token.line}) catch unreachable;
        switch (token.ttype) {
            .EOF => stdErr.print(" at end", .{}) catch unreachable,
            .ERROR => {},
            else => stdErr.print(" at '{s}'", .{token.start}) catch unreachable
        }
        stdErr.print("{s}\n", .{message}) catch unreachable;
        self.hadError = true;
    }

    inline fn errorAtPrevious(self: *Parser, message: []const u8) void {
        self.errorAt(self.previous, message);
    }

    inline fn errorAtCurrent(self: *Parser, message: []const u8) void {
        self.errorAt(self.current, message);
    }

    pub fn advance(self: *Parser) void {
        self.previous = self.current;
        while (true) {
            self.current = &self.scanner.scanToken(); 
            if (self.current.ttype != .ERROR) break;
            self.errorAtCurrent(self.current.start);
        }
    }

    pub fn consume(self: *Parser, ttype: TokenType, message: []const u8) void {
        if (self.current.ttype == ttype) {
            self.advance();
        } else {
            self.errorAtCurrent(message);
        }
    }

    fn emitByte(self: *Parser, byte: Opcode) void {
        self.compilingChunk.writeChunk(byte, self.previous.line);
    }

    inline fn emitBytes(self: *Parser, byte1: Opcode, byte2: Opcode) void {
        self.emitByte(byte1);
        self.emitByte(byte2);
    }

    inline fn emitReturn(self: *Parser) void {
        self.emitByte(Opcode.RETURN);
    }

    pub inline fn endCompiler(self: *Parser) void {
        self.emitReturn();
        if (comptime LOGGING) {
            debug.disassembleChunk(self.compilingChunk, "code") catch |e| {
                std.debug.print("Could not print debug {}", .{e});
            };
        }
    }

    inline fn makeConstant(self: *Parser, value: Value) Opcode {
        const constant = self.compilingChunk.addConstant(value);
        return constant;
    }

    inline fn emitConstant(self: *Parser, value: Value) void {
        self.emitBytes(Opcode.CONSTANT, self.makeConstant(value));
    }

    inline fn getRule(t_type: TokenType) *const ParseRule {
        return &rules[@intFromEnum(t_type)];
    }

    inline fn parsePrecedence(self: *Parser, precIndex: usize) void {
        self.advance();
        const prefix_rule = getRule(self.previous.ttype).prefix orelse {
            self.errorAtPrevious("Expect expression");
            return;
        };
        prefix_rule(self);

        while (precIndex <= @intFromEnum(getRule(self.current.ttype).precedence)) {
            self.advance();
            const infix_rule = getRule(self.previous.ttype).infix orelse {
                self.errorAtPrevious("Expect expression");
                return;
            };
            infix_rule(self);
        }
    }

    inline fn expression(self: *Parser) void {
        self.parsePrecedence(@intFromEnum(Precedence.ASSIGNMENT));
    }

    pub fn number(self: *Parser) void {
        const num = std.fmt.parseFloat(f64, self.previous.start) catch {
            std.debug.print("Could not parse float!", .{});
            std.process.exit(64);
        };
        const value = Value.setNumber(num);
        self.emitConstant(value);
    }

    pub fn unary(self: *Parser) void {
        const op_type = self.previous.ttype;
        self.parsePrecedence(@intFromEnum(Precedence.UNARY));

        switch (op_type) {
            .MINUS => self.emitByte(Opcode.NEGATE),
            else => unreachable
        }
    }

    pub fn binary(self: *Parser) void {
        const op_type = self.previous.ttype;
        const rule = getRule(op_type);
        const precedence: usize = @intFromEnum(rule.precedence) + 1;
        self.parsePrecedence(precedence);

        switch (op_type) {
            .PLUS => self.emitByte(.ADD),
            .MINUS => self.emitByte(.SUBTRACT),
            .STAR => self.emitByte(.MULTIPLY),
            .SLASH => self.emitByte(.DIVIDE),
            else => unreachable
        }
    }

    pub fn grouping(self: *Parser) void {
        self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after expression.");
    }
};

pub fn compile(source: []u8, chunks: Chunks) bool {
    const scanner = Scanner.init(source);
    var parser = Parser.init(scanner, chunks);
    parser.advance();
    parser.expression();
    parser.consume(.EOF, "Expect end of expression.");
    parser.endCompiler();
    return !parser.hadError;
}

