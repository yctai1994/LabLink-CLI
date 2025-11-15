const SOCKET_MODE: comptime_int = posix.SOCK.STREAM;
const PROTOCOL: comptime_int = posix.IPPROTO.TCP;

pub fn main() !void {
    const listener_ipaddr: net.IpAddress = try net.IpAddress.parse("127.0.0.1", 5025);
    const listener_sockaddr: posix.sockaddr = @bitCast(
        posix.sockaddr.in{
            .port = mem.nativeToBig(u16, listener_ipaddr.ip4.port), // must
            .addr = mem.bytesAsValue(u32, &listener_ipaddr.ip4.bytes).*,
        },
    );
    const listener = try posix.socket(
        listener_sockaddr.family,
        SOCKET_MODE,
        PROTOCOL,
    );
    defer posix.close(listener);

    try posix.setsockopt(
        listener,
        posix.SOL.SOCKET,
        posix.SO.REUSEADDR,
        &std.mem.toBytes(@as(c_int, 1)),
    );

    try posix.bind(
        listener,
        &listener_sockaddr,
        switch (listener_sockaddr.family) {
            posix.AF.INET => @as(posix.socklen_t, @intCast(@sizeOf(posix.sockaddr.in))),
            posix.AF.INET6 => @as(posix.socklen_t, @intCast(@sizeOf(posix.sockaddr.in6))),
            posix.AF.UNIX => blk: {
                if (!has_unix_sockets) unreachable;
                break :blk @as(posix.socklen_t, @intCast(@sizeOf(posix.sockaddr.un)));
            },
            else => unreachable,
        },
    );
    try posix.listen(listener, 128);

    var client_sockaddr: posix.sockaddr.storage = undefined;
    var client_sockaddr_len: posix.socklen_t = @sizeOf(@TypeOf(client_sockaddr));

    // ~/.../zig-x86_64-macos-0.16.0-dev.1316+181b25ce4/lib/std/posix.zig:3481
    // needs `pub const AcceptError = std.Io.net.Server.AcceptError || error{SocketNotListening};`
    const socket = posix.accept(
        listener,
        @as(*posix.sockaddr, @ptrCast(&client_sockaddr)),
        &client_sockaddr_len,
        0,
    ) catch |err| {
        std.debug.print("error accept: {}\n", .{err});
        return;
    };
    defer posix.close(socket);

    write(socket, "Hello (and goodbye, server is closing...)\n") catch |err| {
        debug.print("error writing: {}\n", .{err});
    };
}

fn write(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;
    while (pos < msg.len) {
        const written = try posix.write(socket, msg[pos..]);
        if (written == 0) {
            return error.Closed;
        }
        pos += written;
    }
}

const std = @import("std");
const mem = std.mem;
const net = std.Io.net;
const posix = std.posix;
const debug = std.debug;
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const has_unix_sockets = switch (native_os) {
    .windows => builtin.os.version_range.windows.isAtLeast(.win10_rs4) orelse false,
    .wasi => false,
    else => true,
};
