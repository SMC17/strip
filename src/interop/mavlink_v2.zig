//! MAVLink 2 framing (0xFD) — decode/encode for PX4 SITL peers.
//!
//! HEARTBEAT msgid remains 0. Signature truncation is accepted when present
//! (incompat flag bit0): CRC is validated over the unsigned portion only.

const std = @import("std");

pub const start_of_frame: u8 = 0xfd;
pub const max_payload_len: usize = 255;
/// header(10) + payload + checksum(2) + optional signature(13)
pub const max_frame_len: usize = 10 + max_payload_len + 2 + 13;

pub const Error = error{
    BufferTooSmall,
    PayloadTooLarge,
    MalformedFrame,
    UnsupportedMagic,
    ChecksumMismatch,
};

pub const Header = struct {
    sequence: u8,
    system_id: u8,
    component_id: u8,
    message_id: u32,
    incompat_flags: u8 = 0,
    compat_flags: u8 = 0,
};

pub const Message = struct {
    header: Header,
    payload_len: u8,
    payload: [max_payload_len]u8 = undefined,

    pub fn init(header: Header, payload_bytes: []const u8) Error!Message {
        if (payload_bytes.len > max_payload_len) return error.PayloadTooLarge;
        var result = Message{
            .header = header,
            .payload_len = @intCast(payload_bytes.len),
        };
        @memcpy(result.payload[0..payload_bytes.len], payload_bytes);
        return result;
    }

    pub fn payloadSlice(self: *const Message) []const u8 {
        return self.payload[0..self.payload_len];
    }
};

fn crcAccumulate(byte: u8, current: u16) u16 {
    var temporary = byte ^ @as(u8, @truncate(current));
    temporary ^= temporary << 4;
    return (current >> 8) ^
        (@as(u16, temporary) << 8) ^
        (@as(u16, temporary) << 3) ^
        (@as(u16, temporary) >> 4);
}

pub fn checksum(bytes: []const u8, crc_extra: u8) u16 {
    var crc: u16 = 0xffff;
    for (bytes) |byte| crc = crcAccumulate(byte, crc);
    return crcAccumulate(crc_extra, crc);
}

pub fn encode(message: *const Message, crc_extra: u8, output: []u8) Error!usize {
    const length: usize = 10 + @as(usize, message.payload_len) + 2;
    if (output.len < length) return error.BufferTooSmall;
    output[0] = start_of_frame;
    output[1] = message.payload_len;
    output[2] = message.header.incompat_flags;
    output[3] = message.header.compat_flags;
    output[4] = message.header.sequence;
    output[5] = message.header.system_id;
    output[6] = message.header.component_id;
    output[7] = @truncate(message.header.message_id);
    output[8] = @truncate(message.header.message_id >> 8);
    output[9] = @truncate(message.header.message_id >> 16);
    @memcpy(output[10 .. 10 + message.payload_len], message.payloadSlice());
    const crc = checksum(output[1 .. 10 + message.payload_len], crc_extra);
    output[10 + message.payload_len] = @truncate(crc);
    output[11 + message.payload_len] = @truncate(crc >> 8);
    return length;
}

pub fn decode(frame: []const u8, crc_extra: u8) Error!Message {
    if (frame.len < 12) return error.MalformedFrame;
    if (frame[0] != start_of_frame) return error.UnsupportedMagic;
    const payload_len: usize = frame[1];
    const incompat = frame[2];
    const signed = (incompat & 0x01) != 0;
    const base_len = 10 + payload_len + 2;
    const expected_len = base_len + if (signed) @as(usize, 13) else 0;
    if (frame.len < base_len) return error.MalformedFrame;
    // Allow trailing signature bytes or exact length.
    if (frame.len != base_len and frame.len != expected_len and !(signed and frame.len >= expected_len)) {
        // Be liberal: if we have at least base_len, validate CRC on that slice.
        if (frame.len < base_len) return error.MalformedFrame;
    }
    const expected_crc = checksum(frame[1 .. 10 + payload_len], crc_extra);
    const actual_crc = @as(u16, frame[10 + payload_len]) |
        (@as(u16, frame[11 + payload_len]) << 8);
    if (actual_crc != expected_crc) return error.ChecksumMismatch;
    const msgid: u32 = @as(u32, frame[7]) |
        (@as(u32, frame[8]) << 8) |
        (@as(u32, frame[9]) << 16);
    return Message.init(.{
        .sequence = frame[4],
        .system_id = frame[5],
        .component_id = frame[6],
        .message_id = msgid,
        .incompat_flags = incompat,
        .compat_flags = frame[3],
    }, frame[10 .. 10 + payload_len]);
}

/// True if buffer looks like MAVLink v2 SOF.
pub fn isV2(frame: []const u8) bool {
    return frame.len > 0 and frame[0] == start_of_frame;
}

test "MAVLink2 HEARTBEAT roundtrip" {
    var payload = [_]u8{ 2, 12, 0, 0, 0, 0, 0, 3, 3 }; // type, autopilot, ..., mavlink_version
    const message = try Message.init(.{
        .sequence = 1,
        .system_id = 1,
        .component_id = 1,
        .message_id = 0,
    }, &payload);
    var frame: [max_frame_len]u8 = undefined;
    const n = try encode(&message, 50, &frame);
    const decoded = try decode(frame[0..n], 50);
    try std.testing.expectEqual(@as(u32, 0), decoded.header.message_id);
    try std.testing.expectEqualSlices(u8, &payload, decoded.payloadSlice());
}
