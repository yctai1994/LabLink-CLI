queue: Queue,
mutex: Thread.Mutex,
cond: Thread.Condition,

const Self: type = @This();

pub inline fn init(cache: []Event) Self {
    return .{ .queue = Queue.init(cache), .mutex = .{}, .cond = .{} };
}

pub fn enqueue(self: *Self, event: Event) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    while (true) {
        self.queue.enqueue(event) catch |err| switch (err) {
            error.FullQueue => {
                self.cond.wait(&self.mutex);
                continue;
            },
            else => return err,
        };
        break;
    }
    self.cond.signal(); // wake a waiting execution
}

pub fn dequeue(self: *Self) !Event {
    self.mutex.lock();
    defer self.mutex.unlock();

    while (true) {
        const event = self.queue.dequeue() catch |err| switch (err) {
            error.EmptyQueue => {
                self.cond.wait(&self.mutex);
                continue;
            },
            else => return err,
        };
        self.cond.signal(); // wake a waiting execution
        return event;
    }
}

test "A queue with thread-safety" {
    const SharedQueue: type = Self;
    const page = testing.allocator;

    const queue_cache: []Event = try page.alloc(Event, 8);
    defer page.free(queue_cache);

    var shared_queue = SharedQueue.init(queue_cache);

    const thread_producer = try Thread.spawn(.{}, producerExec, .{&shared_queue});
    const thread_consumer = try Thread.spawn(.{}, consumerExec, .{ &shared_queue, page });
    thread_producer.join();
    thread_consumer.join();
}

fn producerExec(queue: *Self) !void {
    var index: usize = 0;

    while (index < MESSAGE_LIST.len) {
        queue.enqueue(.{
            .timestamp = try Event.Timestamp.now(TIMEZONE_HOURS),
            .prefix = .dash,
            .header = .info,
            .msgtxt = MESSAGE_LIST[index],
            .suffix = .none,
        }) catch {
            unreachable;
        };
        index += 1;
    }

    queue.enqueue(.{ .signal = .shutdown }) catch unreachable;
}

fn consumerExec(queue: *Self, allocator: mem.Allocator) !void {
    const logger: *Logger = try Logger.init(allocator, 1024);
    defer logger.deinit(allocator);

    while (true) {
        const event: Event = queue.dequeue() catch unreachable;
        if (event.signal == .shutdown) return;
        try logger.log(event);
    }
}

const MESSAGE_LIST: [10][]const u8 = .{
    "message #01",
    "message #02",
    "message #03",
    "message #04",
    "message #05",
    "message #06",
    "message #07",
    "message #08",
    "message #09",
    "message #10",
};

const TIMEZONE_HOURS: comptime_int = 8;

const std = @import("std");
const mem = std.mem;
const Thread = std.Thread;
const testing = std.testing;

const Event = @import("./Event.zig");
const Queue: type = RingBufferQueue(Event, 8);
const Logger = @import("./logger.zig").Logger;
const RingBufferQueue = @import("./queue.zig").RingBufferQueue;
