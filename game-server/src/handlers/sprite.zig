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

    try rsp.sprite_ability_list.ensureTotalCapacity(gpa, sprite_data.abilities.count());
    for (sprite_data.abilities.map.values()) |ability| {
        rsp.sprite_ability_list.appendAssumeCapacity(ability.toClient());
    }

    return rsp;
}

pub fn onSetSpriteNameReq(gpa: Allocator, interface: *AppInterface, req: pb.SetSpriteNameReq) !pb.SetSpriteNameRsp {
    const sprite = interface.player.sprite.sprites.getPtr(req.sprite_id) orelse return .{ .retcode = .RetSpriteNotExist };
    try sprite.setName(gpa, req.name.getSlice());

    return .{ .retcode = .RetSucc };
}

pub fn onSpriteAbilitySetCurSpriteReq(_: Allocator, interface: *AppInterface, req: pb.SpriteAbilitySetCurSpriteReq) !pb.SpriteAbilitySetCurSpriteRsp {
    const sprite_data = &interface.player.sprite;

    if (!sprite_data.sprites.contains(req.sprite_id)) return .{ .retcode = .RetSpriteNotExist };
    const ability = sprite_data.abilities.getPtr(req.sprite_ability_id) orelse return .{ .retcode = .RetSpriteAbilityNotExist };
    ability.cur_sprite_id = req.sprite_id;

    return .{
        .retcode = .RetSucc,
        .cur_sprite_id = ability.id,
        .cur_sprite_ability_id = ability.cur_sprite_id,
    };
}

pub fn onSpriteAbilityCastReq(_: Allocator, _: *AppInterface, req: pb.SpriteAbilityCastReq) !pb.SpriteAbilityCastRsp {
    return .{
        .retcode = .RetSucc,
        .cur_sprite_id = req.sprite_id,
        .cur_sprite_ability_id = req.sprite_ability_id,
    };
}
