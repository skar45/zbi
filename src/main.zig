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

    // var chunks = Chunks.init();
    // var constant = chunks.addConstant(3.4);
    // chunks.writeChunk(Opcode.CONSTANT, 123);
    // chunks.writeChunk(constant, 123);
// 
    // constant = chunks.addConstant(1.2);
    // chunks.writeChunk(Opcode.CONSTANT, 123);
    // chunks.writeChunk(constant, 123);
// 
    // chunks.writeChunk(Opcode.ADD, 123);
// 
    // constant = chunks.addConstant(5.6);
    // chunks.writeChunk(Opcode.CONSTANT, 123);
    // chunks.writeChunk(constant, 123);
// 
    // chunks.writeChunk(Opcode.DIVIDE, 123);
    // chunks.writeChunk(Opcode.NEGATE, 123);
    // chunks.writeChunk(Opcode.RETURN, 123);
    // var vm = VM.init(chunks);
    // _ = try vm.run();
}

test "Chunk Test" {
    try std.testing.expectEqual(2 + 2, 4);
}
