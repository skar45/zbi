const std = @import("std");
const s = @import("scanner.zig");

const Scanner = s.Scanner;
const TokenType = s.TokenType;

pub fn compile(source: []u8) void {
    var scanner = Scanner.init(source);
    const line = -1;

    while (true) {
        const token = scanner.scanToken();
        const stdout = std.io.getStdOut().writer();
        if (token.line != line) {
            stdout.print("{d:0>4} ", .{token.line}) catch unreachable;
        } else {
            stdout.print("   | ", .{}) catch unreachable;
        }
        stdout.print("{d:0>2} {s}", .{token.line, token.start}) catch unreachable;
        if (token.ttype == TokenType.EOF) break;
    }
}
