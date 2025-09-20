const std = @import("std");

const fs = std.fs;
const posix = std.posix;
const Address = std.net.Address;
const Allocator = std.mem.Allocator;

pub const initial_xorpad = @embedFile("xorpad.bin");

address: Address,
socket: fs.File,
writer: fs.File.Writer,
reader: fs.File.Reader,
recv_buffer: [16384]u8 = undefined,
send_buffer: [16384]u8 = undefined,
player_uid: ?u32 = null,

pub fn create(gpa: Allocator, fd: posix.socket_t, address: Address) Allocator.Error!*@This() {
    const self = try gpa.create(@This());

    self.* = .{
        .address = address,
        .socket = .{ .handle = fd },
        .reader = self.socket.reader(&self.recv_buffer),
        .writer = self.socket.writer(&self.send_buffer),
    };

    return self;
}

pub fn destroy(self: *@This(), gpa: Allocator) void {
    self.socket.close();
    gpa.destroy(self);
}
