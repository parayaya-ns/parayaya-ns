const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.mail);

pub fn onGetMailReq(_: Allocator, _: *AppInterface, _: pb.GetMailReq) !pb.GetMailRsp {
    return .{ .retcode = .RetSucc };
}
