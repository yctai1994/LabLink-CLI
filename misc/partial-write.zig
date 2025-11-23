const STASH = "0123456789";
const HEADER = "ABCDEFGHIJ";
const BUFFER = "KLMNOPQRST";
const SUFFIX = "UVWXYZ";
const UNWRITTEN = STASH ++ HEADER ++ BUFFER ++ SUFFIX;

const WRITTEN_TESTING = [_]usize{ 0, 4, 10, 16, 20, 28, 30, 33, 36 };

test "Test partial-write: normal behavior" {
    const page = testing.allocator;

    const cache: []u8 = try page.alloc(u8, 64);
    defer page.free(cache);

    for (WRITTEN_TESTING) |written| {
        // Fresh state for each scenario
        @memcpy(cache.ptr, STASH);
        const stash: []u8 = cache[0..STASH.len];

        const iovecs: [4]posix.iovec_const = .{
            .{ .base = stash.ptr, .len = stash.len },
            .{ .base = HEADER.ptr, .len = HEADER.len },
            .{ .base = BUFFER.ptr, .len = BUFFER.len },
            .{ .base = SUFFIX.ptr, .len = SUFFIX.len },
        };

        const result: []u8 = try consume(cache, &iovecs, written);
        try testing.expect(mem.eql(u8, result, UNWRITTEN[written..]));
    }
}

test "Test partial-write: unexpected behavior" {
    const page = testing.allocator;

    const cache: []u8 = try page.alloc(u8, 64);
    defer page.free(cache);

    @memcpy(cache.ptr, STASH);
    const stash: []u8 = cache[0..STASH.len];

    const iovecs: [4]posix.iovec_const = .{
        .{ .base = stash.ptr, .len = stash.len },
        .{ .base = UNWRITTEN.ptr, .len = UNWRITTEN.len },
        .{ .base = UNWRITTEN.ptr, .len = UNWRITTEN.len },
        .{ .base = SUFFIX.ptr, .len = SUFFIX.len },
    };

    try testing.expectError(error.CacheOverflow, consume(cache, &iovecs, 48));
    try testing.expectError(error.UnexpectedWritten, consume(cache, &iovecs, 96));
}

const ConsumeError = error{
    UnexpectedWritten,
    CacheOverflow,
};

fn consume(cache: []u8, iovecs: []const posix.iovec_const, written: usize) ConsumeError![]u8 {
    const iovec_total_size: usize = blk: {
        var temp: usize = 0;
        for (iovecs) |iovec| temp += iovec.len;
        break :blk temp;
    };

    if (iovec_total_size < written) return error.UnexpectedWritten;
    if (cache.len < iovec_total_size) return error.CacheOverflow;

    var remaining_written_bytes: usize = written;
    var first_unwritten_iovec: usize = 0;
    var cache_index_to_stash: usize = 0;

    for (iovecs) |iovec| {
        defer first_unwritten_iovec += 1;

        if (remaining_written_bytes < iovec.len) {
            const iovec_slice: []const u8 = iovec.base[0..iovec.len][remaining_written_bytes..];
            copyto(cache[cache_index_to_stash..].ptr, iovec_slice);
            cache_index_to_stash += iovec_slice.len;
            break;
        } else {
            remaining_written_bytes -= iovec.len;
        }
    }

    for (iovecs[first_unwritten_iovec..]) |iovec| {
        const iovec_slice: []const u8 = iovec.base[0..iovec.len];
        copyto(cache[cache_index_to_stash..].ptr, iovec_slice);
        cache_index_to_stash += iovec_slice.len;
    }

    return cache[0..cache_index_to_stash];
}

fn copyto(dest: [*]u8, src: []const u8) void {
    for (src, 0..) |value, index| {
        dest[index] = value;
    }
    return;
}

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const debug = std.debug;
const testing = std.testing;
