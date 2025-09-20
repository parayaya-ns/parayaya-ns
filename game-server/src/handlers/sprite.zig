const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.sprite);

pub fn onGetSpriteDataReq(_: Allocator, _: *AppInterface, _: pb.GetSpriteDataReq) !pb.GetSpriteDataRsp {
    return .{ .retcode = .RetSucc };
}
