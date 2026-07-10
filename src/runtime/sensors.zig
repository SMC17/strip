//! Bounded sensor transport with explicit source and delivery timing.
const std = @import("std");

pub const OverflowPolicy = enum { reject_newest, drop_oldest };

pub fn Sample(comptime T: type) type {
    return struct {
        value: T,
        source_tick: u64,
        capture_timestamp_ns: i64,
        delivery_timestamp_ns: i64,
        latency_ns: u64,
        dropout: bool,
    };
}

pub fn SensorQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        items: [capacity]Sample(T) = undefined,
        head: usize = 0,
        len: usize = 0,
        dropped: u64 = 0,
        policy: OverflowPolicy,

        const Self = @This();
        pub const Error = error{ QueueFull, InvalidTimestamp };

        pub fn init(policy: OverflowPolicy) Self {
            return .{ .policy = policy };
        }

        pub fn push(
            self: *Self,
            value: T,
            source_tick: u64,
            capture_timestamp_ns: i64,
            delivery_timestamp_ns: i64,
            dropout: bool,
        ) Error!void {
            if (delivery_timestamp_ns < capture_timestamp_ns) return error.InvalidTimestamp;
            const latency: u64 = @intCast(delivery_timestamp_ns - capture_timestamp_ns);
            if (self.len == capacity) {
                self.dropped += 1;
                if (self.policy == .reject_newest) return error.QueueFull;
                self.head = (self.head + 1) % capacity;
                self.len -= 1;
            }
            const tail = (self.head + self.len) % capacity;
            self.items[tail] = .{
                .value = value,
                .source_tick = source_tick,
                .capture_timestamp_ns = capture_timestamp_ns,
                .delivery_timestamp_ns = delivery_timestamp_ns,
                .latency_ns = latency,
                .dropout = dropout,
            };
            self.len += 1;
        }

        pub fn popReady(self: *Self, now_ns: i64) ?Sample(T) {
            if (self.len == 0) return null;
            const sample = self.items[self.head];
            if (sample.delivery_timestamp_ns > now_ns) return null;
            self.head = (self.head + 1) % capacity;
            self.len -= 1;
            return sample;
        }
    };
}

test "sensor samples preserve source tick latency dropout and bounded policy" {
    var queue = SensorQueue(f32, 2).init(.drop_oldest);
    try queue.push(1, 10, 100, 125, false);
    try queue.push(2, 11, 110, 150, true);
    try queue.push(3, 12, 120, 170, false);
    try std.testing.expectEqual(@as(u64, 1), queue.dropped);
    const sample = queue.popReady(160).?;
    try std.testing.expectEqual(@as(u64, 11), sample.source_tick);
    try std.testing.expectEqual(@as(u64, 40), sample.latency_ns);
    try std.testing.expect(sample.dropout);
    try std.testing.expect(queue.popReady(160) == null);
}
