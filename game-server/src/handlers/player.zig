const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");
const scene_util = @import("../scene/scene_util.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.player);

const default_teleport_id: u32 = 2;

pub fn onPlayerLoginReq(gpa: Allocator, interface: *AppInterface, req: pb.PlayerLoginReq) !pb.PlayerLoginRsp {
    log.debug("received PlayerLoginReq from {f}: {}", .{ interface.getRemoteAddress(), req });

    try interface.player.onFirstLogin(gpa, interface.assets);
    interface.player.resetChangeState();

    // Initialize scene
    const teleport = interface.assets.table_configs.teleport_table.get(default_teleport_id).?;
    interface.scene = try scene_util.createDefaultScene(
        gpa,
        interface.player.uid,
        interface.player.basic_info.actor_id.value,
    );

    interface.scene.?.fastTravelToTeleport(interface.player.uid, teleport);
    try scene_util.spawnBattleNpcNearPlayer(gpa, &interface.scene.?, interface.player.uid);

    interface.scene.?.is_modified = false;

    return .{
        .retcode = .RetSucc,
        .server_timestamp = @intCast(std.time.timestamp()),
    };
}

pub fn onPlayerHeartBeatReq(_: Allocator, _: *AppInterface, _: pb.PlayerHeartBeatReq) !pb.PlayerHeartBeatRsp {
    return .{
        .retcode = .RetSucc,
        .server_timestamp = @intCast(std.time.timestamp()),
    };
}

pub fn onPlayerGetBasicInfoReq(gpa: Allocator, interface: *AppInterface, _: pb.PlayerGetBasicInfoReq) !pb.PlayerGetBasicInfoRsp {
    return .{
        .retcode = .RetSucc,
        .player_basic_info = try interface.player.basic_info.toClient(gpa),
    };
}

pub fn onGetBuffReq(_: Allocator, _: *AppInterface, _: pb.GetBuffReq) !pb.GetBuffRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onPlayerGetWorldVarReq(_: Allocator, _: *AppInterface, _: pb.PlayerGetWorldVarReq) !pb.PlayerGetWorldVarRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onSetNicknameReq(gpa: Allocator, interface: *AppInterface, req: pb.SetNicknameReq) !pb.SetNicknameRsp {
    try interface.player.basic_info.nickname.set(gpa, req.nickname.getSlice());

    return .{ .retcode = .RetSucc };
}

pub fn onSetActorReq(_: Allocator, interface: *AppInterface, req: pb.SetActorReq) !pb.SetActorRsp {
    const scene = &(interface.scene orelse return .{ .retcode = .RetServerInternalError });

    const entity = scene.findPlayerActor(interface.player.uid).?;
    entity.parameters.actor.config_id = req.trainer_id;
    scene.is_modified = true;

    return .{
        .retcode = .RetSucc,
        .is_trainer_changed = req.is_trainer,
        .new_trainer_id = req.trainer_id,
    };
}
