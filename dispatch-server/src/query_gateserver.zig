const std = @import("std");
const pb = @import("proto").pb;

const Config = @import("Config.zig");
const rsa = @import("rsa.zig");

const Allocator = std.mem.Allocator;
const Request = std.http.Server.Request;

pub fn process(gpa: Allocator, config: *const Config, request: *Request, _: []const u8) !void {
    var rsp: pb.Gateserver = .{
        .error_code = .RetSucc,
        .region_name = .{ .Const = "parayaya_ns" },
        .ip = .{ .Const = "127.0.0.1" },
        .port = 23301,
        .use_tcp = true,
        .ifix_url = .managed(config.resources.ifix_url),
        .design_data_url = .managed(config.resources.design_data_url),
        .resource_url = .managed(config.resources.resource_url),
        .video_url = .managed(config.resources.video_url),
        .ini_url = .managed(config.resources.ini_url),
        .audio_url = .managed(config.resources.audio_url),
        .FC25194623A47B94 = true,
        .AC507CB15DF154AA = true,
    };

    var writer = std.Io.Writer.Allocating.init(gpa);
    defer writer.deinit();

    try rsp.pb.encode(&writer.writer);
    const rsp_body = writer.written();

    const content = try gpa.alloc(u8, rsa.paddedLength(rsp_body.len));
    defer gpa.free(content);

    var sign: [rsa.sign_size]u8 = undefined;

    rsa.encrypt(rsp_body, content);
    rsa.sign(rsp_body, &sign);

    const json_response = try std.fmt.allocPrint(gpa, "{{\"content\":\"{b64}\",\"sign\":\"{b64}\"}}", .{ content, &sign });
    defer gpa.free(json_response);

    try request.respond(json_response, .{});
}
