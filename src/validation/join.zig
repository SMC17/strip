//! Join validation cases, reports, and source registries into authoritative checks.
const std = @import("std");
const coverage = @import("coverage.zig");
const source = @import("source.zig");
const types = @import("types.zig");

pub const ValidatedReport = struct {
    case_id: []const u8,
    report_id: []const u8,
    report_status: types.ReportStatus,
    coverage: coverage.Matrix,
    all_expected_dimensions_present: bool,
    all_source_ids_resolved: bool,
    joined: bool,

    pub fn passed(self: ValidatedReport) bool {
        return self.joined and
            self.all_expected_dimensions_present and
            self.all_source_ids_resolved and
            self.report_status == .passed;
    }
};

pub fn sourceIdResolved(registry: source.DatasetManifest, source_id: []const u8) bool {
    for (registry.records) |record| {
        if (std.mem.eql(u8, record.id, source_id)) return true;
    }
    return false;
}

pub fn dimensionPresent(report: types.ValidationReport, dimension: types.EvidenceDimension) bool {
    for (report.evidence) |entry| {
        if (entry.dimension == dimension) return true;
    }
    return false;
}

pub fn validateReportAgainstCase(
    case: types.ValidationCase,
    report: types.ValidationReport,
    registry: source.DatasetManifest,
) !ValidatedReport {
    try case.validate();
    try report.validate();
    try registry.validate();

    const case_joined = std.mem.eql(u8, report.case_id, case.id);

    var all_dimensions = true;
    for (case.expected_dimensions) |dimension| {
        if (!dimensionPresent(report, dimension)) all_dimensions = false;
    }

    var all_sources = true;
    for (case.source_ids) |source_id| {
        if (!sourceIdResolved(registry, source_id)) all_sources = false;
    }

    const matrix = try coverage.Matrix.build(case.expected_dimensions, report.evidence);

    return .{
        .case_id = case.id,
        .report_id = report.id,
        .report_status = report.status,
        .coverage = matrix,
        .all_expected_dimensions_present = all_dimensions,
        .all_source_ids_resolved = all_sources,
        .joined = case_joined,
    };
}

test "joined report requires every case dimension and resolved source id" {
    const case_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/validation-case.valid.json",
        std.testing.allocator,
        .limited(128 * 1024),
    );
    defer std.testing.allocator.free(case_bytes);
    var validation_case = try types.parseCase(std.testing.allocator, case_bytes);
    defer validation_case.deinit();

    const report_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/validation-report.valid.json",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(report_bytes);
    var report = try types.parseReport(std.testing.allocator, report_bytes);
    defer report.deinit();

    const registry = source.DatasetManifest{
        .schema = "strip.dataset-manifest.v1",
        .records = &.{.{
            .id = "synthetic-comparator-fixture",
            .title = "Synthetic comparator fixture",
            .publisher = "Strip",
            .edition = "fixture",
            .version = "1",
            .url = "https://example.invalid/strip/fixtures/validation/comparator-perturbed",
            .license = "fixture",
            .retrieved_at = "2026-07-10",
            .digest = "sha256:00ff94c1e0df81fc56790c0f2288d0c58f98377bf375bb7bdc95616626b0b6dd",
            .digest_scope = .fixture_content,
            .extraction = "Fixture bytes pinned under fixtures/validation/comparator-perturbed.json.",
            .extraction_provenance = .{
                .citation_anchor = "fixtures/validation/comparator-perturbed.json",
                .extracted_artifact_path = "fixtures/validation/comparator-perturbed.json",
                .extracted_artifact_digest = "sha256:00ff94c1e0df81fc56790c0f2288d0c58f98377bf375bb7bdc95616626b0b6dd",
            },
            .limitations = &.{"Not physical evidence."},
        }},
    };

    const validated = try validateReportAgainstCase(
        validation_case.value,
        report.value,
        registry,
    );
    try std.testing.expect(validated.joined);
    try std.testing.expect(validated.all_expected_dimensions_present);
    try std.testing.expect(validated.all_source_ids_resolved);
    try std.testing.expect(!validated.passed());
}
