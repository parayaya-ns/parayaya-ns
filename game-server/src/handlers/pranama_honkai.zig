const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.pranama_honkai);

pub fn onGetPranamaHonkaiReq(_: Allocator, _: *AppInterface, _: pb.GetPranamaHonkaiReq) !pb.GetPranamaHonkaiRsp {
    return .{ .retcode = .RetSucc };
}
