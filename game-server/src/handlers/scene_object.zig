const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.scene_object);

pub fn onGetSceneObjectAliasReq(_: Allocator, _: *AppInterface, _: pb.GetSceneObjectAliasReq) !pb.GetSceneObjectAliasRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onClientEventReportReq(_: Allocator, interface: *AppInterface, req: pb.ClientEventReportReq) !pb.ClientEventReportRsp {
    log.debug("player with uid {} reported an event: {?}", .{ interface.player.uid, req.cast_skill_event });
    return .{ .retcode = .RetSucc };
}
