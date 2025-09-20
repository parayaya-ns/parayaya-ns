const std = @import("std");
const pb = @import("proto").pb;
const properties = @import("properties.zig");
const tables = @import("../config/tables.zig");

const Allocator = std.mem.Allocator;

pub const default: @This() = .{};

property: properties.PropertyMixin(@This()) = .{},
avatar_id: properties.BasicType(u32) = .{ .value = 0 },
unlocked_avatars: properties.PropertyHashSet(u32) = .empty,

pub fn deinit(data: *@This(), gpa: Allocator) void {
    data.unlocked_avatars.deinit(gpa);
}
