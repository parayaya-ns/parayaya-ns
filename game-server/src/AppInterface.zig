const std = @import("std");
const pb = @import("proto").pb;

const Assets = @import("Assets.zig");
const Battle = @import("battle/Battle.zig");
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
scene: ?Scene = null,
battle: ?Battle = null,
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

    if (interface.scene != null) {
        const scene = &interface.scene.?;

        if (scene.is_modified) {
            // TODO: use SceneRefreshNotify for non-transitional updates

            const notify: pb.SceneInfoNotify = .{ .new_scene_info = try scene.toClient(gpa) };
            defer notify.pb.deinit(gpa);

            try interface.send(notify);
            scene.is_modified = false;
        }
    }

    if (interface.battle != null and interface.battle.?.is_settled) {
        interface.destructBattle(gpa);
    }
}

pub fn enterBattle(interface: *AppInterface, gpa: Allocator, battle: Battle) !void {
    interface.destructBattle(gpa);

    const notify: pb.EnterBattleNotify = .{
        .state = battle.state,
        .stage_battle_info = battle.toClient(),
    };

    defer notify.pb.deinit(gpa);
    try interface.send(notify);

    interface.battle = battle;
}

pub fn getRemoteAddress(interface: *const AppInterface) std.net.Address {
    return interface.vtable.getRemoteAddress(interface);
}

pub fn deinit(interface: *AppInterface, gpa: Allocator) void {
    interface.destructScene(gpa);
    interface.destructBattle(gpa);
}

fn destructScene(interface: *AppInterface, gpa: Allocator) void {
    if (interface.scene != null) {
        interface.scene.?.deinit(gpa);
        interface.scene = null;
    }
}

fn destructBattle(interface: *AppInterface, gpa: Allocator) void {
    if (interface.battle != null) {
        interface.battle.?.deinit(gpa);
        interface.battle = null;
    }
}
