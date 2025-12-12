timestamp: ?Timestamp = null,
prefix: EventPrefix = .none,
header: EventHeader = .info,
suffix: EventSuffix = .none,
signal: EventSignal = .normal,

buffer: [Config.INTERNAL_BUFFER_SIZE]u8 = undefined,
msglen: usize = undefined,

const Self: type = @This();

pub fn setMessage(self: *Self, msg: []const u8) void {
    // This function is not thread-safe
    debug.assert(msg.len <= Config.INTERNAL_BUFFER_SIZE);

    @memcpy(self.buffer[0..msg.len], msg);
    self.msglen = msg.len;
}

const SECONDS_PER_MINUTE: comptime_int = 60;
const SECONDS_PER_HOUR: comptime_int = 3_600;
const SECONDS_PER_DAY: comptime_int = 86_400;

pub const TimestampError = error{
    NegativeTimespecValue,
    CacheOverflow,
} || posix.ClockGetTimeError;

pub const Timestamp = struct {
    comptime {
        if (@sizeOf(usize) != 8 or @sizeOf(isize) != 8) {
            @compileError("Timestamp requires 64-bit usize/isize.");
        }
    }

    date: Date,
    time: Time,

    pub fn now(comptime TIMEZONE_HOURS: isize) TimestampError!Timestamp {
        if (TIMEZONE_HOURS < -12 or 14 < TIMEZONE_HOURS) {
            @compileError("Timestamp(TIMEZONE_HOURS): must satisfy  -12 ≤ TIMEZONE_HOURS ≤ 14");
        }

        const timespec: posix.timespec = try posix.clock_gettime(posix.clockid_t.REALTIME);

        // NOTE: We assume isize is 64-bit; overflow for this addition
        // would require timespec.sec to be near the end of 64-bit range.
        const seconds_since_epoch: isize = timespec.sec + TIMEZONE_HOURS * SECONDS_PER_HOUR;

        // All real clocks for logging are going to be ≥ 1970 by multiple decades.
        if (seconds_since_epoch < 0) return error.NegativeTimespecValue;
        return Timestamp.convert(@intCast(seconds_since_epoch));
    }

    inline fn convert(seconds_since_epoch: usize) Timestamp {
        return .{
            .date = Date.init(seconds_since_epoch / SECONDS_PER_DAY),
            .time = Time.init(seconds_since_epoch % SECONDS_PER_DAY),
        };
    }

    pub fn format(self: *const Timestamp, buffer: []u8) TimestampError![]const u8 {
        if (buffer.len < 19) return error.CacheOverflow;

        self.date.format(buffer[0..10]);
        self.time.format(buffer[11..19]);
        buffer[10] = ' ';

        return buffer[0..19];
    }
};

fn isLeapYear(year: u16) bool {
    // Gregorian calendar rule
    if (year % 400 == 0) return true;
    if (year % 100 == 0) return false;
    return if (year % 4 == 0) true else false;
}

fn daysInYear(year: u16) usize {
    return if (isLeapYear(year)) 366 else 365;
}

fn daysInMonth(year: u16, month: u8) usize {
    return switch (month) {
        2 => if (isLeapYear(year)) 29 else 28,
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        else => unreachable,
    };
}

const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    fn init(days_since_epoch: usize) Date {
        var remaining: usize = days_since_epoch;
        var date: Date = .{ .year = 1970, .month = 1, .day = 1 };

        while (true) {
            const days_in_year: usize = @intCast(daysInYear(date.year));
            if (days_in_year <= remaining) {
                remaining -= days_in_year;
                date.year += 1;
            } else break;
        }

        while (true) {
            const days_in_month: usize = @intCast(daysInMonth(date.year, date.month));
            if (days_in_month <= remaining) {
                remaining -= days_in_month;
                date.month += 1;
            } else break;
        }

        debug.assert(remaining < daysInMonth(date.year, date.month));
        date.day += @intCast(remaining);

        return date;
    }

    fn format(self: *const Date, dest: []u8) void {
        debug.assert(dest.len == 10);
        debug.assert(self.year <= 9999);
        debug.assert(0 < self.month and self.month < 13); // 01 ~ 12
        debug.assert(0 < self.day and self.day < 32); // 01 ~ 31

        // Format YYYY
        var temp: u16 = self.year;
        dest[0] = @intCast('0' + temp / 1000);
        temp %= 1000;

        dest[1] = @intCast('0' + temp / 100);
        temp %= 100;

        dest[2] = @intCast('0' + temp / 10);
        dest[3] = @intCast('0' + temp % 10);

        // Format MM
        dest[4] = '-';
        dest[5] = @intCast('0' + self.month / 10);
        dest[6] = @intCast('0' + self.month % 10);

        // Format DD
        dest[7] = '-';
        dest[8] = @intCast('0' + self.day / 10);
        dest[9] = @intCast('0' + self.day % 10);
    }
};

const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,

    fn init(seconds_in_day: usize) Time {
        debug.assert(seconds_in_day < SECONDS_PER_DAY);

        var remaining: usize = seconds_in_day;
        var time: Time = .{ .hour = 0, .minute = 0, .second = 0 };

        time.hour = @intCast(remaining / SECONDS_PER_HOUR);
        remaining %= SECONDS_PER_HOUR;

        time.minute = @intCast(remaining / SECONDS_PER_MINUTE);
        remaining %= SECONDS_PER_MINUTE;

        time.second = @intCast(remaining);

        return time;
    }

    fn format(self: *const Time, dest: []u8) void {
        debug.assert(dest.len == 8);

        // Format HH
        dest[0] = '0' + self.hour / 10;
        dest[1] = '0' + self.hour % 10;

        // Format MM
        dest[2] = ':';
        dest[3] = '0' + self.minute / 10;
        dest[4] = '0' + self.minute % 10;

        // Format SS
        dest[5] = ':';
        dest[6] = '0' + self.second / 10;
        dest[7] = '0' + self.second % 10;
    }
};

const EXPECTED_DATES: [14][]const u8 = .{
    "1970-01-01 00:00:00",
    "1970-01-01 12:34:56",
    "1971-02-02 12:34:56",
    "1972-02-29 12:34:56",
    "1972-03-03 12:34:56",
    "1973-04-04 12:34:56",
    "1974-05-05 12:34:56",
    "1975-06-06 12:34:56",
    "1976-07-07 12:34:56",
    "1977-08-08 12:34:56",
    "1978-09-09 12:34:56",
    "1979-10-10 12:34:56",
    "1980-11-11 12:34:56",
    "1981-12-12 12:34:56",
};

const TESTING_TIMESTAMPS: [14]usize = .{
    0,
    45296,
    34346096,
    68214896,
    68474096,
    102774896,
    136989296,
    171290096,
    205590896,
    239891696,
    274192496,
    308406896,
    342794096,
    377008496,
};

test "Calendar math test" {
    var buffer: [128]u8 = undefined;
    var timestamp = try Timestamp.now(8);

    for (TESTING_TIMESTAMPS, EXPECTED_DATES) |seconds_since_epoch, expected_date| {
        timestamp = Timestamp.convert(seconds_since_epoch);
        const result: []const u8 = try timestamp.format(&buffer);
        try testing.expectEqualStrings(expected_date, result);
    }
}

pub const PREFIX_NONE = "";
pub const PREFIX_DASH = " - ";

pub const EventPrefix = enum {
    none,
    dash,

    pub fn iovec(self: EventPrefix) posix.iovec_const {
        return switch (self) {
            .none => .{ .base = PREFIX_NONE.ptr, .len = PREFIX_NONE.len },
            .dash => .{ .base = PREFIX_DASH.ptr, .len = PREFIX_DASH.len },
        };
    }
};

pub const HEADER_NONE = "";
pub const HEADER_INFO = "Info: ";
pub const HEADER_WARN = "Warn: ";

pub const EventHeader = enum {
    none,
    info,
    warn,

    pub fn iovec(self: EventHeader) posix.iovec_const {
        return switch (self) {
            .none => .{ .base = HEADER_NONE.ptr, .len = HEADER_NONE.len },
            .info => .{ .base = HEADER_INFO.ptr, .len = HEADER_INFO.len },
            .warn => .{ .base = HEADER_WARN.ptr, .len = HEADER_WARN.len },
        };
    }
};

pub const SUFFIX_NONE = "\n";

pub const EventSuffix = enum {
    none,

    pub fn iovec(self: EventSuffix) posix.iovec_const {
        return switch (self) {
            .none => .{ .base = SUFFIX_NONE.ptr, .len = SUFFIX_NONE.len },
        };
    }
};

pub const EventSignal = enum { normal, command, shutdown };

const std = @import("std");
const posix = std.posix;
const debug = std.debug;
const testing = std.testing;

const Config = @import("./Config.zig");
