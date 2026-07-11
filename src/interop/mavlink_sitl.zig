//! In-process MAVLink v1 HEARTBEAT loopback with clock reconcile + fault inject.
//!
//! This is a PX4-SITL *protocol* stand-in: framing, checksum, clock anchors, and
//! deliberate faults. It does not launch a PX4 binary and does not claim HIL/ops
//! qualification. When `px4-sitl` / `px4_sitl` is on PATH, `probePx4Binary` reports
//! presence only.

const std = @import("std");
const mavlink = @import("mavlink.zig");
const clock = @import("../flight_test/clock.zig");

pub const heartbeat_msg_id: u8 = 0;
/// MAVLink common.xml HEARTBEAT crc_extra.
pub const heartbeat_crc_extra: u8 = 50;

pub const Heartbeat = struct {
    type: u8 = 2, // MAV_TYPE_QUADROTOR
    autopilot: u8 = 12, // MAV_AUTOPILOT_PX4
    base_mode: u8 = 0,
    custom_mode: u32 = 0,
    system_status: u8 = 3, // MAV_STATE_STANDBY
    mavlink_version: u8 = 3,

    pub fn encodePayload(self: Heartbeat, out: *[9]u8) void {
        out[0] = self.type;
        out[1] = self.autopilot;
        out[2] = self.base_mode;
        std.mem.writeInt(u32, out[3..7], self.custom_mode, .little);
        out[7] = self.system_status;
        out[8] = self.mavlink_version;
    }

    pub fn decodePayload(payload: []const u8) !Heartbeat {
        if (payload.len != 9) return error.InvalidHeartbeatPayload;
        return .{
            .type = payload[0],
            .autopilot = payload[1],
            .base_mode = payload[2],
            .custom_mode = std.mem.readInt(u32, payload[3..7], .little),
            .system_status = payload[7],
            .mavlink_version = payload[8],
        };
    }
};

pub const FaultMode = enum {
    none,
    drop,
    corrupt_crc,
    clock_skew,
};

pub const LoopbackResult = struct {
    frames_sent: usize,
    frames_received: usize,
    frames_dropped: usize,
    checksum_failures: usize,
    clock_rms_error_ns: f64,
    clock_drift_ppm: f64,
    heartbeat_ok: bool,
    fault_mode: FaultMode,
    px4_binary_present: bool,
};

pub fn probePx4Binary(io: std.Io, allocator: std.mem.Allocator) bool {
    _ = allocator;
    const paths = [_][]const u8{
        "/usr/bin/px4",
        "/usr/local/bin/px4",
        "/usr/bin/px4-sitl",
        "/usr/local/bin/px4-sitl",
    };
    for (paths) |p| {
        var file = std.Io.Dir.cwd().openFile(io, p, .{}) catch continue;
        file.close(io);
        return true;
    }
    return false;
}

pub fn runLoopback(
    allocator: std.mem.Allocator,
    io: std.Io,
    fault: FaultMode,
    frame_count: usize,
) !LoopbackResult {
    _ = allocator;
    _ = io;

    var hb = Heartbeat{};
    var payload: [9]u8 = undefined;
    hb.encodePayload(&payload);

    var sent: usize = 0;
    var received: usize = 0;
    var dropped: usize = 0;
    var crc_fail: usize = 0;
    var anchors: [16]clock.Anchor = undefined;
    var anchor_count: usize = 0;
    var heartbeat_ok = true;

    const skew_ns: i128 = if (fault == .clock_skew) 25_000 else 0;

    var seq: u8 = 0;
    var i: usize = 0;
    while (i < frame_count) : (i += 1) {
        const message = try mavlink.Message.init(.{
            .sequence = seq,
            .system_id = 1,
            .component_id = 1,
            .message_id = heartbeat_msg_id,
        }, &payload);
        seq +%= 1;
        sent += 1;

        if (fault == .drop and i % 3 == 1) {
            dropped += 1;
            continue;
        }

        var frame_buf: [mavlink.max_frame_len]u8 = undefined;
        const frame_len = try mavlink.encode(&message, heartbeat_crc_extra, &frame_buf);
        if (fault == .corrupt_crc and i % 4 == 2) {
            frame_buf[frame_len - 1] ^= 0xff;
        }

        const decoded = mavlink.decode(frame_buf[0..frame_len], heartbeat_crc_extra) catch |err| {
            if (err == error.ChecksumMismatch) {
                crc_fail += 1;
                continue;
            }
            return err;
        };
        received += 1;

        const decoded_hb = Heartbeat.decodePayload(decoded.payloadSlice()) catch {
            heartbeat_ok = false;
            continue;
        };
        if (decoded_hb.type != hb.type or decoded_hb.autopilot != hb.autopilot) heartbeat_ok = false;

        if (anchor_count < anchors.len) {
            const mono: i128 = @as(i128, @intCast(i)) * 1_000_000_000;
            anchors[anchor_count] = .{
                .source_ns = mono,
                .reference_ns = 1_700_000_000_000_000_000 + mono + skew_ns,
                .quality = .valid,
            };
            anchor_count += 1;
        }
    }

    var rms: f64 = 0;
    var drift: f64 = 0;
    if (anchor_count >= 2) {
        const affine = try clock.reconcile(.monotonic, .utc, anchors[0..anchor_count]);
        rms = affine.rms_error_ns;
        drift = affine.driftPpm();
    }

    return .{
        .frames_sent = sent,
        .frames_received = received,
        .frames_dropped = dropped,
        .checksum_failures = crc_fail,
        .clock_rms_error_ns = rms,
        .clock_drift_ppm = drift,
        .heartbeat_ok = heartbeat_ok,
        .fault_mode = fault,
        .px4_binary_present = false,
    };
}

pub fn selftest(allocator: std.mem.Allocator, io: std.Io) !LoopbackResult {
    const clean = try runLoopback(allocator, io, .none, 8);
    if (!clean.heartbeat_ok or clean.frames_received != 8 or clean.checksum_failures != 0)
        return error.MavlinkSitlCleanFailed;
    if (clean.clock_rms_error_ns > 1.0) return error.MavlinkSitlClockFailed;

    const drop = try runLoopback(allocator, io, .drop, 9);
    if (drop.frames_dropped == 0 or drop.frames_received >= drop.frames_sent)
        return error.MavlinkSitlDropFailed;

    const corrupt = try runLoopback(allocator, io, .corrupt_crc, 8);
    if (corrupt.checksum_failures == 0) return error.MavlinkSitlCorruptFailed;

    const skew = try runLoopback(allocator, io, .clock_skew, 8);
    // Constant skew is absorbed into affine intercept; RMS stays near zero.
    if (skew.clock_rms_error_ns > 1.0) return error.MavlinkSitlSkewFailed;

    _ = probePx4Binary(io, allocator);
    return clean;
}

test "heartbeat encode/decode roundtrip" {
    var hb = Heartbeat{ .custom_mode = 0x11223344 };
    var payload: [9]u8 = undefined;
    hb.encodePayload(&payload);
    const back = try Heartbeat.decodePayload(&payload);
    try std.testing.expectEqual(hb.custom_mode, back.custom_mode);

    const message = try mavlink.Message.init(.{
        .sequence = 1,
        .system_id = 1,
        .component_id = 1,
        .message_id = heartbeat_msg_id,
    }, &payload);
    var frame: [mavlink.max_frame_len]u8 = undefined;
    const n = try mavlink.encode(&message, heartbeat_crc_extra, &frame);
    const decoded = try mavlink.decode(frame[0..n], heartbeat_crc_extra);
    try std.testing.expectEqual(@as(u8, heartbeat_msg_id), decoded.header.message_id);
}

test "loopback selftest passes offline" {
    _ = try selftest(std.testing.allocator, std.testing.io);
}
