//! Evidence coverage matrix. Absence is represented as `missing`, never pass.
const std = @import("std");
const types = @import("types.zig");

pub const Entry = struct {
    dimension: types.EvidenceDimension,
    status: types.EvidenceStatus,
};

pub const Matrix = struct {
    entries: [8]Entry = undefined,
    len: usize = 0,

    pub fn build(
        required: []const types.EvidenceDimension,
        evidence: []const types.EvidenceResult,
    ) !Matrix {
        if (required.len == 0 or required.len > 8) return error.InvalidRequiredDimensions;
        var result: Matrix = .{};
        for (evidence) |record| try record.validate();
        for (required, 0..) |dimension, index| {
            for (required[0..index]) |prior| {
                if (dimension == prior) return error.DuplicateRequiredDimension;
            }
            var coverage_status: types.EvidenceStatus = .missing;
            for (evidence) |record| {
                if (record.dimension != dimension) continue;
                coverage_status = switch (record.status) {
                    .failed => .failed,
                    .passed => if (coverage_status == .failed) .failed else .passed,
                    .missing => coverage_status,
                };
            }
            result.entries[result.len] = .{ .dimension = dimension, .status = coverage_status };
            result.len += 1;
        }
        return result;
    }

    pub fn status(self: Matrix, dimension: types.EvidenceDimension) ?types.EvidenceStatus {
        for (self.entries[0..self.len]) |entry| {
            if (entry.dimension == dimension) return entry.status;
        }
        return null;
    }

    pub fn allPassed(self: Matrix) bool {
        if (self.len == 0) return false;
        for (self.entries[0..self.len]) |entry| {
            if (entry.status != .passed) return false;
        }
        return true;
    }
};

test "coverage distinguishes passed failed and missing dimensions" {
    const evidence = [_]types.EvidenceResult{
        .{ .dimension = .unit_test, .status = .passed, .evidence_id = "test:42", .note = "Local unit test passed." },
        .{ .dimension = .cross_implementation, .status = .failed, .evidence_id = "report:perturbed", .note = "Perturbed comparator exceeded tolerance." },
    };
    const matrix = try Matrix.build(
        &.{ .unit_test, .cross_implementation, .experimental },
        &evidence,
    );
    try std.testing.expectEqual(types.EvidenceStatus.passed, matrix.status(.unit_test).?);
    try std.testing.expectEqual(types.EvidenceStatus.failed, matrix.status(.cross_implementation).?);
    try std.testing.expectEqual(types.EvidenceStatus.missing, matrix.status(.experimental).?);
    try std.testing.expect(!matrix.allPassed());
}

test "failed evidence cannot be hidden by later pass" {
    const evidence = [_]types.EvidenceResult{
        .{ .dimension = .unit_test, .status = .failed, .evidence_id = "failure", .note = "Failure." },
        .{ .dimension = .unit_test, .status = .passed, .evidence_id = "pass", .note = "Pass." },
    };
    const matrix = try Matrix.build(&.{.unit_test}, &evidence);
    try std.testing.expectEqual(types.EvidenceStatus.failed, matrix.status(.unit_test).?);
}
