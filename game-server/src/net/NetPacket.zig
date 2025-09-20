const std = @import("std");
const proto = @import("proto");

const fs = std.fs;
const Io = std.Io;

const overhead_size: usize = 16;
const head_magic: [4]u8 = .{ 0x75, 0xCC, 0xB4, 0xFB };
const tail_magic: [4]u8 = .{ 0x4B, 0xBD, 0x7F, 0xD7 };

reader: *Io.Reader,
cmd_id: u16,
head: []const u8,
body: []const u8,

pub fn decode(reader: *Io.Reader) error{ Incomplete, Corrupted }!@This() {
    if (reader.bufferedLen() < overhead_size) return error.Incomplete;

    const header = reader.peekArray(overhead_size) catch unreachable;
    if (!std.mem.eql(u8, header[0..4], &head_magic)) return error.Corrupted;

    const head_size: usize = @intCast(std.mem.readInt(u16, header[6..8], .big));
    const body_size: usize = @intCast(std.mem.readInt(u32, header[8..12], .big));

    if (reader.bufferedLen() < overhead_size + head_size + body_size) return error.Incomplete;

    const buffer = reader.peek(overhead_size + head_size + body_size) catch unreachable;

    const tail_offset = 12 + head_size + body_size;
    if (!std.mem.eql(u8, buffer[tail_offset .. tail_offset + 4], &tail_magic)) return error.Corrupted;

    return .{
        .reader = reader,
        .cmd_id = std.mem.readInt(u16, buffer[4..6], .big),
        .head = buffer[12 .. 12 + head_size],
        .body = buffer[12 + head_size .. 12 + head_size + body_size],
    };
}

pub fn encode(writer: *Io.Writer, body: anytype) Io.Writer.Error!void {
    try writer.writeAll(&head_magic);
    try writer.writeInt(u16, body.pb.getCmdId(), .big);
    try writer.writeInt(u16, 0, .big); // head length
    try writer.writeInt(u32, @truncate(body.pb.encodingLength()), .big);
    try body.pb.encode(writer);
    try writer.writeAll(&tail_magic);
}

pub fn deinit(packet: @This()) void {
    packet.reader.toss(overhead_size + packet.head.len + packet.body.len);
}
