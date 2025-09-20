const std = @import("std");
const common = @import("common");

const http = @import("http.zig");
const Config = @import("Config.zig");

pub fn main() void {
    var allocator = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(allocator.deinit() == .ok);
    const gpa = allocator.allocator();

    std.fs.File.stdout().writeAll(
        \\     ____                                           _   _______
        \\    / __ \____ __________ ___  ______ ___  ______ _/ | / / ___/
        \\   / /_/ / __ `/ ___/ __ `/ / / / __ `/ / / / __ `/  |/ /\__ \ 
        \\  / ____/ /_/ / /  / /_/ / /_/ / /_/ / /_/ / /_/ / /|  /___/ / 
        \\ /_/    \__,_/_/   \__,_/\__, /\__,_/\__, /\__,_/_/ |_//____/  
        \\                        /____/      /____/                     
        \\
    ) catch {};

    const config = common.config_util.loadOrCreateConfig(Config, "dispatch_config.zon", gpa) catch @panic("failed to load config");
    defer common.config_util.freeConfig(gpa, config);

    const handlers: []const http.RequestHandler = &(.{
        .{ "/query_dispatch", @import("query_dispatch.zig") },
        .{ "/query_gateserver", @import("query_gateserver.zig") },
    } ++ @import("autopatch.zig").handlers);

    http.serve(gpa, config.http_addr, config.http_port, &config, handlers) catch |err| {
        std.log.err("http.serve failed: {}", .{err});
    };
}
