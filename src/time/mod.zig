//! Integer simulation time, monotonic clocks, and stable event keys.

const std = @import("std");

pub const Duration = struct {
    nanoseconds: i64,

    pub const Error = error{Overflow};

    pub fn fromNanoseconds(value: i64) Duration {
        return .{ .nanoseconds = value };
    }

    pub fn fromSeconds(value: f64) error{ NonFinite, OutOfRange }!Duration {
        if (!std.math.isFinite(value)) return error.NonFinite;
        const scaled = value * std.time.ns_per_s;
        if (scaled > @as(f64, @floatFromInt(std.math.maxInt(i64))) or
            scaled < @as(f64, @floatFromInt(std.math.minInt(i64)))) return error.OutOfRange;
        return .{ .nanoseconds = @intFromFloat(@round(scaled)) };
    }

    pub fn add(a: Duration, b: Duration) Error!Duration {
        return .{ .nanoseconds = try std.math.add(i64, a.nanoseconds, b.nanoseconds) };
    }

    pub fn sub(a: Duration, b: Duration) Error!Duration {
        return .{ .nanoseconds = try std.math.sub(i64, a.nanoseconds, b.nanoseconds) };
    }
};

pub const Instant = struct {
    nanoseconds: i64,

    pub fn add(self: Instant, duration: Duration) Duration.Error!Instant {
        return .{ .nanoseconds = try std.math.add(i64, self.nanoseconds, duration.nanoseconds) };
    }

    pub fn since(self: Instant, earlier: Instant) Duration.Error!Duration {
        return .{ .nanoseconds = try std.math.sub(i64, self.nanoseconds, earlier.nanoseconds) };
    }
};

pub const SimulationClock = struct {
    now: Instant = .{ .nanoseconds = 0 },

    pub const Error = Duration.Error || error{NegativeStep};

    pub fn advance(self: *SimulationClock, step: Duration) Error!Instant {
        if (step.nanoseconds < 0) return error.NegativeStep;
        self.now = try self.now.add(step);
        return self.now;
    }
};

/// A total-order key. Sequence is assigned monotonically at scheduling time,
/// making equal-time event order stable and independent of sorting algorithm.
pub const EventKey = struct {
    at: Instant,
    sequence: u64,

    pub fn lessThan(_: void, lhs: EventKey, rhs: EventKey) bool {
        if (lhs.at.nanoseconds != rhs.at.nanoseconds)
            return lhs.at.nanoseconds < rhs.at.nanoseconds;
        return lhs.sequence < rhs.sequence;
    }
};

pub const EventSequencer = struct {
    next_sequence: u64 = 0,

    pub fn key(self: *EventSequencer, at: Instant) error{SequenceExhausted}!EventKey {
        if (self.next_sequence == std.math.maxInt(u64)) return error.SequenceExhausted;
        const result = EventKey{ .at = at, .sequence = self.next_sequence };
        self.next_sequence += 1;
        return result;
    }
};

test "clock is monotonic and durations are exact" {
    var clock = SimulationClock{};
    _ = try clock.advance(.fromNanoseconds(20));
    _ = try clock.advance(.fromNanoseconds(22));
    try std.testing.expectEqual(@as(i64, 42), clock.now.nanoseconds);
    try std.testing.expectError(error.NegativeStep, clock.advance(.fromNanoseconds(-1)));
}

test "event keys preserve insertion order at equal times" {
    var sequencer = EventSequencer{};
    const at = Instant{ .nanoseconds = 100 };
    const first = try sequencer.key(at);
    const second = try sequencer.key(at);
    try std.testing.expect(EventKey.lessThan({}, first, second));
    try std.testing.expect(!EventKey.lessThan({}, second, first));
}
