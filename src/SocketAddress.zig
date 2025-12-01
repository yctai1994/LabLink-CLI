fd_t: posix.sockaddr.storage,
size: posix.socklen_t,

const Self: type = @This();

const SocketAddressClass = enum { sockaddr, in, in6, un };

fn ConstCastType(comptime class: SocketAddressClass) type {
    return switch (class) {
        .sockaddr => *const posix.sockaddr,
        .in => *const posix.sockaddr.in,
        .in6 => *const posix.sockaddr.in6,
        .un => *const posix.sockaddr.un,
    };
}

pub inline fn constCastTo(self: *const Self, comptime class: SocketAddressClass) ConstCastType(class) {
    return @ptrCast(&self.fd_t);
}

fn PtrCastType(comptime class: SocketAddressClass) type {
    return switch (class) {
        .sockaddr => *posix.sockaddr,
        .in => *posix.sockaddr.in,
        .in6 => *posix.sockaddr.in6,
        .un => *posix.sockaddr.un,
    };
}

pub inline fn ptrCastTo(self: *Self, comptime class: SocketAddressClass) PtrCastType(class) {
    return @ptrCast(&self.fd_t);
}

pub inline fn family(self: *const Self) posix.sa_family_t {
    return self.fd_t.family;
}

// For accept(): big buffer, size set to `posix.storage` size.
pub fn initForAccept() Self {
    return .{
        .fd_t = std.mem.zeroes(posix.sockaddr.storage),
        .size = @sizeOf(posix.sockaddr.storage),
    };
}

// For bind/connect: exact IPv4 address, size set to `sockaddr.in` size.
pub fn fromIPv4Address(ipv4_addr: IPv4Address) Self {
    var self: Self = .{
        .fd_t = std.mem.zeroes(posix.sockaddr.storage),
        .size = @sizeOf(posix.sockaddr.in),
    };

    const ptr: *posix.sockaddr.in = self.ptrCastTo(.in);
    ptr.* = posix.sockaddr.in{
        .addr = mem.bytesAsValue(u32, &ipv4_addr.addr).*,
        .port = mem.nativeToBig(u16, ipv4_addr.port), // must
    };

    return self;
}

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const debug = std.debug;
const IPv4Address = @import("./IPv4Address.zig");
