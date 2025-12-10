pub const INTERNAL_CACHE_SIZE: usize = 1024;
pub const INTERNAL_BUFFER_SIZE: usize = 64;
pub const INVALID_FILE_DESCRIPTOR: posix.socket_t = -1;

const std = @import("std");
const posix = std.posix;
