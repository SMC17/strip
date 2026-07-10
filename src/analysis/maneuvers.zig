//! Deterministic flight-test command generators.

const std = @import("std");

pub const Doublet = struct {
    start_s: f64,
    half_width_s: f64,
    amplitude: f64,

    pub fn sample(self: Doublet, time_s: f64) f64 {
        if (time_s < self.start_s or time_s >= self.start_s + 2.0 * self.half_width_s) return 0.0;
        return if (time_s < self.start_s + self.half_width_s) self.amplitude else -self.amplitude;
    }
};

pub const Step = struct {
    start_s: f64,
    initial: f64,
    final: f64,

    pub fn sample(self: Step, time_s: f64) f64 {
        return if (time_s < self.start_s) self.initial else self.final;
    }
};

/// Standard 3-2-1-1 sequence with alternating signs and one-unit rests.
pub const ThreeTwoOneOne = struct {
    start_s: f64,
    unit_s: f64,
    amplitude: f64,

    pub fn sample(self: ThreeTwoOneOne, time_s: f64) f64 {
        const elapsed = time_s - self.start_s;
        if (elapsed < 0.0) return 0.0;
        const segments = [_]struct { duration: f64, sign: f64 }{
            .{ .duration = 3.0, .sign = 1.0 },
            .{ .duration = 1.0, .sign = 0.0 },
            .{ .duration = 2.0, .sign = -1.0 },
            .{ .duration = 1.0, .sign = 0.0 },
            .{ .duration = 1.0, .sign = 1.0 },
            .{ .duration = 1.0, .sign = 0.0 },
            .{ .duration = 1.0, .sign = -1.0 },
        };
        var cursor: f64 = 0.0;
        for (segments) |segment| {
            const end = cursor + segment.duration * self.unit_s;
            if (elapsed < end) return self.amplitude * segment.sign;
            cursor = end;
        }
        return 0.0;
    }
};

test "maneuver generators honor timing and signs" {
    const doublet = Doublet{ .start_s = 1.0, .half_width_s = 0.5, .amplitude = 0.2 };
    try std.testing.expectEqual(@as(f64, 0.0), doublet.sample(0.9));
    try std.testing.expectEqual(@as(f64, 0.2), doublet.sample(1.2));
    try std.testing.expectEqual(@as(f64, -0.2), doublet.sample(1.7));
    const sequence = ThreeTwoOneOne{ .start_s = 0.0, .unit_s = 1.0, .amplitude = 1.0 };
    try std.testing.expectEqual(@as(f64, 1.0), sequence.sample(2.0));
    try std.testing.expectEqual(@as(f64, -1.0), sequence.sample(5.0));
    try std.testing.expectEqual(@as(f64, 0.0), sequence.sample(10.0));
}
