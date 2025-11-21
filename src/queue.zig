pub fn RingBufferQueue(comptime DATA: type, comptime SIZE: usize) type {
    if (SIZE <= 1) @compileError("Queue(DATA, SIZE): `SIZE` should be larger than 1.");
    if (SIZE & (SIZE - 1) != 0) @compileError("Queue(DATA, SIZE): `SIZE` should be power of 2.");

    return struct {
        buff: []DATA,
        head: usize, // index to dequeue
        tail: usize, // index to enqueue

        const mask: usize = SIZE - 1;
        const Self: type = @This();

        pub const RingBufferQueueError = error{
            FullQueue,
            EmptyQueue,
        };

        pub fn init(buff: []DATA) Self {
            debug.assert(buff.len == SIZE);
            return .{ .buff = buff, .head = 0, .tail = 0 };
        }

        pub fn isFull(self: *const Self) bool {
            return (self.tail - self.head) == SIZE;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.tail == self.head;
        }

        pub fn enqueue(self: *Self, data: DATA) RingBufferQueueError!void {
            if (self.isFull()) return error.FullQueue;
            defer self.tail += 1;
            self.buff[self.tail & mask] = data;
        }

        pub fn dequeue(self: *Self) RingBufferQueueError!DATA {
            if (self.isEmpty()) return error.EmptyQueue;
            defer self.head += 1;
            return self.buff[self.head & mask];
        }
    };
}

test "Single Thread Test" {
    const Queue: type = RingBufferQueue(usize, 8);
    var buffer: [8]usize = undefined;
    var queue = Queue.init(&buffer);

    {
        for (0..8) |n| try queue.enqueue(n);
        try testing.expectError(error.FullQueue, queue.enqueue(8));
    }

    {
        for (0..4) |_| {
            _ = try queue.dequeue();
        }

        for (0..4) |n| try queue.enqueue(8 + n);

        for (0..3) |_| {
            _ = try queue.dequeue();
        }

        try testing.expectEqual(7, try queue.dequeue());
    }

    {
        for (0..3) |_| {
            _ = try queue.dequeue();
        }

        try testing.expectEqual(11, try queue.dequeue());
        try testing.expectError(error.EmptyQueue, queue.dequeue());
    }
}

const std = @import("std");
const debug = std.debug;
const testing = std.testing;
