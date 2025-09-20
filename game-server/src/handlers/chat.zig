const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.chat);

pub fn onGetChatSessionListReq(_: Allocator, _: *AppInterface, _: pb.GetChatSessionListReq) !pb.GetChatSessionListRsp {
    return .{ .retcode = .RetSucc };
}
