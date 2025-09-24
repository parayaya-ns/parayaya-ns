const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.battle);

pub fn onBattleRoundResultReq(gpa: Allocator, interface: *AppInterface, req: pb.BattleRoundResultReq) !pb.BattleRoundResultRsp {
    if (interface.battle == null) return .{ .retcode = .RetFail };

    const battle = &interface.battle.?;
    try battle.roundSettled(gpa, req.status);

    return .{
        .retcode = .RetSucc,
        .verify_status = req.status,
        .verify_round_end_reason = req.round_end_reason,
        .refresh_stage_battle_info = battle.toClient(),
        .round_settle_list = try battle.toClientRoundList(gpa),
    };
}

pub fn onBattleSettleReq(gpa: Allocator, interface: *AppInterface, req: pb.BattleSettleReq) !pb.BattleSettleRsp {
    if (interface.battle == null) return .{ .retcode = .RetFail };

    const battle = &interface.battle.?;
    battle.is_settled = true;

    return .{
        .retcode = .RetSucc,
        .battle_result = .BattleResult_Win,
        .verify_battle_id = req.battle_id,
        .round_settle_list = try battle.toClientRoundList(gpa),
    };
}
