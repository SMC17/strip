const std = @import("std");
const strip = @import("strip");

fn writeUsage(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: strip atmosphere <geopotential-altitude-m> [intended-use]
        \\Intended use: education | research | preliminary_design | simulation_training
        \\
    );
}

fn writeInvalidInput(writer: *std.Io.Writer, intended_use: strip.evidence.IntendedUse) !void {
    try writer.print(
        "{{\"schema\":\"strip.result.atmosphere.v0\",\"context\":{{\"intended_use\":\"{s}\"}},\"validity\":{{\"status\":\"invalid_input\"}},\"result\":null}}\n",
        .{@tagName(intended_use)},
    );
}

fn writeEvaluation(
    writer: *std.Io.Writer,
    evaluation: strip.atmosphere.Evaluation,
    intended_use: strip.evidence.IntendedUse,
) !void {
    const model = strip.atmosphere.manifest;
    try writer.print(
        "{{\"schema\":\"strip.result.atmosphere.v0\",\"context\":{{\"intended_use\":\"{s}\"}},\"input\":{{\"geopotential_altitude\":{{\"value\":{d},\"unit\":\"m\"}}}},\"model\":{{\"id\":\"{s}\",\"version\":\"{s}\",\"proof_level\":\"{s}\",\"source\":\"{s}\"}},\"validity\":{{\"status\":\"{s}\",\"envelope\":{{\"min\":{d},\"max\":{d},\"unit\":\"{s}\"}}}},\"result\":",
        .{
            @tagName(intended_use),
            evaluation.altitude.meters,
            model.id,
            model.version,
            @tagName(model.proof_level),
            model.source,
            @tagName(evaluation.validity),
            model.valid_min,
            model.valid_max,
            model.valid_unit,
        },
    );

    if (evaluation.state) |state| {
        try writer.print(
            "{{\"temperature\":{{\"value\":{d},\"unit\":\"K\"}},\"pressure\":{{\"value\":{d},\"unit\":\"Pa\"}},\"density\":{{\"value\":{d},\"unit\":\"kg/m^3\"}},\"speed_of_sound\":{{\"value\":{d},\"unit\":\"m/s\"}}}}}}\n",
            .{
                state.temperature.kelvin,
                state.pressure.pascals,
                state.density.kilograms_per_cubic_meter,
                state.speed_of_sound.meters_per_second,
            },
        );
    } else {
        try writer.writeAll("null}\n");
    }
}

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args: std.ArrayList([]const u8) = .empty;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    while (it.next()) |arg| try args.append(allocator, arg);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    if (args.items.len < 3 or args.items.len > 4 or !std.mem.eql(u8, args.items[1], "atmosphere")) {
        try writeUsage(stdout);
        return 1;
    }

    const intended_use = if (args.items.len == 4)
        std.meta.stringToEnum(strip.evidence.IntendedUse, args.items[3]) orelse {
            try writeUsage(stdout);
            return 1;
        }
    else
        strip.evidence.IntendedUse.research;

    const altitude_value = std.fmt.parseFloat(f64, args.items[2]) catch {
        try writeInvalidInput(stdout, intended_use);
        return 2;
    };
    const altitude = strip.units.GeopotentialAltitude.init(altitude_value) catch {
        try writeInvalidInput(stdout, intended_use);
        return 2;
    };
    const evaluation = strip.atmosphere.evaluate(altitude);
    try writeEvaluation(stdout, evaluation, intended_use);
    return if (evaluation.validity == .valid) 0 else 2;
}
