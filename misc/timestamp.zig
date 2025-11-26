const SECONDS_PER_MINUTE: comptime_int = 60;
const SECONDS_PER_HOUR: comptime_int = 3_600;
const SECONDS_PER_DAY: comptime_int = 86_400;

const Timestamp = error{
    NegativeTimeValue,
};

fn isLeapYear(year: usize) bool {
    // Gregorian calendar rule
    if (year % 400 == 0) return true;
    if (year % 100 == 0) return false;
    return if (year % 4 == 0) true else false;
}

fn daysInYear(year: usize) usize {
    return if (isLeapYear(year)) 366 else 365;
}

fn daysInMonth(year: usize, month: usize) usize {
    return switch (month) {
        2 => if (isLeapYear(year)) 29 else 28,
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        else => unreachable,
    };
}

pub const Date = struct {
    year: usize,
    month: usize,
    day: usize,

    pub const init = Date{ .year = 1970, .month = 1, .day = 1 };

    pub fn toString(self: *const Date, dest: []u8) void {
        debug.assert(dest.len == 10);

        {
            var temp: usize = self.year;
            dest[0] = @intCast('0' + temp / 1000);
            temp %= 1000;

            dest[1] = @intCast('0' + temp / 100);
            temp %= 100;

            dest[2] = @intCast('0' + temp / 10);
            dest[3] = @intCast('0' + temp % 10);
        }

        dest[4] = '-';
        dest[5] = @intCast('0' + self.month / 10);
        dest[6] = @intCast('0' + self.month % 10);

        dest[7] = '-';
        dest[8] = @intCast('0' + self.day / 10);
        dest[9] = @intCast('0' + self.day % 10);
    }
};

const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,

    pub fn toString(self: *const Time, dest: []u8) void {
        debug.assert(dest.len == 8);

        dest[0] = '0' + self.hour / 10;
        dest[1] = '0' + self.hour % 10;

        dest[2] = ':';
        dest[3] = '0' + self.minute / 10;
        dest[4] = '0' + self.minute % 10;

        dest[5] = ':';
        dest[6] = '0' + self.second / 10;
        dest[7] = '0' + self.second % 10;
    }
};

const EXPECTED_DATES: [13][]const u8 = .{
    "1970-01-01 00:00:00 GMT",
    "1970-01-01 12:34:56 GMT",
    "1971-02-02 12:34:56 GMT",
    "1972-03-03 12:34:56 GMT",
    "1973-04-04 12:34:56 GMT",
    "1974-05-05 12:34:56 GMT",
    "1975-06-06 12:34:56 GMT",
    "1976-07-07 12:34:56 GMT",
    "1977-08-08 12:34:56 GMT",
    "1978-09-09 12:34:56 GMT",
    "1979-10-10 12:34:56 GMT",
    "1980-11-11 12:34:56 GMT",
    "1981-12-12 12:34:56 GMT",
};

const TESTING_TIMESTAMPS: [13]usize = .{
    0,
    45296,
    34346096,
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
    // const timespec: posix.timespec = try posix.clock_gettime(posix.clockid_t.REALTIME);
    // const seconds_since_epoch: usize = if (0 <= timespec.sec) @intCast(timespec.sec) else return error.NegativeTimeValue;

    var buffer: [23]u8 = undefined;
    inline for (.{ ' ', ' ', 'G', 'M', 'T' }, .{ 10, 19, 20, 21, 22 }) |val, ind| buffer[ind] = val;

    for (TESTING_TIMESTAMPS, EXPECTED_DATES) |seconds_since_epoch, expected_date| {
        // Find calendar date
        var days_since_epoch: usize = seconds_since_epoch / SECONDS_PER_DAY;
        var date: Date = .init;

        while (true) {
            const days_in_year: usize = daysInYear(date.year);
            if (days_in_year <= days_since_epoch) {
                days_since_epoch -= days_in_year;
                date.year += 1;
            } else break;
        }

        while (true) {
            const days_in_month: usize = daysInMonth(date.year, date.month);
            if (days_in_month <= days_since_epoch) {
                days_since_epoch -= days_in_month;
                date.month += 1;
            } else break;
        }

        date.day += days_since_epoch;
        date.toString(buffer[0..10]);

        // Find clock time
        var time_second: usize = seconds_since_epoch % SECONDS_PER_DAY;
        debug.assert(time_second < 86400);

        const time_hour: usize = time_second / SECONDS_PER_HOUR;
        time_second %= SECONDS_PER_HOUR;

        const time_minute: usize = time_second / SECONDS_PER_MINUTE;
        time_second %= SECONDS_PER_MINUTE;

        const time: Time = .{
            .hour = @intCast(time_hour),
            .minute = @intCast(time_minute),
            .second = @intCast(time_second),
        };

        time.toString(buffer[11..19]);

        // Test result
        try testing.expectEqualStrings(expected_date, &buffer);
    }
}

const std = @import("std");
const posix = std.posix;
const debug = std.debug;
const testing = std.testing;
