//! Simplex-style runtime-assurance switching contract.
const std = @import("std");

pub const Controller = enum { mission, recovery };
pub const MonitorInput = struct {
    safety_margin: f64,
    minimum_margin: f64,
    state_fresh: bool,
};

pub const Selection = struct {
    controller: Controller,
    reason: Reason,

    pub const Reason = enum { within_envelope, margin_violation, stale_state, invalid_margin };
};

pub fn select(input: MonitorInput) Selection {
    if (!std.math.isFinite(input.safety_margin) or !std.math.isFinite(input.minimum_margin))
        return .{ .controller = .recovery, .reason = .invalid_margin };
    if (!input.state_fresh) return .{ .controller = .recovery, .reason = .stale_state };
    if (input.safety_margin < input.minimum_margin)
        return .{ .controller = .recovery, .reason = .margin_violation };
    return .{ .controller = .mission, .reason = .within_envelope };
}

test "monitor fails over on stale or invalid state" {
    try std.testing.expectEqual(Controller.recovery, select(.{
        .safety_margin = 2,
        .minimum_margin = 1,
        .state_fresh = false,
    }).controller);
    try std.testing.expectEqual(Selection.Reason.invalid_margin, select(.{
        .safety_margin = std.math.nan(f64),
        .minimum_margin = 1,
        .state_fresh = true,
    }).reason);
}
