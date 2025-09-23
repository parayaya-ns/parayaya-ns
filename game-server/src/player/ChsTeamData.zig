const std = @import("std");
const pb = @import("proto").pb;
const properties = @import("properties.zig");
const tables = @import("../config/tables.zig");

const Allocator = std.mem.Allocator;

pub const max_team_count: u32 = 20;
pub const default: @This() = .{};

property: properties.PropertyMixin(@This()) = .{},
teams: properties.PropertyArrayHashMap(u32, ChsTeam) = .empty,
active_team_index: properties.BasicType(u32) = .{ .value = 0 },

pub fn deinit(data: *@This(), gpa: Allocator) void {
    data.teams.deinit(gpa);
}

pub fn setTeam(data: *@This(), gpa: Allocator, team: ChsTeam) Allocator.Error!void {
    try data.teams.put(gpa, team.index, team);
}

pub fn syncToClient(data: *const @This(), gpa: Allocator, notify: *pb.PlayerSyncNotify) !void {
    var chs_player_team_sync: pb.ChsPlayerTeamSyncInfo = .{};
    try chs_player_team_sync.sync_chs_team_list.ensureTotalCapacity(gpa, data.teams.changed_keys.items.len);

    for (data.teams.changed_keys.items) |index| {
        if (data.teams.getConstPtr(index)) |team| {
            chs_player_team_sync.sync_chs_team_list.appendAssumeCapacity(try team.toClient(gpa));
        }
    }

    notify.chs_player_team_sync = chs_player_team_sync;
}

pub const ChsTeam = struct {
    pub const max_trainer_count: u32 = 3;
    pub const chs_cells_count: u32 = 56;
    pub const max_team_name_length: usize = 32;

    index: u32,
    trainers: [max_trainer_count]?ChsTrainer = @splat(null),
    sprites: [chs_cells_count]?ChsSprite = @splat(null),
    name: [max_team_name_length]u8 = undefined,
    name_len: usize = 0,

    pub const ChsTrainer = struct {
        id: u32,
        rank: u32,
    };

    pub const ChsSprite = struct {
        sprite_id: u32,
        rank: u32,
        level: u32,
        sprite_skin_id: u32,
    };

    pub fn toClient(team: *const ChsTeam, allocator: Allocator) Allocator.Error!pb.ChsPlayerTeam {
        var chs_player_team: pb.ChsPlayerTeam = .{
            .index = team.index,
            .name = try .copy(team.name[0..team.name_len], allocator),
        };

        try chs_player_team.chs_trainer_list.ensureTotalCapacity(allocator, max_trainer_count);
        try chs_player_team.chs_sprite_list.ensureTotalCapacity(allocator, chs_cells_count);

        for (team.trainers, 0..) |t, index| {
            const trainer = t orelse continue;

            chs_player_team.chs_trainer_list.appendAssumeCapacity(.{
                .index = @intCast(index),
                .trainer_id = trainer.id,
                .rank = trainer.rank,
            });
        }

        for (team.sprites, 0..) |s, index| {
            const sprite = s orelse continue;

            chs_player_team.chs_sprite_list.appendAssumeCapacity(.{
                .chs_cell_index = @intCast(index),
                .sprite_id = sprite.sprite_id,
                .sprite_skin_id = sprite.sprite_skin_id,
                .level = sprite.level,
                .rank = sprite.rank,
                .unit_type = .ChsUnitType_Sprite,
            });
        }

        return chs_player_team;
    }
};
