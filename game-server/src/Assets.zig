const std = @import("std");
const pb = @import("proto").pb;

const TableConfigManager = @import("config/tables.zig").TableConfigManager;

const Allocator = std.mem.Allocator;

table_configs: TableConfigManager,

const config_dir_path = "assets/config";

pub fn init(gpa: Allocator) !@This() {
    var config_dir = try std.fs.cwd().openDir(config_dir_path, .{});
    defer config_dir.close();

    var table_configs = try TableConfigManager.loadAll(gpa, config_dir);
    errdefer table_configs.deinit();

    return .{
        .table_configs = table_configs,
    };
}

pub fn deinit(this: *@This()) void {
    this.table_configs.deinit();
}
