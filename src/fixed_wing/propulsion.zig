//! Bounded simple propulsive thrust and fuel-flow model.

const std = @import("std");

pub const Error = error{ InvalidParameter, InvalidThrottle, OutsideEnvelope };

pub const Model = struct {
    static_thrust_n: f64,
    zero_thrust_speed_mps: f64,
    idle_fuel_kgps: f64 = 0.0,
    full_fuel_kgps: f64,

    pub fn evaluate(self: Model, throttle: f64, airspeed_mps: f64) Error!Output {
        const parameters = [_]f64{
            self.static_thrust_n, self.zero_thrust_speed_mps,
            self.idle_fuel_kgps,  self.full_fuel_kgps,
        };
        for (parameters) |value| if (!std.math.isFinite(value) or value < 0.0) return error.InvalidParameter;
        if (!(self.zero_thrust_speed_mps > 0.0) or self.full_fuel_kgps < self.idle_fuel_kgps)
            return error.InvalidParameter;
        if (!std.math.isFinite(throttle) or throttle < 0.0 or throttle > 1.0) return error.InvalidThrottle;
        if (!std.math.isFinite(airspeed_mps) or airspeed_mps < 0.0 or airspeed_mps > self.zero_thrust_speed_mps)
            return error.OutsideEnvelope;
        const advance_factor = 1.0 - airspeed_mps / self.zero_thrust_speed_mps;
        return .{
            .thrust_n = throttle * self.static_thrust_n * advance_factor,
            .fuel_flow_kgps = self.idle_fuel_kgps +
                throttle * (self.full_fuel_kgps - self.idle_fuel_kgps),
        };
    }
};

pub const Output = struct {
    thrust_n: f64,
    fuel_flow_kgps: f64,
};

test "simple propulsion is monotone and bounded" {
    const model = Model{
        .static_thrust_n = 100.0,
        .zero_thrust_speed_mps = 100.0,
        .idle_fuel_kgps = 0.01,
        .full_fuel_kgps = 0.11,
    };
    const half = try model.evaluate(0.5, 20.0);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), half.thrust_n, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.06), half.fuel_flow_kgps, 1e-12);
    try std.testing.expectError(error.InvalidThrottle, model.evaluate(1.01, 20.0));
}
