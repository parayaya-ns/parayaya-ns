const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.dialog);

pub fn onGetDialogDataReq(_: Allocator, _: *AppInterface, _: pb.GetDialogDataReq) !pb.GetDialogDataRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onFinishDialogPackReq(gpa: Allocator, interface: *AppInterface, _: pb.FinishDialogPackReq) !pb.FinishDialogPackRsp {
    try interface.enterBattle(gpa, .{ .battle_id = 1002, .stage_id = 10002 });

    return .{ .retcode = .RetSucc };
}
