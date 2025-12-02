pub fn main() !void {
    var logger_cache: [128]u8 = undefined;
    var logger = Logger.stdout(&logger_cache);
    try logger.info("SCPI Server Started", TIMEZONE);

    // $ nc 127.0.0.1 5025 && netstat -an | grep 5025
    const listener_addr = IPv4Address{ .addr = .{ 127, 0, 0, 1 }, .port = 5025 };

    const listener = try Listener.init(listener_addr, &logger);
    defer listener.deinit();

    try listener.listen();

    const client: Client = try listener.accept();
    defer client.deinit();

    try client.greet();
}

const TIMEZONE: comptime_int = 8;

const Logger = @import("./logger.zig").Logger;
const Client = @import("./Client.zig");
const Listener = @import("./Listener.zig");
const IPv4Address = @import("./IPv4Address.zig");
const SocketAddress = @import("./SocketAddress.zig");
