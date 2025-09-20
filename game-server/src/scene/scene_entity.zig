const std = @import("std");
const pb = @import("proto").pb;
const tables = @import("../config/tables.zig");

const Allocator = std.mem.Allocator;

pub const EntityType = enum(i32) {
    actor = 1,
};

pub const Entity = union(EntityType) {
    actor: Actor,

    pub fn toClient(entity: *const Entity) pb.SceneEntity {
        return switch (entity.*) {
            inline else => |e| e.toClient(),
        };
    }

    pub fn getMotion(entity: *Entity) *Motion {
        return switch (entity.*) {
            inline else => |*e| &e.motion,
        };
    }

    pub const Actor = struct {
        motion: Motion,
        player_uid: u32,
        config_id: u32,

        pub fn toClient(actor: *const Actor) pb.SceneEntity {
            return .{
                .entity_type = .EntityActor,
                .owner_uid = actor.player_uid,
                .motion = actor.motion.toClient(),
                .scene_actor = .{
                    .config_id = actor.config_id,
                    .player_uid = actor.player_uid,
                },
            };
        }
    };
};

pub const Motion = struct {
    pos: @Vector(3, f32) = @splat(0),
    rot: @Vector(3, f32) = @splat(0),

    pub fn toClient(motion: *const Motion) pb.MotionInfo {
        return .{
            .pos = .{ .x = motion.pos[0], .y = motion.pos[1], .z = motion.pos[2] },
            .rot = .{ .x = motion.rot[0], .y = motion.rot[1], .z = motion.rot[2] },
        };
    }

    pub fn initFromConfig(pos: *const tables.Vector3, rot: *const tables.Vector3) Motion {
        return .{
            .pos = .{ pos.x, pos.y, pos.z },
            .rot = .{ rot.x, rot.y, rot.z },
        };
    }

    pub fn fromClient(motion: *Motion, client_info: *const pb.MotionInfo) void {
        if (client_info.pos) |pos| {
            motion.pos = .{ pos.x, pos.y, pos.z };
        }

        if (client_info.rot) |rot| {
            motion.rot = .{ rot.x, rot.y, rot.z };
        }
    }
};
