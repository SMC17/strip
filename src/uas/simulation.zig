//! Deterministic multirotor point-mission composition.
//! This is a bounded simulation fixture, not an operational controller.

const std = @import("std");
const policy = @import("policy.zig");
const dynamics = @import("../dynamics/rigid_body.zig");
const math = @import("../dynamics/math.zig");
const mass_properties = @import("../vehicle/mass_properties.zig");
const gnss_model = @import("../sensor/gnss.zig");
const trace = @import("../trace/mod.zig");

pub const Scenario = struct {
    duration_s: f64 = 10.0,
    step_s: f64 = 0.02,
    seed: u64 = 1,
    wind_force_north_n: f64 = 0.0,
    geofence_radius_m: f64 = 50.0,
    link_loss_at_s: ?f64 = null,
    navigation_fault_at_s: ?f64 = null,

    pub fn validate(self: Scenario) error{InvalidScenario}!void {
        const values = [_]f64{
            self.duration_s,
            self.step_s,
            self.wind_force_north_n,
            self.geofence_radius_m,
        };
        for (values) |value| if (!std.math.isFinite(value)) return error.InvalidScenario;
        if (!(self.duration_s > 0.0) or !(self.step_s > 0.0) or
            self.step_s > self.duration_s or !(self.geofence_radius_m > 0.0))
            return error.InvalidScenario;
        if (self.link_loss_at_s) |time| {
            if (!std.math.isFinite(time) or time < 0.0 or time > self.duration_s)
                return error.InvalidScenario;
        }
        if (self.navigation_fault_at_s) |time| {
            if (!std.math.isFinite(time) or time < 0.0 or time > self.duration_s)
                return error.InvalidScenario;
        }
    }
};

pub const Result = struct {
    final_position_m: math.Vec3,
    final_velocity_mps: math.Vec3,
    maximum_north_displacement_m: f64,
    gnss_fix_count: u64,
    final_decision: policy.Decision,
    step_count: u64,
    scenario_identity: trace.ContentId,
};

fn scenarioIdentity(scenario: Scenario) trace.ContentId {
    var storage: [512]u8 = undefined;
    const link_loss = scenario.link_loss_at_s orelse -1.0;
    const navigation_fault = scenario.navigation_fault_at_s orelse -1.0;
    const bytes = std.fmt.bufPrint(
        &storage,
        "duration={d};step={d};seed={d};wind={d};geofence={d};link={d};nav={d}",
        .{
            scenario.duration_s,
            scenario.step_s,
            scenario.seed,
            scenario.wind_force_north_n,
            scenario.geofence_radius_m,
            link_loss,
            navigation_fault,
        },
    ) catch unreachable;
    return .hash(bytes);
}

pub fn run(scenario: Scenario) !Result {
    try scenario.validate();
    const properties = try mass_properties.MassProperties.init(
        2.0,
        math.Vec3.zero,
        .{ .xx = 0.08, .yy = 0.08, .zz = 0.12 },
    );
    var state = dynamics.State{
        .position_world_m = math.Vec3.zero,
        .velocity_world_mps = math.Vec3.zero,
        .body_to_world = math.Quaternion.identity,
        .angular_velocity_body_radps = math.Vec3.zero,
    };
    var gnss = try gnss_model.Gnss.init(.{
        .update_period_s = 0.2,
        .position_noise_std_m = 0.5,
        .velocity_noise_std_mps = 0.05,
    }, scenario.seed);

    const steps: u64 = @intFromFloat(@ceil(scenario.duration_s / scenario.step_s));
    var maximum_north: f64 = 0.0;
    var fix_count: u64 = 0;
    var final_decision = policy.decide(.{
        .link = .available,
        .fault = .none,
        .geofence = .inside,
        .designated_site_available = true,
    });

    for (0..steps) |index| {
        const time_s = @as(f64, @floatFromInt(index)) * scenario.step_s;
        const link: policy.LinkState = if (scenario.link_loss_at_s) |at|
            if (time_s >= at) .lost else .available
        else
            .available;
        const fault: policy.Fault = if (scenario.navigation_fault_at_s) |at|
            if (time_s >= at) .navigation_unreliable else .none
        else
            .none;
        const abs_north = @abs(state.position_world_m.x);
        const geofence: policy.GeofenceState = if (abs_north >= scenario.geofence_radius_m)
            .breached
        else if (abs_north >= 0.8 * scenario.geofence_radius_m)
            .predicted_breach
        else
            .inside;
        final_decision = policy.decide(.{
            .link = link,
            .fault = fault,
            .geofence = geofence,
            .designated_site_available = true,
        });

        var north_force = scenario.wind_force_north_n;
        if (final_decision.action == .return_to_home) {
            north_force += if (state.position_world_m.x >= 0.0) -2.0 else 2.0;
        } else if (final_decision.action == .hold) {
            north_force += -1.5 * state.velocity_world_mps.x;
        }
        state = try dynamics.rk4Step(
            state,
            properties,
            .{ .force_world_n = .{
                .x = north_force,
                .y = 0.0,
                .z = properties.mass_kg * 9.80665,
            } },
            .{ .x = 0.0, .y = 0.0, .z = -9.80665 },
            scenario.step_s,
        );
        maximum_north = @max(maximum_north, @abs(state.position_world_m.x));
        if (fault != .navigation_unreliable) {
            if (try gnss.sample(time_s, state.position_world_m, state.velocity_world_mps) != null)
                fix_count += 1;
        }
    }

    return .{
        .final_position_m = state.position_world_m,
        .final_velocity_mps = state.velocity_world_mps,
        .maximum_north_displacement_m = maximum_north,
        .gnss_fix_count = fix_count,
        .final_decision = final_decision,
        .step_count = steps,
        .scenario_identity = scenarioIdentity(scenario),
    };
}

test "nominal hover remains stationary" {
    const result = try run(.{ .duration_s = 2.0, .step_s = 0.02, .seed = 7 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.final_position_m.normSquared(), 1e-20);
    try std.testing.expectEqual(policy.Action.continue_mission, result.final_decision.action);
    try std.testing.expect(result.gnss_fix_count > 0);
}

test "same scenario replays exactly and changed input changes identity" {
    const scenario = Scenario{
        .duration_s = 4.0,
        .step_s = 0.02,
        .seed = 19,
        .wind_force_north_n = 1.0,
        .link_loss_at_s = 2.0,
    };
    const first = try run(scenario);
    const second = try run(scenario);
    try std.testing.expectEqualDeep(first, second);
    const changed = try run(.{
        .duration_s = scenario.duration_s,
        .step_s = scenario.step_s,
        .seed = scenario.seed + 1,
        .wind_force_north_n = scenario.wind_force_north_n,
        .link_loss_at_s = scenario.link_loss_at_s,
    });
    try std.testing.expect(!first.scenario_identity.eql(changed.scenario_identity));
}

test "loss of link invokes bounded return response" {
    const result = try run(.{
        .duration_s = 4.0,
        .step_s = 0.02,
        .wind_force_north_n = 1.0,
        .link_loss_at_s = 2.0,
    });
    try std.testing.expectEqual(policy.Action.return_to_home, result.final_decision.action);
    try std.testing.expect(result.maximum_north_displacement_m > 0.0);
}
