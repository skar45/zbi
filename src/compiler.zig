const std = @import("std");
const lexer = @import("scanner.zig");
const c = @import("chunks.zig");
const parserule = @import("parserule.zig");
const debug = @import("debug.zig");
const values = @import("values.zig");

const Allocator = std.mem.Allocator;
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
    compilingChunk: *Chunks,
    token_buf: [2]Token,
    scanner: Scanner,
    hadError: bool,
    panicMode: bool,
    _allocator: *const Allocator,

    pub fn init(scanner: Scanner, chunks: *Chunks, allocator: *const Allocator) Parser {
        var mut_scanner = scanner;
        const token = mut_scanner.scanToken();
        const token_buf: [2]Token = [2]Token{token, token};
        return Parser {
            .compilingChunk = chunks,
            .token_buf = token_buf,
            .scanner = mut_scanner,
            .hadError = false,
            .panicMode = false,
            ._allocator = allocator
        };
    }

    inline fn previous(self: *Parser) *const Token {
        return &self.token_buf[0];
    }

    inline fn current(self: *Parser) *const Token {
        return &self.token_buf[1];
    }

    inline fn errorAt(self: *Parser, token: *const Token, message: []const u8) void {
        if (self.panicMode) return;
        self.panicMode = true;
        const stdErr = std.io.getStdErr().writer();
        stdErr.print("[line {d}] Error", .{token.line}) catch unreachable;
        switch (token.ttype) {
            TokenType.EOF => stdErr.print(" at end", .{}) catch unreachable,
            TokenType.ERROR => {},
            else => stdErr.print(" at '{s}'", .{token.start.items}) catch unreachable
        }
        stdErr.print(" {s}\n", .{message}) catch unreachable;
        self.hadError = true;
    }

    inline fn errorAtPrevious(self: *Parser, message: []const u8) void {
        self.errorAt(self.previous(), message);
    }

    inline fn errorAtCurrent(self: *Parser, message: []const u8) void {
        self.errorAt(self.current(), message);
    }

    inline fn match_prev(self: *Parser, ttype: TokenType) bool {
        return if (self.previous().ttype == ttype) true else false ;
    }

    inline fn match(self: *Parser, ttype: TokenType) bool {
        return if (self.current().ttype == ttype) true else false ;
    } 

    pub fn advance(self: *Parser) void {
        self.token_buf[0] = self.token_buf[1];
        self.token_buf[1] = self.scanner.scanToken(); 
        if (self.current().ttype != .ERROR) return;
        self.errorAtCurrent(self.current().start.items);
    }

    pub fn consume(self: *Parser, ttype: TokenType, message: []const u8) void {
        if (self.current().ttype == ttype) {
            self.advance();
        } else {
            self.errorAtCurrent(message);
        }
    }

    fn emitByte(self: *Parser, byte: Opcode) void {
        self.compilingChunk.writeChunk(byte, self.previous().line);
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

    fn synchronize(self: *Parser) void {
        self.panicMode = false;

        while (!self.match(TokenType.EOF)) {
            if (self.match_prev(TokenType.SEMICOLON)) return;
            switch (self.current().ttype) {
                .CLASS, .FUN, .VAR, .FOR,
                .IF, .WHILE, .PRINT, .RETURN => return,
                _ => self.advance()
            }
        }
    }

    inline fn getRule(t_type: TokenType) *const ParseRule {
        return &rules[@intFromEnum(t_type)];
    }

    inline fn parsePrecedence(self: *Parser, precIndex: usize) void {
        self.advance();
        const prefix_rule = getRule(self.previous().ttype).prefix orelse {
            self.errorAtPrevious("Expect expression");
            return;
        };
        prefix_rule(self);

        while (precIndex <= @intFromEnum(getRule(self.current().ttype).precedence)) {
            self.advance();
            const infix_rule = getRule(self.previous().ttype).infix orelse {
                self.errorAtPrevious("Expect expression");
                return;
            };
            infix_rule(self);
        }
    }

    inline fn identifierConstant(self: *Parser, name: *const Token) Opcode {
        const str = Value.setString(name.start.items, self._allocator);
        return self.makeConstant(str);
    }

    inline fn parseVariable(self: *Parser, msg: []const u8) Opcode {
        self.consume(.IDENTIFIER, msg);
        return self.identifierConstant(self.previous());
    }

    inline fn defineVariable(self: *Parser, global: Opcode) void {
        self.emitBytes(.DEFINE_GLOBAL, global);
    }

    inline fn expression(self: *Parser) void {
        self.parsePrecedence(@intFromEnum(Precedence.ASSIGNMENT));
    }

    inline fn expressionStmt(self: *Parser) void {
        self.expression();
        self.consume(.SEMICOLON, "Expected ';' after expression");
        self.emitByte(.POP);
    }

    inline fn printStmt(self: *Parser) void {
        self.expression();
        self.consume(.SEMICOLON, "Expected ';' after print expression");
        self.emitByte(.PRINT);
    }

    inline fn statement(self: *Parser) void {
        if (self.match(.PRINT)) {
            self.advance();
            self.printStmt();
        }
    }

    inline fn varDeclaration(self: *Parser) void {
        const global = self.parseVariable("Expect variable name");
        if (self.match(.EQUAL)) {
            self.expression();
        } else {
            self.emitByte(.NIL);
        }
        self.consume(.SEMICOLON, "Expected ';' after var declaration");
        self.defineVariable(global);
    }

    inline fn declaration(self: *Parser) void {
        if (self.match(.VAR)) {
            self.advance();
            self.varDeclaration();
        } else {
            self.statement();
        }
    }

    inline fn namedVariable(self: *Parser, name: *const Token) void {
        const arg = self.identifierConstant(name);
        self.emitBytes(.GET_GLOBAL, arg);
    }

    pub fn variable(self: *Parser) void {
        self.namedVariable(self.previous());
    }

    pub fn number(self: *Parser) void {
        const num = std.fmt.parseFloat(f64, self.previous().start.items) catch {
            std.debug.print("Could not parse float! \n", .{});
            std.process.exit(64);
        };
        const value = Value.setNumber(num);
        self.emitConstant(value);
    }

    pub fn string(self: *Parser) void {
        const str = self.previous().start.items;
        const value = Value.setString(str[1..(str.len - 1)], self._allocator);
        self.emitConstant(value);
    }

    pub fn unary(self: *Parser) void {
        const op_type = self.previous().ttype;
        self.parsePrecedence(@intFromEnum(Precedence.UNARY));

        switch (op_type) {
            .BANG => self.emitByte(Opcode.NOT),
            .MINUS => self.emitByte(Opcode.NEGATE),
            else => unreachable
        }
    }

    pub fn binary(self: *Parser) void {
        const op_type = self.previous().ttype;
        const rule = getRule(op_type);
        const precedence: usize = @intFromEnum(rule.precedence) + 1;
        self.parsePrecedence(precedence);

        switch (op_type) {
            .BANG_EQUAL => self.emitBytes(.EQUAL, .NOT),
            .EQUAL_EQUAL => self.emitByte(.EQUAL),
            .GREATER => self.emitByte(.GREATER),
            .GREATER_EQUAL => self.emitBytes(.LESS,  .NOT),
            .LESS => self.emitByte(.LESS),
            .LESS_EQUAL => self.emitBytes(.GREATER, .NOT),
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

    pub fn literal(self: *Parser) void {
        switch (self.previous().ttype) {
            .FALSE => self.emitByte(Opcode.FALSE),
            .NIL => self.emitByte(Opcode.NIL),
            .TRUE => self.emitByte(Opcode.TRUE),
            else => return
        }
    }
};

pub fn compile(source: []u8, chunks: *Chunks, allocator: *const Allocator) bool {
    var scanner = Scanner.init(source);
    defer scanner.deinit();
    var parser = Parser.init(scanner, chunks, allocator);
    while (!parser.match(TokenType.EOF)) {
        parser.declaration();
    }
    parser.consume(TokenType.EOF, "Expected end of file");
    parser.endCompiler();
    return !parser.hadError;
}

