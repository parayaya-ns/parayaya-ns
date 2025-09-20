const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.scene);

pub fn onGetEventGroupFinishEventReq(_: Allocator, _: *AppInterface, _: pb.GetEventGroupFinishEventReq) !pb.GetEventGroupFinishEventRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onGetTeleportReq(gpa: Allocator, interface: *AppInterface, _: pb.GetTeleportReq) !pb.GetTeleportRsp {
    const scene_data = &interface.player.scene_data;
    var rsp: pb.GetTeleportRsp = .{ .retcode = .RetSucc };

    try rsp.teleport_id_list.ensureTotalCapacity(gpa, scene_data.unlocked_teleports.count());
    var teleports = scene_data.unlocked_teleports.iterate();
    while (teleports.next()) |id| {
        rsp.teleport_id_list.appendAssumeCapacity(id.*);
    }

    return rsp;
}

pub fn onGetSceneInfoReq(gpa: Allocator, interface: *AppInterface, _: pb.GetSceneInfoReq) !pb.GetSceneInfoRsp {
    return .{
        .retcode = .RetSucc,
        .scene_info = try interface.scene.?.toClient(gpa),
    };
}

pub fn onSceneEntityMoveReq(_: Allocator, interface: *AppInterface, req: pb.SceneEntityMoveReq) !pb.SceneEntityMoveRsp {
    const scene = interface.scene orelse return .{ .retcode = .RetServerInternalError };

    for (req.entity_motion_list.items) |entity_motion| {
        if (scene.entities.getPtr(entity_motion.entity_id)) |entity| {
            entity.getMotion().fromClient(&(entity_motion.motion orelse .{}));
        }
    }

    return .{ .retcode = .RetSucc };
}

pub fn onFastTravelReq(_: Allocator, interface: *AppInterface, req: pb.FastTravelReq) !pb.FastTravelRsp {
    if (req.travel_point != null) {
        log.debug("Fast travel to point is not implemented yet. Requested point: {}", .{req.travel_point.?});
        return .{ .retcode = .RetServerInternalError };
    }

    if (!interface.player.scene_data.unlocked_teleports.contains(req.teleport_id)) {
        return .{ .retcode = .RetSceneTeleportNotActivated };
    }

    const config = interface.assets.table_configs.teleport_table.get(req.teleport_id) orelse {
        return .{ .retcode = .RetFail }; // should not happen, unless unlocked teleport was removed from table.
    };

    if (interface.scene) |scene| {
        scene.fastTravelToTeleport(interface.player.uid, config);
    }

    return .{ .retcode = .RetSucc };
}
