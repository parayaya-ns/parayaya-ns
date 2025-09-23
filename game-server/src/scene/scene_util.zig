const std = @import("std");
const Scene = @import("Scene.zig");

const Allocator = std.mem.Allocator;

pub fn createDefaultScene(
    gpa: Allocator,
    owner_uid: u32,
    owner_actor_config_id: u32,
) Allocator.Error!*Scene {
    const scene = try gpa.create(Scene);
    scene.* = .{
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
