socket: ?posix.socket_t,

cache: []u8, // backing buffer for stash
stash: []u8, // always a slice into `cache`
// Invariant: `stash` is either empty (&.{}) or a subslice of `cache`.

state: StashState,

const Self: type = @This();

const ClientError = error{
    OutOfCache,
    ClientClosed,
};

// Invariant:
// - no_newline: stash.len >= 0 and stash contains NO '\n'.
// - need_scan:  stash.len > 0 and stash MAY contain '\n' (not yet re-scanned).
const StashState = enum {
    no_newline,
    need_scan,
};

pub fn init(allocator: mem.Allocator, socket: ?posix.socket_t) !*Self {
    const self: *Self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.socket = socket;

    self.cache = try allocator.alloc(u8, Config.INTERNAL_CACHE_SIZE);
    errdefer allocator.free(self.cache);

    self.stash = &.{};
    self.state = .no_newline;

    return self;
}

pub fn deinit(self: *const Self, allocator: mem.Allocator) void {
    if (self.socket) |socket| posix.close(socket);

    allocator.free(self.cache);
    allocator.destroy(self);
}

fn chunkFromBytes(self: *const Self, bytes: []const u8) ![]u8 {
    if (self.cache.len < (self.stash.len + bytes.len)) return error.OutOfCache;
    const chunk: []u8 = self.cache[self.stash.len..(self.stash.len + bytes.len)];
    @memcpy(chunk, bytes);
    return chunk;
}

test "join: single complete line" {
    const allocator = testing.allocator;

    var self: *Self = try Self.init(allocator, null);
    defer self.deinit(allocator);

    var cmd_opt: ?Event = undefined;
    var chunk: []u8 = undefined;

    // single complete line

    {
        chunk = try self.chunkFromBytes("MOVE 1.0\n");
        cmd_opt = self.joinFromChunk(chunk);
        try testing.expect(cmd_opt != null);
        const cmd: Event = cmd_opt.?;

        try testing.expectEqualStrings("MOVE 1.0", cmd.buffer[0..cmd.msglen]);
        try testing.expectEqual(0, self.stash.len);
        try testing.expect(self.state == .no_newline);
    }

    // partial line across chunks

    {
        chunk = try self.chunkFromBytes("MO");
        cmd_opt = self.joinFromChunk(chunk);
        try testing.expect(cmd_opt == null);
        try testing.expectEqualStrings("MO", self.stash);
        try testing.expect(self.state == .no_newline);
    }
    {
        chunk = try self.chunkFromBytes("VE 1.");
        cmd_opt = self.joinFromChunk(chunk);
        try testing.expect(cmd_opt == null);
        try testing.expectEqualStrings("MOVE 1.", self.stash);
        try testing.expect(self.state == .no_newline);
    }
    {
        chunk = try self.chunkFromBytes("0\n");
        cmd_opt = self.joinFromChunk(chunk);
        try testing.expect(cmd_opt != null);
        const cmd: Event = cmd_opt.?;

        try testing.expectEqualStrings("MOVE 1.0", cmd.buffer[0..cmd.msglen]);
        try testing.expectEqual(0, self.stash.len);
        try testing.expect(self.state == .no_newline);
    }

    // multiple commands in one chunk

    {
        chunk = try self.chunkFromBytes("*IDN?\nPOS?\n");
        cmd_opt = self.joinFromChunk(chunk);
        try testing.expect(cmd_opt != null);
        const cmd1: Event = cmd_opt.?;
        try testing.expectEqualStrings("*IDN?", cmd1.buffer[0..cmd1.msglen]);
        try testing.expect(self.state == .need_scan);
    }
    { // second command should already be in stash; no new data needed
        cmd_opt = self.joinFromStash();
        try testing.expect(cmd_opt != null);
        const cmd2: Event = cmd_opt.?;
        try testing.expectEqualStrings("POS?", cmd2.buffer[0..cmd2.msglen]);
        try testing.expect(self.state == .no_newline);
        try testing.expectEqual(0, self.stash.len);
    }

    // chunk too big

    {
        const long_str: []u8 = try allocator.alloc(u8, Config.INTERNAL_CACHE_SIZE + 1);
        defer allocator.free(long_str);

        try testing.expectError(
            error.OutOfCache,
            self.chunkFromBytes(long_str),
        );
    }
}

fn joinFromChunk(self: *Self, chunk: []const u8) ?Event {
    debug.assert(self.state == .no_newline);

    if (chunk.len == 0) return null; // quick return;

    if (scanForLF(chunk)) |found| {
        const cmd_len: usize = self.stash.len + found;
        const command: Event = emitCommand(self.cache[0..cmd_len]);
        const residue: []const u8 = chunk[(found + 1)..];
        if (residue.len == 0) {
            debug.assert(self.state == .no_newline);
            self.stash = &.{};
        } else {
            utils.copyto(self.cache.ptr, residue);
            self.stash = self.cache[0..residue.len];
            self.state = .need_scan;
        }
        return command;
    } else {
        debug.assert((self.stash.len + chunk.len) <= self.cache.len);
        self.stash = self.cache[0..(self.stash.len + chunk.len)];
        debug.assert(self.state == .no_newline);
        return null;
    }
}

fn joinFromStash(self: *Self) ?Event {
    debug.assert(self.state == .need_scan);

    if (scanForLF(self.stash)) |found| {
        const command: Event = emitCommand(self.stash[0..found]);
        const residue: []u8 = self.stash[(found + 1)..];
        if (residue.len == 0) {
            self.state = .no_newline;
            self.stash = &.{};
        } else {
            utils.copyto(self.stash.ptr, residue);
            self.stash = self.stash[0..residue.len];
            debug.assert(self.state == .need_scan);
        }
        return command;
    } else {
        self.state = .no_newline;
        return null;
    }
}

fn scanForLF(slice: []const u8) ?usize {
    for (slice, 0..) |char, index| {
        if (char == '\n') return index;
    }
    return null;
}

fn emitCommand(slice: []const u8) Event {
    var cmd: Event = .{
        .timestamp = null,
        .prefix = .none,
        .header = .info,
        .suffix = .none,
        .signal = .normal,
    };
    debug.assert(slice.len <= cmd.buffer.len);

    @memcpy(cmd.buffer[0..slice.len], slice);
    cmd.msglen = slice.len;

    return cmd;
}

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const debug = std.debug;
const testing = std.testing;

const utils = @import("./utils.zig");
const Event = @import("./Event.zig");
const Config = @import("./Config.zig");
