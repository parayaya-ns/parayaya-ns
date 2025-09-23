const std = @import("std");
const pb = @import("proto").pb;
const AppInterface = @import("../AppInterface.zig");
const ChsTeamData = @import("../player/ChsTeamData.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.chs);

pub fn onGetChsPlayerTeamReq(gpa: Allocator, interface: *AppInterface, _: pb.GetChsPlayerTeamReq) !pb.GetChsPlayerTeamRsp {
    const chs_teams = &interface.player.chs_teams;
    var rsp: pb.GetChsPlayerTeamRsp = .{ .retcode = .RetSucc };

    try rsp.chs_team_list.ensureTotalCapacity(gpa, chs_teams.teams.count());
    for (chs_teams.teams.map.values()) |team| {
        rsp.chs_team_list.appendAssumeCapacity(try team.toClient(gpa));
    }

    return rsp;
}

pub fn onUpdateChsPlayerTeamReq(gpa: Allocator, interface: *AppInterface, req: pb.UpdateChsPlayerTeamReq) !pb.UpdateChsPlayerTeamRsp {
    const chs_player_team = req.player_team orelse return .{ .retcode = .RetReqParaInvalid };
    if (chs_player_team.index >= ChsTeamData.max_team_count) return .{ .retcode = .RetTeamIdxInvalid };
    if (chs_player_team.name.getSlice().len > ChsTeamData.ChsTeam.max_team_name_length) return .{ .retcode = .RetTeamNameFormatError };

    var team: ChsTeamData.ChsTeam = .{ .index = chs_player_team.index };
    team.name_len = chs_player_team.name.getSlice().len;
    @memcpy(team.name[0..team.name_len], chs_player_team.name.getSlice());

    for (chs_player_team.chs_trainer_list.items) |chs_trainer| {
        if (chs_trainer.index >= ChsTeamData.ChsTeam.max_trainer_count) return .{ .retcode = .RetTeamTrainerInvalid };
        const trainer = interface.player.trainer.trainers.getConstPtr(chs_trainer.trainer_id) orelse return .{ .retcode = .RetTrainerNotExist };

        team.trainers[chs_trainer.index] = ChsTeamData.ChsTeam.ChsTrainer{
            .id = trainer.id,
            .rank = trainer.rank,
        };
    }

    for (chs_player_team.chs_sprite_list.items) |chs_sprite| {
        if (chs_sprite.chs_cell_index >= ChsTeamData.ChsTeam.chs_cells_count) return .{ .retcode = .RetTeamSpriteInvalid };
        const sprite = interface.player.sprite.sprites.getConstPtr(chs_sprite.sprite_id) orelse return .{ .retcode = .RetSpriteNotExist };

        team.sprites[chs_sprite.chs_cell_index] = ChsTeamData.ChsTeam.ChsSprite{
            .sprite_id = sprite.id,
            .level = sprite.level,
            .rank = sprite.rank,
            .sprite_skin_id = 0,
        };
    }

    try interface.player.chs_teams.setTeam(gpa, team);

    return .{ .retcode = .RetSucc, .new_player_team = req.player_team };
}

pub fn onChangeChsPlayerTeamNameReq(_: Allocator, interface: *AppInterface, req: pb.ChangeChsPlayerTeamNameReq) !pb.ChangeChsPlayerTeamNameRsp {
    const team = interface.player.chs_teams.teams.getPtr(req.team_index) orelse return .{ .retcode = .RetTeamIdxInvalid };
    if (req.team_name.getSlice().len > ChsTeamData.ChsTeam.max_team_name_length) return .{ .retcode = .RetTeamNameFormatError };

    team.name_len = req.team_name.getSlice().len;
    @memcpy(team.name[0..team.name_len], req.team_name.getSlice());

    return .{ .retcode = .RetSucc, .change_team_index = req.team_index, .change_team_name = req.team_name };
}
