const std = @import("std");

const ArrayList = std.ArrayList;

pub const TokenType = enum(usize) {
  // Single-character tokens.
  LEFT_PAREN = 0, RIGHT_PAREN,
  LEFT_BRACE, RIGHT_BRACE,
  COMMA, DOT, MINUS, PLUS,
  SEMICOLON, SLASH, STAR,
  // One or two character tokens.
  BANG, BANG_EQUAL,
  EQUAL, EQUAL_EQUAL,
  GREATER, GREATER_EQUAL,
  LESS, LESS_EQUAL,
  // Literals.
  IDENTIFIER, STRING, NUMBER,
  // Keywords.
  AND, CLASS, ELSE, FALSE,
  FOR, FUN, IF, NIL, OR,
  PRINT, RETURN, SUPER, THIS,
  TRUE, VAR, WHILE,
  ERROR, EOF
};


pub const Token = struct {
    ttype: TokenType,
    start: ArrayList(u8),
    line: usize,
};

pub const Scanner = struct {
    start: []const u8,
    current: []const u8,
    end: usize,
    line: usize,
    _allocator: std.heap.GeneralPurposeAllocator(.{}),

    pub fn init(source: []const u8) Scanner {
        const allocator = std.heap.GeneralPurposeAllocator(.{}).init;
        return Scanner {
            .start = source,
            .current = source,
            .end = @intFromPtr(source.ptr) + source.len,
            .line = 1,
            ._allocator = allocator,
        };
    }

    inline fn isAtEnd(self: *Scanner) bool {
        std.debug.print("end {d}\n", .{self.end});
        return @intFromPtr(self.current.ptr) == self.end;
    }

    pub inline fn advance(self: *Scanner) u8 {
        const char = self.current[0];
        self.current.ptr += 1;
        return char;
    }

    inline fn match(self: *Scanner, expected: u8) bool {
        // if (self.isAtEnd()) return false;
        if (self.current[0] != expected) return false;
        self.current.ptr += 1;
        return true;
    }

    inline fn peek(self: *Scanner) u8 {
        return self.current[0];
    }

    inline fn peekNext(self: *Scanner) u8 {
        // TODO: fix this
        // if (self.isAtEnd()) return 0;
        return self.current[1];
    }

    inline fn skipWhiteSpace(self: *Scanner) void {
        while (true) {
            switch (self.peek()) {
                ' ', '\r', '\t' => {
                    _ = self.advance();
                    return;
                },
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                    break;
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        while (self.peek() != '\n') _ = self.advance();
                    } else {
                        return;
                    }
                    return;
                },
                else => return
            }
        }
    }

    inline fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    inline fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn checkKeyword(
        self: *Scanner,
        start: usize,
        length: usize,
        rest: []const u8,
        ttype: TokenType) TokenType {
        const end = start + length;
        if (std.mem.eql(u8, self.start[start..end], rest)){
            return ttype;
        } else {
            return TokenType.IDENTIFIER;
        }
    }

    fn identifierType(self: *Scanner) TokenType {
         return switch (self.start[0]) {
            'a' => self.checkKeyword(1, 2, "nd", TokenType.AND),
            'c' => self.checkKeyword(1, 4, "lass", TokenType.CLASS),
            'e' => self.checkKeyword(1, 3, "lse", TokenType.ELSE),
            'f' =>{
                if (@intFromPtr(self.current.ptr) - @intFromPtr(self.start.ptr) > 1) {
                    return switch (self.start[1]) {
                        'a' => self.checkKeyword(2, 3, "lse", TokenType.FALSE),
                        'o' => self.checkKeyword(2, 1, "r",TokenType.FOR),
                        'u' => self.checkKeyword(2, 1, "n", TokenType.FUN),
                        else => TokenType.IDENTIFIER
                    };
                }
                return TokenType.IDENTIFIER;
            },
            'i' => self.checkKeyword(1, 1, "f", TokenType.IF),
            'n' => self.checkKeyword(1, 2, "il", TokenType.NIL),
            'o' => self.checkKeyword(1, 1, "r", TokenType.OR),
            'p' => self.checkKeyword(1, 4, "rint", TokenType.PRINT),
            'r' => self.checkKeyword(1, 5, "eturn", TokenType.RETURN),
            's' => self.checkKeyword(1, 4, "uper", TokenType.SUPER),
            't' => {
                if (@intFromPtr(self.current.ptr) - @intFromPtr(self.start.ptr) > 1) {
                    return switch (self.start[1]) {
                        'h' => self.checkKeyword(2, 2, "is", TokenType.THIS),
                        'r' => self.checkKeyword(2, 2, "ue",TokenType.TRUE),
                        else => TokenType.IDENTIFIER
                    };
                }
                return TokenType.IDENTIFIER;
            },
            'v' => self.checkKeyword(1, 3, "ar", TokenType.VAR),
            'w' => self.checkKeyword(1, 4, "hile", TokenType.WHILE),
            else => TokenType.IDENTIFIER
        };

    }

    fn makeToken(self: *Scanner, ttype: TokenType) Token {
        const token_len: usize = @intFromPtr(self.current.ptr) - @intFromPtr(self.start.ptr);
        var list = ArrayList(u8).initCapacity(self._allocator.allocator(), token_len) catch unreachable;
        for (self.start[0..token_len]) |v| {
            list.append(v) catch unreachable;
        }
        const token = Token {
            .ttype = ttype,
            .start = list,
            .line = self.line
        };
        return token;
    }

    fn errorToken(self: *Scanner, message: []const u8) Token {
        var list = ArrayList(u8).initCapacity(self._allocator.allocator(), message.len) catch unreachable;
        for (message) |v| {
            list.append(v) catch unreachable;
        }
        const token = Token {
            .ttype = TokenType.ERROR,
            .start = list,
            .line = self.line
        };
        return token;
    }

    fn identiferToken(self: *Scanner) Token {
        while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();
        return self.makeToken(self.identifierType());
    }

    fn numericLiteral(self: *Scanner) Token {
        while (isDigit(self.peek())) _ = self.advance();

        if (self.peek() == '.' and isDigit(self.peekNext())) {
            _ = self.advance();
            while (isDigit(self.peek())) _ = self.advance();
        }

        return self.makeToken(TokenType.NUMBER);
    }

    fn stringLiteral(self: *Scanner) Token {
        while (self.peek() != '"') {
            if (self.peek() == '\n') self.line += 1;
            const char = self.advance();
            if (char == 0) return self.errorToken("Unterminated string");
        }
        _ = self.advance();
        return self.makeToken(TokenType.STRING);
    }

    pub fn scanToken(self: *Scanner) Token {
        self.skipWhiteSpace();
        self.start = self.current;
        const c = self.advance();
        if (isAlpha(c)) return self.identiferToken();
        if (isDigit(c)) return self.numericLiteral();
        return switch (c) {
            '(' => self.makeToken(TokenType.LEFT_PAREN),
            ')' => self.makeToken(TokenType.RIGHT_PAREN),
            '{' => self.makeToken(TokenType.LEFT_BRACE),
            '}' => self.makeToken(TokenType.RIGHT_BRACE),
            ';' => self.makeToken(TokenType.SEMICOLON),
            ',' => self.makeToken(TokenType.COMMA),
            '.' => self.makeToken(TokenType.DOT),
            '-' => self.makeToken(TokenType.MINUS),
            '+' => self.makeToken(TokenType.PLUS),
            '*' => self.makeToken(TokenType.STAR),
            '/' => self.makeToken(TokenType.SLASH),
            '!' => self.makeToken(if (self.match('=')) TokenType.BANG_EQUAL else TokenType.BANG),
            '=' => self.makeToken(if (self.match('=')) TokenType.EQUAL_EQUAL else TokenType.EQUAL),
            '<' => self.makeToken(if (self.match('=')) TokenType.LESS_EQUAL else TokenType.LESS),
            '>' => self.makeToken(if (self.match('=')) TokenType.GREATER_EQUAL else TokenType.GREATER),
            '"' => self.stringLiteral(),
            0 => self.makeToken(TokenType.EOF),
            else => {
                var buf: [32]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Unexpected character: {d}", .{c}) catch unreachable;
                return self.errorToken(msg);
            }
        };
    }

    pub fn deinit(self: *Scanner) void {
        const check = self._allocator.deinit();
        switch(check) {
            .leak => std.debug.print("[Scanner] memory leak \n", .{}),
            .ok => {}
        }
    }
};

