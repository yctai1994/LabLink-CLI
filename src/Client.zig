/// Line-oriented receive buffer that assembles '\n'-terminated commands
/// from arbitrary-sized chunks (e.g. from posix.read).
///
/// Usage:
///   - call receive(.{}) repeatedly
///   - each call may:
///       * return an Event (complete line),
///       * return null (need more data),
///       * or error (closed socket / overflow).
///
/// Internals:
///   - `cache` owns the backing memory
///   - `stash` is always a prefix of `cache` containing unparsed bytes
///   - `state` tracks whether `stash` is known to have no '\n' (Pure)
///     or might contain '\n' and needs to be scanned (Impure)
socket: ?posix.socket_t,

cache: []u8, // backing storage for all received-but-unparsed bytes
stash: []u8, // active prefix of cache containing unparsed bytes
// Invariant: `stash` is either empty (&.{}) or a subslice of `cache`.

state: State,

const Self: type = @This();

const ClientError = error{
    OutOfCache,
    ClientClosed,
};

// State invariants:
// - dirty: stash.len > 0 and stash MAY contain '\n' (must scan before reading more).
// - clean: stash.len >= 0 and stash contains NO '\n'.
const State = enum { dirty, clean };

pub fn init(allocator: mem.Allocator, socket: ?posix.socket_t) !*Self {
    const self: *Self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.socket = socket;

    self.cache = try allocator.alloc(u8, Config.INTERNAL_CACHE_SIZE);
    errdefer allocator.free(self.cache);

    self.stash = &.{};
    self.state = .clean;

    return self;
}

pub fn deinit(self: *Self, allocator: mem.Allocator) void {
    if (self.socket) |socket| posix.close(socket);

    allocator.free(self.cache);
    allocator.destroy(self);
}

pub fn receive(self: *Self, comptime opt: EventOption) !?Event {
    switch (self.state) {
        .dirty => return try self.assemble(opt),
        .clean => {
            const obtained: usize = try posix.read(self.socket.?, self.cache[self.stash.len..]);
            if (obtained == 0) return error.ClientClosed; // EOF
            return try self.consume(self.cache[self.stash.len..(self.stash.len + obtained)], opt);
        },
    }
}

test "Deterministic partial-read tests" {
    const pipe: [2]posix.fd_t = try posix.pipe();
    defer posix.close(pipe[1]); // close write-end

    const allocator = testing.allocator;

    var self: *Self = try Self.init(allocator, pipe[0]);
    defer self.deinit(allocator); // pipe[0] will be closed here

    var cmd_opt: ?Event = undefined;

    { // Empty line (\n) as first byte of chunk when stash is non-empty
        try utils.writeAll(pipe[1], "CMD");
        cmd_opt = try self.receive(.{});
        try utils.writeAll(pipe[1], "\n");
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt != null);
        const cmd: Event = cmd_opt.?;

        try testing.expectEqualStrings("CMD", cmd.buffer[0..cmd.msglen]);
        try testing.expectEqual(0, self.stash.len);
        try testing.expect(self.state == .clean);
    }
    { // single complete line
        try utils.writeAll(pipe[1], "MOVE 1.0\n");
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt != null);
        const cmd: Event = cmd_opt.?;

        try testing.expectEqualStrings("MOVE 1.0", cmd.buffer[0..cmd.msglen]);
        try testing.expectEqual(0, self.stash.len);
        try testing.expect(self.state == .clean);
    }
    { // partial line across chunks
        try utils.writeAll(pipe[1], "MO");
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt == null);
        try testing.expectEqualStrings("MO", self.stash);
        try testing.expect(self.state == .clean);
    }
    {
        try utils.writeAll(pipe[1], "VE 1.");
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt == null);
        try testing.expectEqualStrings("MOVE 1.", self.stash);
        try testing.expect(self.state == .clean);
    }
    {
        try utils.writeAll(pipe[1], "0\n");
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt != null);
        const cmd: Event = cmd_opt.?;

        try testing.expectEqualStrings("MOVE 1.0", cmd.buffer[0..cmd.msglen]);
        try testing.expectEqual(0, self.stash.len);
        try testing.expect(self.state == .clean);
    }

    { // multiple commands in one chunk
        try utils.writeAll(pipe[1], "*IDN?\nPOS?\n");
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt != null);
        const cmd1: Event = cmd_opt.?;
        try testing.expectEqualStrings("*IDN?", cmd1.buffer[0..cmd1.msglen]);
        try testing.expect(self.state == .dirty);
    }
    { // second command should already be in stash; no new data needed
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt != null);
        const cmd2: Event = cmd_opt.?;
        try testing.expectEqualStrings("POS?", cmd2.buffer[0..cmd2.msglen]);
        try testing.expectEqual(0, self.stash.len);
        try testing.expect(self.state == .clean);
    }
    {
        try utils.writeAll(pipe[1], "CMD1\nCMD2\nPARTIAL");
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt != null);
        const cmd1: Event = cmd_opt.?;
        try testing.expectEqualStrings("CMD1", cmd1.buffer[0..cmd1.msglen]);
        try testing.expect(self.state == .dirty);
    }
    {
        cmd_opt = try self.receive(.{});
        try testing.expect(cmd_opt != null);
        const cmd2: Event = cmd_opt.?;
        try testing.expectEqualStrings("CMD2", cmd2.buffer[0..cmd2.msglen]);
        try testing.expectEqualStrings("PARTIAL", self.stash);
        try testing.expect(self.state == .dirty);
    }
}

// assemble potentially existing command string
fn assemble(self: *Self, comptime opt: EventOption) !?Event {
    debug.assert(self.state == .dirty);

    if (scan(self.stash)) |found| {
        const command: Event = try emit(self.stash[0..found], opt);
        const residue: []u8 = self.stash[(found + 1)..];
        if (residue.len == 0) {
            self.state = .clean;
            self.stash = &.{};
        } else {
            utils.copyto(self.stash.ptr, residue);
            self.stash = self.stash[0..residue.len];
        }
        return command;
    } else {
        self.state = .clean;
        return null;
    }
}

// Consume in-coming string
fn consume(self: *Self, chunk: []const u8, comptime opt: EventOption) !?Event {
    debug.assert(self.state == .clean);

    if (chunk.len == 0) return null; // quick return;

    if (scan(chunk)) |found| {
        const cmd_len: usize = self.stash.len + found;
        const command: Event = try emit(self.cache[0..cmd_len], opt);
        const residue: []const u8 = chunk[(found + 1)..];
        if (residue.len == 0) {
            self.stash = &.{};
        } else {
            utils.copyto(self.cache.ptr, residue);
            self.stash = self.cache[0..residue.len];
            self.state = .dirty;
        }
        return command;
    } else {
        if (self.cache.len < (self.stash.len + chunk.len)) return error.OutOfCache;
        self.stash = self.cache[0..(self.stash.len + chunk.len)];
        return null;
    }
}

fn scan(slice: []const u8) ?usize {
    for (slice, 0..) |char, index| {
        if (char == '\n') return index;
    }
    return null;
}

const EventOption = struct {
    timestamp: bool = false,
    prefix: Event.EventPrefix = .none,
    header: Event.EventHeader = .info,
    suffix: Event.EventSuffix = .none,
};

fn emit(slice: []const u8, comptime opt: EventOption) !Event {
    var cmd: Event = .{
        .timestamp = if (opt.timestamp) try Event.Timestamp.now(Config.TIMEZONE_HOURS) else null,
        .prefix = opt.prefix,
        .header = opt.header,
        .suffix = opt.suffix,
        .signal = .command,
    };
    if (cmd.buffer.len < slice.len) return error.OutOfCache;

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
