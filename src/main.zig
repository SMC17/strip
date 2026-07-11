const std = @import("std");
const strip = @import("strip");
const json = strip.serialization.canonical_json;

fn writeUsage(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: strip atmosphere <geopotential-altitude-m> [intended-use]
        \\Intended use: education | research | preliminary_design | simulation_training
        \\
    );
}

fn writeInvalidInput(writer: *std.Io.Writer, intended_use: strip.evidence.IntendedUse) !void {
    var root = try json.Object.begin(writer);
    try root.key("context");
    var context = try json.Object.begin(writer);
    try context.key("intended_use");
    try json.writeString(writer, @tagName(intended_use));
    try context.end();
    try root.key("result");
    try writer.writeAll("null");
    try root.key("schema");
    try json.writeString(writer, "strip.result.atmosphere.v0");
    try root.key("validity");
    var validity = try json.Object.begin(writer);
    try validity.key("status");
    try json.writeString(writer, "invalid_input");
    try validity.end();
    try root.end();
    try writer.writeByte('\n');
}

fn writeQuantity(writer: *std.Io.Writer, unit: []const u8, value: f64) !void {
    var quantity = try json.Object.begin(writer);
    try quantity.key("unit");
    try json.writeString(writer, unit);
    try quantity.key("value");
    try json.writeNumber(writer, value);
    try quantity.end();
}

fn writeEvaluation(
    writer: *std.Io.Writer,
    evaluation: strip.atmosphere.Evaluation,
    intended_use: strip.evidence.IntendedUse,
) !void {
    const model = evaluation.model;
    var root = try json.Object.begin(writer);
    try root.key("context");
    var context = try json.Object.begin(writer);
    try context.key("intended_use");
    try json.writeString(writer, @tagName(intended_use));
    try context.end();

    try root.key("input");
    var input = try json.Object.begin(writer);
    try input.key("geopotential_altitude");
    try writeQuantity(writer, "m", evaluation.altitude.meters);
    try input.end();

    try root.key("model");
    var model_json = try json.Object.begin(writer);
    try model_json.key("id");
    try json.writeString(writer, model.id);
    try model_json.key("proof_level");
    try json.writeString(writer, @tagName(model.proof_level));
    try model_json.key("source");
    try json.writeString(writer, model.source);
    try model_json.key("version");
    try json.writeString(writer, model.version);
    try model_json.end();

    try root.key("result");
    if (evaluation.state) |state| {
        var result = try json.Object.begin(writer);
        try result.key("density");
        try writeQuantity(writer, "kg/m^3", state.density.kilograms_per_cubic_meter);
        try result.key("pressure");
        try writeQuantity(writer, "Pa", state.pressure.pascals);
        try result.key("speed_of_sound");
        try writeQuantity(writer, "m/s", state.speed_of_sound.meters_per_second);
        try result.key("temperature");
        try writeQuantity(writer, "K", state.temperature.kelvin);
        try result.end();
    } else {
        try writer.writeAll("null");
    }

    try root.key("schema");
    try json.writeString(writer, "strip.result.atmosphere.v0");
    try root.key("validity");
    var validity = try json.Object.begin(writer);
    try validity.key("envelope");
    var envelope = try json.Object.begin(writer);
    try envelope.key("max");
    try json.writeNumber(writer, evaluation.envelope.maximum);
    try envelope.key("min");
    try json.writeNumber(writer, evaluation.envelope.minimum);
    try envelope.key("unit");
    try json.writeString(writer, evaluation.envelope.unit);
    try envelope.end();
    try validity.key("status");
    try json.writeString(writer, @tagName(evaluation.validity));
    try validity.end();
    try root.end();
    try writer.writeByte('\n');
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
