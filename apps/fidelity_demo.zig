//! Coupled fixed-wing, multirotor, runtime, and atmosphere integration fixture.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const atmosphere = try strip.weather.atmosphere.evaluate(0.0);

    const alpha_axis = [_]f64{ -0.2, 0.2 };
    const beta_axis = [_]f64{ -0.1, 0.1 };
    const mach_axis = [_]f64{ 0.0, 0.4 };
    var coeffs: [8]strip.fixed_wing.coefficients.Six = undefined;
    var index: usize = 0;
    for (alpha_axis) |alpha| for (beta_axis) |beta| for (mach_axis) |_| {
        coeffs[index] = .{ .cx = -0.03, .cy = -beta, .cz = -3.0 * alpha, .cm = -0.4 * alpha };
        index += 1;
    };
    const provider = strip.fixed_wing.provider.Provider{
        .geometry = .{ .area_m2 = 1.0, .span_m = 2.0, .chord_m = 0.5 },
        .aerodynamics = .{ .grid = .{
            .alpha_rad = &alpha_axis,
            .beta_rad = &beta_axis,
            .mach = &mach_axis,
            .values = &coeffs,
        } },
        .engine = .{
            .static_thrust_n = 80.0,
            .zero_thrust_speed_mps = 90.0,
            .full_fuel_kgps = 0.008,
        },
    };
    const wing_eval = try provider.evaluate(
        .{
            .velocity_world_mps = .{ .x = 25.0, .y = 0.0, .z = 0.0 },
            .body_to_world = strip.fixed_wing.types.Quaternion.identity,
            .angular_velocity_body_radps = strip.fixed_wing.types.Vec3.zero,
        },
        .{
            .density_kg_m3 = atmosphere.density_kg_m3,
            .speed_of_sound_mps = atmosphere.speed_of_sound_mps,
            .temperature_k = atmosphere.temperature_k,
        },
        .{ .throttle = 0.3 },
    );

    const model = strip.multirotor.propulsion.CoefficientModel{
        .diameter_m = 0.5,
        .thrust_coefficient = 0.12,
        .torque_coefficient = 0.015,
        .max_omega_radps = 9000.0 * (2.0 * std.math.pi) / 60.0,
    };
    const rotor_eval = try model.evaluate(atmosphere.density_kg_m3, 4200.0 * (2.0 * std.math.pi) / 60.0);

    const Scheduler = strip.runtime.scheduler.Scheduler(4, 16);
    var scheduler = try Scheduler.init(1_000_000, 4);
    try scheduler.register(.{ .id = 1, .period_ticks = 1, .deadline_ns = 500_000 });
    try scheduler.register(.{ .id = 2, .period_ticks = 4, .deadline_ns = 2_000_000 });
    const advance = try scheduler.advance(4_000_000);

    var buffer: [2048]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.fidelity.demo.v0\",\"atmosphere_layer\":{d},\"fixed_wing_force_x_n\":{d:.6},\"rotor_thrust_n\":{d:.6},\"scheduler_dispatches\":{d},\"flight_qualification_claimed\":false}}\n",
        .{
            atmosphere.layer_index,
            wing_eval.wrench.force_world_n.x,
            rotor_eval.thrust_n,
            advance.emitted.len,
        },
    );
    return 0;
}
