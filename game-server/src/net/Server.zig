const std = @import("std");
const Client = @import("Client.zig");

const posix = std.posix;
const Allocator = std.mem.Allocator;
const Address = std.net.Address;

const ClientMap = std.AutoHashMapUnmanaged(std.fs.File.Handle, *Client);

const tcp_backlog: u31 = 100;
const initial_polls_array_size: usize = 1024;

const log = std.log.scoped(.tcp);

listener: posix.socket_t,
polls: std.ArrayList(posix.pollfd),
clients: ClientMap,

pub fn init(gpa: Allocator, address: Address) !@This() {
    const listener = try posix.socket(address.any.family, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, posix.IPPROTO.TCP);
    errdefer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, tcp_backlog);

    var polls: std.ArrayList(posix.pollfd) = .empty;
    try polls.ensureTotalCapacity(gpa, initial_polls_array_size);

    polls.appendAssumeCapacity(.{
        .fd = listener,
        .revents = 0,
        .events = posix.POLL.IN,
    });

    return .{
        .listener = listener,
        .polls = polls,
        .clients = .empty,
    };
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    posix.close(self.listener);

    var clients = self.clients.valueIterator();
    while (clients.next()) |client| {
        client.*.destroy(gpa);
    }

    self.clients.deinit(gpa);
    self.polls.deinit(gpa);
}

pub const PollIterator = struct {
    pollfds: *const std.ArrayList(posix.pollfd),
    listener_fd: posix.socket_t,
    clients: *ClientMap,
    index: usize = 0,

    pub const Recv = struct {
        client: *Client,
        poll_index: usize,
    };

    pub const Event = union(enum) {
        accept: void,
        recv: Recv,
    };

    pub fn next(iter: *@This()) ?PollIterator.Event {
        while (iter.index < iter.pollfds.items.len) {
            const item = iter.pollfds.items[iter.index];
            iter.index += 1;

            if (item.revents == 0) continue;

            if (item.fd == iter.listener_fd) {
                return .{ .accept = {} };
            } else {
                const client = iter.clients.get(item.fd).?;
                return .{ .recv = .{
                    .client = client,
                    .poll_index = iter.index - 1,
                } };
            }
        }

        return null;
    }
};

pub fn poll(server: *@This()) posix.PollError!PollIterator {
    _ = try posix.poll(server.polls.items, -1);

    return .{
        .listener_fd = server.listener,
        .pollfds = &server.polls,
        .clients = &server.clients,
    };
}

pub fn onConnect(
    self: *@This(),
    gpa: Allocator,
) (Allocator.Error || posix.AcceptError)!void {
    var addr: Address = undefined;
    var addr_len: posix.socklen_t = @sizeOf(Address);

    const fd = try posix.accept(self.listener, &addr.any, &addr_len, posix.SOCK.NONBLOCK);

    try self.polls.append(gpa, .{
        .fd = fd,
        .revents = 0,
        .events = posix.POLL.IN,
    });

    const client = try Client.create(gpa, fd, addr);
    try self.clients.put(gpa, client.socket.handle, client);

    log.debug("new connection from {f}", .{addr});
}

pub fn onDisconnect(self: *@This(), gpa: Allocator, poll_index: usize, client: *Client) void {
    log.debug("client from {f} disconnected", .{client.address});

    _ = self.clients.remove(client.socket.handle);
    _ = self.polls.orderedRemove(poll_index);

    client.destroy(gpa);
}
