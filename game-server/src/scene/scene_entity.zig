const std = @import("std");
const pb = @import("proto").pb;
const tables = @import("../config/tables.zig");

const Allocator = std.mem.Allocator;

pub const EntityType = enum(i32) {
    actor = 1,
    character = 3,
    minion = 5,
};

pub const Entity = struct {
    entity_id: u64 = 0,
    owner_uid: u32,
    group_id: u32 = 0,
    inst_id: u32 = 0,
    motion: Motion,
    parameters: EntityParameters,

    pub fn toClient(entity: *const Entity) pb.SceneEntity {
        return switch (entity.parameters) {
            inline else => |e| @TypeOf(e).toClient(entity),
        };
    }
};

pub const EntityParameters = union(EntityType) {
    actor: Actor,
    character: Character,
    minion: Minion,

    pub const Actor = struct {
        player_uid: u32,
        config_id: u32,

        pub fn toClient(entity: *const Entity) pb.SceneEntity {
            return .{
                .entity_id = entity.entity_id,
                .entity_type = .EntityActor,
                .owner_uid = entity.owner_uid,
                .motion = entity.motion.toClient(),
                .scene_actor = .{
                    .config_id = entity.parameters.actor.config_id,
                    .player_uid = entity.parameters.actor.player_uid,
                },
            };
        }
    };

    pub const Character = struct {
        stage_id: u32 = 0,

        pub fn toClient(entity: *const Entity) pb.SceneEntity {
            return .{
                .entity_id = entity.entity_id,
                .entity_type = .EntityCharacter,
                .owner_uid = entity.owner_uid,
                .group_id = entity.group_id,
                .inst_id = entity.inst_id,
                .motion = entity.motion.toClient(),
                .scene_character = .{ .stage_id = entity.parameters.character.stage_id },
            };
        }
    };

    pub const Minion = struct {
        config_id: u32,
        summoner_entity_id: u64,

        pub fn toClient(entity: *const Entity) pb.SceneEntity {
            return .{
                .entity_id = entity.entity_id,
                .entity_type = .EntityActor,
                .owner_uid = entity.owner_uid,
                .motion = entity.motion.toClient(),
                .scene_minion = .{
                    .config_id = entity.parameters.minion.config_id,
                    .summoner_entity_id = entity.parameters.minion.summoner_entity_id,
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

    pub fn fromClient(client_info: *const pb.MotionInfo) Motion {
        var motion: Motion = .{};

        if (client_info.pos) |pos| {
            motion.pos = .{ pos.x, pos.y, pos.z };
        }

        if (client_info.rot) |rot| {
            motion.rot = .{ rot.x, rot.y, rot.z };
        }

        return motion;
    }
};
