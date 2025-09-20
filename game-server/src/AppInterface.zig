const std = @import("std");
const pb = @import("proto").pb;

const Assets = @import("Assets.zig");
const Scene = @import("scene/Scene.zig");
const Player = @import("player/Player.zig");
const NetPacket = @import("net/NetPacket.zig");

const AppInterface = @This();
const Allocator = std.mem.Allocator;

pub const VTable = struct {
    getRemoteAddress: *const fn (interface: *const AppInterface) std.net.Address,
};

vtable: *const VTable,
assets: *const Assets,
player: *Player,
scene: ?*Scene = null,
client_writer: *std.Io.Writer,

pub fn send(interface: *AppInterface, message: anytype) !void {
    try NetPacket.encode(interface.client_writer, message);
}

pub fn sendAutoNotifies(interface: *AppInterface, gpa: Allocator) !void {
    if (interface.player.isAnyFieldChanged()) {
        const player_sync_notify = try interface.player.buildPlayerSyncNotify(gpa);
        defer player_sync_notify.pb.deinit(gpa);

        try interface.send(player_sync_notify);
        interface.player.resetChangeState();
    }

    if (interface.scene) |scene| {
        if (scene.is_modified) {
            // TODO: use SceneRefreshNotify for non-transitional updates

            const notify: pb.SceneInfoNotify = .{ .new_scene_info = try scene.toClient(gpa) };
            defer notify.pb.deinit(gpa);

            try interface.send(notify);
            scene.is_modified = false;
        }
    }
}

pub fn getRemoteAddress(interface: *const AppInterface) std.net.Address {
    return interface.vtable.getRemoteAddress(interface);
}

pub fn deinit(interface: *AppInterface, gpa: Allocator) void {
    if (interface.scene) |scene| scene.deinit(gpa);
}
