const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.faction);

pub fn onGetAdvFactionReq(gpa: Allocator, _: *AppInterface, _: pb.GetAdvFactionReq) !pb.GetAdvFactionRsp {
    var rsp: pb.GetAdvFactionRsp = .{
        .retcode = .RetSucc,
        .happy_faction = .{
            .adv_faction = .{
                .type = .AdvFactionType_Happy,
                .level = 1,
            },
        },
        .fight_faction = .{
            .adv_faction = .{
                .type = .AdvFactionType_Fight,
                .level = 2,
                .F21FA5201F6E3FB3 = true,
                .F99CB1AB2858499E = true,
            },
        },
        .truth_faction = .{
            .adv_faction = .{
                .type = .AdvFactionType_Truth,
                .level = 1,
            },
        },
        .usurper_faction = .{
            .adv_faction = .{
                .type = .AdvFactionType_Usurper,
                .level = 1,
            },
        },
    };

    try rsp.fight_faction.?.faction_npc_list.append(gpa, .{
        .faction_npc_id = 6,
        .status = .AdvFactionNpcStatusShow,
    });

    return rsp;
}
