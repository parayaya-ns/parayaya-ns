const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.short_message);

pub fn onGetShortMessageReq(_: Allocator, _: *AppInterface, _: pb.GetShortMessageReq) !pb.GetShortMessageRsp {
    return .{ .retcode = .RetSucc };
}
