const std = @import("std");

pub const Value = union(enum) {
    boolean: bool,
    number: f64,
    nil,

    pub fn setBool(boolean: bool) Value {
        return Value {
            .boolean = boolean
        };
    }

    pub fn setNumber(num: f64) Value {
        return Value {
            .number = num
        };
    }

    pub fn setNil() Value {
        return Value {
            .nil = void
        };
    }
};

pub fn printValue(value: Value) !void {
    const stdout = std.io.getStdOut().writer();
    switch (value) {
        .boolean => |b| try stdout.print("{} ", .{b}),
        .number => |n| try stdout.print("{d} ", .{n}),
        .nil => try stdout.print("nil ", .{})
    }
    
}
