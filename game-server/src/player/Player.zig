const std = @import("std");
const pb = @import("proto").pb;
const Allocator = std.mem.Allocator;

const Player = @This();

const Assets = @import("../Assets.zig");
const BasicInfo = @import("BasicInfo.zig");
const SceneData = @import("SceneData.zig");
const TrainerData = @import("TrainerData.zig");
const Customization = @import("Customization.zig");

const properties = @import("properties.zig");

uid: u32,
basic_info: BasicInfo = .default,
scene_data: SceneData = .default,
trainer: TrainerData = .default,
customization: Customization = .default,

pub fn deinit(player: *@This(), gpa: Allocator) void {
    player.basic_info.deinit(gpa);
    player.scene_data.deinit(gpa);
    player.trainer.deinit(gpa);
    player.customization.deinit(gpa);
}

pub fn isAnyFieldChanged(player: *const Player) bool {
    inline for (std.meta.fields(@This())) |field| {
        if (comptime std.meta.activeTag(@typeInfo(field.type)) != .@"struct") continue;

        if (@hasField(field.type, "property")) {
            if (@field(player, field.name).property.isChanged()) return true;
        }
    }

    return false;
}

pub fn resetChangeState(player: *Player) void {
    inline for (std.meta.fields(@This())) |field| {
        if (comptime std.meta.activeTag(@typeInfo(field.type)) != .@"struct") continue;

        if (@hasField(field.type, "property")) {
            @field(player, field.name).property.resetChangeState();
        }
    }
}

pub fn buildPlayerSyncNotify(player: *const @This(), allocator: Allocator) !pb.PlayerSyncNotify {
    var notify: pb.PlayerSyncNotify = .{};

    inline for (std.meta.fields(@This())) |field| {
        if (comptime std.meta.activeTag(@typeInfo(field.type)) != .@"struct") continue;

        if (@hasField(field.type, "property") and std.meta.hasFn(field.type, "syncToClient")) {
            if (@field(player, field.name).property.isChanged()) {
                try @field(player, field.name).syncToClient(allocator, &notify);
            }
        }
    }

    return notify;
}

pub fn onFirstLogin(player: *Player, gpa: Allocator, assets: *const Assets) !void {
    try player.basic_info.nickname.set(gpa, "Parayaya");
    player.basic_info.create_timestamp.set(@intCast(std.time.timestamp()));

    const tables = &assets.table_configs;

    for (tables.trainer_common_table_config.items) |*config| {
        try player.trainer.unlockTrainer(gpa, config);
    }

    player.customization.avatar_id.set(51002);
    for (tables.player_avatar_table_config.items) |*config| {
        _ = try player.customization.unlocked_avatars.put(gpa, config.config_id);
    }

    for (tables.teleport_table.items) |*config| {
        _ = try player.scene_data.unlocked_teleports.put(gpa, config.config_id);
    }
}
