const std = @import("std");
const values = @import("values.zig");

const Condition = std.Thread.Condition;
const Value = values.Value;
const FnObj = values.FnObj;

const MAX_FUTURE_QUEUE = 256;

pub const FutureResult = union(enum) {
    result: Value,
    pending, 
    err,

    pub fn init() FutureResult {
        return FutureResult {
            .pending
        };
    }
};

pub const Future = struct {
    ret_ip: usize,
    call_stack_ptr: usize,
    value: ?Value,
    ready: bool,
    curr: usize,
    fn_obj: FnObj,

    pub fn poll(self: *Future) FutureResult {
        var res = FutureResult.init();
        if (!self.ready) return res;
        if (self.value) |v| {
            res.result = v;
            return res;
        }
        res.err = void;
        return res;
    }

    pub fn notify(self: *Future) void {
        self.ready = true;
    }
};

pub const Executor = struct {
    queue: [MAX_FUTURE_QUEUE]Future,
    queue_count: usize,

    pub fn init() Executor {
        return Executor {
            .queue = undefined,
            .queue_count = 0
        };
    }

    pub fn add_future(self: *Executor, future: Future) void {
        self.queue[self.queue_count] = future;
        self.queue_count += 1;
    }

//     pub fn block(self: *Executor, future: Future) void {
// 
//     }

    pub fn execute(self: *Executor) ?FutureResult {
        if (self.queue_count == 0) return null;
        for (0..self.queue_count) |i| {
            const fut = self.queue[i];
            const result = fut.poll();
            return result;
        }
        return null;
    }
};
