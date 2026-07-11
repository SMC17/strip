//! Evidence-bearing numerical results. Authoritative model functions should
//! return `NumericalResult(T)`, not naked scalars or untyped structs.

const evidence = @import("evidence.zig");

pub fn NumericalResult(comptime T: type) type {
    return struct {
        value: T,
        model: evidence.ModelManifest,
        context: evidence.Context,
        validity: evidence.ValidityStatus,
        evaluated_point: EvaluatedPoint,
        envelope: evidence.ValidityEnvelope,
        execution_identity: evidence.ExecutionIdentity,
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
