//! Reproducible design-candidate and constraint contracts.
const std = @import("std");

pub const Candidate = struct {
    id: u64,
    parent_id: ?u64,
    parameters_digest: [32]u8,
    objective: ?f64 = null,
    feasible: ?bool = null,
};

pub const ConstraintResult = struct {
    name: []const u8,
    margin: f64,

    pub fn satisfied(self: ConstraintResult) bool {
        return std.math.isFinite(self.margin) and self.margin >= 0;
    }
};

pub fn allSatisfied(results: []const ConstraintResult) bool {
    for (results) |result| if (!result.satisfied()) return false;
    return true;
}

test "non-finite and negative margins are not feasible" {
    try std.testing.expect(!allSatisfied(&.{
        .{ .name = "mass", .margin = 0.1 },
        .{ .name = "range", .margin = std.math.nan(f64) },
    }));
    try std.testing.expect(!allSatisfied(&.{.{ .name = "energy", .margin = -0.01 }}));
}
