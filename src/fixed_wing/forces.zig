//! Dimensional reconstruction for body-axis aerodynamic coefficients.

const std = @import("std");
const Vec3 = @import("types.zig").Vec3;
const Six = @import("coefficients.zig").Six;
const evidence = @import("../evidence.zig");
const numerical_result = @import("../result.zig");

pub const manifest = evidence.ModelManifest{
    .id = "strip.fixed-wing.coefficient-reconstruction",
    .version = "0.1.0",
    .proof_level = .analytical,
    .source = "Dimensional body-axis force and moment reconstruction from coefficients",
    .assumptions = &.{ "positive dynamic pressure", "positive reference geometry" },
    .valid_min = 0.0,
    .valid_max = 200000.0,
    .valid_unit = "Pa",
};

pub const Geometry = struct {
    area_m2: f64,
    span_m: f64,
    chord_m: f64,

    pub fn validate(self: Geometry) error{InvalidGeometry}!void {
        if (!std.math.isFinite(self.area_m2) or !(self.area_m2 > 0.0) or
            !std.math.isFinite(self.span_m) or !(self.span_m > 0.0) or
            !std.math.isFinite(self.chord_m) or !(self.chord_m > 0.0))
            return error.InvalidGeometry;
    }
};

pub const BodyWrench = struct {
    /// Positive x forward, y right, z down.
    force_n: Vec3,
    /// Positive roll right-wing-down, pitch nose-up, yaw nose-right.
    moment_nm: Vec3,
};

pub fn reconstruct(coefficient: Six, dynamic_pressure_pa: f64, geometry: Geometry) error{
    InvalidDynamicPressure,
    InvalidGeometry,
}!BodyWrench {
    try geometry.validate();
    if (!std.math.isFinite(dynamic_pressure_pa) or dynamic_pressure_pa < 0.0)
        return error.InvalidDynamicPressure;
    const q_area = dynamic_pressure_pa * geometry.area_m2;
    return .{
        .force_n = .{
            .x = q_area * coefficient.cx,
            .y = q_area * coefficient.cy,
            .z = q_area * coefficient.cz,
        },
        .moment_nm = .{
            .x = q_area * geometry.span_m * coefficient.cl,
            .y = q_area * geometry.chord_m * coefficient.cm,
            .z = q_area * geometry.span_m * coefficient.cn,
        },
    };
}

pub fn reconstructResult(
    context: evidence.Context,
    coefficient: Six,
    dynamic_pressure_pa: f64,
    geometry: Geometry,
) error{ InvalidDynamicPressure, InvalidGeometry }!numerical_result.NumericalResult(?BodyWrench) {
    if (!std.math.isFinite(dynamic_pressure_pa) or dynamic_pressure_pa < 0.0)
        return error.InvalidDynamicPressure;
    const envelope = manifest.effectiveEnvelope("dynamic_pressure_pa");
    if (!envelope.contains(dynamic_pressure_pa)) {
        return .{
            .value = null,
            .model = manifest,
            .context = context,
            .validity = .outside_envelope,
            .evaluated_point = .{
                .variable = "dynamic_pressure_pa",
                .value = dynamic_pressure_pa,
                .unit = "Pa",
            },
            .envelope = envelope,
            .execution_identity = .fromModel(manifest),
        };
    }
    const wrench = try reconstruct(coefficient, dynamic_pressure_pa, geometry);
    return .{
        .value = wrench,
        .model = manifest,
        .context = context,
        .validity = .valid,
        .evaluated_point = .{
            .variable = "dynamic_pressure_pa",
            .value = dynamic_pressure_pa,
            .unit = "Pa",
        },
        .envelope = envelope,
        .execution_identity = .fromModel(manifest),
    };
}

test "dimensional reconstruction preserves body-axis signs and reference lengths" {
    const wrench = try reconstruct(.{
        .cx = -0.1,
        .cy = 0.2,
        .cz = -0.5,
        .cl = 0.01,
        .cm = -0.02,
        .cn = 0.03,
    }, 100.0, .{ .area_m2 = 2.0, .span_m = 4.0, .chord_m = 1.0 });
    try std.testing.expectApproxEqAbs(@as(f64, -20.0), wrench.force_n.x, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -100.0), wrench.force_n.z, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), wrench.moment_nm.x, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -4.0), wrench.moment_nm.y, 1e-12);
}
