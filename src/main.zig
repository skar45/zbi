const std = @import("std");
const chunks = @import("chunks.zig");
const debug = @import("debug.zig");
const vm = @import("vm.zig");

const Allocator = std.mem.Allocator;
const VM = vm.VM;
const interpret = vm.interpret;
const Opcode = chunks.Opcode;
const Chunks = chunks.Chunks;

pub fn repl(allocator: *const Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var line: [1024]u8 = [_]u8{0} ** 1024;
    while (true) {
        try stdout.print("> ", .{});
        _ = try stdin.read(&line);
        if (line.len <= 0) {
            break;
        }
        const result = interpret(&line, allocator);
        switch (result) {
            .INTERPRET_COMPILE_ERROR => std.debug.print("compile error \n", .{}),
            .INTERPRET_OK => std.debug.print("", .{}),
            .INTERPRET_RUNTIME_ERROR => std.debug.print("runtime error \n", .{})
        }
    }
}

pub fn runFile(path: []const u8, allocator: *const Allocator) !void {
    const file = try std.fs.cwd().readFileAlloc(allocator.*, path, 4096 * 10);
    const result = interpret(file, allocator);
    switch (result) {
        .INTERPRET_COMPILE_ERROR => std.debug.print("compile error \n", .{}),
        .INTERPRET_OK => std.debug.print("", .{}),
        .INTERPRET_RUNTIME_ERROR => std.debug.print("runtime error \n", .{})
    }
}


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = false
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
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
        try runFile(path, &allocator);
    } else {
        try repl(&allocator);
    }
}

test "Chunk Test" {
    try std.testing.expectEqual(2 + 2, 4);
}
