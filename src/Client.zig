handle: posix.socket_t,
logger: *Logger,
ipaddr: IPv4Address,

const Self: type = @This();

pub fn init(socket: posix.socket_t, sa: SocketAddress, logger: *Logger) !Self {
    const ip: IPv4Address = IPv4Address.fromSocketAddress(&sa);
    var buffer: [128]u8 = undefined;
    @memcpy(buffer[0..19], "ACCEPT client from ");
    const written: usize = ip.format(buffer[19..]);
    try logger.info(buffer[0 .. written + 19], TIMEZONE);

    return .{ .handle = socket, .logger = logger, .ipaddr = ip };
}

pub fn deinit(self: *const Self) void {
    if (self.handle != INVALID_FD) {
        const mutable: *Self = @constCast(self);
        posix.close(mutable.handle);
        mutable.handle = INVALID_FD;
    }
}

pub fn greet(self: *const Self) !void {
    const msg: []const u8 = "Hello (and goodbye, server is closing...)\n";
    try writeAll(self.handle, msg);
}

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

const TIMEZONE: comptime_int = 8;
const INVALID_FD: posix.socket_t = -1;

const std = @import("std");
const posix = std.posix;

const Logger = @import("./logger.zig").Logger;
const IPv4Address = @import("./IPv4Address.zig");
const SocketAddress = @import("./SocketAddress.zig");
