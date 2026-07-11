//! Typed validation cases and reports with explicit evidence dimensions.
const std = @import("std");
const envelope = @import("envelope.zig");

pub const EvidenceDimension = enum {
    analytical,
    unit_test,
    cross_implementation,
    public_benchmark,
    experimental,
    hardware_in_loop,
    flight,
    certification,
};

pub const EvidenceStatus = enum { missing, passed, failed };
pub const ReportStatus = enum { passed, failed, incomplete };

pub const Acceptance = struct {
    absolute_tolerance: f64,
    relative_tolerance: f64,

    pub fn validate(self: Acceptance) !void {
        if (!std.math.isFinite(self.absolute_tolerance) or self.absolute_tolerance < 0)
            return error.InvalidTolerance;
        if (!std.math.isFinite(self.relative_tolerance) or
            self.relative_tolerance < 0 or self.relative_tolerance > 1)
            return error.InvalidTolerance;
    }
};

pub const MetricAcceptance = struct {
    variable: []const u8,
    unit: []const u8,
    absolute_tolerance: f64,
    relative_tolerance: f64,
    rationale: []const u8,

    pub fn validate(self: MetricAcceptance) !void {
        try bounded(self.variable, 1, 64);
        try bounded(self.unit, 1, 32);
        try bounded(self.rationale, 1, 256);
        if (!std.math.isFinite(self.absolute_tolerance) or self.absolute_tolerance < 0)
            return error.InvalidTolerance;
        if (!std.math.isFinite(self.relative_tolerance) or
            self.relative_tolerance < 0 or self.relative_tolerance > 1)
            return error.InvalidTolerance;
    }

    pub fn toleranceFor(self: MetricAcceptance, reference: f64) f64 {
        return @max(
            self.absolute_tolerance,
            self.relative_tolerance * @abs(reference),
        );
    }
};

pub const MetricAcceptanceSet = struct {
    metrics: []const MetricAcceptance,

    pub fn validate(self: MetricAcceptanceSet) !void {
        if (self.metrics.len == 0 or self.metrics.len > 32) return error.InvalidMetricCount;
        for (self.metrics, 0..) |metric, index| {
            try metric.validate();
            for (self.metrics[0..index]) |prior| {
                if (std.mem.eql(u8, prior.variable, metric.variable)) return error.DuplicateMetricVariable;
            }
        }
    }

    pub fn forVariable(self: MetricAcceptanceSet, variable: []const u8) ?MetricAcceptance {
        for (self.metrics) |metric| {
            if (std.mem.eql(u8, metric.variable, variable)) return metric;
        }
        return null;
    }
};

pub const ValidationCase = struct {
    schema: []const u8,
    id: []const u8,
    subject: []const u8,
    comparator: []const u8,
    source_ids: []const []const u8,
    envelope: envelope.Envelope,
    expected_dimensions: []const EvidenceDimension,
    acceptance: Acceptance,

    pub fn validate(self: ValidationCase) !void {
        if (!std.mem.eql(u8, self.schema, "strip.validation-case.v1"))
            return error.UnsupportedSchema;
        try bounded(self.id, 1, 96);
        try bounded(self.subject, 1, 160);
        try bounded(self.comparator, 1, 160);
        if (self.source_ids.len == 0 or self.source_ids.len > 32)
            return error.InvalidSourceCount;
        for (self.source_ids, 0..) |source_id, index| {
            try bounded(source_id, 1, 96);
            for (self.source_ids[0..index]) |prior| {
                if (std.mem.eql(u8, source_id, prior)) return error.DuplicateSourceId;
            }
        }
        try self.envelope.validate();
        if (self.expected_dimensions.len == 0 or
            self.expected_dimensions.len > @typeInfo(EvidenceDimension).@"enum".fields.len)
            return error.InvalidEvidenceDimensions;
        for (self.expected_dimensions, 0..) |dimension, index| {
            for (self.expected_dimensions[0..index]) |prior| {
                if (dimension == prior) return error.DuplicateEvidenceDimension;
            }
        }
        try self.acceptance.validate();
    }
};

pub const Comparison = struct {
    variable: []const u8,
    reference: f64,
    observed: f64,
    absolute_error: f64,
    tolerance: f64,
    status: EvidenceStatus,

    pub fn validate(self: Comparison) !void {
        try bounded(self.variable, 1, 64);
        inline for (.{ self.reference, self.observed, self.absolute_error, self.tolerance }) |value| {
            if (!std.math.isFinite(value)) return error.NonFiniteComparison;
        }
        if (self.absolute_error < 0 or self.tolerance < 0) return error.InvalidComparison;
        const calculated_error = @abs(self.observed - self.reference);
        const rounding_margin = @max(1.0e-12, calculated_error * 1.0e-12);
        if (@abs(calculated_error - self.absolute_error) > rounding_margin)
            return error.InconsistentAbsoluteError;
        if (self.status == .missing) return error.InvalidComparison;
        const actually_passes = self.absolute_error <= self.tolerance;
        if (actually_passes != (self.status == .passed)) return error.InconsistentComparison;
    }
};

pub const EvidenceResult = struct {
    dimension: EvidenceDimension,
    status: EvidenceStatus,
    evidence_id: ?[]const u8 = null,
    note: []const u8,

    pub fn validate(self: EvidenceResult) !void {
        try bounded(self.note, 1, 512);
        if (self.status == .missing) {
            if (self.evidence_id != null) return error.MissingEvidenceHasId;
        } else {
            try bounded(self.evidence_id orelse return error.EvidenceIdRequired, 1, 160);
        }
    }
};

pub const ValidationReport = struct {
    schema: []const u8,
    id: []const u8,
    case_id: []const u8,
    generated_at: []const u8,
    status: ReportStatus,
    comparisons: []const Comparison,
    evidence: []const EvidenceResult,
    limitations: []const []const u8,

    pub fn validate(self: ValidationReport) !void {
        if (!std.mem.eql(u8, self.schema, "strip.validation-report.v1"))
            return error.UnsupportedSchema;
        try bounded(self.id, 1, 96);
        try bounded(self.case_id, 1, 96);
        if (self.generated_at.len < 20 or self.generated_at.len > 40 or
            self.generated_at[10] != 'T' or self.generated_at[self.generated_at.len - 1] != 'Z')
            return error.InvalidGenerationTime;
        if (self.comparisons.len == 0 or self.comparisons.len > 4096)
            return error.InvalidComparisonCount;
        var has_failed = false;
        for (self.comparisons) |comparison| {
            try comparison.validate();
            has_failed = has_failed or comparison.status == .failed;
        }
        if (self.evidence.len == 0 or self.evidence.len > 32)
            return error.InvalidEvidenceCount;
        var has_missing = false;
        for (self.evidence, 0..) |result, index| {
            try result.validate();
            has_failed = has_failed or result.status == .failed;
            has_missing = has_missing or result.status == .missing;
            for (self.evidence[0..index]) |prior| {
                if (prior.dimension == result.dimension) return error.DuplicateEvidenceDimension;
            }
        }
        const expected_status: ReportStatus =
            if (has_failed) .failed else if (has_missing) .incomplete else .passed;
        if (self.status != expected_status) return error.InconsistentReportStatus;
        if (self.limitations.len == 0 or self.limitations.len > 32)
            return error.InvalidLimitations;
        for (self.limitations) |limitation| try bounded(limitation, 1, 512);
    }
};

pub fn parseCase(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(ValidationCase) {
    if (bytes.len > 128 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(ValidationCase, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

pub fn parseReport(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(ValidationReport) {
    if (bytes.len > 1024 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(ValidationReport, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

fn bounded(value: []const u8, minimum: usize, maximum: usize) !void {
    if (value.len < minimum or value.len > maximum) return error.InvalidTextLength;
}

test "typed validation fixtures reject inconsistent evidence" {
    const case_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/validation-case.valid.json",
        std.testing.allocator,
        .limited(128 * 1024),
    );
    defer std.testing.allocator.free(case_bytes);
    var valid_case = try parseCase(std.testing.allocator, case_bytes);
    defer valid_case.deinit();

    const invalid_case_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/validation-case.invalid.json",
        std.testing.allocator,
        .limited(128 * 1024),
    );
    defer std.testing.allocator.free(invalid_case_bytes);
    try std.testing.expectError(
        error.InvertedBounds,
        parseCase(std.testing.allocator, invalid_case_bytes),
    );

    const report_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/validation-report.valid.json",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(report_bytes);
    var valid_report = try parseReport(std.testing.allocator, report_bytes);
    defer valid_report.deinit();
    try std.testing.expectEqual(ReportStatus.failed, valid_report.value.status);

    const invalid_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/validation-report.invalid.json",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(invalid_bytes);
    try std.testing.expectError(
        error.InconsistentReportStatus,
        parseReport(std.testing.allocator, invalid_bytes),
    );
}
