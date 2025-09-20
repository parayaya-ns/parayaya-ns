const std = @import("std");
const proto = @import("proto");
const AppInterface = @import("AppInterface.zig");
const NetPacket = @import("net/NetPacket.zig");

const Allocator = std.mem.Allocator;

const cmd_id_name = "cmd_id";

const namespaces: []const type = &.{
    @import("handlers/player.zig"),
    @import("handlers/chs.zig"),
    @import("handlers/mission.zig"),
    @import("handlers/sprite.zig"),
    @import("handlers/customization.zig"),
    @import("handlers/item.zig"),
    @import("handlers/sprite_contract.zig"),
    @import("handlers/dialog.zig"),
    @import("handlers/quest.zig"),
    @import("handlers/tutorial.zig"),
    @import("handlers/scene_object.zig"),
    @import("handlers/dungeon.zig"),
    @import("handlers/archive.zig"),
    @import("handlers/stage.zig"),
    @import("handlers/shop.zig"),
    @import("handlers/trainer.zig"),
    @import("handlers/faction.zig"),
    @import("handlers/item_submit.zig"),
    @import("handlers/scene.zig"),
    @import("handlers/activity.zig"),
    @import("handlers/mail.zig"),
    @import("handlers/chat.zig"),
    @import("handlers/short_message.zig"),
    @import("handlers/pranama_honkai.zig"),
    @import("handlers/daily_stage.zig"),
};

pub const Handler = struct {
    namespace: type,
    Message: type,
    Response: type,
    name: []const u8,

    pub inline fn invoke(
        comptime handler: Handler,
        gpa: Allocator,
        app_interface: *AppInterface,
        message: handler.Message,
    ) handler.Response {
        return try @field(handler.namespace, handler.name)(gpa, app_interface, message);
    }

    pub inline fn hasResponse(comptime handler: Handler) bool {
        return handler.Response != void;
    }
};

const CmdId = build_enum: {
    var fields: []const std.builtin.Type.EnumField = &.{};

    for (namespaces) |namespace| {
        for (std.meta.declarations(namespace)) |decl| {
            switch (@typeInfo(@TypeOf(@field(namespace, decl.name)))) {
                .@"fn" => |fn_info| {
                    const Message = fn_info.params[2].type.?;
                    if (!@hasDecl(Message, cmd_id_name)) continue;

                    fields = fields ++ .{std.builtin.Type.EnumField{
                        .name = @typeName(Message),
                        .value = @field(Message, cmd_id_name),
                    }};
                },
                else => {},
            }
        }
    }

    break :build_enum @Type(.{ .@"enum" = .{
        .decls = &.{},
        .tag_type = u16,
        .fields = fields,
        .is_exhaustive = true,
    } });
};

pub const ProcessError = error{
    UnknownCmd,
    HandlerFailed,
    SendNotifiesFailed,
    SendResponseFailed,
} || proto.protobuf.UnionDecodingError;

pub fn dispatchPacket(
    gpa: Allocator,
    packet: *const NetPacket,
    interface: *AppInterface,
) ProcessError!void {
    const cmd_id = std.meta.intToEnum(CmdId, packet.cmd_id) catch return error.UnknownCmd;

    switch (cmd_id) {
        inline else => |id| {
            const handler = getHandler(id);
            const message = try proto.decode(handler.Message, packet.body, gpa);

            const response = handler.invoke(gpa, interface, message) catch |err| {
                std.log.err("failed to handle message of type {s}, error: {}", .{ @typeName(handler.Message), err });
                return error.HandlerFailed;
            };

            defer if (@TypeOf(response) != void) response.pb.deinit(gpa);
            interface.sendAutoNotifies(gpa) catch return error.SendNotifiesFailed;

            if (@TypeOf(response) != void) {
                interface.send(response) catch return error.SendResponseFailed;
            }

            std.log.debug("successfully handled message of type {s}", .{@typeName(handler.Message)});
        },
    }
}

pub inline fn getHandler(comptime cmd_id: CmdId) Handler {
    @setEvalBranchQuota(100_000);

    inline for (namespaces) |namespace| {
        inline for (comptime std.meta.declarations(namespace)) |decl| {
            switch (@typeInfo(@TypeOf(@field(namespace, decl.name)))) {
                .@"fn" => |fn_info| {
                    const Message = fn_info.params[2].type.?;
                    if (!@hasDecl(Message, cmd_id_name)) continue;

                    const handler_cmd_id: CmdId = @enumFromInt(@field(Message, cmd_id_name));

                    if (cmd_id == handler_cmd_id) {
                        return .{
                            .namespace = namespace,
                            .Message = Message,
                            .Response = fn_info.return_type.?,
                            .name = decl.name,
                        };
                    }
                },
                else => {},
            }
        }
    }

    unreachable; // the 'CmdId' enum is generated from all possible handlers
}
