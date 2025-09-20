const std = @import("std");
const AppInterface = @import("../AppInterface.zig");
const Assets = @import("../Assets.zig");
const Client = @import("Client.zig");
const Player = @import("../player/Player.zig");

const PlayerSession = @This();
const Allocator = std.mem.Allocator;

interface: AppInterface,
client: *Client,
player: Player,

pub fn create(gpa: Allocator, client: *Client, assets: *const Assets) Allocator.Error!*PlayerSession {
    const session = try gpa.create(PlayerSession);

    session.* = .{
        .client = client,
        .player = .{ .uid = client.player_uid.? },
        .interface = .{
            .vtable = &vtable,
            .assets = assets,
            .player = &session.player,
            .client_writer = &client.writer.interface,
        },
    };

    return session;
}

pub fn destroy(session: *PlayerSession, gpa: Allocator) void {
    session.interface.deinit(gpa);
    session.player.deinit(gpa);
}

const vtable: AppInterface.VTable = .{
    .getRemoteAddress = getRemoteAddress,
};

fn getRemoteAddress(interface: *const AppInterface) std.net.Address {
    const session: *const PlayerSession = @fieldParentPtr("interface", interface);
    return session.client.address;
}
