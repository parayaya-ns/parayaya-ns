const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.faction);

pub fn onGetAdvFactionReq(_: Allocator, _: *AppInterface, _: pb.GetAdvFactionReq) !pb.GetAdvFactionRsp {
    return .{
        .retcode = .RetSucc,
        .happy_faction = .{
            .adv_faction = .{
                .type = .AdvFactionType_Happy,
                .level = 10,
            },
        },
        .fight_faction = .{
            .adv_faction = .{
                .type = .AdvFactionType_Fight,
                .level = 10,
            },
        },
        .truth_faction = .{
            .adv_faction = .{
                .type = .AdvFactionType_Truth,
                .level = 10,
            },
        },
        .usurper_faction = .{
            .adv_faction = .{
                .type = .AdvFactionType_Usurper,
                .level = 10,
            },
        },
    };
}
