//! Evidence-bearing numerical results. Authoritative model functions should
//! return `NumericalResult(T)`, not naked scalars or untyped structs.

const evidence = @import("evidence.zig");

/// NASA-STD-7009B-inspired credibility vector C = (P, V, E, R, G).
/// Scores are ordinal 0–4 (none → strong). Not a certification claim.
pub const CredibilityVector = struct {
    pedigree: u8 = 0,
    verification: u8 = 0,
    validation: u8 = 0,
    uncertainty: u8 = 0,
    review: u8 = 0,

    pub fn fromProof(proof: evidence.ProofDimensions) CredibilityVector {
        return .{
            .pedigree = switch (proof.implementation) {
                .described => 1,
                .implemented => 2,
            },
            .verification = switch (proof.testing) {
                .untested => 0,
                .unit_tested => 2,
            },
            .validation = switch (proof.validation) {
                .none => 0,
                .experimental => 1,
                .hil_validated => 3,
                .accredited => 4,
                .certification_evidence => 4,
            },
            .uncertainty = switch (proof.analysis) {
                .none => 0,
                .analytical => 2,
            },
            .review = switch (proof.comparison) {
                .none => 0,
                .cross_implementation => 2,
                .public_benchmark => 3,
            },
        };
    }

    pub fn weakestComponent(self: CredibilityVector) u8 {
        return @min(
            @min(self.pedigree, self.verification),
            @min(@min(self.validation, self.uncertainty), self.review),
        );
    }
};

pub fn NumericalResult(comptime T: type) type {
    return struct {
        value: T,
        model: evidence.ModelManifest,
        context: evidence.Context,
        validity: evidence.ValidityStatus,
        evaluated_point: EvaluatedPoint,
        envelope: evidence.ValidityEnvelope,
        execution_identity: evidence.ExecutionIdentity,
        credibility: CredibilityVector,
        warnings: []const []const u8 = &.{},

        pub const EvaluatedPoint = struct {
            variable: []const u8,
            value: f64,
            unit: []const u8,
        };

        pub fn isAuthoritative(self: @This()) bool {
            return self.validity == .valid;
        }
    };
}

pub const AtmosphereState = struct {
    temperature: @import("units.zig").Temperature,
    pressure: @import("units.zig").Pressure,
    density: @import("units.zig").Density,
    speed_of_sound: @import("units.zig").Speed,
    layer_index: u8,
};

/// Backward-compatible evaluation view used by the CLI JSON encoder.
pub const AtmosphereEvaluation = struct {
    altitude: @import("units.zig").GeopotentialAltitude,
    validity: evidence.ValidityStatus,
    state: ?AtmosphereState,
    model: evidence.ModelManifest,
    envelope: evidence.ValidityEnvelope,
};
