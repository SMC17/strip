//! Development JSBSim protocol shim (atmosphere + fixed-wing fixture replay).
//! Not JSBSim — must not be cited as cross-implementation evidence.

const std = @import("std");
const strip = @import("strip");

const protocol_schema = "strip.jsbsim-protocol.v0";

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args: std.ArrayList([]const u8) = .empty;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    while (it.next()) |arg| try args.append(allocator, arg);

    const subcommand = if (args.items.len > 1) args.items[1] else "atmosphere";
    if (std.mem.eql(u8, subcommand, "fixed-wing")) return fixedWing(init);
    if (std.mem.eql(u8, subcommand, "atmosphere")) return atmosphere(init);
    return 2;
}

fn atmosphere(init: std.process.Init) !u8 {
    const parsed = try readRequest(AtmosphereRequest, init);
    if (parsed.value.query != .atmosphere) return 2;
    const state = try strip.weather.atmosphere.evaluate(parsed.value.geopotential_altitude_m);
    var out_buffer: [512]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &out_buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"{s}\",\"backend\":\"development_shim\",\"temperature_k\":{d:.12},\"pressure_pa\":{d:.12},\"density_kg_m3\":{d:.12},\"speed_of_sound_mps\":{d:.12}}}\n",
        .{ protocol_schema, state.temperature_k, state.pressure_pa, state.density_kg_m3, state.speed_of_sound_mps },
    );
    return 0;
}

fn fixedWing(init: std.process.Init) !u8 {
    const parsed = try readRequest(FixedWingRequest, init);
    if (parsed.value.query != .fixed_wing_integrate) return 2;
    _ = parsed.value;
    var out_buffer: [1024]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &out_buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"{s}\",\"backend\":\"development_shim\",\"query\":\"fixed_wing_integrate\",\"model\":\"f16\",\"steps\":50,\"altitude_m\":{d:.12},\"vt_mps\":{d:.12},\"alpha_deg\":{d:.12},\"theta_deg\":{d:.12},\"q_radps\":{d:.12},\"ax_mps2\":{d:.12},\"az_mps2\":{d:.12},\"qdot_radps2\":{d:.12}}}\n",
        .{
            protocol_schema,
            3049.526036222005,
            242.55685718545251,
            2.286899298340511,
            3.787082546980751,
            -0.04842600247627126,
            -1.912416979972653,
            -19.193011924045102,
            0.04931461155916598,
        },
    );
    return 0;
}

fn readRequest(comptime T: type, init: std.process.Init) !std.json.Parsed(T) {
    var stdin_buffer: [1024]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(init.io, &stdin_buffer);
    const line = try stdin.interface.takeDelimiterInclusive('\n');
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyRequest;
    const parsed = try std.json.parseFromSlice(T, init.gpa, trimmed, .{
        .ignore_unknown_fields = true,
        .max_value_len = 256,
    });
    if (!std.mem.eql(u8, parsed.value.schema, protocol_schema)) return error.InvalidSchema;
    return parsed;
}

const AtmosphereRequest = struct {
    schema: []const u8,
    query: enum { atmosphere },
    geopotential_altitude_m: f64,
};

const FixedWingRequest = struct {
    schema: []const u8,
    query: enum { fixed_wing_integrate },
    model: []const u8 = "f16",
    altitude_ft: f64 = 10000,
    vt_fps: f64 = 800,
    alpha_deg: f64 = 5,
    theta_deg: f64 = 5,
    steps: u32 = 50,
};
