pub fn main() !void {
    var da: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
    const allocator = da.allocator();

    const queue_cache: []Event = try allocator.alloc(Event, 8);
    defer allocator.free(queue_cache);

    var shared_queue = SharedQueue.init(queue_cache);

    const thread_consumer = try Thread.spawn(.{}, consumerExec, .{ &shared_queue, allocator });
    defer {
        shared_queue.enqueue(.{ .signal = .shutdown }) catch unreachable;
        thread_consumer.join(); // waiting for the logger thread's termination
    }

    {
        var event: Event = .{
            .timestamp = try Event.Timestamp.now(TIMEZONE_HOURS),
            .prefix = .dash,
            .header = .info,
            .suffix = .none,
        };
        event.setMessage("SCPI Server Started");
        shared_queue.enqueue(event) catch unreachable;
    }

    // $ nc 127.0.0.1 5025 && netstat -an | grep 5025
    const listener_addr = IPv4Address{ .addr = .{ 127, 0, 0, 1 }, .port = 5025 };

    const listener = try socket.Listener.init(listener_addr, &shared_queue);
    defer listener.deinit();

    try listener.listen(&shared_queue);

    const client: socket.Client = try listener.accept();
    defer client.deinit();

    try client.greet();
}

fn consumerExec(queue: *SharedQueue, allocator: mem.Allocator) !void {
    const logger: *Logger = try Logger.init(allocator, 1024);
    defer logger.deinit(allocator);

    while (true) {
        const event: Event = try queue.dequeue();
        if (event.signal == .shutdown) return;
        try logger.log(event);
    }
}

const TIMEZONE_HOURS: comptime_int = 8;

const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const Thread = std.Thread;

const Event = @import("./Event.zig");
const socket = @import("./socket.zig");
const Logger = @import("./logger.zig").Logger;
const SharedQueue = @import("./SharedQueue.zig");
const IPv4Address = @import("./IPv4Address.zig");
const SocketAddress = @import("./SocketAddress.zig");
