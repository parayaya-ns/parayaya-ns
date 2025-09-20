const std = @import("std");
const gateway = @import("net/gateway.zig");
const Assets = @import("Assets.zig");

const address = std.net.Address.parseIp4("0.0.0.0", 23301) catch unreachable;

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

    const assets = Assets.init(gpa) catch |err| {
        std.log.err("failed to load assets: {}", .{err});
        std.process.exit(1);
    };

    gateway.serve(gpa, address, &assets) catch |err| {
        std.log.err("gateway.serve failed: {}", .{err});
    };
}
