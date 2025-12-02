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

test "SocketAddress + IPv4Address roundtrip" {
    const origin = IPv4Address{ .addr = .{ 123, 12, 3, 1 }, .port = 45678 };
    const parsed = IPv4Address.fromSocketAddress(
        @constCast(&Self.fromIPv4Address(origin)),
    );

    try testing.expectEqualSlices(u8, &origin.addr, &parsed.addr);
    try testing.expectEqual(origin.port, parsed.port);
}

test "SocketAddress ptrCast/constCast aliases fd_t correctly" {
    // Main point: writing through one view shows up in the other.)

    const ip = IPv4Address{ .addr = .{ 123, 12, 3, 1 }, .port = 45678 };
    var sa_storage = Self.initForAccept();

    // Write via sockaddr.in view…
    const in_ptr: *posix.sockaddr.in = sa_storage.ptrCastTo(.in);
    in_ptr.* = .{
        .addr = mem.bytesAsValue(u32, &ip.addr).*,
        .port = mem.nativeToBig(u16, ip.port),
    };

    // …read via generic sockaddr view
    const sa_val: posix.sockaddr = sa_storage.ptrCastTo(.sockaddr).*;
    try testing.expectEqual(sa_val.family, posix.AF.INET);

    // The underlying storage is actually shared.
    // We can re-interpret as sockaddr.in again and compare.
    const sa_in: posix.sockaddr.in = sa_storage.ptrCastTo(.in).*;

    try testing.expectEqual(mem.bytesAsValue(u32, &ip.addr).*, sa_in.addr);
    try testing.expectEqual(mem.nativeToBig(u16, ip.port), sa_in.port);
}

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const debug = std.debug;
const testing = std.testing;

const IPv4Address = @import("./IPv4Address.zig");
