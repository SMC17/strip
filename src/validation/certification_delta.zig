//! Certification-delta engine: what must be revalidated when artifacts change.

const std = @import("std");

pub const Impact = enum { documentation, model, validation, assurance, flight };

pub const ChangedArtifact = struct {
    path: []const u8,
    digest: []const u8,
    impact: Impact,
};

pub const Delta = struct {
    schema: []const u8 = "strip.certification-delta.v0",
    id: []const u8,
    baseline_digest: []const u8,
    candidate_digest: []const u8,
    changed_artifacts: []const ChangedArtifact,
    required_revalidation: []const []const u8,
    operational_qualification_claimed: bool = false,
};

pub const ModelEntry = struct {
    id: []const u8,
    version: []const u8,
    digest: []const u8,
};

pub const ModelPackageView = struct {
    id: []const u8,
    version: []const u8,
    models: []const ModelEntry,
};

fn impactForModelChange() Impact {
    return .model;
}

pub fn computeDelta(
    allocator: std.mem.Allocator,
    baseline: ModelPackageView,
    candidate: ModelPackageView,
    baseline_digest: []const u8,
    candidate_digest: []const u8,
) !Delta {
    var changed = try std.ArrayList(ChangedArtifact).initCapacity(allocator, 8);
    errdefer changed.deinit(allocator);
    var revalidation = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    errdefer revalidation.deinit(allocator);

    for (candidate.models) |cand| {
        var found = false;
        var digest_changed = false;
        for (baseline.models) |base| {
            if (std.mem.eql(u8, base.id, cand.id)) {
                found = true;
                if (!std.mem.eql(u8, base.digest, cand.digest) or !std.mem.eql(u8, base.version, cand.version))
                    digest_changed = true;
                break;
            }
        }
        if (!found or digest_changed) {
            const path = try std.fmt.allocPrint(allocator, "models/{s}", .{cand.id});
            try changed.append(allocator, .{
                .path = path,
                .digest = cand.digest,
                .impact = impactForModelChange(),
            });
            try revalidation.append(allocator, path);
            try revalidation.append(allocator, "campaigns/reference-uas-contingency.toml");
        }
    }

    const id = try std.fmt.allocPrint(
        allocator,
        "delta-{s}-to-{s}",
        .{ baseline.id, candidate.id },
    );
    return .{
        .id = id,
        .baseline_digest = baseline_digest,
        .candidate_digest = candidate_digest,
        .changed_artifacts = try changed.toOwnedSlice(allocator),
        .required_revalidation = try revalidation.toOwnedSlice(allocator),
    };
}

pub fn formatJson(allocator: std.mem.Allocator, delta: Delta) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    const head = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"{s}\",\"id\":\"{s}\",\"baseline_digest\":\"{s}\",\"candidate_digest\":\"{s}\",\"changed_artifacts\":[",
        .{ delta.schema, delta.id, delta.baseline_digest, delta.candidate_digest },
    );
    defer allocator.free(head);
    try list.appendSlice(allocator, head);
    for (delta.changed_artifacts, 0..) |art, i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(
            allocator,
            "{{\"path\":\"{s}\",\"digest\":\"{s}\",\"impact\":\"{s}\"}}",
            .{ art.path, art.digest, @tagName(art.impact) },
        );
        defer allocator.free(item);
        try list.appendSlice(allocator, item);
    }
    try list.appendSlice(allocator, "],\"required_revalidation\":[");
    for (delta.required_revalidation, 0..) |item, i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        const entry = try std.fmt.allocPrint(allocator, "\"{s}\"", .{item});
        defer allocator.free(entry);
        try list.appendSlice(allocator, entry);
    }
    try list.appendSlice(allocator, "],\"operational_qualification_claimed\":false}\n");
    return try list.toOwnedSlice(allocator);
}

test "delta engine flags model digest changes" {
    const baseline = ModelPackageView{
        .id = "pkg-a",
        .version = "0.1.0",
        .models = &.{.{
            .id = "strip.atmosphere.us76-layered",
            .version = "0.2.0",
            .digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }},
    };
    const candidate = ModelPackageView{
        .id = "pkg-a",
        .version = "0.1.1",
        .models = &.{.{
            .id = "strip.atmosphere.us76-layered",
            .version = "0.2.1",
            .digest = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        }},
    };
    const delta = try computeDelta(
        std.testing.allocator,
        baseline,
        candidate,
        "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    );
    defer {
        std.testing.allocator.free(delta.id);
        for (delta.changed_artifacts) |art| std.testing.allocator.free(art.path);
        std.testing.allocator.free(delta.changed_artifacts);
        std.testing.allocator.free(delta.required_revalidation);
    }
    try std.testing.expect(delta.changed_artifacts.len >= 1);
    try std.testing.expect(!delta.operational_qualification_claimed);
}
