//! World-model predict → execute → residual → update loop.
//!
//! Toy 1-D plant for trajectory governance demos. Not a vehicle dynamics twin.

const std = @import("std");

pub const State = struct {
    position: f64,
    velocity: f64,
};

pub const Action = struct {
    acceleration: f64,
    dt: f64,
};

pub const WorldModel = struct {
    accel_scale: f64 = 1.0,
    last_residual: f64 = 0,
    updates: u32 = 0,

    pub fn predict(self: WorldModel, state: State, action: Action) State {
        const a = action.acceleration * self.accel_scale;
        const v = state.velocity + a * action.dt;
        const p = state.position + state.velocity * action.dt + 0.5 * a * action.dt * action.dt;
        return .{ .position = p, .velocity = v };
    }

    pub fn executeTruth(state: State, action: Action, truth_scale: f64) State {
        const a = action.acceleration * truth_scale;
        const v = state.velocity + a * action.dt;
        const p = state.position + state.velocity * action.dt + 0.5 * a * action.dt * action.dt;
        return .{ .position = p, .velocity = v };
    }

    pub fn residual(predicted: State, observed: State) f64 {
        const dp = predicted.position - observed.position;
        const dv = predicted.velocity - observed.velocity;
        return @sqrt(dp * dp + dv * dv);
    }

    /// Gradient-free scale update from one-step residual on velocity.
    pub fn update(self: *WorldModel, predicted: State, observed: State, action: Action) void {
        const r = residual(predicted, observed);
        self.last_residual = r;
        if (action.acceleration != 0 and action.dt != 0) {
            const dv_err = observed.velocity - predicted.velocity;
            const scale_step = dv_err / (action.acceleration * action.dt);
            self.accel_scale += 0.5 * scale_step;
            if (self.accel_scale < 0.1) self.accel_scale = 0.1;
            if (self.accel_scale > 3.0) self.accel_scale = 3.0;
        }
        self.updates += 1;
    }
};

pub const LoopReport = struct {
    initial_residual: f64,
    final_residual: f64,
    updates: u32,
    final_scale: f64,
    passed: bool,
};

pub fn selftest() !LoopReport {
    var model: WorldModel = .{ .accel_scale = 1.0 };
    const truth_scale: f64 = 1.5;
    var state: State = .{ .position = 0, .velocity = 0 };
    const action: Action = .{ .acceleration = 2.0, .dt = 0.1 };

    const pred0 = model.predict(state, action);
    const obs0 = WorldModel.executeTruth(state, action, truth_scale);
    const r0 = WorldModel.residual(pred0, obs0);

    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        const pred = model.predict(state, action);
        const obs = WorldModel.executeTruth(state, action, truth_scale);
        model.update(pred, obs, action);
        state = obs;
    }

    const pred_f = model.predict(state, action);
    const obs_f = WorldModel.executeTruth(state, action, truth_scale);
    const r_f = WorldModel.residual(pred_f, obs_f);
    const passed = r_f < r0 * 0.25 and model.updates >= 8;
    if (!passed) return error.WorldModelDidNotImprove;
    return .{
        .initial_residual = r0,
        .final_residual = r_f,
        .updates = model.updates,
        .final_scale = model.accel_scale,
        .passed = passed,
    };
}

test "world model residual shrinks toward truth scale" {
    const report = try selftest();
    try std.testing.expect(report.passed);
    try std.testing.expect(report.final_residual < report.initial_residual);
}
