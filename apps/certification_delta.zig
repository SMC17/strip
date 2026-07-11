//! `strip-certification-delta` — compute revalidation delta between model packages.

const std = @import("std");
const strip = @import("strip");

const ModelJson = struct {
    id: []const u8,
    version: []const u8,
    digest: []const u8,
};

const PackageJson = struct {
    id: []const u8,
    version: []const u8,
    models: []const ModelJson,
};

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        std.debug.print("usage: strip-certification-delta diff <baseline.json> <candidate.json>\n", .{});
        return 2;
    };
    if (!std.mem.eql(u8, sub, "diff")) return 2;
    const baseline_path = it.next() orelse return 2;
    const candidate_path = it.next() orelse return 2;

    const baseline_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, baseline_path, allocator, .limited(1024 * 1024));
    defer allocator.free(baseline_bytes);
    const candidate_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, candidate_path, allocator, .limited(1024 * 1024));
    defer allocator.free(candidate_bytes);

    var baseline_parsed = try std.json.parseFromSlice(PackageJson, allocator, baseline_bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    defer baseline_parsed.deinit();
    var candidate_parsed = try std.json.parseFromSlice(PackageJson, allocator, candidate_bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    defer candidate_parsed.deinit();

    var baseline_digest: [64]u8 = undefined;
    var candidate_digest: [64]u8 = undefined;
    strip.flight_test.flight_seal.digestHexOf(baseline_bytes, &baseline_digest);
    strip.flight_test.flight_seal.digestHexOf(candidate_bytes, &candidate_digest);
    var baseline_digest_full: [71]u8 = undefined;
    var candidate_digest_full: [71]u8 = undefined;
    const bdig = try std.fmt.bufPrint(&baseline_digest_full, "sha256:{s}", .{&baseline_digest});
    const cdig = try std.fmt.bufPrint(&candidate_digest_full, "sha256:{s}", .{&candidate_digest});

    var baseline_models = try allocator.alloc(strip.validation.certification_delta.ModelEntry, baseline_parsed.value.models.len);
    defer allocator.free(baseline_models);
    for (baseline_parsed.value.models, 0..) |m, idx| {
        baseline_models[idx] = .{ .id = m.id, .version = m.version, .digest = m.digest };
    }
    var candidate_models = try allocator.alloc(strip.validation.certification_delta.ModelEntry, candidate_parsed.value.models.len);
    defer allocator.free(candidate_models);
    for (candidate_parsed.value.models, 0..) |m, idx| {
        candidate_models[idx] = .{ .id = m.id, .version = m.version, .digest = m.digest };
    }

    const delta = try strip.validation.certification_delta.computeDelta(
        allocator,
        .{ .id = baseline_parsed.value.id, .version = baseline_parsed.value.version, .models = baseline_models },
        .{ .id = candidate_parsed.value.id, .version = candidate_parsed.value.version, .models = candidate_models },
        bdig,
        cdig,
    );
    defer {
        allocator.free(delta.id);
        for (delta.changed_artifacts) |art| allocator.free(art.path);
        allocator.free(delta.changed_artifacts);
        allocator.free(delta.required_revalidation);
    }
    const json = try strip.validation.certification_delta.formatJson(allocator, delta);
    defer allocator.free(json);

    var buffer: [8192]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(json);
    return 0;
}
