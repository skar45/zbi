const std = @import("std");
const c = @import("chunks.zig");
const debug = @import("debug.zig");
const v = @import("vm.zig");

const VM = v.VM;
const interpret = v.interpret;
const Opcode = c.Opcode;
const Chunks = c.Chunks;

pub fn repl() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var line: [1024]u8 = [_]u8{0} ** 1024;
    while (true) {
        try stdout.print("> ", .{});
        _ = try stdin.read(&line);
        if (line.len <= 0) {
            break;
        }
        const result = interpret(&line);
        switch (result) {
            .INTERPRET_COMPILE_ERROR => std.debug.print("compile error", .{}),
            .INTERPRET_OK => std.debug.print("", .{}),
            .INTERPRET_RUNTIME_ERROR => std.debug.print("runtime error", .{})
        }
    }
}

pub fn runFile(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const file = try std.fs.cwd().readFileAlloc(allocator, path, 4096 * 10);
    _ = interpret(file);
}


pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args_iter = try std.process.argsWithAllocator(allocator);
    if (args_iter.skip() == false) {
        std.debug.print("Usage: zbi [path]\n", .{});
        std.process.exit(64);
    }
    const file_path = args_iter.next();
    if (args_iter.next()) |_| {
        std.debug.print("Usage: zbi [path]\n", .{});
        std.process.exit(64);
    }
    if (file_path) |path| {
        try runFile(path);
    } else {
        try repl();
    }
}

test "Chunk Test" {
    try std.testing.expectEqual(2 + 2, 4);
}
