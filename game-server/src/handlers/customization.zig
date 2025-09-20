const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.customization);

pub fn onGetPlayerTitleReq(_: Allocator, _: *AppInterface, _: pb.GetPlayerTitleReq) !pb.GetPlayerTitleRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onGetPlayerAvatarReq(gpa: Allocator, interface: *AppInterface, _: pb.GetPlayerAvatarReq) !pb.GetPlayerAvatarRsp {
    const customization = &interface.player.customization;

    var rsp: pb.GetPlayerAvatarRsp = .{
        .retcode = .RetSucc,
        .cur_avatar_id = customization.avatar_id.value,
    };

    try rsp.unlocked_avatar_id_list.ensureTotalCapacity(gpa, customization.unlocked_avatars.count());
    var unlocked_avatars = customization.unlocked_avatars.iterate();
    while (unlocked_avatars.next()) |id| {
        rsp.unlocked_avatar_id_list.appendAssumeCapacity(id.*);
    }

    return rsp;
}

pub fn onGetCharacterCustomizationReq(_: Allocator, _: *AppInterface, _: pb.GetCharacterCustomizationReq) !pb.GetCharacterCustomizationRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onGetCharacterDressingReq(_: Allocator, _: *AppInterface, _: pb.GetCharacterDressingReq) !pb.GetCharacterDressingRsp {
    return .{ .retcode = .RetSucc };
}

pub fn onSetPlayerAvatarReq(_: Allocator, interface: *AppInterface, req: pb.SetPlayerAvatarReq) !pb.SetPlayerAvatarRsp {
    const customization = &interface.player.customization;
    std.log.debug("{}", .{req});

    if (!customization.unlocked_avatars.contains(req.player_avatar_id)) return .{ .retcode = .RetPlayerAvatarLocked };
    customization.avatar_id.set(req.player_avatar_id);

    return .{ .retcode = .RetSucc };
}
