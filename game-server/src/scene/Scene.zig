const std = @import("std");
const pb = @import("proto").pb;
const scene_entity = @import("scene_entity.zig");
const tables = @import("../config/tables.zig");

const Scene = @This();
const Allocator = std.mem.Allocator;
pub const Entity = scene_entity.Entity;
pub const Motion = scene_entity.Motion;

scene_id: u32,
owner_uid: u32,
entity_id_counter: u64 = 0,
entities: std.AutoArrayHashMapUnmanaged(u64, Entity) = .empty,
is_modified: bool = false,

pub fn deinit(scene: *Scene, gpa: Allocator) void {
    scene.entities.deinit(gpa);
}

pub fn fastTravelToTeleport(scene: *Scene, player_uid: u32, config: *const tables.TeleportConfig) void {
    scene.is_modified = true;
    scene.scene_id = config.scene_id;

    if (scene.findPlayerActor(player_uid)) |entity| {
        entity.motion = .initFromConfig(&config.position, &config.rotation);
    }
}

pub fn addEntity(scene: *Scene, gpa: Allocator, entity: Entity) !u64 {
    scene.entity_id_counter += 1;

    const result = try scene.entities.getOrPut(gpa, scene.entity_id_counter);
    result.value_ptr.* = entity;
    result.value_ptr.entity_id = scene.entity_id_counter;

    return scene.entity_id_counter;
}

pub fn summon(scene: *Scene, gpa: Allocator, summoner: *const Entity, summonee_id: u32, placement: Motion) !u64 {
    return try scene.addEntity(gpa, .{
        .owner_uid = summoner.owner_uid,
        .motion = placement,
        .parameters = .{ .minion = .{
            .config_id = summonee_id,
            .summoner_entity_id = summoner.entity_id,
        } },
    });
}

pub fn findPlayerActor(scene: *Scene, player_uid: u32) ?*Entity {
    var entities = scene.entities.iterator();
    while (entities.next()) |e| {
        if (std.meta.activeTag(e.value_ptr.parameters) == .actor and e.value_ptr.parameters.actor.player_uid == player_uid) return e.value_ptr;
    }

    return null;
}

pub fn toClient(scene: *const Scene, gpa: Allocator) !pb.SceneInfo {
    var scene_info: pb.SceneInfo = .{
        .scene_id = scene.scene_id,
        .owner_uid = scene.owner_uid,
    };

    try scene_info.scene_entity_list.ensureTotalCapacity(gpa, scene.entities.count());

    var entities = scene.entities.iterator();
    while (entities.next()) |e| {
        scene_info.scene_entity_list.appendAssumeCapacity(e.value_ptr.toClient());
    }

    return scene_info;
}
