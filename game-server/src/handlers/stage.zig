const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.stage);

pub fn onStageGetRecordReq(_: Allocator, _: *AppInterface, _: pb.StageGetRecordReq) !pb.StageGetRecordRsp {
    return .{ .retcode = .RetSucc };
}
