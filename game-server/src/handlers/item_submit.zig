const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.item_submit);

pub fn onGetItemSubmitReq(_: Allocator, _: *AppInterface, _: pb.GetItemSubmitReq) !pb.GetItemSubmitRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onGetRewardExchangeReq(_: Allocator, _: *AppInterface, _: pb.GetRewardExchangeReq) !pb.GetRewardExchangeRsp {
    return .{ .retcode = .RetSucc };
}
