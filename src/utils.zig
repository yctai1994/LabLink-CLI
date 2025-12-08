pub fn copyto(dest: [*]u8, src: []const u8) void {
    for (src, 0..) |value, index| {
        dest[index] = value;
    }
    return;
}

pub fn writeAll(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;
    while (pos < msg.len) {
        const written = try posix.write(socket, msg[pos..]);
        if (written == 0) {
            return error.Closed;
        }
        pos += written;
    }
}

const std = @import("std");
const posix = std.posix;
