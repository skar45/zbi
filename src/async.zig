const std = @import("std");
const values = @import("values.zig");
const chunks = @import("chunks.zig");

const ArrayList = std.ArrayList;
const Condition = std.Thread.Condition;
const Value = values.Value;
const FnObj = values.FnObj;
const OpCode = chunks.OpCode;

const MAX_FUTURE_QUEUE = 256;

const IOPollFn = *const fn (p: * IO_Future) void;

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
    value: ?Value,
    ready: bool,
    poll_fn: IOPollFn,

    pub fn new(id: usize, caller: usize, poll_fn: IOPollFn) IO_Future {
        return IO_Future {
            .id = id,
            .caller_id = caller,
            .value = null,
            .ready = false,
            .poll_fn = poll_fn
        };
    }
};

// async fut
// {
//  res = await fut;
//  res = await fut(res);
//  return res;
// }

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
        // get future from current state
        const fut = self.future_list.items[self.curr_future];
        const res = fut.poll();
        // switch(res) {
            // .pending => return res,
            // .result => |r| 
        // }
        if (self.value) |v| {
            res.result = v;
            return res;
        }
        res.err = void;
        return res;
    }

    pub fn notify(self: *BaseFuture) void {
        self.ready = true;
    }
};

pub const FutureType = union(enum) {
    base: BaseFuture,
    io: IO_Future,

    pub fn log_size() void {
        @compileLog("size of future: {}", @sizeOf(FutureType));
    }

    pub fn poll(self: *FutureType) FutureResult {
        return switch(self.*) {
            .base => |b| b.poll(),
            .io => |i| i.poll()
        };
    }

    pub fn get_curr_
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

    pub fn execute(self: *Executor) ?[]OpCode {
        if (self.queue_count == 0) return null;
        for (0..self.queue_count) |i| {
            const fut = self.queue[i];
            const result = fut.poll();
            switch (result) {
                .pending => return null,
                .value => return 
            }
        }
        return null;
    }
};
