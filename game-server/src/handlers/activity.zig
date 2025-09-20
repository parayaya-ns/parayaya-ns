const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.activity);

pub fn onGetActivityScheduleReq(_: Allocator, _: *AppInterface, _: pb.GetActivityScheduleReq) !pb.GetActivityScheduleRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onGetChallengeThemeActivityReq(_: Allocator, _: *AppInterface, _: pb.GetChallengeThemeActivityReq) !pb.GetChallengeThemeActivityRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onGetPataActivityReq(_: Allocator, _: *AppInterface, _: pb.GetPataActivityReq) !pb.GetPataActivityRsp {
    return .{ .retcode = .RetSucc };
}
