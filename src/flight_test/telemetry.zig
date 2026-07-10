//! Bounded telemetry records. Missing values remain explicit and never become zero.
const std = @import("std");

pub const Quality = enum {
    valid,
    degraded,
    invalid,
    missing,
};

pub const ClockDomain = enum {
    monotonic,
    utc,
    gnss,
};

pub const Sample = struct {
    sequence: u64,
    time_ns: i128,
    clock: ClockDomain,
    value: ?f64,
    standard_uncertainty: ?f64,
    quality: Quality,

    pub fn validate(self: Sample) !void {
        if (self.quality == .missing) {
            if (self.value != null) return error.MissingSampleHasValue;
        } else {
            const value = self.value orelse return error.PresentSampleHasNoValue;
            if (!std.math.isFinite(value)) return error.NonFiniteValue;
        }
        if (self.standard_uncertainty) |uncertainty| {
            if (!std.math.isFinite(uncertainty) or uncertainty <= 0.0)
                return error.InvalidUncertainty;
        } else if (self.quality == .valid) {
            return error.ValidSampleNeedsUncertainty;
        }
        if (self.quality == .invalid and self.value == null)
            return error.InvalidSampleNeedsObservedValue;
    }

    pub fn usable(self: Sample) bool {
        return self.quality == .valid or self.quality == .degraded;
    }
};

pub const Channel = struct {
    id: []const u8,
    unit: []const u8,
    samples: []const Sample,

    pub fn validate(self: Channel) !void {
        if (self.id.len == 0 or self.id.len > 64) return error.InvalidChannelId;
        if (self.unit.len == 0 or self.unit.len > 24) return error.InvalidUnit;
        if (self.samples.len == 0 or self.samples.len > 1_000_000)
            return error.InvalidSampleCount;
        for (self.samples, 0..) |sample, index| {
            try sample.validate();
            if (index > 0 and sample.sequence <= self.samples[index - 1].sequence)
                return error.NonMonotonicSequence;
        }
    }
};

test "telemetry distinguishes missing invalid and usable samples" {
    const samples = [_]Sample{
        .{ .sequence = 1, .time_ns = 10, .clock = .monotonic, .value = 2.0, .standard_uncertainty = 0.1, .quality = .valid },
        .{ .sequence = 2, .time_ns = 20, .clock = .monotonic, .value = null, .standard_uncertainty = null, .quality = .missing },
        .{ .sequence = 3, .time_ns = 30, .clock = .monotonic, .value = 90.0, .standard_uncertainty = null, .quality = .invalid },
    };
    const channel: Channel = .{ .id = "body_ax", .unit = "m/s2", .samples = &samples };
    try channel.validate();
    try std.testing.expect(samples[0].usable());
    try std.testing.expect(!samples[1].usable());
    try std.testing.expect(!samples[2].usable());
}
