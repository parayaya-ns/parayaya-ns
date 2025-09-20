const std = @import("std");
const fs = std.fs;
const posix = std.posix;

const Allocator = std.mem.Allocator;
const Address = std.net.Address;
const Request = std.http.Server.Request;
const ClientMap = std.AutoHashMapUnmanaged(posix.socket_t, *Client);

const log = std.log.scoped(.http);
pub const RequestHandler = struct { [:0]const u8, type };

fn PathEnum(comptime handlers: []const RequestHandler) type {
    var fields: []const std.builtin.Type.EnumField = &.{};

    for (handlers, 0..) |handler, i| {
        const path, _ = handler;

        fields = fields ++ .{std.builtin.Type.EnumField{
            .name = path,
            .value = i,
        }};
    }

    return @Type(.{ .@"enum" = .{
        .decls = &.{},
        .fields = fields,
        .is_exhaustive = true,
        .tag_type = u32,
    } });
}

pub fn serve(
    gpa: Allocator,
    bind_addr: []const u8,
    bind_port: u16,
    user_data: anytype,
    comptime request_handlers: []const RequestHandler,
) !void {
    const address = std.net.Address.parseIp4(bind_addr, bind_port) catch return error.InvalidBindAddress;

    var server = try Server.init(gpa, address);
    defer server.deinit(gpa);

    log.info("server is listening at {f}", .{address});

    while (true) {
        _ = try posix.poll(server.polls.items, -1);

        var i: usize = 0;
        while (i < server.polls.items.len) : (i += 1) {
            const poll = server.polls.items[i];
            if (poll.revents == 0) continue;

            if (poll.fd == server.listener) {
                var addr: Address = undefined;
                var addr_len: posix.socklen_t = @sizeOf(Address);

                const fd = try posix.accept(server.listener, &addr.any, &addr_len, posix.SOCK.NONBLOCK);
                try server.onConnect(gpa, fd, addr);

                log.debug("new connection from {f}", .{addr});
            } else {
                const client = server.clients.get(poll.fd).?;
                const status = client.onReceive(gpa, user_data, request_handlers);

                if (status == .disconnected) {
                    log.debug("client from {f} disconnected", .{client.address});

                    server.destroyClient(gpa, poll.fd, i);
                    i -= 1;
                }
            }
        }
    }
}

const Client = struct {
    address: Address,
    stream: fs.File,
    recv_buffer: [4096]u8 = undefined,
    reader: fs.File.Reader,
    writer: fs.File.Writer,
    http_state: std.http.Server,

    pub const Status = enum {
        connected,
        disconnected,
    };

    pub fn create(gpa: Allocator, fd: posix.socket_t, address: Address) Allocator.Error!*@This() {
        const self = try gpa.create(@This());
        const stream: fs.File = .{ .handle = fd };

        self.address = address;
        self.stream = stream;
        self.reader = self.stream.reader(&self.recv_buffer);
        self.writer = self.stream.writer(&.{});

        self.http_state = .init(&self.reader.interface, &self.writer.interface);
        return self;
    }

    pub fn onReceive(
        self: *@This(),
        gpa: Allocator,
        user_data: anytype,
        comptime request_handlers: []const RequestHandler,
    ) Status {
        const Path = PathEnum(request_handlers);

        var request = self.http_state.receiveHead() catch |err| {
            return if (err != error.ReadFailed or self.reader.err.? != error.WouldBlock) .disconnected else .connected;
        };

        log.debug("Received HTTP request, method: {}, target: {s}", .{
            request.head.method,
            request.head.target,
        });

        if (request.head.method != .GET) {
            log.debug("Unsupported method: {} from {f} to {s}", .{
                request.head.method,
                self.address,
                request.head.target,
            });

            return .disconnected;
        }

        var iter = std.mem.splitScalar(u8, request.head.target, '?');
        const path = iter.next() orelse return .disconnected;
        const query = iter.next() orelse "";

        if (std.meta.stringToEnum(Path, path)) |p| {
            switch (p) {
                inline else => |path_variant| {
                    inline for (request_handlers) |handler| {
                        const declared_path, const namespace = handler;

                        if (comptime std.mem.eql(u8, @tagName(path_variant), declared_path)) {
                            namespace.process(gpa, user_data, &request, query) catch return .disconnected;
                            return .connected;
                        }
                    }

                    @compileError("Missing handler for declared path: " ++ @tagName(p));
                },
            }
        } else {
            log.debug("unhandled request: {s}", .{path});
        }

        return .connected;
    }

    pub fn destroy(self: *@This(), gpa: Allocator) void {
        self.stream.close();
        gpa.destroy(self);
    }
};

const Server = struct {
    const tcp_backlog: u31 = 100;
    const initial_polls_array_size: usize = 1024;

    listener: posix.socket_t,
    polls: std.ArrayList(posix.pollfd),
    clients: ClientMap,

    fn init(gpa: Allocator, address: Address) !@This() {
        const listener = try posix.socket(address.any.family, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, posix.IPPROTO.TCP);
        errdefer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, tcp_backlog);

        var polls: std.ArrayList(posix.pollfd) = .empty;
        try polls.ensureTotalCapacity(gpa, initial_polls_array_size);
        errdefer polls.deinit(gpa);

        try polls.append(gpa, .{
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

    fn deinit(self: *@This(), gpa: Allocator) void {
        var clients = self.clients.valueIterator();
        while (clients.next()) |ptr| {
            ptr.*.destroy(gpa);
        }

        posix.close(self.listener);

        self.clients.deinit(gpa);
        self.polls.deinit(gpa);
    }

    fn onConnect(self: *@This(), gpa: Allocator, fd: posix.socket_t, addr: Address) Allocator.Error!void {
        try self.polls.append(gpa, .{
            .fd = fd,
            .revents = 0,
            .events = posix.POLL.IN,
        });

        try self.clients.put(gpa, fd, try .create(gpa, fd, addr));
    }

    fn destroyClient(self: *@This(), gpa: Allocator, fd: posix.socket_t, index: usize) void {
        if (self.clients.fetchRemove(fd)) |entry| entry.value.destroy(gpa);
        _ = self.polls.orderedRemove(index);
    }
};
