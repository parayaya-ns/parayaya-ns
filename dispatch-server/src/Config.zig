pub const defaults = @embedFile("dispatch_config.default.zon");

http_addr: []const u8,
http_port: u16,
resources: ResourceConfig,

pub const ResourceConfig = struct {
    ifix_url: []const u8,
    design_data_url: []const u8,
    resource_url: []const u8,
    video_url: []const u8,
    ini_url: []const u8,
    audio_url: []const u8,
};
