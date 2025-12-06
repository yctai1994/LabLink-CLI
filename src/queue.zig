pub fn EventQueue(comptime SIZE: usize) type {
    if (SIZE <= 1) @compileError("EventQueue(SIZE): `SIZE` should be larger than 1.");
    if (SIZE & (SIZE - 1) != 0) @compileError("Event(SIZE): `SIZE` should be power of 2.");

    return struct {
        mutex: Thread.Mutex,
        cond: Thread.Condition,

        buff: []Event,
        head: usize, // index to dequeue
        tail: usize, // index to enqueue

        const mask: usize = SIZE - 1;
        const Self: type = @This();

        pub fn init(allocator: mem.Allocator) !*Self {
            const self: *Self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.buff = try allocator.alloc(Event, SIZE);
            errdefer allocator.free(self.buff);

            self.mutex = .{};
            self.cond = .{};
            self.head = 0;
            self.tail = 0;

            return self;
        }

        pub fn deinit(self: *const Self, allocator: mem.Allocator) void {
            allocator.free(self.buff);
            allocator.destroy(self);
        }

        pub inline fn isFull(self: *const Self) bool {
            return (self.tail - self.head) == SIZE;
        }

        pub inline fn isEmpty(self: *const Self) bool {
            return self.tail == self.head;
        }

        pub fn enqueue(self: *Self, event: Event) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.isFull()) self.cond.wait(&self.mutex);
            defer {
                self.tail += 1;
                self.cond.signal(); // wake one waiting consumer, if any
            }
            self.buff[self.tail & mask] = event;
        }

        pub fn dequeue(self: *Self) Event {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.isEmpty()) self.cond.wait(&self.mutex);
            defer {
                self.head += 1;
                self.cond.signal(); // wake one waiting producer, if any
            }
            return self.buff[self.head & mask];
        }
    };
}

const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const Thread = std.Thread;
const testing = std.testing;

const Event = @import("./Event.zig");
