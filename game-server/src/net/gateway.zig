const std = @import("std");
const proto = @import("proto");
const pb = proto.pb;

const Assets = @import("../Assets.zig");
const Server = @import("Server.zig");
const Client = @import("Client.zig");
const NetPacket = @import("NetPacket.zig");
const PlayerSession = @import("PlayerSession.zig");
const handlers = @import("../handlers.zig");

const Address = std.net.Address;
const Allocator = std.mem.Allocator;
const SessionMap = std.AutoHashMapUnmanaged(u32, *PlayerSession);

const log = std.log.scoped(.gateway);

pub fn serve(gpa: Allocator, address: Address, assets: *const Assets) !void {
    var server = Server.init(gpa, address) catch |err| {
        log.err("TCP server initialization failed: {}", .{err});
        return error.InitFailed;
    };

    var sessions: SessionMap = .empty;
    defer {
        var iter = sessions.iterator();
        while (iter.next()) |entry| entry.value_ptr.*.destroy(gpa);

        sessions.deinit(gpa);
    }

    defer server.deinit(gpa);
    log.info("server is listening at {f}", .{address});

    while (true) {
        var events = server.poll() catch @panic("poll failed");
        while (events.next()) |event| {
            switch (event) {
                .accept => try server.onConnect(gpa),
                .recv => |recv| onReceive(gpa, recv.client, &sessions, assets) catch |err| {
                    if (err != error.EndOfStream) log.err(
                        "onReceive failed: {}, remote address: {f}",
                        .{ err, recv.client.address },
                    );

                    if (recv.client.player_uid) |uid| {
                        if (sessions.fetchRemove(uid)) |session| {
                            session.value.destroy(gpa);
                        }
                    }

                    server.onDisconnect(gpa, recv.poll_index, recv.client);
                    events.index -= 1; // since one poll is now removed, rewind index by one
                },
            }
        }
    }
}

fn onReceive(gpa: Allocator, client: *Client, sessions: *SessionMap, assets: *const Assets) !void {
    try client.reader.interface.fillMore();

    const player_session = if (client.player_uid) |uid| sessions.get(uid) else null;

    while (NetPacket.decode(&client.reader.interface)) |packet| {
        defer packet.deinit();

        if (player_session) |session| {
            handlePacket(gpa, session, &packet) catch return error.HandlePacketFailed;
        } else {
            if (packet.cmd_id == pb.GetPlayerTokenReq.cmd_id) {
                const uid = getPlayerToken(gpa, client, &packet) catch return error.GetPlayerTokenFailed;
                try sessions.put(gpa, uid, try PlayerSession.create(gpa, client, assets));
            } else {
                log.err("received unexpected first cmd_id: {}", .{packet.cmd_id});
                return error.UnexpectedFirstCmd;
            }
        }
    } else |err| {
        switch (err) {
            error.Incomplete => {},
            error.Corrupted => return error.StreamCorrupted,
        }
    }

    client.writer.interface.flush() catch return error.SendFailed;
}

fn handlePacket(gpa: Allocator, session: *PlayerSession, packet: *const NetPacket) !void {
    @setEvalBranchQuota(1_000_000);

    handlers.dispatchPacket(gpa, packet, &session.interface) catch |err| {
        if (err == handlers.ProcessError.UnknownCmd) {
            std.log.warn(
                "no handler found for message with cmd_id {}, payload: {X}",
                .{ packet.cmd_id, packet.body },
            );
            return;
        }

        return err;
    };
}

fn getPlayerToken(gpa: Allocator, client: *Client, packet: *const NetPacket) !u32 {
    const req = try proto.decode(pb.GetPlayerTokenReq, packet.body, gpa);
    defer req.pb.deinit(gpa);

    log.debug("received PlayerGetTokenReq: {}", .{req});

    const player_uid: u32 = 1337;
    try NetPacket.encode(&client.writer.interface, pb.GetPlayerTokenRsp{
        .retcode = .RetSucc,
        .uid = player_uid,
    });

    client.player_uid = 1337;
    try client.writer.interface.flush();

    return player_uid;
}
