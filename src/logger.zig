const PREFIX_INFO = "[INFO] ";
const PREFIX_WARN = "[WARN] ";
const NEWLINE = "\n";

const RecordHeader = enum {
    Info,
    Warn,

    fn toString(self: RecordHeader) []const u8 {
        return switch (self) {
            .Info => PREFIX_INFO,
            .Warn => PREFIX_WARN,
        };
    }
};

const Record = struct {
    header: RecordHeader,
    context: []const u8,
};

pub const Logger = struct {
    fd_no: posix.fd_t,

    cache: []u8, // backing buffer for stash
    stash: []u8, // always a slice into `cache`
    // Invariant: `stash` is either empty (&.{}) or a subslice of `cache`.

    const Self = @This();

    pub fn stdout(cache: []u8) Self {
        return .{
            .fd_no = posix.STDOUT_FILENO,
            .cache = cache,
            .stash = &.{},
        };
    }

    pub fn info(self: *Self, msg: []const u8) !void {
        try self.log(.{ .header = .Info, .context = msg });
    }

    pub fn warn(self: *Self, msg: []const u8) !void {
        try self.log(.{ .header = .Warn, .context = msg });
    }

    pub fn log(self: *Self, record: Record) !void {
        const header: []const u8 = record.header.toString();
        const iovecs: [4]posix.iovec_const = .{
            .{ .base = self.stash.ptr, .len = self.stash.len },
            .{ .base = header.ptr, .len = header.len },
            .{ .base = record.context.ptr, .len = record.context.len },
            .{ .base = NEWLINE.ptr, .len = NEWLINE.len },
        };

        // On .WouldBlock, treat as written = 0:
        // stash the entire message and retry on future `log()` calls.
        const written: usize = posix.writev(self.fd_no, &iovecs) catch |err| switch (err) {
            error.WouldBlock => 0,
            else => return err,
        };
        self.stash = try consume(self.cache, &iovecs, written);
    }
};

test "End-to-end write test" {
    const MSG1 = "Testing Logger #1";
    const MSG2 = "Testing Logger #2";

    const pipe: [2]posix.fd_t = try posix.pipe();
    defer posix.close(pipe[0]);

    var logger_cache: [1024]u8 = undefined;
    var logger = Logger{
        .fd_no = pipe[1],
        .cache = &logger_cache,
        .stash = &.{},
    };

    try logger.info(MSG1);
    try logger.warn(MSG2);

    // No more writes, close writer so read can see EOF if it wants to.
    posix.close(pipe[1]);

    const expected: []const u8 = PREFIX_INFO ++ MSG1 ++ NEWLINE ++ PREFIX_WARN ++ MSG2 ++ NEWLINE;

    var read_buffer: [1024]u8 = undefined;
    var total_read: usize = 0;
    while (total_read < expected.len) {
        const n: usize = try posix.read(pipe[0], read_buffer[total_read..]);
        if (n == 0) break; // EOF
        total_read += n;
    }

    try testing.expectEqualStrings(expected, read_buffer[0..total_read]);
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
    if (cache.len < (iovec_total_size - written)) return error.CacheOverflow;

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

test "Deterministic partial-write tests" {
    const STASH = "0123456789";
    const HEADER = "ABCDEFGHIJ";
    const BUFFER = "KLMNOPQRST";
    const SUFFIX = "UVWXYZ";
    const UNWRITTEN = STASH ++ HEADER ++ BUFFER ++ SUFFIX;

    const WRITTEN_TESTING = [_]usize{ 0, 4, 10, 16, 20, 28, 30, 33, 36 };

    var cache: [64]u8 = undefined;

    for (WRITTEN_TESTING) |written| {
        // Fresh state for each scenario
        @memcpy(cache[0..STASH.len], STASH);
        const stash: []u8 = cache[0..STASH.len];

        const iovecs: [4]posix.iovec_const = .{
            .{ .base = stash.ptr, .len = stash.len },
            .{ .base = HEADER.ptr, .len = HEADER.len },
            .{ .base = BUFFER.ptr, .len = BUFFER.len },
            .{ .base = SUFFIX.ptr, .len = SUFFIX.len },
        };

        const result: []u8 = try consume(cache[0..], &iovecs, written);
        try testing.expectEqualStrings(result, UNWRITTEN[written..]);
    }
}

const std = @import("std");
const posix = std.posix;
const debug = std.debug;
const testing = std.testing;
