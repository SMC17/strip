//! Development atmosphere shim for out-of-process protocol testing.
//! This is not JSBSim and must not be cited as cross-implementation evidence.

const std = @import("std");
const strip = @import("strip");

const protocol_schema = "strip.jsbsim-protocol.v0";

pub fn main(init: std.process.Init) !u8 {
    var stdin_buffer: [512]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(init.io, &stdin_buffer);
    const line = try stdin.interface.takeDelimiterInclusive('\n');
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return 2;

    var parsed = try std.json.parseFromSlice(Request, init.gpa, trimmed, .{
        .ignore_unknown_fields = true,
        .max_value_len = 128,
    });
    defer parsed.deinit();

    if (!std.mem.eql(u8, parsed.value.schema, protocol_schema)) return 2;
    if (parsed.value.query != .atmosphere) return 2;

    const state = try strip.weather.atmosphere.evaluate(parsed.value.geopotential_altitude_m);

    var out_buffer: [512]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &out_buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"{s}\",\"backend\":\"development_shim\",\"temperature_k\":{d:.12},\"pressure_pa\":{d:.12},\"density_kg_m3\":{d:.12},\"speed_of_sound_mps\":{d:.12}}}\n",
        .{
            protocol_schema,
            state.temperature_k,
            state.pressure_pa,
            state.density_kg_m3,
            state.speed_of_sound_mps,
        },
    );
    return 0;
}

const Request = struct {
    schema: []const u8,
    query: enum { atmosphere },
    geopotential_altitude_m: f64,
};
