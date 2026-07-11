//! `strip-mavlink-sitl selftest` — MAVLink HEARTBEAT loopback + fault inject (offline).

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        std.debug.print("usage: strip-mavlink-sitl selftest\n", .{});
        return 2;
    };
    if (!std.mem.eql(u8, sub, "selftest")) return 2;

    const result = try strip.interop.mavlink_sitl.selftest(allocator, init.io);
    const px4 = strip.interop.mavlink_sitl.probePx4Binary(init.io, allocator);

    var buffer: [1024]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.mavlink-sitl.v0\",\"mode\":\"loopback\",\"frames_sent\":{d},\"frames_received\":{d},\"heartbeat_ok\":{},\"clock_rms_error_ns\":{d:.3},\"clock_drift_ppm\":{d:.6},\"fault_modes_exercised\":[\"none\",\"drop\",\"corrupt_crc\",\"clock_skew\"],\"px4_binary_present\":{},\"operational_qualification_claimed\":false,\"limitations\":[\"In-process MAVLink v1 HEARTBEAT loopback; not a live PX4 SITL session.\",\"Replace with UDP link to px4-sitl before claiming hardware MAVLink evidence.\"]}}\n",
        .{
            result.frames_sent,
            result.frames_received,
            result.heartbeat_ok,
            result.clock_rms_error_ns,
            result.clock_drift_ppm,
            px4,
        },
    );
    return 0;
}
