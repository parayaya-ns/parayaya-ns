const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.dungeon);

pub fn onGetDungeonReq(_: Allocator, _: *AppInterface, _: pb.GetDungeonReq) !pb.GetDungeonRsp {
    return .{ .retcode = .RetSucc };
}
