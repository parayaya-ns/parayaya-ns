const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.quest);

pub fn onGetQuestReq(_: Allocator, _: *AppInterface, _: pb.GetQuestReq) !pb.GetQuestRsp {
    return .{ .retcode = .RetSucc };
}
