const std = @import("std");
const pb = @import("proto").pb;
const properties = @import("properties.zig");

const Allocator = std.mem.Allocator;

pub const default: @This() = .{};

property: properties.PropertyMixin(@This()) = .{},
nickname: properties.Slice(u8) = .empty,
level: properties.BasicType(u32) = .{ .value = 1 },
exp: properties.BasicType(u32) = .default,
create_timestamp: properties.BasicType(u32) = .default,
actor_id: properties.BasicType(u32) = .{ .value = 22900 },

pub fn deinit(basic_info: *@This(), gpa: Allocator) void {
    basic_info.nickname.deinit(gpa);
}

pub fn toClient(basic_info: *const @This(), gpa: Allocator) !pb.PlayerBasicInfo {
    return .{
        .nickname = if (basic_info.nickname.slice.len != 0) try .copy(basic_info.nickname.slice, gpa) else .Empty,
        .level = basic_info.level.value,
        .exp = basic_info.exp.value,
        .create_timestamp = basic_info.create_timestamp.value,
    };
}

pub fn syncToClient(basic_info: *const @This(), gpa: Allocator, notify: *pb.PlayerSyncNotify) !void {
    notify.player_basic_info_sync = try basic_info.toClient(gpa);
}
