handle: posix.socket_t,
logger: *Logger,
ipaddr: IPv4Address,

const Self: type = @This();

pub fn init(ip: IPv4Address, logger: *Logger) !Self {
    const sa = SocketAddress.fromIPv4Address(ip);

    const listener: posix.socket_t = try posix.socket(sa.family(), SOCKET_MODE, PROTOCOL);
    errdefer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, sa.constCastTo(.sockaddr), sa.size);

    var buffer: [128]u8 = undefined;
    @memcpy(buffer[0..8], "BIND to ");
    const written: usize = ip.format(buffer[8..]);
    try logger.info(buffer[0 .. written + 8], TIMEZONE);

    return .{ .handle = listener, .logger = logger, .ipaddr = ip };
}

pub fn deinit(self: *const Self) void {
    if (self.handle != INVALID_FD) {
        const mutable: *Self = @constCast(self);
        posix.close(mutable.handle);
        mutable.handle = INVALID_FD;
    }
}

pub fn listen(self: *const Self) !void {
    try posix.listen(self.handle, BACKLOG_SIZE);

    var buffer: [128]u8 = undefined;
    @memcpy(buffer[0..13], "LISTENING on ");
    const written: usize = self.ipaddr.format(buffer[13..]);
    try self.logger.info(buffer[0 .. written + 13], TIMEZONE);
}

pub fn accept(self: *const Self) !Client {
    var sa: SocketAddress = SocketAddress.initForAccept(); // client

    // ~/.../zig-x86_64-macos-0.16.0-dev.../lib/std/posix.zig:3409
    // needs `pub const AcceptError = std.Io.net.Server.AcceptError || error{SocketNotListening};`
    const socket = try posix.accept(self.handle, sa.ptrCastTo(.sockaddr), &sa.size, 0);
    errdefer posix.close(socket);

    return try Client.init(socket, sa, self.logger);
}

const TIMEZONE: comptime_int = 8;
const INVALID_FD: posix.socket_t = -1;

const SOCKET_MODE: comptime_int = posix.SOCK.STREAM;
const PROTOCOL: comptime_int = posix.IPPROTO.TCP;
const BACKLOG_SIZE: u31 = 128; // the number of pending connections the queue can hold.

const std = @import("std");
const posix = std.posix;

const Logger = @import("./logger.zig").Logger;
const Client = @import("./Client.zig");
const IPv4Address = @import("./IPv4Address.zig");
const SocketAddress = @import("./SocketAddress.zig");
