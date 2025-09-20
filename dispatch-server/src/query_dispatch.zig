const std = @import("std");
const pb = @import("proto").pb;

const Config = @import("Config.zig");

const Allocator = std.mem.Allocator;
const Request = std.http.Server.Request;

pub fn process(gpa: Allocator, _: *const Config, request: *Request, _: []const u8) !void {
    var rsp: pb.Dispatch = .{
        .error_code = .RetSucc,
    };

    try rsp.region_list.ensureTotalCapacity(gpa, 2);
    defer rsp.region_list.deinit(gpa);

    rsp.region_list.appendAssumeCapacity(.{
        .region_name = .{ .Const = "parayaya_ns" },
        .dispatch_url = .{ .Const = "http://127.0.0.1:10100/query_gateserver" },
        .title = .{ .Const = "parayaya-ns" },
        .sdk_env = .{ .Const = "2" },
    });

    rsp.region_list.appendAssumeCapacity(.{
        .region_name = .{ .Const = "parayaya_ns_02" },
        .dispatch_url = .{ .Const = "http://127.0.0.1:10100/query_gateserver" },
        .title = .{ .Const = "parayaya-ns" },
        .sdk_env = .{ .Const = "2" },
    });

    var writer = std.Io.Writer.Allocating.init(gpa);
    defer writer.deinit();
    try rsp.pb.encode(&writer.writer);

    const content = try std.fmt.allocPrint(gpa, "{b64}", .{writer.written()});
    defer gpa.free(content);

    try request.respond(content, .{});
}
