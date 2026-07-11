//! `strip-model-passport issue` — issue a credibility passport for a model id.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        std.debug.print("usage: strip-model-passport issue <model-id>\n", .{});
        return 2;
    };
    if (!std.mem.eql(u8, sub, "issue")) return 2;
    const model_id = it.next() orelse return 2;

    const model = if (std.mem.eql(u8, model_id, strip.atmosphere.manifest.id))
        strip.atmosphere.manifest
    else if (std.mem.eql(u8, model_id, strip.multirotor.propulsion.manifest.id))
        strip.multirotor.propulsion.manifest
    else if (std.mem.eql(u8, model_id, strip.energy.battery.manifest.id))
        strip.energy.battery.manifest
    else if (std.mem.eql(u8, model_id, strip.sensor.imu.manifest.id))
        strip.sensor.imu.manifest
    else if (std.mem.eql(u8, model_id, strip.sensor.gnss.manifest.id))
        strip.sensor.gnss.manifest
    else if (std.mem.eql(u8, model_id, strip.analysis.trim.manifest.id))
        strip.analysis.trim.manifest
    else if (std.mem.eql(u8, model_id, strip.contact.landing_gear.manifest.id))
        strip.contact.landing_gear.manifest
    else if (std.mem.eql(u8, model_id, strip.control.pid.manifest.id))
        strip.control.pid.manifest
    else {
        std.debug.print("unknown model id: {s}\n", .{model_id});
        return 1;
    };

    const passport = strip.validation.model_passport.issueFromManifest(
        model,
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        &.{ .preliminary_design, .simulation_training },
        &.{
            "operational flight clearance",
            "certification evidence without independent review",
        },
    );
    const json = try strip.validation.model_passport.formatJson(allocator, passport);
    defer allocator.free(json);

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(json);
    return 0;
}
