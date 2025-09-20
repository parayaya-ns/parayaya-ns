const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.daily_stage);

pub fn onGetDailyMaterialStageReq(_: Allocator, _: *AppInterface, _: pb.GetDailyMaterialStageReq) !pb.GetDailyMaterialStageRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onGetDailySpriteFragmentStageReq(_: Allocator, _: *AppInterface, _: pb.GetDailySpriteFragmentStageReq) !pb.GetDailySpriteFragmentStageRsp {
    return .{ .retcode = .RetSucc };
}
