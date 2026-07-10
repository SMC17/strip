//! Content identities and bounded checkpoint/replay records.

const std = @import("std");

pub const ContentId = struct {
    bytes: [32]u8,

    pub fn hash(content: []const u8) ContentId {
        var bytes: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(content, &bytes, .{});
        return .{ .bytes = bytes };
    }

    pub fn eql(a: ContentId, b: ContentId) bool {
        return std.mem.eql(u8, &a.bytes, &b.bytes);
    }

    pub fn formatHex(self: ContentId, output: *[64]u8) []const u8 {
        const alphabet = "0123456789abcdef";
        for (self.bytes, 0..) |byte, index| {
            output[index * 2] = alphabet[byte >> 4];
            output[index * 2 + 1] = alphabet[byte & 0x0f];
        }
        return output;
    }
};

pub fn Checkpoint(comptime State: type) type {
    return struct {
        event_index: u64,
        simulation_nanoseconds: i64,
        state: State,
        state_identity: ContentId,

        pub fn init(
            event_index: u64,
            simulation_nanoseconds: i64,
            state: State,
            canonical_state_bytes: []const u8,
        ) @This() {
            return .{
                .event_index = event_index,
                .simulation_nanoseconds = simulation_nanoseconds,
                .state = state,
                .state_identity = .hash(canonical_state_bytes),
            };
        }

        pub fn validates(self: @This(), canonical_state_bytes: []const u8) bool {
            return self.state_identity.eql(.hash(canonical_state_bytes));
        }
    };
}

pub fn ReplayTrace(comptime Event: type, comptime capacity: usize) type {
    return struct {
        events: [capacity]Entry = undefined,
        len: usize = 0,

        const Self = @This();
        pub const Error = error{Full};
        pub const Entry = struct {
            sequence: u64,
            simulation_nanoseconds: i64,
            event: Event,
            identity: ContentId,
        };

        pub fn append(
            self: *Self,
            sequence: u64,
            simulation_nanoseconds: i64,
            event: Event,
            canonical_event_bytes: []const u8,
        ) Error!void {
            if (self.len == capacity) return error.Full;
            self.events[self.len] = .{
                .sequence = sequence,
                .simulation_nanoseconds = simulation_nanoseconds,
                .event = event,
                .identity = .hash(canonical_event_bytes),
            };
            self.len += 1;
        }

        pub fn slice(self: *const Self) []const Entry {
            return self.events[0..self.len];
        }

        pub fn replayFrom(self: *const Self, sequence: u64) []const Entry {
            var index: usize = 0;
            while (index < self.len and self.events[index].sequence < sequence) : (index += 1) {}
            return self.events[index..self.len];
        }

        pub fn isStrictlyOrdered(self: *const Self) bool {
            if (self.len < 2) return true;
            var index: usize = 1;
            while (index < self.len) : (index += 1) {
                const previous = self.events[index - 1];
                const current = self.events[index];
                if (current.simulation_nanoseconds < previous.simulation_nanoseconds) return false;
                if (current.simulation_nanoseconds == previous.simulation_nanoseconds and
                    current.sequence <= previous.sequence) return false;
            }
            return true;
        }
    };
}

test "SHA-256 content identity is stable" {
    const expected = [_]u8{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    try std.testing.expectEqualSlices(u8, &expected, &ContentId.hash("abc").bytes);
}

test "checkpoint validation and replay suffix" {
    const State = struct { position: i32 };
    const checkpoint = Checkpoint(State).init(2, 100, .{ .position = 7 }, "position=7");
    try std.testing.expect(checkpoint.validates("position=7"));
    try std.testing.expect(!checkpoint.validates("position=8"));

    var trace = ReplayTrace(u8, 3){};
    try trace.append(0, 10, 4, "4");
    try trace.append(1, 10, 5, "5");
    try trace.append(2, 20, 6, "6");
    try std.testing.expect(trace.isStrictlyOrdered());
    const suffix = trace.replayFrom(1);
    try std.testing.expectEqual(@as(usize, 2), suffix.len);
    try std.testing.expectEqual(@as(u8, 5), suffix[0].event);
    try std.testing.expectError(error.Full, trace.append(3, 30, 7, "7"));
}
