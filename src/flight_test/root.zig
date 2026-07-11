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
pub const hil_bench = @import("hil_bench.zig");
pub const evidence = @import("evidence.zig");
pub const flight_seal = @import("flight_seal.zig");
pub const metadata = @import("metadata.zig");
pub const campaign = @import("campaign.zig");
pub const telemetry_csv = @import("telemetry_csv.zig");
pub const qualification = @import("qualification.zig");

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
    _ = hil_bench;
    _ = evidence;
    _ = flight_seal;
    _ = metadata;
    _ = campaign;
    _ = telemetry_csv;
    _ = qualification;
}
