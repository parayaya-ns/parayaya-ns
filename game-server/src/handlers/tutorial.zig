const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.tutorial);

pub fn onGetTutorialReq(gpa: Allocator, _: *AppInterface, _: pb.GetTutorialReq) !pb.GetTutorialRsp {
    var rsp: pb.GetTutorialRsp = .{ .retcode = .RetSucc };

    try rsp.tutorial_id_list.ensureTotalCapacity(gpa, 200);
    for (0..100) |id| rsp.tutorial_id_list.appendAssumeCapacity(@intCast(id));
    for (1000..1100) |id| rsp.tutorial_id_list.appendAssumeCapacity(@intCast(id));

    return rsp;
}

pub fn onGetGraphicsTutorialReq(_: Allocator, _: *AppInterface, _: pb.GetGraphicsTutorialReq) !pb.GetGraphicsTutorialRsp {
    return .{ .retcode = .RetSucc };
}
