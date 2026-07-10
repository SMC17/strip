//! Allocation-free MAVLink 1 compatible framing and X.25 checksum.
const std = @import("std");

pub const start_of_frame: u8 = 0xfe;
pub const max_payload_len: usize = 255;
pub const max_frame_len: usize = 6 + max_payload_len + 2;

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
    message_id: u8,
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

pub fn crcAccumulate(byte: u8, current: u16) u16 {
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
    const length: usize = 6 + @as(usize, message.payload_len) + 2;
    if (output.len < length) return error.BufferTooSmall;
    output[0] = start_of_frame;
    output[1] = message.payload_len;
    output[2] = message.header.sequence;
    output[3] = message.header.system_id;
    output[4] = message.header.component_id;
    output[5] = message.header.message_id;
    @memcpy(output[6 .. 6 + message.payload_len], message.payloadSlice());
    const crc = checksum(output[1 .. 6 + message.payload_len], crc_extra);
    output[6 + message.payload_len] = @truncate(crc);
    output[7 + message.payload_len] = @truncate(crc >> 8);
    return length;
}

pub fn decode(frame: []const u8, crc_extra: u8) Error!Message {
    if (frame.len < 8) return error.MalformedFrame;
    if (frame[0] != start_of_frame) return error.UnsupportedMagic;
    const payload_len: usize = frame[1];
    const expected_len = 6 + payload_len + 2;
    if (frame.len != expected_len) return error.MalformedFrame;
    const expected_crc = checksum(frame[1 .. 6 + payload_len], crc_extra);
    const actual_crc = @as(u16, frame[6 + payload_len]) |
        (@as(u16, frame[7 + payload_len]) << 8);
    if (actual_crc != expected_crc) return error.ChecksumMismatch;
    return Message.init(.{
        .sequence = frame[2],
        .system_id = frame[3],
        .component_id = frame[4],
        .message_id = frame[5],
    }, frame[6 .. 6 + payload_len]);
}

fn hexDigit(value: u8) u8 {
    return "0123456789abcdef"[value & 0xf];
}

fn writeHex(bytes: []const u8, output: []u8) Error![]const u8 {
    if (output.len < bytes.len * 2) return error.BufferTooSmall;
    for (bytes, 0..) |byte, index| {
        output[index * 2] = hexDigit(byte >> 4);
        output[index * 2 + 1] = hexDigit(byte);
    }
    return output[0 .. bytes.len * 2];
}

test "MAVLink-like frame matches checked-in golden vector" {
    const message = try Message.init(.{
        .sequence = 9,
        .system_id = 1,
        .component_id = 200,
        .message_id = 42,
    }, &.{ 1, 2, 3, 4 });
    var frame_buffer: [max_frame_len]u8 = undefined;
    const frame_len = try encode(&message, 77, &frame_buffer);
    var hex_buffer: [max_frame_len * 2]u8 = undefined;
    const actual_hex = try writeHex(frame_buffer[0..frame_len], &hex_buffer);
    try std.testing.expectEqualStrings("fe040901c82a01020304dd8f", actual_hex);

    const decoded = try decode(frame_buffer[0..frame_len], 77);
    try std.testing.expectEqual(message.header.message_id, decoded.header.message_id);
    try std.testing.expectEqualSlices(u8, message.payloadSlice(), decoded.payloadSlice());
}

test "MAVLink-like decoder rejects malformed and corrupt frames" {
    try std.testing.expectError(error.MalformedFrame, decode(&.{ start_of_frame, 0 }, 0));
    var corrupt = [_]u8{ start_of_frame, 1, 0, 1, 1, 2, 9, 0, 0 };
    try std.testing.expectError(error.ChecksumMismatch, decode(&corrupt, 5));
    corrupt[0] = 0xfd;
    try std.testing.expectError(error.UnsupportedMagic, decode(&corrupt, 5));
}
