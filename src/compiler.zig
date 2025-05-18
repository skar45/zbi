const std = @import("std");
const s = @import("scanner.zig");
const c = @import("chunks.zig");

const Scanner = s.Scanner;
const TokenType = s.TokenType;
const Token = s.Token;
const Chunks = c.Chunks;
const Opcode = c.Opcode;

pub const Precedence = enum {
    NONE,
    ASSIGNMENT,
    OR,
    AND,
    EQUALITY,
    COMPARISION,
    TERM,
    FACTOR,
    UNARY,
    CALL,
    PRIMARY
};

const ParseFn = fn () void;

const ParseRule = struct {
    prefix: *ParseFn,
    suffix: *ParseFn,
    precednce: Precedence
};

const rules = comptime {
    var rules: []const ParseRule = undefined;
    rules[TokenType.LEFT_PAREN] = {
    }
};

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
            if (self.current.ttype != TokenType.ERROR) break;
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

    fn emitByte(self: *Parser, byte: u8) void {
        self.compilingChunk.writeChunk(byte, self.previous.line);
    }

    inline fn emitBytes(self: *Parser, byte1: u8, byte2: u8) void {
        self.emitByte(byte1);
        self.emitByte(byte2);
    }

    inline fn emitReturn(self: *Parser) void {
        self.emitByte(Opcode.RETURN);
    }

    pub inline fn endCompiler(self: *Parser) void {
        self.emitReturn();
    }

    inline fn makeConstant(comptime T: type, self: *Parser, value: T) u8 {
        const constant = self.compilingChunk.addConstant(value);
        return constant;
    }

    inline fn emitConstant(comptime T: type, self: *Parser, value: T) void {
        self.emitBytes(Opcode.CONSTANT, self.makeConstant(f64, value));
    }

    inline fn number(self: *Parser) void {
        const value = std.fmt.parseFloat(f64, self.previous.start);
        self.emitConstant(value);
    }

    inline fn parsePrecedence(self: *Parser, prec: Precedence) {
    }

    inline fn expression(self: *Parser) void {
        self.parsePrecedence(Precedence.ASSIGNMENT);
    }

    inline fn unary(self: *Parser) void {
        const op_type = self.previous.ttype;
        self.parsePrecedence(Precedence.UNARY);

        switch (op_type) {
            .MINUS => self.emitByte(Opcode.NEGATE),
            else => unreachable
        }
    }

    inline fn binary(self: *Parser) void {
        const op_type = self.previous.ttype;
        const rule = self.getRule(op_type);
        self.parsePrecedence(@enumFromInt(rule.precedence + 1));

        switch (op_type) {
            .PLUS => self.emitByte(Opcode.ADD),
            .MINUS => self.emitByte(Opcode.SUBTRACT),
            .STAR => self.emitByte(Opcode.MULTIPLY),
            .SLASH => self.emitByte(Opcode.DIVIDE),
            else => unreachable
        }
    }

    inline fn grouping(self: *Parser) void {
        self.expression();
        self.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression.");
    }
};

pub fn compile(source: []u8, chunks: Chunks) bool {
    const scanner = Scanner.init(source);
    var parser = Parser.init(scanner, chunks);
    // _ = scanner.expression();
    parser.consume(TokenType.EOF, "Expect end of expression.");
    return !parser.hadError;
}
