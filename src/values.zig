const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    boolean: bool,
    number: f64,
    string: StringObj,
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

    pub fn setString(str: []const u8, allocator: *const Allocator) !Value {
        return Value {
            .string = try StringObj.init(str, allocator)
        };
    }

    pub fn concatString(str1: []const u8, str2: []const u8, allocator: *const Allocator) !Value {
        return Value {
            .string = try StringObj.concat(str1, str2, allocator)
        };
    }

    pub fn setNil() Value {
        return Value {
            .nil = undefined
        };
    }
};

pub const StringObj = struct {
    str: []const u8,
    _allocator: *const Allocator,

    pub fn init(str: []const u8, allocator: *const Allocator) !StringObj {
        const result = try allocator.alloc(u8, str.len);
        @memcpy(result,  str);

        return StringObj {
            .str = result,
            ._allocator = allocator
        };
    }

    pub fn concat(str1: []const u8, str2: []const u8, allocator: *const Allocator) !StringObj {
        const result = try allocator.alloc(u8, str1.len + str2.len);
        @memcpy(result[0..str1.len],  str1);
        @memcpy(result[str1.len..],  str2);

        return StringObj {
            .str = result,
            ._allocator = allocator
        };
    }

    pub fn append(self: *const StringObj, val: []const u8) !void {
        const result: []u8 = try self._allocator.realloc(self.str, val.len + self.len);
        @memcpy(result[(self.str.len - 1)..result.len], val);
        self.str = result;
    }

    pub fn compare(self: *const StringObj, comp: []const u8) bool {
        if (self.str.len != comp.len) return false;
        for (0..comp.len) |i| {
            if (self.str[i] != comp[i]) return false;
        }
        return true;
    }

    pub fn deinit(self: *const StringObj) void {
        self._allocator.free(self.str_ptr);
        self.str = undefined;
    }
};

pub fn printValue(value: Value) !void {
    const stdout = std.io.getStdOut().writer();
    switch (value) {
        .boolean => |b| try stdout.print("{} ", .{b}),
        .number => |n| try stdout.print("{d} ", .{n}),
        .string => |s| try stdout.print("{s} ", .{s.str}),
        .nil => try stdout.print("nil ", .{})
    }
}
