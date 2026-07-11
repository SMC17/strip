//! `strip-hil-bench` — physical HIL protocol: local, Unix-socket daemon, serial.

const std = @import("std");
const strip = @import("strip");

fn printReport(init: std.process.Init, result: anytype) !void {
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
}

fn usage() void {
    std.debug.print(
        \\usage:
        \\  strip-hil-bench local
        \\  strip-hil-bench selftest-unix
        \\  strip-hil-bench serve --unix <path> [--once]
        \\  strip-hil-bench run --unix <path>
        \\  strip-hil-bench serve --serial <device> [--once]
        \\  strip-hil-bench run --serial <device>
        \\
    , .{});
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const cmd = it.next() orelse "local";

    const deadline_ns: u64 = 50_000_000;
    if (std.mem.eql(u8, cmd, "local")) {
        const result = try strip.flight_test.hil_bench.runLocalProgression(allocator, deadline_ns);
        defer {
            allocator.free(result.records);
            allocator.free(result.samples_owned);
        }
        try printReport(init, result);
        return if (result.report.passed) 0 else 1;
    }
    if (std.mem.eql(u8, cmd, "selftest-unix")) {
        const result = try strip.flight_test.hil_bench.selftestUnix(init.io, allocator, deadline_ns);
        defer {
            allocator.free(result.records);
            allocator.free(result.samples_owned);
        }
        try printReport(init, result);
        return if (result.report.passed) 0 else 1;
    }
    if (std.mem.eql(u8, cmd, "serve")) {
        var path: ?[]const u8 = null;
        var serial = false;
        var once = false;
        while (it.next()) |arg| {
            if (std.mem.eql(u8, arg, "--unix")) {
                path = it.next() orelse return 2;
                serial = false;
            } else if (std.mem.eql(u8, arg, "--serial")) {
                path = it.next() orelse return 2;
                serial = true;
            } else if (std.mem.eql(u8, arg, "--once")) {
                once = true;
            } else return 2;
        }
        const p = path orelse {
            usage();
            return 2;
        };
        if (serial) try strip.flight_test.hil_bench.serveSerial(init.io, p, once) else try strip.flight_test.hil_bench.serveUnix(init.io, p, once);
        return 0;
    }
    if (std.mem.eql(u8, cmd, "run")) {
        var path: ?[]const u8 = null;
        var serial = false;
        while (it.next()) |arg| {
            if (std.mem.eql(u8, arg, "--unix")) {
                path = it.next() orelse return 2;
                serial = false;
            } else if (std.mem.eql(u8, arg, "--serial")) {
                path = it.next() orelse return 2;
                serial = true;
            } else return 2;
        }
        const p = path orelse {
            usage();
            return 2;
        };
        const result = if (serial)
            try strip.flight_test.hil_bench.runSerial(init.io, allocator, p, deadline_ns)
        else
            try strip.flight_test.hil_bench.runUnix(init.io, allocator, p, deadline_ns);
        defer {
            allocator.free(result.records);
            allocator.free(result.samples_owned);
        }
        try printReport(init, result);
        return if (result.report.passed) 0 else 1;
    }
    usage();
    return 2;
}
