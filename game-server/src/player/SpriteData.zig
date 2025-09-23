const std = @import("std");
const pb = @import("proto").pb;
const properties = @import("properties.zig");
const tables = @import("../config/tables.zig");

const Allocator = std.mem.Allocator;

pub const default: @This() = .{};

property: properties.PropertyMixin(@This()) = .{},
sprites: properties.PropertyArrayHashMap(u32, Sprite) = .empty,
abilities: properties.PropertyArrayHashMap(u32, SpriteAbility) = .empty,

pub fn deinit(data: *@This(), gpa: Allocator) void {
    for (data.sprites.map.values()) |*sprite| {
        sprite.deinit(gpa);
    }

    data.sprites.deinit(gpa);
    data.abilities.deinit(gpa);
}

pub fn unlockSprite(data: *@This(), gpa: Allocator, config: *const tables.SpriteCommonConfig) Allocator.Error!void {
    if (!data.sprites.contains(config.config_id)) {
        try data.sprites.put(gpa, config.config_id, .{
            .id = config.config_id,
            .level = 0,
            .exp = 0,
            .rank = Sprite.max_rank,
            .seen = true,
        });
    }
}

pub fn unlockAbility(data: *@This(), gpa: Allocator, config: *const tables.SpriteAbilityConfig) Allocator.Error!void {
    if (!data.abilities.contains(config.config_id)) {
        try data.abilities.put(gpa, config.config_id, .{
            .id = config.config_id,
        });
    }
}

pub fn syncToClient(data: *const @This(), gpa: Allocator, notify: *pb.PlayerSyncNotify) !void {
    try notify.sprites.ensureTotalCapacity(gpa, data.sprites.changed_keys.items.len);

    for (data.sprites.changed_keys.items) |id| {
        if (data.sprites.getConstPtr(id)) |sprite| {
            notify.sprites.appendAssumeCapacity(try sprite.toClient(gpa));
        }
    }
}

pub const Sprite = struct {
    pub const max_rank: u32 = 5;

    id: u32,
    level: u32,
    exp: u32,
    rank: u32,
    seen: bool,
    name: []const u8 = "",

    pub fn toClient(sprite: *const Sprite, gpa: Allocator) Allocator.Error!pb.Sprite {
        return .{
            .sprite_id = sprite.id,
            .level = sprite.level,
            .exp = sprite.exp,
            .rank = sprite.rank,
            .has_seen_sprite = sprite.seen,
            .name = if (sprite.name.len != 0) try .copy(sprite.name, gpa) else .Empty,
        };
    }

    pub fn setName(sprite: *Sprite, gpa: Allocator, name: []const u8) Allocator.Error!void {
        if (sprite.name.len != 0) gpa.free(sprite.name);
        sprite.name = try gpa.dupe(u8, name);
    }

    pub fn deinit(sprite: *Sprite, gpa: Allocator) void {
        gpa.free(sprite.name);
    }
};

pub const SpriteAbility = struct {
    pub const flight_ability_id: u32 = 1;

    id: u32,
    cur_sprite_id: u32 = 0,

    pub fn toClient(ability: *const SpriteAbility) pb.SpriteAbility {
        return .{
            .sprite_ability_id = ability.id,
            .cur_ability_sprite_id = ability.cur_sprite_id,
        };
    }
};
