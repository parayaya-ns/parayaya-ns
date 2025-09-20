const std = @import("std");
const Config = @import("Config.zig");
const RequestHandler = @import("http.zig").RequestHandler;

const assets: []const []const u8 = &.{
    "ini/v0.3_live/820659_5356a584dd/DefaultSettings.bin",
    "ini/v0.3_live/820659_5356a584dd/DefaultDeviceProfile.bin",
    "ini/v0.3_live/820659_5356a584dd/Windows/DefaultSettings.bin",
    "ini/v0.3_live/820659_5356a584dd/Windows/DefaultDeviceProfile.bin",
    "ifix/v0.3_live/1188647018_836485/Windows/Patch/ifix.manifest",
    "ifix/v0.3_live/1188647018_836485/Windows/Patch/ABC.Adventure.dll.patch",
    "ifix/v0.3_live/1188647018_836485/Windows/Patch/ABC.Chess.dll.patch",
    "ifix/v0.3_live/1188647018_836485/Windows/Patch/ABC.Common.dll.patch",
    "ifix/v0.3_live/1188647018_836485/Windows/Patch/ABC.TechArt.dll.patch",
    "design_data/v0.3_live/847131_e347a33b7f/Block/ConfigDownloadManifest.bin",
    "audio/v0.3_live/820661_d420f801f3/Windows/DownloadManifests/AudioDownloadManifest.bin",
    "video/v0.3_live/821844_90bb61786e/Windows/videoconfig.bin",
    "resource/v0.3_live/847921_ab1b0dc1e2/Windows/Block/ArchiveVerifyConfig_0_3.bin",
    "resource/v0.3_live/847921_ab1b0dc1e2/Windows/Patch/ContentPatchConfig.bin",
};

pub const handlers: [assets.len]RequestHandler = blk: {
    var asset_handlers: [assets.len]RequestHandler = undefined;

    for (assets, 0..) |path, i| {
        asset_handlers[i] = asset(path);
    }

    break :blk asset_handlers;
};

pub fn asset(comptime path: []const u8) RequestHandler {
    const binary_data = @embedFile(path);

    return .{ "/" ++ path, struct {
        pub fn process(
            _: std.mem.Allocator,
            _: *const Config,
            request: *std.http.Server.Request,
            _: []const u8,
        ) !void {
            try request.respond(binary_data, .{});
        }
    } };
}
