const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.item);

pub fn onGetBagReq(_: Allocator, _: *AppInterface, _: pb.GetBagReq) !pb.GetBagRsp {
    return .{ .retcode = .RetSucc };
}
