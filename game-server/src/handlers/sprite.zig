const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.sprite);

pub fn onGetSpriteDataReq(gpa: Allocator, interface: *AppInterface, _: pb.GetSpriteDataReq) !pb.GetSpriteDataRsp {
    const sprite_data = &interface.player.sprite;
    var rsp: pb.GetSpriteDataRsp = .{ .retcode = .RetSucc };

    try rsp.sprite_list.ensureTotalCapacity(gpa, sprite_data.sprites.count());
    for (sprite_data.sprites.map.values()) |sprite| {
        rsp.sprite_list.appendAssumeCapacity(try sprite.toClient(gpa));
    }

    return rsp;
}

pub fn onSetSpriteNameReq(gpa: Allocator, interface: *AppInterface, req: pb.SetSpriteNameReq) !pb.SetSpriteNameRsp {
    const sprite = interface.player.sprite.sprites.getPtr(req.sprite_id) orelse return .{ .retcode = .RetSpriteNotExist };
    try sprite.setName(gpa, req.name.getSlice());

    return .{ .retcode = .RetSucc };
}
