const std = @import("std");
const chunks = @import("chunks.zig");
const debug = @import("debug.zig");
const vm = @import("vm.zig");

const Allocator = std.mem.Allocator;
const VM = vm.VM;
const interpret = vm.interpret;
const Opcode = chunks.Opcode;
const Chunks = chunks.Chunks;

// TODO:
// - For loops
// - Loop control flow: break, continue
// - Stack overflow check
// - Call frame overflow check
// - Optimize away unecessary POP instructions
// - Nested string interpolation
//
// - Pattern match
// - Dynamic arrays
// - Structs
// - Copy on write strings
// - Async with futures and io uring
// - Turbo mode: JIT to x86
// - GC with
//   - concurrent relocation
//   - concurrent marking with coloured pointers
//   - region based memory management
//   - concurrent batched free


pub fn repl(io: std.Io, allocator: *const Allocator) !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buf);
    const stdin = &stdin_reader.interface;
    // scanner reads past the end of the source, so keep it zero padded
    var line: [stdin_buf.len + 16]u8 = undefined;
    while (true) {
        try stdout.print("> ", .{});
        try stdout.flush();
        const input = try stdin.takeDelimiter('\n') orelse break;
        @memset(&line, 0);
        @memcpy(line[0..input.len], input);
        const result = interpret(io, &line, allocator);
        switch (result) {
            .INTERPRET_COMPILE_ERROR => std.debug.print("compile error \n", .{}),
            .INTERPRET_OK => std.debug.print("", .{}),
            .INTERPRET_RUNTIME_ERROR => std.debug.print("runtime error \n", .{})
        }
    }
}

pub fn runFile(io: std.Io, path: []const u8, allocator: *const Allocator) !void {
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator.*, .limited(4096 * 10));
    // scanner reads past the end of the source, so keep it zero padded
    const file = try allocator.alloc(u8, contents.len + 16);
    @memset(file, 0);
    @memcpy(file[0..contents.len], contents);
    const result = interpret(io, file, allocator);
    switch (result) {
        .INTERPRET_COMPILE_ERROR => std.debug.print("compile error \n", .{}),
        .INTERPRET_OK => std.debug.print("", .{}),
        .INTERPRET_RUNTIME_ERROR => std.debug.print("runtime error \n", .{})
    }
}


pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    var args_iter = try init.minimal.args.iterateAllocator(allocator);
    defer args_iter.deinit();
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
        try runFile(io, path, &allocator);
    } else {
        try repl(io, &allocator);
    }
}

test "Chunk Test" {
    try std.testing.expectEqual(2 + 2, 4);
}
