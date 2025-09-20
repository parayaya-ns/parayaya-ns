const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.archive);

pub fn onGetArchiveReq(_: Allocator, _: *AppInterface, _: pb.GetArchiveReq) !pb.GetArchiveRsp {
    return .{ .retcode = .RetSucc };
}
