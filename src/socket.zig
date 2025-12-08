pub const Listener = struct {
    socket: posix.socket_t,
    addr: IPv4Address,

    pub fn init(addr: IPv4Address, queue: *EventQueue) !Listener {
        const sa = SocketAddress.fromIPv4Address(addr);

        const socket: posix.socket_t = try posix.socket(sa.family(), SOCKET_MODE, PROTOCOL);
        errdefer posix.close(socket);

        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(socket, sa.constCastTo(.sockaddr), sa.size);

        // = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

        var buffer: [64]u8 = undefined;
        @memcpy(buffer[0..8], "BIND to ");
        const written: usize = addr.format(buffer[8..]);

        var event: Event = .{
            .timestamp = try Event.Timestamp.now(TIMEZONE_HOURS),
            .prefix = .dash,
            .header = .info,
            .suffix = .none,
        };
        event.setMessage(buffer[0 .. written + 8]);
        queue.enqueue(event);

        // = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

        return .{ .socket = socket, .addr = addr };
    }

    pub fn deinit(self: *const Listener) void {
        if (self.socket != INVALID_FD) {
            const mutable: *Listener = @constCast(self);
            posix.close(mutable.socket);
            mutable.socket = INVALID_FD;
        }
    }

    pub fn listen(self: *const Listener, queue: *EventQueue) !void {
        try posix.listen(self.socket, BACKLOG_SIZE);

        var buffer: [64]u8 = undefined;
        @memcpy(buffer[0..13], "LISTENING on ");
        const written: usize = self.addr.format(buffer[13..]);

        var event: Event = .{
            .timestamp = try Event.Timestamp.now(TIMEZONE_HOURS),
            .prefix = .dash,
            .header = .info,
            .suffix = .none,
        };
        event.setMessage(buffer[0 .. written + 13]);
        queue.enqueue(event);
    }

    pub fn accept(self: *const Listener, allocator: mem.Allocator) !*Client {
        var sa: SocketAddress = SocketAddress.initForAccept(); // client

        // ~/.../zig-x86_64-macos-0.16.0-dev.../lib/std/posix.zig:3409
        // needs `pub const AcceptError = std.Io.net.Server.AcceptError || error{SocketNotListening};`
        const socket = try posix.accept(self.socket, sa.ptrCastTo(.sockaddr), &sa.size, 0);
        errdefer posix.close(socket);

        return try Client.init(allocator, socket);
    }
};

pub const Client = struct {
    socket: posix.socket_t,

    cache: []u8, // backing buffer for stash
    stash: []u8, // always a slice into `cache`
    // Invariant: `stash` is either empty (&.{}) or a subslice of `cache`.

    const ClientError = error{ ClientClosed, LineTooLong };

    pub fn init(allocator: mem.Allocator, socket: posix.socket_t) !*Client {
        const self: *Client = try allocator.create(Client);
        errdefer allocator.destroy(self);

        self.socket = socket;

        self.cache = try allocator.alloc(u8, 1024);
        errdefer allocator.free(self.cache);

        self.stash = &.{};

        return self;
    }

    pub fn deinit(self: *const Client, allocator: mem.Allocator) void {
        if (self.socket != INVALID_FD) {
            const mutable: *Client = @constCast(self);
            posix.close(mutable.socket);
            mutable.socket = INVALID_FD;
        }

        allocator.free(self.cache);
        allocator.destroy(self);
    }

    pub fn greet(self: *const Client) !void {
        const msg: []const u8 = "Hello (and goodbye, server is closing...)\n";
        try utils.writeAll(self.socket, msg);
    }

    pub fn echo(self: *Client, queue: *EventQueue) !void {
        var buffer: []u8 = undefined;
        outer: while (true) {
            buffer = self.cache[self.stash.len..];
            const obtained: usize = try posix.read(self.socket, buffer);

            if (obtained == 0) return error.ClientClosed; // EOF

            var index: usize = 0;
            inner: while (index < obtained) : (index += 1) {
                if (buffer[index] != '\n') continue :inner;
                const message: []const u8 = switch (buffer[index - 1] == '\r') {
                    true => self.cache[0..(self.stash.len + index - 1)], // '\r\n' is excluded
                    false => self.cache[0..(self.stash.len + index)], // '\n' is excluded
                };

                var event: Event = .{
                    .timestamp = try Event.Timestamp.now(TIMEZONE_HOURS),
                    .prefix = .dash,
                    .header = .info,
                    .suffix = .none,
                    .signal = .normal,
                };
                event.setMessage(message);
                queue.enqueue(event);

                utils.copyto(self.cache.ptr, buffer[(index + 1)..obtained]);
                self.stash = self.cache[0..(obtained - index - 1)];
                break :outer;
            } else {
                self.stash = self.cache[0..(self.stash.len + obtained)];
            }
        }
    }
};

const TIMEZONE_HOURS: comptime_int = 8;
const INVALID_FD: posix.socket_t = -1;

const SOCKET_MODE: comptime_int = posix.SOCK.STREAM;
const PROTOCOL: comptime_int = posix.IPPROTO.TCP;
const BACKLOG_SIZE: u31 = 128; // the number of pending connections the queue can hold.

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const debug = std.debug;

const Event = @import("./Event.zig");
const Logger = @import("./logger.zig").Logger;
const EventQueue = @import("./queue.zig").EventQueue(8);
const IPv4Address = @import("./IPv4Address.zig");
const SocketAddress = @import("./SocketAddress.zig");

const utils = @import("./utils.zig");
