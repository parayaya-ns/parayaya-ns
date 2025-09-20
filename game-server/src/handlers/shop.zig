const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.shop);

pub fn onGetShopListReq(_: Allocator, _: *AppInterface, _: pb.GetShopListReq) !pb.GetShopListRsp {
    return .{ .retcode = .RetSucc };
}
