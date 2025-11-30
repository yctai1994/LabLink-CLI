fd_t: posix.sockaddr.storage,
size: posix.socklen_t,

const Self: type = @This();

pub const init = Self{
    .fd_t = undefined,
    .size = @sizeOf(posix.sockaddr.storage),
};

pub inline fn sockaddr(self: *Self) *posix.sockaddr {
    return @ptrCast(&self.fd_t);
}

pub inline fn ip4addr(self: *Self) *posix.sockaddr.in {
    return @ptrCast(&self.fd_t);
}

const std = @import("std");
const posix = std.posix;
