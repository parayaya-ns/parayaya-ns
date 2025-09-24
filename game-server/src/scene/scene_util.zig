const std = @import("std");
const Scene = @import("Scene.zig");

const Allocator = std.mem.Allocator;

pub fn createDefaultScene(
    gpa: Allocator,
    owner_uid: u32,
    owner_actor_config_id: u32,
) Allocator.Error!Scene {
    var scene: Scene = .{
        .scene_id = 0,
        .owner_uid = owner_uid,
    };

    _ = try scene.addEntity(gpa, .{
        .motion = .{},
        .owner_uid = owner_uid,
        .parameters = .{ .actor = .{
            .config_id = owner_actor_config_id,
            .player_uid = owner_uid,
        } },
    });

    return scene;
}

pub fn spawnBattleNpcNearPlayer(gpa: Allocator, scene: *Scene, player_uid: u32) Allocator.Error!void {
    // Test battle NPC group and entity
    // TODO: remove once it will be implemented properly.
    // This NPC's spawn should depend on AdvFaction progress.

    const actor = scene.findPlayerActor(player_uid).?;
    try scene.addGroup(gpa, 102933);

    _ = try scene.addEntity(gpa, .{
        .motion = actor.motion,
        .owner_uid = player_uid,
        .group_id = 102933,
        .inst_id = 10001,
        .parameters = .{ .character = .{} },
    });
}
