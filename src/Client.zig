socket: posix.socket_t,

cache: []u8, // backing buffer for stash
stash: []u8, // always a slice into `cache`
// Invariant: `stash` is either empty (&.{}) or a subslice of `cache`.

const Self: type = @This();

const SelfError = error{ SelfClosed, LineTooLong };

pub fn init(allocator: mem.Allocator, socket: posix.socket_t) !*Self {
    const self: *Self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.socket = socket;

    self.cache = try allocator.alloc(u8, 1024);
    errdefer allocator.free(self.cache);

    self.stash = &.{};

    return self;
}

pub fn deinit(self: *const Self, allocator: mem.Allocator) void {
    if (self.socket != INVALID_FD) {
        const mutable: *Self = @constCast(self);
        posix.close(mutable.socket);
        mutable.socket = INVALID_FD;
    }

    allocator.free(self.cache);
    allocator.destroy(self);
}

const INVALID_FD: posix.socket_t = -1;

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const debug = std.debug;
