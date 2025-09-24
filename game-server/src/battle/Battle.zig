const std = @import("std");
const pb = @import("proto").pb;

const Allocator = std.mem.Allocator;
pub const State = pb.BattleState;

const Battle = @This();

battle_id: u32,
stage_id: u32,
is_settled: bool = false,
state: State = .BattleState_RoundPrepare,
finished_rounds: std.ArrayList(RoundSettle) = .empty,

pub fn deinit(battle: *Battle, gpa: Allocator) void {
    battle.finished_rounds.deinit(gpa);
}

pub const RoundSettle = struct {
    pub const Status = pb.BattleRoundStatus;

    stage_id: u32,
    index: u32,
    status: Status,

    pub fn toClient(settle: *const RoundSettle) pb.BattleRoundSettle {
        return .{
            .battle_stage_id = settle.stage_id,
            .battle_round_index = settle.index,
            .round_status = settle.status,
        };
    }
};

pub fn roundSettled(battle: *Battle, gpa: Allocator, status: RoundSettle.Status) Allocator.Error!void {
    try battle.finished_rounds.append(gpa, .{
        .index = @truncate(battle.finished_rounds.items.len),
        .stage_id = battle.stage_id,
        .status = status,
    });

    battle.state = .BattleState_WaitSettle;
}

pub fn toClientStageBrief(battle: *const Battle) pb.StageBrief {
    return .{ .stage_id = battle.stage_id };
}

pub fn toClientRoundList(battle: *const Battle, allocator: Allocator) Allocator.Error!std.ArrayList(pb.BattleRoundSettle) {
    var list: std.ArrayList(pb.BattleRoundSettle) = try .initCapacity(allocator, battle.finished_rounds.items.len);
    for (battle.finished_rounds.items) |settle| list.appendAssumeCapacity(settle.toClient());

    return list;
}

pub fn toClient(battle: *const Battle) pb.StageBattleInfo {
    const battle_info: pb.BattleInfo = .{
        .battle_id = battle.battle_id,
        .battle_stage_id = battle.stage_id,
        .battle_state = battle.state,
        .battle_round_index = @truncate(battle.finished_rounds.items.len),
    };

    return .{
        .battle_info = battle_info,
        .stage_brief = battle.toClientStageBrief(),
    };
}
