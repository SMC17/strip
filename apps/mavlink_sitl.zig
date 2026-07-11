//! `strip-mavlink-sitl` — MAVLink HEARTBEAT loopback + UDP echo + optional live SITL.

const std = @import("std");
const strip = @import("strip");

fn usage() void {
    std.debug.print(
        \\usage:
        \\  strip-mavlink-sitl selftest
        \\  strip-mavlink-sitl udp-echo
        \\  strip-mavlink-sitl udp --host 127.0.0.1 --port 14280
        \\
    , .{});
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        usage();
        return 2;
    };

    if (std.mem.eql(u8, sub, "selftest")) {
        const result = try strip.interop.mavlink_sitl.selftest(allocator, init.io);
        const px4 = strip.interop.mavlink_sitl.probePx4Binary(init.io, allocator);
        const udp = try strip.interop.mavlink_sitl.runUdpEcho(init.io, allocator);
        var buffer: [1536]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
        const writer = &file_writer.interface;
        defer writer.flush() catch {};
        try writer.print(
            "{{\"schema\":\"strip.mavlink-sitl.v0\",\"mode\":\"loopback+udp_echo\",\"frames_sent\":{d},\"frames_received\":{d},\"heartbeat_ok\":{},\"udp_echo_ok\":{},\"clock_rms_error_ns\":{d:.3},\"clock_drift_ppm\":{d:.6},\"fault_modes_exercised\":[\"none\",\"drop\",\"corrupt_crc\",\"clock_skew\"],\"px4_binary_present\":{},\"operational_qualification_claimed\":false,\"limitations\":[\"In-process MAVLink v1 HEARTBEAT loopback + localhost UDP echo on 28570/28571.\",\"Live px4-sitl (MAVLink v2): strip-mavlink-sitl udp --host 127.0.0.1 (probes 13030/14280/14580/18570)\"]}}\n",
            .{
                result.frames_sent,
                result.frames_received,
                result.heartbeat_ok,
                udp.heartbeat_ok,
                result.clock_rms_error_ns,
                result.clock_drift_ppm,
                px4,
            },
        );
        return if (result.heartbeat_ok and udp.heartbeat_ok) 0 else 1;
    }

    if (std.mem.eql(u8, sub, "udp-echo")) {
        const udp = try strip.interop.mavlink_sitl.runUdpEcho(init.io, allocator);
        return emitUdp(init, udp);
    }

    if (std.mem.eql(u8, sub, "udp")) {
        var host: []const u8 = "127.0.0.1";
        var port: u16 = 0; // 0 = probe sitl_probe_ports
        while (it.next()) |arg| {
            if (std.mem.eql(u8, arg, "--host")) {
                host = it.next() orelse return 2;
            } else if (std.mem.eql(u8, arg, "--port")) {
                const p = it.next() orelse return 2;
                port = try std.fmt.parseInt(u16, p, 10);
            } else return 2;
        }
        const udp = try strip.interop.mavlink_sitl.runUdpSitl(init.io, allocator, host, port);
        return emitUdp(init, udp);
    }

    usage();
    return 2;
}

fn emitUdp(init: std.process.Init, udp: strip.interop.mavlink_sitl.UdpResult) !u8 {
    var buffer: [1024]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.mavlink-sitl.v0\",\"mode\":\"{s}\",\"frames_sent\":{d},\"frames_received\":{d},\"heartbeat_ok\":{},\"host\":\"{s}\",\"port\":{d},\"px4_binary_present\":{},\"live_attempted\":{},\"live_connected\":{},\"operational_qualification_claimed\":false}}\n",
        .{
            udp.mode,
            udp.frames_sent,
            udp.frames_received,
            udp.heartbeat_ok,
            udp.host,
            udp.port,
            udp.px4_binary_present,
            udp.live_attempted,
            udp.live_connected,
        },
    );
    if (udp.live_attempted) return if (udp.live_connected) 0 else 1;
    return if (udp.heartbeat_ok) 0 else 1;
}
