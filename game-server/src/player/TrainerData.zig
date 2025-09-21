const std = @import("std");
const pb = @import("proto").pb;
const properties = @import("properties.zig");
const tables = @import("../config/tables.zig");

const Allocator = std.mem.Allocator;

pub const default: @This() = .{};

property: properties.PropertyMixin(@This()) = .{},
trainers: properties.PropertyArrayHashMap(u32, Trainer) = .empty,

pub fn deinit(data: *@This(), gpa: Allocator) void {
    data.trainers.deinit(gpa);
}

pub fn unlockTrainer(data: *@This(), gpa: Allocator, config: *const tables.TrainerCommonConfig) Allocator.Error!void {
    if (!data.trainers.contains(config.config_id)) {
        try data.trainers.put(gpa, config.config_id, .{
            .id = config.config_id,
            .rank = Trainer.max_rank,
        });
    }
}

pub const Trainer = struct {
    pub const max_rank: u32 = 5;

    id: u32,
    rank: u32,

    pub fn toClient(trainer: *const Trainer) pb.Trainer {
        return .{
            .trainer_id = trainer.id,
            .rank = trainer.rank,
        };
    }
};
