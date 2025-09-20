const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.trainer);

pub fn onGetTrainerDataReq(gpa: Allocator, interface: *AppInterface, _: pb.GetTrainerDataReq) !pb.GetTrainerDataRsp {
    const trainer_data = &interface.player.trainer;
    var rsp: pb.GetTrainerDataRsp = .{ .retcode = .RetSucc };

    try rsp.trainer_list.ensureTotalCapacity(gpa, trainer_data.trainers.count());
    for (trainer_data.trainers.map.values()) |trainer| {
        rsp.trainer_list.appendAssumeCapacity(trainer.toClient());
    }

    return rsp;
}
