//! `strip-hil-bench run` — exercise the physical HIL bench protocol and emit a report.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    const result = try strip.flight_test.hil_bench.runLocalProgression(allocator, 50_000_000);
    defer {
        allocator.free(result.records);
        allocator.free(result.samples_owned);
    }

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"{s}\",\"backend\":\"{s}\",\"transport\":\"{s}\",\"deadline_ns\":{d},\"actuator_sensor_completed\":{},\"passed\":{},\"stages\":{d}}}\n",
        .{
            result.report.schema,
            result.report.backend,
            result.report.transport,
            result.report.deadline_ns,
            result.report.actuator_sensor_completed,
            result.report.passed,
            result.records.len,
        },
    );
    return if (result.report.passed) 0 else 1;
}
