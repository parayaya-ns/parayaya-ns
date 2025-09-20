const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.chs);

pub fn onGetChsPlayerTeamReq(_: Allocator, _: *AppInterface, _: pb.GetChsPlayerTeamReq) !pb.GetChsPlayerTeamRsp {
    return .{ .retcode = .RetSucc };
}
