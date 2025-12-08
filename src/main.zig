pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
    const allocator = debug_allocator.allocator();

    var queue: *EventQueue = try EventQueue.init(allocator);

    const thread_consumer = try Thread.spawn(.{}, consumerExec, .{ queue, allocator });
    defer {
        queue.enqueue(.{ .signal = .shutdown });
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
        queue.enqueue(event);
    }

    // $ nc 127.0.0.1 5025 && netstat -an | grep 5025
    const listener_addr = IPv4Address{ .addr = .{ 127, 0, 0, 1 }, .port = 5025 };

    const listener = try socket.Listener.init(listener_addr, queue);
    defer listener.deinit();

    try listener.listen(queue);

    const client: *socket.Client = try listener.accept(allocator);
    defer client.deinit(allocator);

    try client.echo(queue);
    try client.greet();
}

fn consumerExec(queue: *EventQueue, allocator: mem.Allocator) !void {
    const logger: *Logger = try Logger.init(allocator, 1024);
    defer logger.deinit(allocator);

    while (true) {
        const event: Event = queue.dequeue();
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
const EventQueue = @import("./queue.zig").EventQueue(8);
const IPv4Address = @import("./IPv4Address.zig");
const SocketAddress = @import("./SocketAddress.zig");
