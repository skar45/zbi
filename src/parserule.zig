const TokenType = @import("scanner.zig").TokenType;
const Parser = @import("compiler.zig").Parser;

pub const GrammarFn = *const fn (p: * Parser) void;

const grouping = Parser.grouping;
const binary = Parser.binary;
const unary = Parser.unary;
const number = Parser.number;

pub const Precedence = enum(usize) {
    NONE,
    ASSIGNMENT,
    OR,
    AND,
    EQUALITY,
    COMPARISON,
    TERM,
    FACTOR,
    UNARY,
    CALL,
    PRIMARY
};

pub const ParseRule = struct {
    prefix: ?GrammarFn,
    infix: ?GrammarFn,
    precedence: Precedence
};

pub const rules = blk: {
    var r: [40]ParseRule = undefined;
    const setRule = struct {
        fn sr(cr: *[40]ParseRule, t_type: TokenType, pre: ?GrammarFn, suf: ?GrammarFn, prec: Precedence) void {
            cr[@intFromEnum(t_type)] = ParseRule {
                .prefix = pre,
                .infix = suf,
                .precedence = prec,
            };
        }
    }.sr;

    setRule(&r, .LEFT_PAREN, grouping, null, .NONE);
    setRule(&r, .RIGHT_PAREN, null, null, .NONE);
    setRule(&r, .LEFT_BRACE, null, null, .NONE);
    setRule(&r, .RIGHT_BRACE, null, null, .NONE);
    setRule(&r, .COMMA, null, null, .NONE);
    setRule(&r, .DOT, null, null, .NONE);
    setRule(&r, .MINUS, unary, binary, .NONE);
    setRule(&r, .PLUS, null, binary, .TERM);
    setRule(&r, .SEMICOLON, null, null, .NONE);
    setRule(&r, .SLASH, null, binary, .FACTOR);
    setRule(&r, .STAR, null, binary, .FACTOR);
    setRule(&r, .BANG, null, null, .NONE);
    setRule(&r, .BANG_EQUAL, null, null, .NONE);
    setRule(&r, .EQUAL, null, null, .NONE);
    setRule(&r, .EQUAL_EQUAL, null, null, .NONE);
    setRule(&r, .GREATER, null, null, .NONE);
    setRule(&r, .GREATER_EQUAL, null, null, .NONE);
    setRule(&r, .LESS, null, null, .NONE);
    setRule(&r, .LESS_EQUAL, null, null, .NONE);
    setRule(&r, .IDENTIFIER, null, null, .NONE);
    setRule(&r, .STRING, null, null, .NONE);
    setRule(&r, .NUMBER, number, null, .NONE);
    setRule(&r, .AND, null, null, .NONE);
    setRule(&r, .CLASS, null, null, .NONE);
    setRule(&r, .ELSE, null, null, .NONE);
    setRule(&r, .FALSE, null, null, .NONE);
    setRule(&r, .FOR, null, null, .NONE);
    setRule(&r, .FUN, null, null, .NONE);
    setRule(&r, .IF, null, null, .NONE);
    setRule(&r, .NIL, null, null, .NONE);
    setRule(&r, .OR, null, null, .NONE);
    setRule(&r, .PRINT, null, null, .NONE);
    setRule(&r, .RETURN, null, null, .NONE);
    setRule(&r, .SUPER, null, null, .NONE);
    setRule(&r, .THIS, null, null, .NONE);
    setRule(&r, .TRUE, null, null, .NONE);
    setRule(&r, .VAR, null, null, .NONE);
    setRule(&r, .WHILE, null, null, .NONE);
    setRule(&r, .ERROR, null, null, .NONE);
    setRule(&r, .EOF, null, null, .NONE);

    break :blk r;
};
