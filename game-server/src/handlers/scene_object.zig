const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.scene_object);

pub fn onGetSceneObjectAliasReq(_: Allocator, _: *AppInterface, _: pb.GetSceneObjectAliasReq) !pb.GetSceneObjectAliasRsp {
    return .{ .retcode = .RetSucc };
}
