const SECONDS_PER_MINUTE: comptime_int = 60;
const SECONDS_PER_HOUR: comptime_int = 3_600;
const SECONDS_PER_DAY: comptime_int = 86_400;

const TimestampError = error{
    NegativeTimespecValue,
} || posix.ClockGetTimeError;

pub fn Timestamp(comptime TIMEZONE_HOURS: isize) type {
    // compile-time assertion reminds the assumption of 64-bit
    debug.assert(@sizeOf(usize) == 8);
    debug.assert(@sizeOf(isize) == 8);

    if (TIMEZONE_HOURS < -12 or 14 < TIMEZONE_HOURS) {
        @compileError("Timestamp(TIMEZONE_HOURS): must satisfy  -12 ≤ TIMEZONE_HOURS ≤ 14");
    }

    return struct {
        date: Date,
        time: Time,

        const Self: type = @This();

        pub fn now() TimestampError!Self {
            const timespec: posix.timespec = try posix.clock_gettime(posix.clockid_t.REALTIME);
            const seconds_since_epoch: isize = timespec.sec + TIMEZONE_HOURS * SECONDS_PER_HOUR;
            // All real clocks for logging are going to be ≥ 1970 by multiple decades.
            if (seconds_since_epoch < 0) return error.NegativeTimespecValue;
            return Self.convert(@intCast(seconds_since_epoch));
        }

        pub inline fn convert(seconds_since_epoch: usize) Self {
            return .{
                .date = Date.init(seconds_since_epoch / SECONDS_PER_DAY),
                .time = Time.init(seconds_since_epoch % SECONDS_PER_DAY),
            };
        }

        pub fn format(self: *const Self, buffer: []u8) void {
            debug.assert(buffer.len == 19);

            self.date.format(buffer[0..10]);
            self.time.format(buffer[11..19]);
            buffer[10] = ' ';
        }
    };
}

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

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn init(days_since_epoch: usize) Date {
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

    pub fn format(self: *const Date, dest: []u8) void {
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

    pub fn init(seconds_in_day: usize) Time {
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

    pub fn format(self: *const Time, dest: []u8) void {
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
    const TimestampUTC = Timestamp(0);

    var buffer: [19]u8 = undefined;
    var timestamp = try TimestampUTC.now();

    for (TESTING_TIMESTAMPS, EXPECTED_DATES) |seconds_since_epoch, expected_date| {
        timestamp = TimestampUTC.convert(seconds_since_epoch);
        timestamp.format(&buffer);
        try testing.expectEqualStrings(expected_date, &buffer);
    }
}

const std = @import("std");
const posix = std.posix;
const debug = std.debug;
const testing = std.testing;
