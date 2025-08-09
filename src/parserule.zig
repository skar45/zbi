const TokenType = @import("scanner.zig").TokenType;
const Parser = @import("compiler.zig").Parser;

const variable = Parser.variable;
const grouping = Parser.grouping;
const binary = Parser.binary;
const unary = Parser.unary;
const number = Parser.number;
const string = Parser.string;
const literal = Parser.literal;
const and_ = Parser.and_;
const or_ = Parser.or_;
const call = Parser.call;
const table_init = Parser.table;

pub const Precedence = enum(u8) {
    NONE = 0,
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

const GrammarFn = *const fn (p: * Parser) void;

pub const ParseRule = struct {
    prefix: ?GrammarFn,
    infix: ?GrammarFn,
    precedence: Precedence
};

pub const rules =  blk: {
    var r: [43]ParseRule = undefined;
    const setRule = struct {
        fn lambda(
            cr: *[43]ParseRule,
            t_type: TokenType,
            pre: ?GrammarFn,
            inf: ?GrammarFn,
            prec: Precedence) void
        {
            cr[@intFromEnum(t_type)] = ParseRule {
                .prefix = pre,
                .infix = inf,
                .precedence = prec,
            };
        }
    }.lambda;

    setRule(&r, .LEFT_PAREN, grouping, call, .CALL);
    setRule(&r, .RIGHT_PAREN, null, null, .NONE);
    setRule(&r, .LEFT_BRACE, table_init, null, .ASSIGNMENT);
    setRule(&r, .RIGHT_BRACE, null, null, .NONE);
    setRule(&r, .COMMA, null, null, .NONE);
    setRule(&r, .DOT, null, null, .NONE);
    setRule(&r, .MINUS, unary, binary, .TERM);
    setRule(&r, .PLUS, null, binary, .TERM);
    setRule(&r, .SEMICOLON, null, null, .NONE);
    setRule(&r, .SLASH, null, binary, .FACTOR);
    setRule(&r, .STAR, null, binary, .FACTOR);
    setRule(&r, .BANG, unary, null, .NONE);
    setRule(&r, .BANG_EQUAL, null, binary, .EQUALITY);
    setRule(&r, .EQUAL, null, null, .NONE);
    setRule(&r, .EQUAL_EQUAL, null, binary, .COMPARISON);
    setRule(&r, .GREATER, null, binary, .COMPARISON);
    setRule(&r, .GREATER_EQUAL, null, binary, .COMPARISON);
    setRule(&r, .LESS, null, binary, .COMPARISON);
    setRule(&r, .LESS_EQUAL, null, binary, .COMPARISON);
    setRule(&r, .IDENTIFIER, variable, null, .NONE);
    setRule(&r, .STRING, string, null, .NONE);
    setRule(&r, .NUMBER, number, null, .NONE);
    setRule(&r, .AND, and_, null, .NONE);
    setRule(&r, .CLASS, null, null, .NONE);
    setRule(&r, .ELSE, null, null, .NONE);
    setRule(&r, .FALSE, literal, null, .NONE);
    setRule(&r, .FOR, null, null, .NONE);
    setRule(&r, .FN, null, null, .NONE);
    setRule(&r, .IF, null, null, .NONE);
    setRule(&r, .NIL, literal, null, .NONE);
    setRule(&r, .OR, or_, null, .NONE);
    setRule(&r, .PRINT, null, null, .NONE);
    setRule(&r, .RETURN, null, null, .NONE);
    setRule(&r, .SUPER, null, null, .NONE);
    setRule(&r, .THIS, null, null, .NONE);
    setRule(&r, .TRUE, literal, null, .NONE);
    setRule(&r, .VAR, null, null, .NONE);
    setRule(&r, .WHILE, null, null, .NONE);
    setRule(&r, .ERROR, null, null, .NONE);
    setRule(&r, .EOF, null, null, .NONE);

    break :blk r;
};
