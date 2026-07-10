//! Bounded UAS contingency policy; not an operational flight controller.

const std = @import("std");

pub const LinkState = enum { available, degraded, lost };
pub const Fault = enum { none, propulsion_degraded, navigation_unreliable };
pub const GeofenceState = enum { inside, predicted_breach, breached };
pub const Action = enum { continue_mission, reduce_speed, return_to_home, hold, land_at_designated_site };

pub const Snapshot = struct {
    link: LinkState,
    fault: Fault,
    geofence: GeofenceState,
    designated_site_available: bool,
};

pub const Decision = struct {
    action: Action,
    reason: Reason,

    pub const Reason = enum {
        nominal,
        degraded_link,
        link_lost,
        geofence_risk,
        geofence_breach,
        propulsion_fault,
        navigation_fault,
    };
};

/// Policy precedence is explicit so simultaneous faults replay identically.
pub fn decide(snapshot: Snapshot) Decision {
    if (snapshot.geofence == .breached) return .{
        .action = if (snapshot.designated_site_available) .land_at_designated_site else .hold,
        .reason = .geofence_breach,
    };
    if (snapshot.fault == .propulsion_degraded) return .{
        .action = if (snapshot.designated_site_available) .land_at_designated_site else .reduce_speed,
        .reason = .propulsion_fault,
    };
    if (snapshot.fault == .navigation_unreliable) return .{
        .action = .hold,
        .reason = .navigation_fault,
    };
    if (snapshot.geofence == .predicted_breach) return .{
        .action = .return_to_home,
        .reason = .geofence_risk,
    };
    return switch (snapshot.link) {
        .available => .{ .action = .continue_mission, .reason = .nominal },
        .degraded => .{ .action = .reduce_speed, .reason = .degraded_link },
        .lost => .{ .action = .return_to_home, .reason = .link_lost },
    };
}

test "breach takes precedence over simultaneous link loss and fault" {
    const decision = decide(.{
        .link = .lost,
        .fault = .navigation_unreliable,
        .geofence = .breached,
        .designated_site_available = true,
    });
    try std.testing.expectEqual(Action.land_at_designated_site, decision.action);
    try std.testing.expectEqual(Decision.Reason.geofence_breach, decision.reason);
}

test "link and predicted breach workflows select bounded responses" {
    try std.testing.expectEqual(
        Action.return_to_home,
        decide(.{
            .link = .available,
            .fault = .none,
            .geofence = .predicted_breach,
            .designated_site_available = false,
        }).action,
    );
    try std.testing.expectEqual(
        Action.reduce_speed,
        decide(.{
            .link = .degraded,
            .fault = .none,
            .geofence = .inside,
            .designated_site_available = false,
        }).action,
    );
}
