pub const Listener = struct {
    socket: posix.socket_t,
    addr: IPv4Address,

    pub fn init(addr: IPv4Address, queue: *SharedQueue) !Listener {
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
        queue.enqueue(event) catch unreachable;

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

    pub fn listen(self: *const Listener, queue: *SharedQueue) !void {
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
        queue.enqueue(event) catch unreachable;
    }

    pub fn accept(self: *const Listener) !Client {
        var sa: SocketAddress = SocketAddress.initForAccept(); // client

        // ~/.../zig-x86_64-macos-0.16.0-dev.../lib/std/posix.zig:3409
        // needs `pub const AcceptError = std.Io.net.Server.AcceptError || error{SocketNotListening};`
        const socket = try posix.accept(self.socket, sa.ptrCastTo(.sockaddr), &sa.size, 0);
        errdefer posix.close(socket);

        return Client{ .socket = socket };
    }
};

pub const Client = struct {
    socket: posix.socket_t,

    pub fn init(socket: posix.socket_t) Client {
        return .{ .socket = socket };
    }

    pub fn deinit(self: *const Client) void {
        if (self.socket != INVALID_FD) {
            const mutable: *Client = @constCast(self);
            posix.close(mutable.socket);
            mutable.socket = INVALID_FD;
        }
    }

    pub fn greet(self: *const Client) !void {
        const msg: []const u8 = "Hello (and goodbye, server is closing...)\n";
        try writeAll(self.socket, msg);
    }
};

fn writeAll(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;
    while (pos < msg.len) {
        const written = try posix.write(socket, msg[pos..]);
        if (written == 0) {
            return error.Closed;
        }
        pos += written;
    }
}

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
const SharedQueue = @import("./SharedQueue.zig");
const IPv4Address = @import("./IPv4Address.zig");
const SocketAddress = @import("./SocketAddress.zig");
