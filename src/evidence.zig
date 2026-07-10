//! Evidence metadata that must accompany an engineering result.
//!
//! Proof is represented by independent dimensions. `LegacyProofLevel` and the
//! `proof_level` manifest field remain as a temporary atmosphere/CLI projection.

const std = @import("std");
pub const serialization = @import("serialization/root.zig");
pub const uncertainty = @import("uncertainty/root.zig");
pub const safety = @import("safety.zig");

pub const ImplementationStatus = enum { described, implemented };
pub const TestStatus = enum { untested, unit_tested };
pub const AnalysisStatus = enum { none, analytical };
pub const ComparisonStatus = enum { none, cross_implementation, public_benchmark };
pub const ValidationStatus = enum {
    none,
    experimental,
    hil_validated,
    accredited,
    certification_evidence,
};

pub const ProofDimensions = struct {
    implementation: ImplementationStatus = .described,
    testing: TestStatus = .untested,
    analysis: AnalysisStatus = .none,
    comparison: ComparisonStatus = .none,
    validation: ValidationStatus = .none,

    pub fn weakestLink(a: ProofDimensions, b: ProofDimensions) ProofDimensions {
        return .{
            .implementation = weaker(ImplementationStatus, a.implementation, b.implementation),
            .testing = weaker(TestStatus, a.testing, b.testing),
            .analysis = weaker(AnalysisStatus, a.analysis, b.analysis),
            .comparison = weaker(ComparisonStatus, a.comparison, b.comparison),
            .validation = weaker(ValidationStatus, a.validation, b.validation),
        };
    }

    fn weaker(comptime T: type, a: T, b: T) T {
        return if (@intFromEnum(a) <= @intFromEnum(b)) a else b;
    }
};

/// Compatibility projection for the original atmosphere manifest and CLI.
/// New manifests should populate `ModelManifest.proof`.
pub const LegacyProofLevel = enum {
    implemented,
    unit_tested,
    analytical,
    cross_implementation,
    public_benchmark,
    experimental,
    hil_validated,
    accredited_use,
    certification_evidence,
};

pub fn dimensionsFromLegacy(level: LegacyProofLevel) ProofDimensions {
    return switch (level) {
        .implemented => .{ .implementation = .implemented },
        .unit_tested => .{ .implementation = .implemented, .testing = .unit_tested },
        .analytical => .{ .implementation = .implemented, .analysis = .analytical },
        .cross_implementation => .{ .implementation = .implemented, .comparison = .cross_implementation },
        .public_benchmark => .{ .implementation = .implemented, .comparison = .public_benchmark },
        .experimental => .{ .implementation = .implemented, .validation = .experimental },
        .hil_validated => .{ .implementation = .implemented, .validation = .hil_validated },
        .accredited_use => .{ .implementation = .implemented, .validation = .accredited },
        .certification_evidence => .{ .implementation = .implemented, .validation = .certification_evidence },
    };
}

pub const IntendedUse = enum {
    education,
    research,
    preliminary_design,
    simulation_training,
};

pub const ValidityStatus = enum {
    valid,
    outside_envelope,
    invalid_input,
};

pub const ProvenanceManifest = struct {
    source: []const u8,
    citation: ?[]const u8 = null,
    license: ?[]const u8 = null,
    retrieved_at: ?[]const u8 = null,
};

pub const DependencyManifest = struct {
    id: []const u8,
    version: []const u8,
    digest: serialization.digest.Identifier,
    proof: ProofDimensions,
};

pub const ValidityEnvelope = struct {
    variable: []const u8,
    minimum: f64,
    maximum: f64,
    unit: []const u8,

    pub fn validate(self: ValidityEnvelope) error{InvalidEnvelope}!void {
        if (!std.math.isFinite(self.minimum) or
            !std.math.isFinite(self.maximum) or
            self.minimum > self.maximum or
            self.variable.len == 0 or
            self.unit.len == 0)
            return error.InvalidEnvelope;
    }

    pub fn contains(self: ValidityEnvelope, value: f64) bool {
        return std.math.isFinite(value) and value >= self.minimum and value <= self.maximum;
    }
};

pub const ModelManifest = struct {
    id: []const u8,
    version: []const u8,
    proof_level: LegacyProofLevel,
    source: []const u8,
    assumptions: []const []const u8,
    valid_min: f64,
    valid_max: f64,
    valid_unit: []const u8,

    proof: ?ProofDimensions = null,
    provenance: ?ProvenanceManifest = null,
    dependencies: []const DependencyManifest = &.{},
    digest: ?serialization.digest.Identifier = null,
    validity_envelope: ?ValidityEnvelope = null,
    uncertainty_status: uncertainty.Status = .unknown,

    pub fn effectiveProof(self: ModelManifest) ProofDimensions {
        var result = self.proof orelse dimensionsFromLegacy(self.proof_level);
        for (self.dependencies) |dependency|
            result = ProofDimensions.weakestLink(result, dependency.proof);
        return result;
    }

    pub fn effectiveEnvelope(self: ModelManifest, variable: []const u8) ValidityEnvelope {
        return self.validity_envelope orelse .{
            .variable = variable,
            .minimum = self.valid_min,
            .maximum = self.valid_max,
            .unit = self.valid_unit,
        };
    }
};

pub const Context = struct {
    intended_use: IntendedUse,
    spatial_frame: ?[]const u8 = null,
    time_reference: ?[]const u8 = null,

    pub fn init(intended_use: IntendedUse) safety.PolicyError!Context {
        try safety.enforcePublicIntendedUse(intended_use);
        return .{ .intended_use = intended_use };
    }

    pub fn enforcePublicPolicy(self: Context) safety.PolicyError!void {
        try safety.enforcePublicIntendedUse(self.intended_use);
    }
};

test "proof inheritance is component-wise weakest link" {
    const model = ProofDimensions{
        .implementation = .implemented,
        .testing = .unit_tested,
        .analysis = .analytical,
        .comparison = .public_benchmark,
        .validation = .experimental,
    };
    const dependency = ProofDimensions{
        .implementation = .implemented,
        .testing = .untested,
        .analysis = .none,
        .comparison = .cross_implementation,
        .validation = .none,
    };
    const inherited = ProofDimensions.weakestLink(model, dependency);
    try std.testing.expectEqual(TestStatus.untested, inherited.testing);
    try std.testing.expectEqual(AnalysisStatus.none, inherited.analysis);
    try std.testing.expectEqual(ComparisonStatus.cross_implementation, inherited.comparison);
    try std.testing.expectEqual(ValidationStatus.none, inherited.validation);
}

test "public context construction accepts the explicit allowlist" {
    inline for (.{ IntendedUse.education, .research, .preliminary_design, .simulation_training }) |use|
        _ = try Context.init(use);
}

test {
    _ = serialization;
    _ = uncertainty;
    _ = safety;
}
