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

const MAX_LOCALS = 256;
const UINT16_MAX = 1 << 16 - 1;

// TODO:
// - For loops
// - Pattern match
// - Loop control flow: break, continue

pub const Local = struct {
    name: Token,
    depth: isize,
};

pub const Compiler = struct {
    locals: [MAX_LOCALS]Local,
    local_count: u32,
    scope_depth: u32,

    pub fn init() Compiler {
        return Compiler {
            .locals = undefined,
            .local_count = 0,
            .scope_depth = 0
        };
    }
};

pub const Parser = struct {
    compilingChunk: *Chunks,
    token_buf: [2]Token,
    scanner: Scanner,
    compiler: *Compiler,
    hadError: bool,
    panicMode: bool,
    canAssign: bool,
    _allocator: *const Allocator,

    pub fn init(scanner: Scanner, compiler: *Compiler, chunks: *Chunks, allocator: *const Allocator) Parser {
        var mut_scanner = scanner;
        const token = mut_scanner.scanToken();
        const token_buf: [2]Token = [2]Token{token, token};
        return Parser {
            .compilingChunk = chunks,
            .token_buf = token_buf,
            .scanner = mut_scanner,
            .compiler = compiler,
            .hadError = false,
            .panicMode = false,
            .canAssign = false,
            ._allocator = allocator
        };
    }

    inline fn previous(self: *Parser) *const Token {
        return &self.token_buf[0];
    }

    inline fn current(self: *Parser) *const Token {
        return &self.token_buf[1];
    }

    inline fn currentChunkCount(self: *Parser) usize {
        return self.compilingChunk.code.items.len;
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

    inline fn emitByte(self: *Parser, byte: Opcode) void {
        self.compilingChunk.writeChunk(byte, self.previous().line);
    }

    inline fn emitBytes(self: *Parser, byte1: Opcode, byte2: Opcode) void {
        self.emitByte(byte1);
        self.emitByte(byte2);
    }

    inline fn emitLoop(self: *Parser, start: usize) void {
        self.emitByte(.LOOP);
        const offset = self.currentChunkCount() - start + 2;
        if (offset > UINT16_MAX) self.errorAtCurrent("Loop body above maximum");
        self.emitByte(@intFromEnum((offset >> 8) & 0xFF));
        self.emitByte(@intFromEnum(offset & 0xFF));
    }

    inline fn emitJump(self: *Parser, instruction: Opcode) usize {
        self.emitByte(instruction);
        self.emitByte(@enumFromInt(0xFF));
        self.emitByte(@enumFromInt(0xFF));
        return self.currentChunkCount() - 2;
    }

    inline fn emitReturn(self: *Parser) void {
        self.emitByte(Opcode.RETURN);
    }

    inline fn makeConstant(self: *Parser, value: Value) Opcode {
        const constant = self.compilingChunk.addConstant(value);
        return constant;
    }

    inline fn emitConstant(self: *Parser, value: Value) void {
        self.emitBytes(Opcode.CONSTANT, self.makeConstant(value));
    }

    inline fn patchJump(self: *Parser, offset: usize) void {
        const jump = self.currentChunkCount() - offset - 2;
        if (jump > UINT16_MAX or jump < 0) {
            self.errorAtCurrent("Jump error");
        }

        self.compilingChunk.code.items[offset] = @enumFromInt((jump >> 8) & 0xFF);
        self.compilingChunk.code.items[offset + 1] = @enumFromInt(jump & 0xFF);
    }

    pub inline fn endCompiler(self: *Parser) void {
        self.emitReturn();
        if (comptime LOGGING) {
            debug.disassembleChunk(self.compilingChunk, "code") catch |e| {
                std.debug.print("Could not print debug {}", .{e});
            };
        }
    }

    inline fn beginScope(self: *Parser) void {
        self.compiler.scope_depth += 1;
    }

    inline fn endScope(self: *Parser) void {
        self.compiler.scope_depth -= 1;
        const locals = &self.compiler.locals;
        while (self.compiler.local_count > 0 and locals[self.compiler.local_count - 1].depth > self.compiler.scope_depth) {
            self.emitByte(.POP);
            self.compiler.local_count -= 1;
        }
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
        const rule = getRule(self.previous().ttype);
        const prefix_fn = rule.prefix orelse {
            self.errorAtPrevious("Expected expression");
            return;
        };
        self.canAssign = @intFromEnum(rule.precedence) <= @intFromEnum(Precedence.ASSIGNMENT);
        prefix_fn(self);

        while (precIndex <= @intFromEnum(getRule(self.current().ttype).precedence)) {
            self.advance();
            const infix_fn = getRule(self.previous().ttype).infix orelse {
                self.errorAtPrevious("Expected expression");
                return;
            };
            infix_fn(self);
        }
    }

    inline fn compareIdentifier(name1: *const Token, name2: *const Token) bool {
       return std.mem.eql(u8, name1.start.items, name2.start.items);
    }

    inline fn resolveLocal(self: *Parser, name: *const Token) ?usize {
        const local_count = self.compiler.local_count;
        for (0..local_count) |i| {
            const index = local_count - 1 - i;
            const local = self.compiler.locals[index];
            if (compareIdentifier(name, &local.name)) {
                if (local.depth == -1) {
                    self.errorAtCurrent("Can't read variables in its own initializer");
                }
                return index;
            }
        }
        return null;
    }

    inline fn identifierConstant(self: *Parser, name: *const Token) Opcode {
        const str = Value.setString(name.start.items, self._allocator);
        return self.makeConstant(str);
    }

    inline fn addLocal(self: *Parser, token: *const Token) void {
        if (self.compiler.local_count >= MAX_LOCALS) {
            self.errorAtCurrent("Local variables exceed the allotted size");
            return;
        }
        const local = Local {
            .depth = -1,
            .name = token.*
        };
        self.compiler.locals[self.compiler.local_count] = local;
        self.compiler.local_count += 1;
    }

    inline fn declareVariable(self: *Parser) void {
        if (self.compiler.scope_depth == 0) return;
        const name = self.previous();
        const local_count = self.compiler.local_count;
        for (0..local_count) |i| {
            const local = self.compiler.locals[local_count - 1 - i];
            if (local.depth != -1 and local.depth < self.compiler.scope_depth) break;
            if (compareIdentifier(&local.name, name)) {
                self.errorAtPrevious("Variable name already exists in the current scope");
            }
        }
        self.addLocal(name);
    }

    fn block(self: *Parser) void {
        while (!self.match(.RIGHT_BRACE) and !self.match(.EOF)) {
            self.declaration();
        }
        self.consume(.RIGHT_BRACE, "Expected '}' after block");
    }

    inline fn markInitialized(self: *Parser) void {
        self.compiler.locals[self.compiler.local_count - 1].depth = self.compiler.scope_depth;
    }

    inline fn parseVariable(self: *Parser, msg: []const u8) Opcode {
        self.consume(.IDENTIFIER, msg);
        self.declareVariable();
        if (self.compiler.scope_depth > 0) return Opcode.RETURN;
        return self.identifierConstant(self.previous());
    }

    inline fn defineVariable(self: *Parser, global: Opcode) void {
        if (self.compiler.scope_depth > 0) {
            self.markInitialized();
            return;
        }
        self.emitBytes(.DEFINE_GLOBAL, global);
    }

    inline fn expression(self: *Parser) void {
        self.parsePrecedence(@intFromEnum(Precedence.ASSIGNMENT));
    }

    fn expressionStmt(self: *Parser) void {
        self.expression();
        self.consume(.SEMICOLON, "Expected ';' after expression");
        self.emitByte(.POP);
    }

    fn ifStatement(self: *Parser) void {
        self.consume(.LEFT_PAREN, "Expected '(' after 'if'");
        self.expression();
        self.consume(.RIGHT_PAREN, "Expected ')' after condition");

        const then_jump = self.emitJump(.JUMP_IF_FALSE);
        self.emitByte(.POP);
        self.statement();
        const else_jump = self.emitJump(.JUMP);
        self.patchJump(then_jump);
        self.emitByte(.POP);
        if (self.match(.ELSE)) {
            self.advance();
            self.statement();
        }
        self.patchJump(else_jump);
    }

    fn printStmt(self: *Parser) void {
        self.expression();
        self.consume(.SEMICOLON, "Expected ';' after print expression");
        self.emitByte(.PRINT);
    }

    fn whileStmt(self: *Parser) void {
        const loop_start = self.compilingChunk.code.items.len;
        self.consume(.LEFT_PAREN, "Expected '(' after 'while'");
        self.expression();
        self.consume(.RIGHT_PAREN, "Expected ')' after condition");

        const exit_jump = self.emitJump(.JUMP_IF_FALSE);
        self.emitByte(.POP);
        self.statement();
        self.emitLoop(loop_start);
        self.patchJump(exit_jump);
        self.emitByte(.POP);
    }

    fn statement(self: *Parser) void {
        switch (self.current().ttype) {
            .PRINT => {
                self.advance();
                self.printStmt();
            },
            .IF => {
                self.advance();
                self.ifStatement();
            },
            .LEFT_BRACE => {
                self.advance();
                self.beginScope();
                self.block();
                self.endScope();
            },
            else => self.expressionStmt()
        }
    }

    inline fn varDeclaration(self: *Parser) void {
        const global = self.parseVariable("Expect variable name");
        if (self.match(.EQUAL)) {
            self.advance();
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
        var getOp: Opcode = undefined;
        var setOp: Opcode = undefined;
        var arg: Opcode = undefined;
        if (self.resolveLocal(name)) |v| {
            arg = @enumFromInt(v);
            getOp = .GET_LOCAL;
            setOp = .SET_LOCAL;
        } else {
            arg = self.identifierConstant(name);
            getOp = .GET_GLOBAL;
            setOp = .SET_GLOBAL;
        }
        if (self.canAssign and self.match(.EQUAL)) {
            self.advance();
            self.emitBytes(setOp, arg);
        } else {
            self.emitBytes(getOp, arg);
        }
    }

    pub fn variable(self: *Parser) void {
        self.namedVariable(self.previous());
    }

    pub fn and_(self: *Parser) void {
        const end_jump = self.emitJump(.JUMP_IF_FALSE);
        self.emitByte(.POP);
        self.parsePrecedence(@intFromEnum(Precedence.AND));
        self.patchJump(end_jump);
    }

    pub fn or_(self: *Parser) void {
        const else_jump = self.emitJump(.JUMP_IF_FALSE);
        const end_jump = self.emitJump(.JUMP);

        self.patchJump(else_jump);
        self.emitByte(.POP);
        self.parsePrecedence(@intFromEnum(Precedence.OR));
        self.patchJump(end_jump);
    }

    pub fn number(self: *Parser) void {
        const num = std.fmt.parseFloat(f64, self.previous().start.items) catch {
            self.errorAt(self.previous(), "Could not parse float! \n");
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
    var compiler = Compiler.init();
    var parser = Parser.init(scanner, &compiler, chunks, allocator);
    while (!parser.match(TokenType.EOF)) {
        parser.declaration();
    }
    parser.consume(TokenType.EOF, "Expected end of file");
    parser.endCompiler();
    return !parser.hadError;
}

