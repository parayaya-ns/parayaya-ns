const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.tutorial);

pub fn onGetTutorialReq(_: Allocator, _: *AppInterface, _: pb.GetTutorialReq) !pb.GetTutorialRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onGetGraphicsTutorialReq(_: Allocator, _: *AppInterface, _: pb.GetGraphicsTutorialReq) !pb.GetGraphicsTutorialRsp {
    return .{ .retcode = .RetSucc };
}
