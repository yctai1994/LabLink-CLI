pub const INTERNAL_CACHE_SIZE: usize = 1024;
pub const INTERNAL_BUFFER_SIZE: usize = 64;
pub const INVALID_FILE_DESCRIPTOR: posix.socket_t = -1;
pub const TIMEZONE_HOURS: comptime_int = 8;

const std = @import("std");
const posix = std.posix;
