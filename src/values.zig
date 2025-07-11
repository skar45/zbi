const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayHashMap = std.ArrayHashMap;
const OpCode = @import("chunks.zig").OpCode;

pub const Value = union(enum) {
    boolean: bool,
    number: f64,
    string: StringObj,
    table: Table,
    closure: ClosureObj,
    function: FnObj,
    nil,
    void,

    pub fn setFn(code_ptr: usize, airity: u8) Value {
        return Value {
            .function = FnObj.init(code_ptr, airity)
        };
    }

    pub fn setVoid() Value {
        return Value {
            .void = undefined
        };
    }

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

    pub fn setString(str: []const u8, allocator: *const Allocator) Value {
        return Value {
            .string = StringObj.init(str, allocator)
        };
    }

    pub fn initTable(allocator: *const Allocator) Value {
        return Value {
            .table = Table.init(allocator)
        };
    }

    pub fn concatString(str1: []const u8, str2: []const u8, allocator: *const Allocator) Value {
        return Value {
            .string = StringObj.concat(str1, str2, allocator)
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

    pub fn init(str: []const u8, allocator: *const Allocator) StringObj {
        const result = allocator.alloc(u8, str.len) catch {
            std.debug.print("Allocator OOM", .{});
            std.process.exit(64);
        };
        @memcpy(result,  str);

        return StringObj {
            .str = result,
            ._allocator = allocator
        };
    }

    pub fn concat(str1: []const u8, str2: []const u8, allocator: *const Allocator) StringObj {
        const result = allocator.alloc(u8, str1.len + str2.len) catch {
            std.debug.print("Allocator OOM", .{});
            std.process.exit(64);
        };
        @memcpy(result[0..str1.len],  str1);
        @memcpy(result[str1.len..],  str2);

        return StringObj {
            .str = result,
            ._allocator = allocator
        };
    }

    // TODO use for native string methods
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
        self._allocator.free(self.str);
        self.str = undefined;
    }
};

pub const Table = struct {
    map: ArrayHashMap(Value, Value, TableHash, true),
    count: usize,

    pub fn init(allocator: *const Allocator) Table {
        return Table {
            .map = ArrayHashMap(Value, Value, TableHash, true).init(allocator.*),
            .count = 0
        };
    }

    pub fn deinit(self: *Table) void {
        self.map.deinit();
    }

    pub fn insert(self: *Table, k: Value, v: Value) void {
        switch (k) {
            .table | .void => unreachable,
            else => self.map.put(k, v) catch unreachable
        }
    }

    pub fn get(self: *const Table, k: Value) Value {
        if (self.map.get(k)) |v| {
            return v;
        } else {
            return Value.setNil();
        }
    }
};

pub const TableHash = struct {
    pub fn hash(_: *const TableHash, k: Value) u32 {
        const key: []const u8 = switch(k) {
            .boolean => |b| if (b == true) "true" else "false",
            .number => |n| blk: {
                var buf: [64]u8 = undefined;
                _ = std.fmt.bufPrint(buf[0..], "{d}", .{n}) catch unreachable;
                break :blk &buf;
            },
            .string => |s| s.str,
            .nil => "nil",
            else => unreachable
        };

        var h: u32 = 2166136261;
        for (key) |s| {
            h ^= s;
            h *%= 1677619;
        }
        return h;
    }

    pub fn eql(_: *const TableHash, key1: Value, key2: Value, _: usize) bool {
        return switch (key1) {
            .boolean => |b1| {
                return switch (key2) {
                    .boolean => |b2| b1 == b2,
                    else => false,
                };
            },
            .number => |n1| {
                return switch (key2) {
                    .number => |n2| n1 == n2,
                    else => false
                };
            },
            .string => |s1| {
                return switch (key2) {
                    .string => |s2| {
                        for (s1.str, 0..) |s, i| {
                            if (s != s2.str[i]) return false;
                        }
                        return true;
                    },
                    else => false
                };
            },
            .nil => {
                return switch (key2) {
                    .nil => true,
                    else => false
                };
            },
            else => unreachable
        };
    }

};

pub const FnObj = struct {
    code_ptr: usize,
    airity: u8,

    pub fn init(code_ptr: usize, airity: u8) FnObj {
        return FnObj {
            .code_ptr = code_ptr,
            .airity = airity
        };
    }
};

pub const ClosureObj = struct {
    values: ArrayList(Value),
    code_ptr: usize,
    airity: u8,
    _allocator: *const Allocator,

    pub fn init(allocator: *const Allocator, code_ptr: usize) ClosureObj {
        return ClosureObj {
            .code_ptr = code_ptr,
            .value = ArrayList(Value).initCapacity(allocator, 32) catch unreachable,
            ._allocator = allocator
        };
    }

    pub fn writeChunk(self: *ClosureObj, op: OpCode) void {
        self.code.append(op);
    }

    pub fn addConstant(self: *ClosureObj, value: Value) OpCode {
        self.values.append(value);
        return @intFromEnum(self.values.items.len - 1);
    }

    pub fn deinit(self: *ClosureObj) void {
        self.code.deinit();
        self.values.deinit();
    }
};

// pub const HashBucket = struct {
//     value: Value,
//     next: ?*HashBucket
// };
// 
// pub const HashMapObj = struct {
//     buckets: ArrayList(HashBucket),
//     count: usize,
//     _arena_allocator: *const Allocator,
// 
//     pub fn init(alloc: *const Allocator) void {
//         return HashMapObj {
//             .buckets = ArrayList(HashBucket).initCapacity(alloc, 2048) catch unreachable,
//             .count = 0,
//             ._arena_allocator = alloc
//         };
//     }
// 
//     fn get_hash(key: []const u8) usize {
//          var hash: usize = 2166136261;
//          for (key) |k| {
//              hash ^= k;
//              hash *= 16777619;
//          }
//          return hash;
//     }
// 
//     pub fn insert(self: *const HashMapObj, key: []const u8, value: Value) void {
//         const hash = get_hash(key);
//         if ((self.count + 1) > (self.buckets.capacity * 0.75)) {
//             self.buckets.resize(self.buckets.capacity * 2);
//         }
//         const index: usize = hash % self.buckets.capacity;
//     }
// 
//     pub fn deinit(self: *const HashMapObj) void {
//         self._arena_allocator.free(self.buckets);
//     }
// };


pub fn printValue(value: Value) !void {
    const stdout = std.io.getStdOut().writer();
    switch (value) {
        .boolean => |b| try stdout.print("{} ", .{b}),
        .number => |n| try stdout.print("{d} ", .{n}),
        .string => |s| try stdout.print("{s} ", .{s.str}),
        .table => |t| {
            const keys = t.map.keys();
            for (keys) |k| {
                switch (k) {
                    .string => |s| {
                        try stdout.print("[{s}]: ", .{s.str});
                        const val = t.get(k);
                        try printValue(val);
                        try stdout.print("\n", .{});
                    },
                    else => unreachable
                }
            }
        },
        .function => |f| try stdout.print("fn {d}({d})", .{f.code_ptr, f.airity}),
        .nil => try stdout.print("nil ", .{}),
        .void => try stdout.print("void", .{}),
        else => try stdout.print("value formatting not implemented", .{}),
    }
}
