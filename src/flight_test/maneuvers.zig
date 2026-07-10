//! Declarative, bounded flight-test maneuvers; definitions are not operational approval.
const std = @import("std");

pub const VehicleClass = enum { fixed_wing, multirotor };
pub const Axis = enum { longitudinal, lateral, directional, roll, pitch, yaw, vertical };

pub const Kind = enum {
    doublet,
    three_two_one_one,
    chirp,
    hover,
    axis_step,
};

pub const Maneuver = struct {
    id: []const u8,
    vehicle: VehicleClass,
    kind: Kind,
    axis: Axis,
    start_s: f64,
    duration_s: f64,
    amplitude: f64,
    initial_frequency_hz: f64 = 0.0,
    final_frequency_hz: f64 = 0.0,

    pub fn validate(self: Maneuver) !void {
        if (self.id.len == 0 or self.id.len > 64) return error.InvalidManeuverId;
        inline for (.{ self.start_s, self.duration_s, self.amplitude }) |value|
            if (!std.math.isFinite(value)) return error.NonFiniteManeuver;
        if (self.start_s < 0.0 or self.duration_s <= 0.0) return error.InvalidTiming;
        switch (self.kind) {
            .doublet, .three_two_one_one, .chirp => {
                if (self.vehicle != .fixed_wing) return error.VehicleManeuverMismatch;
            },
            .hover, .axis_step => {
                if (self.vehicle != .multirotor) return error.VehicleManeuverMismatch;
            },
        }
        if (self.kind == .chirp) {
            if (!std.math.isFinite(self.initial_frequency_hz) or
                !std.math.isFinite(self.final_frequency_hz) or
                self.initial_frequency_hz <= 0.0 or
                self.final_frequency_hz < self.initial_frequency_hz)
                return error.InvalidFrequencySweep;
        }
        if (self.kind == .hover and self.axis != .vertical)
            return error.HoverRequiresVerticalAxis;
    }

    pub fn sample(self: Maneuver, time_s: f64) !f64 {
        try self.validate();
        if (!std.math.isFinite(time_s)) return error.NonFiniteTime;
        const elapsed = time_s - self.start_s;
        if (elapsed < 0.0 or elapsed >= self.duration_s) return 0.0;
        return switch (self.kind) {
            .doublet => if (elapsed < self.duration_s / 2.0)
                self.amplitude
            else
                -self.amplitude,
            .three_two_one_one => blk: {
                const unit = self.duration_s / 10.0;
                if (elapsed < 3.0 * unit) break :blk self.amplitude;
                if (elapsed < 4.0 * unit) break :blk 0.0;
                if (elapsed < 6.0 * unit) break :blk -self.amplitude;
                if (elapsed < 7.0 * unit) break :blk 0.0;
                if (elapsed < 8.0 * unit) break :blk self.amplitude;
                if (elapsed < 9.0 * unit) break :blk 0.0;
                break :blk -self.amplitude;
            },
            .chirp => blk: {
                const sweep_rate =
                    (self.final_frequency_hz - self.initial_frequency_hz) / self.duration_s;
                const phase = 2.0 * std.math.pi *
                    (self.initial_frequency_hz * elapsed + 0.5 * sweep_rate * elapsed * elapsed);
                break :blk self.amplitude * @sin(phase);
            },
            .hover => self.amplitude,
            .axis_step => self.amplitude,
        };
    }
};

pub fn fixedWingDoublet(id: []const u8, axis: Axis, start_s: f64, duration_s: f64, amplitude: f64) Maneuver {
    return .{ .id = id, .vehicle = .fixed_wing, .kind = .doublet, .axis = axis, .start_s = start_s, .duration_s = duration_s, .amplitude = amplitude };
}

pub fn fixedWingThreeTwoOneOne(id: []const u8, axis: Axis, start_s: f64, unit_s: f64, amplitude: f64) Maneuver {
    return .{ .id = id, .vehicle = .fixed_wing, .kind = .three_two_one_one, .axis = axis, .start_s = start_s, .duration_s = 10.0 * unit_s, .amplitude = amplitude };
}

pub fn fixedWingChirp(id: []const u8, axis: Axis, start_s: f64, duration_s: f64, amplitude: f64, start_hz: f64, end_hz: f64) Maneuver {
    return .{ .id = id, .vehicle = .fixed_wing, .kind = .chirp, .axis = axis, .start_s = start_s, .duration_s = duration_s, .amplitude = amplitude, .initial_frequency_hz = start_hz, .final_frequency_hz = end_hz };
}

pub fn multirotorHover(id: []const u8, start_s: f64, duration_s: f64, collective: f64) Maneuver {
    return .{ .id = id, .vehicle = .multirotor, .kind = .hover, .axis = .vertical, .start_s = start_s, .duration_s = duration_s, .amplitude = collective };
}

pub fn multirotorAxisStep(id: []const u8, axis: Axis, start_s: f64, duration_s: f64, amplitude: f64) Maneuver {
    return .{ .id = id, .vehicle = .multirotor, .kind = .axis_step, .axis = axis, .start_s = start_s, .duration_s = duration_s, .amplitude = amplitude };
}

test "fixed-wing and multirotor maneuver definitions are deterministic" {
    const doublet = fixedWingDoublet("fw-pitch-doublet", .longitudinal, 1.0, 2.0, 0.2);
    try std.testing.expectEqual(@as(f64, 0.2), try doublet.sample(1.5));
    try std.testing.expectEqual(@as(f64, -0.2), try doublet.sample(2.5));
    const sequence = fixedWingThreeTwoOneOne("fw-3211", .directional, 0.0, 1.0, 1.0);
    try std.testing.expectEqual(@as(f64, -1.0), try sequence.sample(5.0));
    const hover = multirotorHover("mr-hover", 0.0, 5.0, 0.5);
    try std.testing.expectEqual(@as(f64, 0.5), try hover.sample(2.0));
    const step = multirotorAxisStep("mr-roll-step", .roll, 0.0, 1.0, 0.1);
    try step.validate();
}
