addr: [4]u8,
port: u16,

const Self: type = @This();

pub fn fromSocketAddress(sa: *const SocketAddress) Self {
    const sa_in: posix.sockaddr.in = sa.constCastTo(.in).*;
    return .{
        .addr = mem.toBytes(sa_in.addr),
        .port = mem.toNative(u16, sa_in.port, .big),
    };
}

pub fn format(self: *const Self, buffer: []u8) usize {
    debug.assert(21 <= buffer.len); // "255.255.255.255:65535".len == 21

    var written: usize = 0;
    for (self.addr) |set| {
        written += fmtFromInt(u8, set, buffer[written..]);
        buffer[written] = '.';
        written += 1;
    }

    buffer[written - 1] = ':';
    written += fmtFromInt(u16, self.port, buffer[written..]);

    return written;
}

test "format basic" {
    const addr_list: [3][4]u8 = .{
        .{ 123, 12, 3, 1 },
        .{ 0, 0, 0, 0 },
        .{ 255, 255, 255, 255 },
    };
    const port_list: [3]u16 = .{ 45678, 0, 65535 };
    const result_list: [3][]const u8 = .{
        "123.12.3.1:45678",
        "0.0.0.0:0",
        "255.255.255.255:65535",
    };

    var buffer: [64]u8 = undefined;
    var written: usize = undefined;
    var handler: Self = undefined;

    for (addr_list, port_list, result_list) |addr, port, result| {
        handler = Self{ .addr = addr, .port = port };
        written = handler.format(&buffer);
        try testing.expectEqualStrings(result, buffer[0..written]);
    }
}

fn fmtFromInt(comptime T: type, value: T, buffer: []u8) usize {
    const max_num_of_digits: comptime_int = switch (@typeInfo(T)) {
        .int => |int_info| blk: {
            if (int_info.signedness == .signed) @compileError("fmtFromInt: T must be unsigned integer type.");
            break :blk switch (int_info.bits) {
                8 => 3,
                16 => 5,
                32 => 10,
                64 => 20,
                else => @compileError("fmtFromInt: bits must be 8, 16, 32, 64."),
            };
        },
        else => @compileError("fmtFromInt: T must be integer type."),
    };

    debug.assert(1 <= buffer.len);
    if (value == 0) {
        buffer[0] = '0';
        return 1;
    }

    debug.assert(max_num_of_digits <= buffer.len);

    var tmp: [max_num_of_digits]u8 = undefined;
    var rem: T = value;
    var idx: usize = 0;

    while (0 < rem) : (rem /= 10) {
        tmp[idx] = @intCast('0' + rem % 10); // least-significant digit
        idx += 1;
    }

    // now, idx == num. of written digits

    var cnt: usize = 0; // counts
    while (0 < idx) : (cnt += 1) {
        idx -= 1;
        buffer[cnt] = tmp[idx];
    }

    return cnt;
}

test "fmtFromInt test" {
    const int_list: [3]comptime_int = .{ 0, 255, 65535 };
    const type_list: [3]type = .{ u8, u8, u16 };
    const result_list: [3][]const u8 = .{ "0", "255", "65535" };

    var buffer: [32]u8 = undefined;
    var written: usize = undefined;

    inline for (int_list, type_list, result_list) |int_val, int_type, int_str| {
        written = fmtFromInt(int_type, int_val, buffer[0..]);
        try testing.expectEqualStrings(int_str, buffer[0..written]);
    }
}

const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const posix = std.posix;
const testing = std.testing;

const SocketAddress = @import("./SocketAddress.zig");
