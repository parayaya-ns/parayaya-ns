const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.mission);

pub fn onGetMissionReq(_: Allocator, _: *AppInterface, _: pb.GetMissionReq) !pb.GetMissionRsp {
    return .{ .retcode = .RetSucc };
}
