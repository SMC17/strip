//! Model credibility passport issuer.

const std = @import("std");
const evidence = @import("../evidence.zig");
const result = @import("../result.zig");

pub const Passport = struct {
    schema: []const u8 = "strip.model-passport.v0",
    model_id: []const u8,
    version: []const u8,
    digest: []const u8,
    intended_uses: []const evidence.IntendedUse,
    prohibited_uses: []const []const u8,
    validity_envelope: evidence.ValidityEnvelope,
    credibility: result.CredibilityVector,
    operational_qualification_claimed: bool = false,
};

pub fn issueFromManifest(
    model: evidence.ModelManifest,
    digest: []const u8,
    intended_uses: []const evidence.IntendedUse,
    prohibited_uses: []const []const u8,
) Passport {
    return .{
        .model_id = model.id,
        .version = model.version,
        .digest = digest,
        .intended_uses = intended_uses,
        .prohibited_uses = prohibited_uses,
        .validity_envelope = model.effectiveEnvelope(model.valid_unit),
        .credibility = .fromProof(model.effectiveProof()),
        .operational_qualification_claimed = false,
    };
}

pub fn formatJson(allocator: std.mem.Allocator, passport: Passport) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    const head = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"{s}\",\"model_id\":\"{s}\",\"version\":\"{s}\",\"digest\":\"{s}\",\"intended_uses\":[",
        .{ passport.schema, passport.model_id, passport.version, passport.digest },
    );
    defer allocator.free(head);
    try list.appendSlice(allocator, head);
    for (passport.intended_uses, 0..) |use, i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(allocator, "\"{s}\"", .{@tagName(use)});
        defer allocator.free(item);
        try list.appendSlice(allocator, item);
    }
    try list.appendSlice(allocator, "],\"prohibited_uses\":[");
    for (passport.prohibited_uses, 0..) |item, i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        const entry = try std.fmt.allocPrint(allocator, "\"{s}\"", .{item});
        defer allocator.free(entry);
        try list.appendSlice(allocator, entry);
    }
    const tail = try std.fmt.allocPrint(
        allocator,
        "],\"validity_envelope\":{{\"variable\":\"{s}\",\"minimum\":{d:.6},\"maximum\":{d:.6},\"unit\":\"{s}\"}},\"credibility\":{{\"pedigree\":{d},\"verification\":{d},\"validation\":{d},\"uncertainty\":{d},\"review\":{d}}},\"operational_qualification_claimed\":false}}\n",
        .{
            passport.validity_envelope.variable,
            passport.validity_envelope.minimum,
            passport.validity_envelope.maximum,
            passport.validity_envelope.unit,
            passport.credibility.pedigree,
            passport.credibility.verification,
            passport.credibility.validation,
            passport.credibility.uncertainty,
            passport.credibility.review,
        },
    );
    defer allocator.free(tail);
    try list.appendSlice(allocator, tail);
    return try list.toOwnedSlice(allocator);
}

test "passport issuer maps proof dimensions into credibility vector" {
    const model = evidence.ModelManifest{
        .id = "strip.atmosphere.us76-layered",
        .version = "0.2.0",
        .proof_level = .analytical,
        .source = "US76",
        .assumptions = &.{"dry ideal gas"},
        .valid_min = 0,
        .valid_max = 86000,
        .valid_unit = "m",
        .proof = .{
            .implementation = .implemented,
            .testing = .unit_tested,
            .analysis = .analytical,
            .comparison = .cross_implementation,
            .validation = .none,
        },
    };
    const passport = issueFromManifest(
        model,
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        &.{.preliminary_design},
        &.{"operational flight clearance"},
    );
    try std.testing.expectEqual(@as(u8, 2), passport.credibility.pedigree);
    try std.testing.expectEqual(@as(u8, 2), passport.credibility.review);
    try std.testing.expect(!passport.operational_qualification_claimed);
}
