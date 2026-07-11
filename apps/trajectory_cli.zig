//! `strip-trajectory selftest|audit` — fold JSONL trajectories and audit claims.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        std.debug.print("usage: strip-trajectory selftest|audit [--path PATH] [--expect-fail]\n", .{});
        return 2;
    };

    var path: []const u8 = "fixtures/trajectory/reference-uas-atmosphere.jsonl";
    var expect_fail = false;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--path")) {
            path = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--expect-fail")) {
            expect_fail = true;
        } else return 2;
    }

    if (std.mem.eql(u8, sub, "selftest")) {
        const report = try strip.trajectory.jsonl.selftest(allocator, init.io, path);
        return emit(init.io, "selftest", path, report, expect_fail);
    }
    if (std.mem.eql(u8, sub, "audit")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(256 * 1024));
        defer allocator.free(bytes);
        var folded = strip.trajectory.jsonl.foldJsonl(allocator, bytes) catch |err| {
            if (expect_fail and err == error.ClaimUnsupported) {
                var buffer: [512]u8 = undefined;
                var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
                const writer = &file_writer.interface;
                defer writer.flush() catch {};
                try writer.print(
                    "{{\"schema\":\"strip.trajectory.audit.v0\",\"mode\":\"audit\",\"path\":\"{s}\",\"expect_fail\":true,\"claim_rejected\":true,\"passed\":true,\"operational_qualification_claimed\":false}}\n",
                    .{path},
                );
                return 0;
            }
            return err;
        };
        defer strip.trajectory.jsonl.freeFold(allocator, folded);
        const report = strip.trajectory.jsonl.auditReport(&folded.store);
        return emit(init.io, "audit", path, report, expect_fail);
    }
    return 2;
}

fn emit(
    io: std.Io,
    mode: []const u8,
    path: []const u8,
    report: strip.trajectory.jsonl.AuditReport,
    expect_fail: bool,
) !u8 {
    const ok = if (expect_fail) !report.passed else report.passed;
    var buffer: [1024]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.trajectory.audit.v0\",\"mode\":\"{s}\",\"path\":\"{s}\",\"events_folded\":{d},\"unique_deliveries\":{d},\"duplicate_deliveries\":{d},\"claims_supported\":{d},\"claims_unsupported\":{d},\"verifications_passed\":{d},\"verifications_failed\":{d},\"completed\":{},\"passed\":{},\"expect_fail\":{},\"operational_qualification_claimed\":false}}\n",
        .{
            mode,
            path,
            report.events_folded,
            report.unique_deliveries,
            report.duplicate_deliveries,
            report.claims_supported,
            report.claims_unsupported,
            report.verifications_passed,
            report.verifications_failed,
            report.completed,
            ok,
            expect_fail,
        },
    );
    return if (ok) 0 else 1;
}
