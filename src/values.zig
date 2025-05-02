const std = @import("std");

pub const Value = f64;

pub fn printValue(value: Value) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{d} ", .{value});
}
