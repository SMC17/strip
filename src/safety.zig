//! Public intended-use policy. This is an API guardrail, not a certification claim.

const std = @import("std");

pub const PolicyError = error{ProhibitedIntendedUse};

pub fn isPubliclyPermitted(intended_use: anytype) bool {
    const name = @tagName(intended_use);
    return std.mem.eql(u8, name, "education") or
        std.mem.eql(u8, name, "research") or
        std.mem.eql(u8, name, "preliminary_design") or
        std.mem.eql(u8, name, "simulation_training");
}

pub fn enforcePublicIntendedUse(intended_use: anytype) PolicyError!void {
    if (!isPubliclyPermitted(intended_use)) return error.ProhibitedIntendedUse;
}

pub const public_policy =
    "Public APIs permit education, research, preliminary design, and simulation " ++
    "training only; operational, certification, accreditation, weapon, and " ++
    "targeting uses are rejected.";

test "public policy rejects every prohibited use class" {
    const Use = enum {
        education,
        operational,
        certification,
        accreditation,
        weapon,
        targeting,
    };
    try enforcePublicIntendedUse(Use.education);
    inline for (.{ Use.operational, Use.certification, Use.accreditation, Use.weapon, Use.targeting }) |use| {
        try std.testing.expectError(error.ProhibitedIntendedUse, enforcePublicIntendedUse(use));
    }
}
