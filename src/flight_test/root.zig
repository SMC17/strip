//! Bounded flight-test analytics and evidence contracts.
//! Unit-tested software is not flight, HIL, certification, or operational evidence.

pub const telemetry = @import("telemetry.zig");
pub const clock = @import("clock.zig");
pub const calibration = @import("calibration.zig");
pub const kinematics = @import("kinematics.zig");
pub const regression = @import("regression.zig");
pub const residuals = @import("residuals.zig");
pub const envelope = @import("envelope.zig");
pub const maneuvers = @import("maneuvers.zig");
pub const cards = @import("cards.zig");
pub const hil = @import("hil.zig");
pub const evidence = @import("evidence.zig");
pub const metadata = @import("metadata.zig");

test {
    _ = telemetry;
    _ = clock;
    _ = calibration;
    _ = kinematics;
    _ = regression;
    _ = residuals;
    _ = envelope;
    _ = maneuvers;
    _ = cards;
    _ = hil;
    _ = evidence;
    _ = metadata;
}
