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
    const line: [1024]u8 = {};
    while (true) {
        try stdout.print("> ", .{});
        try stdin.read(line);
        if (line.len <= 0) {
            break;
        }
        interpret(line);
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
        // repl()
    }

    var chunks = try Chunks.init();
    defer chunks.deinit() catch |e| {
        std.debug.print("Error {}", .{e});
    };
    var constant = try chunks.addConstant(3.4);
    try chunks.writeChunk(Opcode.OP_CONSTANT, 123);
    try chunks.writeChunk(constant, 123);

    constant = try chunks.addConstant(1.2);
    try chunks.writeChunk(Opcode.OP_CONSTANT, 123);
    try chunks.writeChunk(constant, 123);

    try chunks.writeChunk(Opcode.OP_ADD, 123);

    constant = try chunks.addConstant(5.6);
    try chunks.writeChunk(Opcode.OP_CONSTANT, 123);
    try chunks.writeChunk(constant, 123);

    try chunks.writeChunk(Opcode.OP_DIVIDE, 123);
    try chunks.writeChunk(Opcode.OP_NEGATE, 123);
    try chunks.writeChunk(Opcode.OP_RETURN, 123);
    var vm = VM.init(chunks);
    _ = try vm.run();
}

test "Chunk Test" {
    try std.testing.expectEqual(2 + 2, 4);
}
