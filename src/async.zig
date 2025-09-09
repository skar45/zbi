const std = @import("std");
const values = @import("values.zig");

const ArrayList = std.ArrayList;
const Condition = std.Thread.Condition;
const Value = values.Value;
const FnObj = values.FnObj;

const MAX_FUTURE_QUEUE = 256;

pub const FutureResult = union(enum) {
    result: Value,
    pending,

    pub fn init() FutureResult {
        return FutureResult {
            .pending
        };
    }
};

pub const IO_Future = struct {
    id: usize,
    caller_id: usize,
    ready: bool,
};

pub const BaseFuture = struct {
    id: usize,
    caller_id: ?usize,
    call_stack_ptr: usize,
    value: ?Value,
    ready: bool,
    curr_future: usize,
    future_list: ArrayList(FutureType),
    fn_obj: FnObj,

    pub fn poll(self: *BaseFuture) FutureResult {
        var res = FutureResult.init();
        if (!self.ready) return res;
        const fut = self.future_list.items[self.curr_future];
        fut.poll();
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

pub const FutureType = union(enum) {
    future: BaseFuture,
    io: IO_Future,

    pub fn log_size() void {
        @compileLog("size of future: {}", @sizeOf(FutureType));
    }
};

pub const Executor = struct {
    queue: [MAX_FUTURE_QUEUE]FutureType,
    queue_count: usize,

    pub fn init() Executor {
        return Executor {
            .queue = undefined,
            .queue_count = 0
        };
    }

    pub fn add_future(self: *Executor, future: FutureType) void {
        self.queue[self.queue_count] = future;
        self.queue_count += 1;
    }

// execute -> poll future -> poll primitive -> request io
// io done -> return future id -> poll future...
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
