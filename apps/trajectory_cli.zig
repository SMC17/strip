//! `strip-trajectory` — fold, audit, frontier pack, receipt, HIL stream.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        std.debug.print(
            \\usage: strip-trajectory selftest|audit|frontier|receipt|hil-stream [--path PATH] [--expect-fail] [--out DIR]
            \\
        , .{});
        return 2;
    };

    var path: []const u8 = "fixtures/trajectory/reference-uas-atmosphere.jsonl";
    var expect_fail = false;
    var out_dir: []const u8 = "trajectory.evidence";
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--path")) {
            path = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--expect-fail")) {
            expect_fail = true;
        } else if (std.mem.eql(u8, arg, "--out")) {
            out_dir = it.next() orelse return 2;
        } else return 2;
    }

    if (std.mem.eql(u8, sub, "selftest")) {
        const report = try strip.trajectory.jsonl.selftest(allocator, init.io, path);
        return emitAudit(init.io, "selftest", path, report, expect_fail);
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
        return emitAudit(init.io, "audit", path, report, expect_fail);
    }
    if (std.mem.eql(u8, sub, "frontier")) {
        const report = try strip.trajectory.frontier.run(allocator, init.io);
        var buffer: [1536]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
        const writer = &file_writer.interface;
        defer writer.flush() catch {};
        try writer.print(
            "{{\"schema\":\"strip.trajectory.frontier.v1\",\"counterfactual_passed\":{},\"fault_lab_passed\":{},\"aerospace_passed\":{},\"causal_support_edges\":{d},\"receipt_sealed\":{},\"memory_classes\":{d},\"scheduler_ready\":{d},\"router_passed\":{},\"workers_passed\":{},\"analogy_passed\":{},\"world_model_passed\":{},\"hil_stream_passed\":{},\"hil_events\":{d},\"passed\":{},\"operational_qualification_claimed\":false,\"limits\":[\"Router does not call external model APIs in verify\",\"Worker fabric is in-process only\",\"Analogy is structural feature overlap not embeddings\",\"World-model is a 1-D toy plant\",\"HIL stream uses in-process bench protocol\"]}}\n",
            .{
                report.counterfactual_passed,
                report.fault_lab_passed,
                report.aerospace_passed,
                report.causal_support_edges,
                report.receipt_sealed,
                report.memory_classes,
                report.scheduler_ready,
                report.router_passed,
                report.workers_passed,
                report.analogy_passed,
                report.world_model_passed,
                report.hil_stream_passed,
                report.hil_events,
                report.passed,
            },
        );
        return if (report.passed) 0 else 1;
    }
    if (std.mem.eql(u8, sub, "receipt")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(256 * 1024));
        defer allocator.free(bytes);
        var folded = try strip.trajectory.jsonl.foldJsonl(allocator, bytes);
        defer strip.trajectory.jsonl.freeFold(allocator, folded);
        var edge_buf: [64]strip.trajectory.causal.Edge = undefined;
        const key = try strip.serialization.signing.resolveKeyPair(init.environ_map);
        const rec = try strip.trajectory.receipt.buildReceipt(allocator, &folded.store, "reference-uas-atmosphere", key, &edge_buf);
        defer allocator.free(rec.signature_json);
        const json = try strip.trajectory.receipt.formatReceiptJson(allocator, rec);
        defer allocator.free(json);

        try std.Io.Dir.cwd().createDirPath(init.io, out_dir);
        const traj_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(256 * 1024));
        defer allocator.free(traj_bytes);
        var traj_path_buf: [512]u8 = undefined;
        const traj_path = try std.fmt.bufPrint(&traj_path_buf, "{s}/trajectory.jsonl", .{out_dir});
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = traj_path, .data = traj_bytes });
        var rec_path_buf: [512]u8 = undefined;
        const rec_path = try std.fmt.bufPrint(&rec_path_buf, "{s}/receipt.json", .{out_dir});
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = rec_path, .data = json });

        var buffer: [768]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
        const writer = &file_writer.interface;
        defer writer.flush() catch {};
        try writer.writeAll(json);
        return 0;
    }
    if (std.mem.eql(u8, sub, "hil-stream")) {
        const result = try strip.trajectory.hil_stream.streamToJsonl(allocator, 50_000_000);
        defer allocator.free(result.jsonl_owned);
        try std.Io.Dir.cwd().createDirPath(init.io, out_dir);
        var path_buf: [512]u8 = undefined;
        const out_path = try std.fmt.bufPrint(&path_buf, "{s}/hil-stream.jsonl", .{out_dir});
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = result.jsonl_owned });
        var buffer: [768]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
        const writer = &file_writer.interface;
        defer writer.flush() catch {};
        try writer.print(
            "{{\"schema\":\"strip.trajectory.hil-stream.v0\",\"out\":\"{s}\",\"events_emitted\":{d},\"hil_passed\":{},\"fold_passed\":{},\"jsonl_bytes\":{d},\"passed\":{},\"operational_qualification_claimed\":false}}\n",
            .{
                out_path,
                result.report.events_emitted,
                result.report.hil_passed,
                result.report.fold_passed,
                result.report.jsonl_bytes,
                result.report.passed,
            },
        );
        return if (result.report.passed) 0 else 1;
    }
    return 2;
}

fn emitAudit(
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
