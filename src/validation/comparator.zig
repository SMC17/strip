//! Deterministic bounded comparison against independent/reference observations.
const std = @import("std");
const envelope = @import("envelope.zig");
const types = @import("types.zig");

pub const max_samples = 256;

pub const Sample = struct {
    coordinates: []const f64,
    variable: []const u8,
    reference: f64,
    observed: f64,
};

pub const Fixture = struct {
    schema: []const u8,
    id: []const u8,
    deliberately_perturbed: bool,
    envelope: envelope.Envelope,
    acceptance: types.Acceptance,
    samples: []const Sample,
};

pub const Summary = struct {
    comparisons: [max_samples]types.Comparison = undefined,
    len: usize = 0,
    passed: usize = 0,
    failed: usize = 0,

    pub fn allPassed(self: Summary) bool {
        return self.len > 0 and self.failed == 0;
    }
};

pub fn compare(
    validity: envelope.Envelope,
    acceptance: types.Acceptance,
    samples: []const Sample,
) !Summary {
    const empty: types.MetricAcceptanceSet = .{ .metrics = &.{} };
    return compareWithMetrics(validity, empty, acceptance, samples);
}

pub fn compareWithMetrics(
    validity: envelope.Envelope,
    metrics: types.MetricAcceptanceSet,
    fallback: types.Acceptance,
    samples: []const Sample,
) !Summary {
    try validity.validate();
    try fallback.validate();
    if (metrics.metrics.len > 0) try metrics.validate();
    if (samples.len == 0 or samples.len > max_samples) return error.InvalidSampleCount;

    var summary: Summary = .{};
    for (samples) |sample| {
        if (!try validity.contains(sample.coordinates)) return error.SampleOutsideEnvelope;
        if (sample.variable.len == 0 or sample.variable.len > 64) return error.InvalidVariable;
        if (!std.math.isFinite(sample.reference) or !std.math.isFinite(sample.observed))
            return error.NonFiniteSample;
        const absolute_error = @abs(sample.observed - sample.reference);
        const tolerance = if (metrics.forVariable(sample.variable)) |metric|
            metric.toleranceFor(sample.reference)
        else
            @max(
                fallback.absolute_tolerance,
                fallback.relative_tolerance * @abs(sample.reference),
            );
        const status: types.EvidenceStatus = if (absolute_error <= tolerance) .passed else .failed;
        summary.comparisons[summary.len] = .{
            .variable = sample.variable,
            .reference = sample.reference,
            .observed = sample.observed,
            .absolute_error = absolute_error,
            .tolerance = tolerance,
            .status = status,
        };
        summary.len += 1;
        if (status == .passed) summary.passed += 1 else summary.failed += 1;
    }
    return summary;
}

pub fn parseFixture(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Fixture) {
    if (bytes.len > 256 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(Fixture, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, "strip.comparator-fixture.v1"))
        return error.UnsupportedSchema;
    if (parsed.value.id.len == 0 or parsed.value.id.len > 96) return error.InvalidId;
    _ = try compare(parsed.value.envelope, parsed.value.acceptance, parsed.value.samples);
    return parsed;
}

test "deliberately perturbed comparator fixture fails honestly" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/comparator-perturbed.json",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var fixture = try parseFixture(std.testing.allocator, bytes);
    defer fixture.deinit();
    try std.testing.expect(fixture.value.deliberately_perturbed);
    const summary = try compare(
        fixture.value.envelope,
        fixture.value.acceptance,
        fixture.value.samples,
    );
    try std.testing.expectEqual(@as(usize, 1), summary.failed);
    try std.testing.expect(!summary.allPassed());
}

test "comparator rejects samples outside any envelope dimension" {
    const validity: envelope.Envelope = .{ .axes = &.{
        .{ .variable = "mach", .unit = "1", .minimum = 0, .maximum = 0.3 },
        .{ .variable = "altitude", .unit = "m", .minimum = 0, .maximum = 1000 },
    } };
    try std.testing.expectError(error.SampleOutsideEnvelope, compare(
        validity,
        .{ .absolute_tolerance = 0.1, .relative_tolerance = 0 },
        &.{.{ .coordinates = &.{ 0.2, 1001 }, .variable = "coefficient", .reference = 1, .observed = 1 }},
    ));
}
