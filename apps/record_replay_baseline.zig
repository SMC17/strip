//! Emit a pinned replay-manifest case for the current target triple.

const std = @import("std");
const strip = @import("strip");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !u8 {
    const fields = try strip.replay.constantAccelerationReplayFields();
    const target = strip.replay.currentTarget(builtin.mode);
    const case_id = try std.fmt.allocPrint(
        init.gpa,
        "constant-acceleration-{s}-{s}-{s}",
        .{ target.arch, target.os, @tagName(builtin.mode) },
    );
    defer init.gpa.free(case_id);

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try strip.replay.formatReplayBaselineJson(case_id, target, fields, writer);
    return 0;
}
