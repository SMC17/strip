//! Public UAS simulation surface.

pub const policy = @import("policy.zig");
pub const simulation = @import("simulation.zig");

pub const LinkState = policy.LinkState;
pub const Fault = policy.Fault;
pub const GeofenceState = policy.GeofenceState;
pub const Action = policy.Action;
pub const Snapshot = policy.Snapshot;
pub const Decision = policy.Decision;
pub const decide = policy.decide;

test {
    _ = policy;
    _ = simulation;
}
