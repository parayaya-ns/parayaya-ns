const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.dialog);

pub fn onGetDialogDataReq(_: Allocator, _: *AppInterface, _: pb.GetDialogDataReq) !pb.GetDialogDataRsp {
    return .{ .retcode = .RetSucc };
}
