const LoggerError = ConsumeError || Event.TimestampError || posix.WriteError;

pub const Logger = struct {
    fd_no: posix.fd_t,

    cache: []u8, // backing buffer for stash
    stash: []u8, // always a slice into `cache`
    // Invariant: `stash` is either empty (&.{}) or a subslice of `cache`.

    const Self = @This();

    pub fn init(allocator: mem.Allocator, cache_size: usize) !*Self {
        const self: *Self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.cache = try allocator.alloc(u8, cache_size);
        errdefer allocator.free(self.cache);

        self.fd_no = posix.STDOUT_FILENO;
        self.stash = &.{};

        return self;
    }

    pub fn deinit(self: *const Self, allocator: mem.Allocator) void {
        allocator.free(self.cache);
        allocator.destroy(self);
    }

    pub fn stdout(cache: []u8) Self {
        return .{
            .fd_no = posix.STDOUT_FILENO,
            .cache = cache,
            .stash = &.{},
        };
    }

    // Future: logger may have a configured timezone from a config file.
    pub fn info(self: *Self, msgtxt: []const u8, comptime TIMEZONE_HOURS: isize) LoggerError!void {
        try self.log(.{
            .timestamp = try Event.Timestamp.now(TIMEZONE_HOURS),
            .prefix = .dash,
            .header = .info,
            .msgtxt = msgtxt,
            .suffix = .none,
        });
    }

    pub fn warn(self: *Self, msgtxt: []const u8, comptime TIMEZONE_HOURS: isize) LoggerError!void {
        try self.log(.{
            .timestamp = try Event.Timestamp.now(TIMEZONE_HOURS),
            .prefix = .dash,
            .header = .warn,
            .msgtxt = msgtxt,
            .suffix = .none,
        });
    }

    pub fn log(self: *Self, event: Event) LoggerError!void {
        var iovecs: [6]posix.iovec_const = undefined;
        var iovec_index: usize = 0;

        iovecs[iovec_index] = .{ .base = self.stash.ptr, .len = self.stash.len };
        iovec_index += 1;

        if (event.timestamp) |timestamp| {
            // Use the bytes after stash as scratch for the timestamp.
            // If stash is so large that < 19 bytes remain, timestamp.format returns
            // error.CacheOverflow and we bail out.
            const timestamp_string: []const u8 = try timestamp.format(self.cache[self.stash.len..]);
            iovecs[iovec_index] = .{ .base = timestamp_string.ptr, .len = timestamp_string.len };
            iovec_index += 1;
        }

        iovecs[iovec_index] = event.prefix.iovec();
        iovec_index += 1;

        iovecs[iovec_index] = event.header.iovec();
        iovec_index += 1;

        iovecs[iovec_index] = .{ .base = event.msgtxt.ptr, .len = event.msgtxt.len };
        iovec_index += 1;

        iovecs[iovec_index] = event.suffix.iovec();
        iovec_index += 1;

        // On .WouldBlock, treat as written = 0:
        // stash the entire message and retry on future `log()` calls.
        const written: usize = posix.writev(self.fd_no, iovecs[0..iovec_index]) catch |err| switch (err) {
            error.WouldBlock => 0,
            else => return err,
        };
        self.stash = try consume(self.cache, iovecs[0..iovec_index], written);
    }
};

test "End-to-end write test" {
    const msgtxt_list: [2][]const u8 = .{
        "This is an info msg.",
        "This is an warn msg.",
    };
    const result_list: [2][]const u8 = .{
        Event.PREFIX_DASH ++ Event.HEADER_INFO ++ msgtxt_list[0] ++ Event.SUFFIX_NONE,
        Event.PREFIX_DASH ++ Event.HEADER_WARN ++ msgtxt_list[1] ++ Event.SUFFIX_NONE,
    };

    const pipe: [2]posix.fd_t = try posix.pipe();
    defer posix.close(pipe[1]);
    defer posix.close(pipe[0]);

    var logger_cache: [128]u8 = undefined;
    var logger = Logger{
        .fd_no = pipe[1],
        .cache = &logger_cache,
        .stash = &.{},
    };

    var read_buffer: [128]u8 = undefined;
    var total_read: usize = undefined;

    {
        const msgtxt: []const u8 = msgtxt_list[0];
        const result: []const u8 = result_list[0];
        try logger.info(msgtxt, 8);

        total_read = 0;
        while (total_read < result.len) {
            const n: usize = try posix.read(pipe[0], read_buffer[total_read..]);
            if (n == 0) break; // EOF
            total_read += n;
        }

        try testing.expectEqualStrings(result, read_buffer[19..total_read]);
    }
    {
        const msgtxt: []const u8 = msgtxt_list[1];
        const result: []const u8 = result_list[1];
        try logger.warn(msgtxt, 8);

        total_read = 0;
        while (total_read < result.len) {
            const n: usize = try posix.read(pipe[0], read_buffer[total_read..]);
            if (n == 0) break; // EOF
            total_read += n;
        }

        try testing.expectEqualStrings(result, read_buffer[19..total_read]);
    }
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
const mem = std.mem;
const posix = std.posix;
const debug = std.debug;
const testing = std.testing;

const Event = @import("./Event.zig");
