const std = @import("std");
const pb = @import("proto").pb;
const properties = @import("properties.zig");
const tables = @import("../config/tables.zig");

const Allocator = std.mem.Allocator;

pub const default: @This() = .{};

property: properties.PropertyMixin(@This()) = .{},
unlocked_teleports: properties.PropertyHashSet(u32) = .empty,

pub fn deinit(data: *@This(), gpa: Allocator) void {
    data.unlocked_teleports.deinit(gpa);
}
