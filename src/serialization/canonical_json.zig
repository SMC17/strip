//! Deterministic JSON primitives for schema-controlled records.
//!
//! Object keys are required in strictly increasing UTF-8 byte order. This is a
//! small, allocation-free canonical subset, not a claim of full RFC 8785/JCS
//! compatibility (whose key ordering is UTF-16 based).

const std = @import("std");

pub const Error = error{
    InvalidUtf8,
    NonFiniteNumber,
    NonCanonicalOrder,
};

pub fn writeString(writer: *std.Io.Writer, value: []const u8) (std.Io.Writer.Error || Error)!void {
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;

    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        0x08 => try writer.writeAll("\\b"),
        0x0c => try writer.writeAll("\\f"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0x00...0x07, 0x0b, 0x0e...0x1f => {
            const alphabet = "0123456789abcdef";
            try writer.writeAll(&.{
                '\\',                'u',                   '0', '0',
                alphabet[byte >> 4], alphabet[byte & 0x0f],
            });
        },
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

pub fn writeNumber(writer: *std.Io.Writer, value: f64) (std.Io.Writer.Error || Error)!void {
    if (!std.math.isFinite(value)) return error.NonFiniteNumber;
    if (value == 0.0) {
        try writer.writeByte('0');
        return;
    }
    try writer.print("{d}", .{value});
}

pub const Object = struct {
    writer: *std.Io.Writer,
    previous_key: ?[]const u8 = null,
    member_count: usize = 0,

    pub fn begin(writer: *std.Io.Writer) std.Io.Writer.Error!Object {
        try writer.writeByte('{');
        return .{ .writer = writer };
    }

    pub fn key(self: *Object, value: []const u8) (std.Io.Writer.Error || Error)!void {
        if (self.previous_key) |previous| {
            if (std.mem.order(u8, previous, value) != .lt)
                return error.NonCanonicalOrder;
        }
        if (self.member_count != 0) try self.writer.writeByte(',');
        try writeString(self.writer, value);
        try self.writer.writeByte(':');
        self.previous_key = value;
        self.member_count += 1;
    }

    pub fn end(self: *Object) std.Io.Writer.Error!void {
        try self.writer.writeByte('}');
    }
};

test "canonical object escapes strings and normalizes negative zero" {
    var storage: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&storage);
    var object = try Object.begin(&writer);
    try object.key("a");
    try writeString(&writer, "line\n");
    try object.key("z");
    try writeNumber(&writer, -0.0);
    try object.end();
    try std.testing.expectEqualStrings("{\"a\":\"line\\n\",\"z\":0}", writer.buffered());
}

test "canonical object rejects unordered and duplicate keys" {
    var storage: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&storage);
    var object = try Object.begin(&writer);
    try object.key("z");
    try std.testing.expectError(error.NonCanonicalOrder, object.key("a"));
}
