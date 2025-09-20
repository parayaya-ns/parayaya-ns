const std = @import("std");
const Allocator = std.mem.Allocator;

const max_config_size: usize = 1024 * 1024;
const defaults_field_name = "defaults";

pub fn loadOrCreateConfig(comptime Config: type, path: []const u8, gpa: Allocator) !Config {
    if (!@hasDecl(Config, defaults_field_name)) @compileError("Config type " ++ @typeName(Config) ++ " doesn't have defaults declared");

    const content = std.fs.cwd().readFileAllocOptions(gpa, path, max_config_size, null, .of(u8), 0) catch {
        return try createAt(Config, path, gpa);
    };

    defer gpa.free(content);
    return try std.zon.parse.fromSlice(Config, gpa, content, null, .{});
}

pub fn freeConfig(gpa: Allocator, config: anytype) void {
    std.zon.parse.free(gpa, config);
}

fn createAt(comptime Config: type, path: []const u8, gpa: std.mem.Allocator) !Config {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    const defaults = @field(Config, defaults_field_name);

    var writer = file.writer(&.{});
    try writer.interface.writeAll(defaults);

    return try std.zon.parse.fromSlice(Config, gpa, defaults, null, .{});
}
