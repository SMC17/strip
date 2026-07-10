//! Six-coefficient aerodynamic representation with bounded trilinear lookup.
//! All fixture values in this module's tests are synthetic.

const std = @import("std");
const airdata = @import("airdata.zig");
const Vec3 = @import("types.zig").Vec3;

pub const Six = struct {
    cx: f64 = 0.0,
    cy: f64 = 0.0,
    cz: f64 = 0.0,
    cl: f64 = 0.0,
    cm: f64 = 0.0,
    cn: f64 = 0.0,

    pub fn add(a: Six, b: Six) Six {
        return .{
            .cx = a.cx + b.cx,
            .cy = a.cy + b.cy,
            .cz = a.cz + b.cz,
            .cl = a.cl + b.cl,
            .cm = a.cm + b.cm,
            .cn = a.cn + b.cn,
        };
    }

    pub fn scale(a: Six, factor: f64) Six {
        return .{
            .cx = a.cx * factor,
            .cy = a.cy * factor,
            .cz = a.cz * factor,
            .cl = a.cl * factor,
            .cm = a.cm * factor,
            .cn = a.cn * factor,
        };
    }
};

pub const Controls = struct {
    aileron_rad: f64 = 0.0,
    elevator_rad: f64 = 0.0,
    rudder_rad: f64 = 0.0,
    flap_rad: f64 = 0.0,
};

pub const Derivatives = struct {
    alpha: Six = .{},
    beta: Six = .{},
    aileron: Six = .{},
    elevator: Six = .{},
    rudder: Six = .{},
    flap: Six = .{},
    p_hat: Six = .{},
    q_hat: Six = .{},
    r_hat: Six = .{},
};

pub const Error = error{
    EmptyAxis,
    NonFiniteGrid,
    AxisNotStrictlyIncreasing,
    ValueCountMismatch,
    OutsideEnvelope,
    NonFiniteQuery,
};

pub const Grid3 = struct {
    alpha_rad: []const f64,
    beta_rad: []const f64,
    mach: []const f64,
    values: []const Six,

    pub fn validate(self: Grid3) Error!void {
        try validateAxis(self.alpha_rad);
        try validateAxis(self.beta_rad);
        try validateAxis(self.mach);
        if (self.values.len != self.alpha_rad.len * self.beta_rad.len * self.mach.len)
            return error.ValueCountMismatch;
        for (self.values) |value| {
            inline for (std.meta.fields(Six)) |field| {
                if (!std.math.isFinite(@field(value, field.name))) return error.NonFiniteGrid;
            }
        }
    }

    pub fn evaluate(self: Grid3, alpha: f64, beta: f64, mach_value: f64) Error!Six {
        try self.validate();
        if (!std.math.isFinite(alpha) or !std.math.isFinite(beta) or !std.math.isFinite(mach_value))
            return error.NonFiniteQuery;
        const ia = try bracket(self.alpha_rad, alpha);
        const ib = try bracket(self.beta_rad, beta);
        const im = try bracket(self.mach, mach_value);
        var result = Six{};
        var da: usize = 0;
        while (da < 2) : (da += 1) {
            var db: usize = 0;
            while (db < 2) : (db += 1) {
                var dm: usize = 0;
                while (dm < 2) : (dm += 1) {
                    const a_index = if (da == 0) ia.low else ia.high;
                    const b_index = if (db == 0) ib.low else ib.high;
                    const m_index = if (dm == 0) im.low else im.high;
                    const wa = if (da == 0) 1.0 - ia.fraction else ia.fraction;
                    const wb = if (db == 0) 1.0 - ib.fraction else ib.fraction;
                    const wm = if (dm == 0) 1.0 - im.fraction else im.fraction;
                    result = result.add(self.values[self.index(a_index, b_index, m_index)].scale(wa * wb * wm));
                }
            }
        }
        return result;
    }

    fn index(self: Grid3, alpha_index: usize, beta_index: usize, mach_index: usize) usize {
        return (alpha_index * self.beta_rad.len + beta_index) * self.mach.len + mach_index;
    }
};

const Bracket = struct { low: usize, high: usize, fraction: f64 };

fn validateAxis(axis: []const f64) Error!void {
    if (axis.len == 0) return error.EmptyAxis;
    for (axis, 0..) |value, i| {
        if (!std.math.isFinite(value)) return error.NonFiniteGrid;
        if (i > 0 and !(value > axis[i - 1])) return error.AxisNotStrictlyIncreasing;
    }
}

fn bracket(axis: []const f64, query: f64) Error!Bracket {
    if (query < axis[0] or query > axis[axis.len - 1]) return error.OutsideEnvelope;
    if (axis.len == 1) return .{ .low = 0, .high = 0, .fraction = 0.0 };
    if (query == axis[axis.len - 1])
        return .{ .low = axis.len - 2, .high = axis.len - 1, .fraction = 1.0 };
    var low: usize = 0;
    var high: usize = axis.len - 1;
    while (high - low > 1) {
        const middle = low + (high - low) / 2;
        if (query < axis[middle]) high = middle else low = middle;
    }
    return .{ .low = low, .high = high, .fraction = (query - axis[low]) / (axis[high] - axis[low]) };
}

pub const Model = struct {
    grid: Grid3,
    reference_alpha_rad: f64 = 0.0,
    reference_beta_rad: f64 = 0.0,
    derivatives: Derivatives = .{},

    pub fn evaluate(
        self: Model,
        air: airdata.State,
        controls: Controls,
        rates_body_radps: Vec3,
        span_m: f64,
        chord_m: f64,
    ) Error!Six {
        var output = try self.grid.evaluate(air.alpha_rad, air.beta_rad, air.mach);
        const p_hat = rates_body_radps.x * span_m / (2.0 * air.speed_mps);
        const q_hat = rates_body_radps.y * chord_m / (2.0 * air.speed_mps);
        const r_hat = rates_body_radps.z * span_m / (2.0 * air.speed_mps);
        output = output
            .add(self.derivatives.alpha.scale(air.alpha_rad - self.reference_alpha_rad))
            .add(self.derivatives.beta.scale(air.beta_rad - self.reference_beta_rad))
            .add(self.derivatives.aileron.scale(controls.aileron_rad))
            .add(self.derivatives.elevator.scale(controls.elevator_rad))
            .add(self.derivatives.rudder.scale(controls.rudder_rad))
            .add(self.derivatives.flap.scale(controls.flap_rad))
            .add(self.derivatives.p_hat.scale(p_hat))
            .add(self.derivatives.q_hat.scale(q_hat))
            .add(self.derivatives.r_hat.scale(r_hat));
        return output;
    }
};

test "synthetic trilinear table interpolates and refuses stall envelope" {
    const alpha = [_]f64{ -0.2, 0.2 };
    const beta = [_]f64{ -0.1, 0.1 };
    const mach = [_]f64{ 0.1, 0.3 };
    var values: [8]Six = undefined;
    var n: usize = 0;
    for (alpha) |a| for (beta) |b| for (mach) |m| {
        values[n] = .{ .cz = -4.0 * a, .cy = -b, .cx = -m };
        n += 1;
    };
    const grid = Grid3{ .alpha_rad = &alpha, .beta_rad = &beta, .mach = &mach, .values = &values };
    try grid.validate();
    const value = try grid.evaluate(0.0, 0.0, 0.2);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), value.cz, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, -0.2), value.cx, 1e-14);
    try std.testing.expectError(error.OutsideEnvelope, grid.evaluate(0.21, 0.0, 0.2));
}

test "synthetic lateral controls and rates preserve expected signs" {
    const axis = [_]f64{0.0};
    const values = [_]Six{.{}};
    const model = Model{
        .grid = .{ .alpha_rad = &axis, .beta_rad = &axis, .mach = &axis, .values = &values },
        .derivatives = .{
            .aileron = .{ .cl = 0.2 },
            .rudder = .{ .cn = -0.3 },
            .p_hat = .{ .cl = -0.5 },
        },
    };
    const value = try model.evaluate(.{
        .velocity_body_mps = .{ .x = 20.0, .y = 0.0, .z = 0.0 },
        .speed_mps = 20.0,
        .dynamic_pressure_pa = 100.0,
        .alpha_rad = 0.0,
        .beta_rad = 0.0,
        .mach = 0.0,
        .reynolds = 1.0,
    }, .{ .aileron_rad = 0.1, .rudder_rad = 0.1 }, .{ .x = 0.4, .y = 0.0, .z = 0.0 }, 2.0, 1.0);
    try std.testing.expect(value.cl < 0.02);
    try std.testing.expect(value.cn < 0.0);
}
