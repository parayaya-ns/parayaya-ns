const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.sprite_contract);

pub fn onGetSpriteContractReq(_: Allocator, _: *AppInterface, _: pb.GetSpriteContractReq) !pb.GetSpriteContractRsp {
    return .{ .retcode = .RetSucc };
}
