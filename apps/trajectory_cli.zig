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
            \\  strip-trajectory selftest|audit|frontier|receipt|hil-stream|verdict-attach [--unix] [--serial DEVICE] [--path PATH] [--expect-fail] [--out DIR] [--id EXP] [--result R]
            \\  strip-trajectory router status [--intent ask|plan|agent|research|validation|hil|long_horizon]
            \\  strip-trajectory router --live [--intent ...] "<prompt>"
            \\
        , .{});
        return 2;
    };

    var path: []const u8 = "fixtures/trajectory/reference-uas-atmosphere.jsonl";
    var expect_fail = false;
    var out_dir: []const u8 = "trajectory.evidence";
    var unix = false;
    var serial_device: ?[]const u8 = null;
    var intent_text: []const u8 = "research";
    var live = false;
    var prompt: ?[]const u8 = null;
    var exp_id: ?[]const u8 = null;
    var verdict_result: []const u8 = "confirmed";
    var receipt_path: []const u8 = "trajectory.evidence/receipt.json";
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--path")) {
            path = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--expect-fail")) {
            expect_fail = true;
        } else if (std.mem.eql(u8, arg, "--out")) {
            out_dir = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--unix")) {
            unix = true;
        } else if (std.mem.eql(u8, arg, "--serial")) {
            serial_device = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--intent")) {
            intent_text = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--live")) {
            live = true;
        } else if (std.mem.eql(u8, arg, "--id")) {
            exp_id = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--result")) {
            verdict_result = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--receipt")) {
            receipt_path = it.next() orelse return 2;
        } else if (arg.len > 0 and arg[0] != '-') {
            prompt = arg;
        } else return 2;
    }

    const parseIntent = struct {
        fn go(text: []const u8) !strip.trajectory.router.Intent {
            inline for (std.meta.fields(strip.trajectory.router.Intent)) |field| {
                if (std.mem.eql(u8, text, field.name)) return @field(strip.trajectory.router.Intent, field.name);
            }
            return error.UnknownIntent;
        }
    }.go;

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
            "{{\"schema\":\"strip.trajectory.frontier.v1\",\"counterfactual_passed\":{},\"fault_lab_passed\":{},\"aerospace_passed\":{},\"causal_support_edges\":{d},\"receipt_sealed\":{},\"memory_classes\":{d},\"scheduler_ready\":{d},\"router_passed\":{},\"workers_passed\":{},\"analogy_passed\":{},\"world_model_passed\":{},\"hil_stream_passed\":{},\"hil_events\":{d},\"passed\":{},\"operational_qualification_claimed\":false,\"limits\":[\"Live OpenRouter/Gemini only via router --live; never from verify\",\"Worker fabric in-process with JSONL assignment persist\",\"Analogy is MAC/FAC feature overlap; EmbeddingLane stub not wired\",\"World-model 1-D ID loop plus rigid-body free-fall residual\",\"HIL JSONL from in-process, threaded unix daemon, and --serial DEVICE (hardware optional)\"]}}\n",
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
        if (unix and serial_device != null) {
            std.debug.print("hil-stream: use --unix or --serial DEVICE, not both\n", .{});
            return 2;
        }
        const result = if (serial_device) |device|
            try strip.trajectory.hil_stream.streamSerial(allocator, init.io, device, 50_000_000)
        else if (unix)
            try strip.trajectory.hil_stream.streamUnix(allocator, init.io, 50_000_000)
        else
            try strip.trajectory.hil_stream.streamToJsonl(allocator, 50_000_000);
        defer allocator.free(result.jsonl_owned);
        try std.Io.Dir.cwd().createDirPath(init.io, out_dir);
        const out_name: []const u8 = if (serial_device != null)
            "hil-serial-stream.jsonl"
        else if (unix)
            "hil-unix-stream.jsonl"
        else
            "hil-stream.jsonl";
        var path_buf: [512]u8 = undefined;
        const out_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ out_dir, out_name });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = result.jsonl_owned });
        var buffer: [768]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
        const writer = &file_writer.interface;
        defer writer.flush() catch {};
        try writer.print(
            "{{\"schema\":\"strip.trajectory.hil-stream.v0\",\"out\":\"{s}\",\"unix\":{},\"serial\":{f},\"events_emitted\":{d},\"hil_passed\":{},\"fold_passed\":{},\"jsonl_bytes\":{d},\"passed\":{},\"operational_qualification_claimed\":false}}\n",
            .{
                out_path,
                unix,
                std.json.fmt(serial_device, .{}),
                result.report.events_emitted,
                result.report.hil_passed,
                result.report.fold_passed,
                result.report.jsonl_bytes,
                result.report.passed,
            },
        );
        return if (result.report.passed) 0 else 1;
    }
    if (std.mem.eql(u8, sub, "router")) {
        const intent = parseIntent(intent_text) catch return 2;
        if (live) {
            const p = prompt orelse {
                std.debug.print("router --live requires a prompt string\n", .{});
                return 2;
            };
            const got = try strip.trajectory.router_live.dispatchLive(init.io, allocator, init.environ_map, intent, p);
            defer {
                allocator.free(got.digest_owned);
                allocator.free(got.preview_owned);
                allocator.free(got.body_owned);
            }
            const json = try strip.trajectory.router_live.formatLiveJson(allocator, got.report);
            defer allocator.free(json);
            var buffer: [4096]u8 = undefined;
            var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
            const writer = &file_writer.interface;
            defer writer.flush() catch {};
            try writer.writeAll(json);
            const ok = if (got.report.http_status) |s| s >= 200 and s < 300 else false;
            return if (ok) 0 else 1;
        }
        const report = try strip.trajectory.router_live.status(init.io, allocator, init.environ_map, intent);
        const json = try strip.trajectory.router_live.formatLiveJson(allocator, report);
        defer allocator.free(json);
        var buffer: [2048]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
        const writer = &file_writer.interface;
        defer writer.flush() catch {};
        try writer.writeAll(json);
        return 0;
    }
    if (std.mem.eql(u8, sub, "verdict-attach")) {
        const id = exp_id orelse {
            std.debug.print("verdict-attach requires --id exp-…\n", .{});
            return 2;
        };
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, receipt_path, allocator, .limited(256 * 1024));
        defer allocator.free(bytes);
        const digest = extractJsonString(bytes, "content_sha256") orelse return error.ReceiptMissingDigest;
        const schema = extractJsonString(bytes, "schema") orelse "strip.trajectory.receipt.v0";
        const abs = try std.Io.Dir.cwd().realPathFileAlloc(init.io, receipt_path, allocator);
        defer allocator.free(abs);
        const evidence = try std.fmt.allocPrint(
            allocator,
            "receipt_path={s} content_sha256={s} schema={s}",
            .{ abs, digest, schema },
        );
        defer allocator.free(evidence);

        var child = try std.process.spawn(init.io, .{
            .argv = &.{ "stax-experiment", "verdict", "--id", id, "--result", verdict_result, "--evidence", evidence },
            .stdin = .ignore,
        });
        const term = try child.wait(init.io);
        const code: u8 = switch (term) {
            .exited => |c| @intCast(c),
            else => 1,
        };
        var buffer: [1024]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
        const writer = &file_writer.interface;
        defer writer.flush() catch {};
        try writer.print(
            "{{\"schema\":\"strip.trajectory.verdict-attach.v0\",\"exp_id\":\"{s}\",\"result\":\"{s}\",\"receipt\":\"{s}\",\"evidence\":{f},\"exit\":{d},\"operational_qualification_claimed\":false}}\n",
            .{ id, verdict_result, abs, std.json.fmt(evidence, .{}), code },
        );
        return code;
    }
    return 2;
}

fn extractJsonString(bytes: []const u8, key: []const u8) ?[]const u8 {
    var key_buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&key_buf, "\"{s}\":\"", .{key}) catch return null;
    const start = std.mem.indexOf(u8, bytes, needle) orelse return null;
    const from = start + needle.len;
    const end = std.mem.indexOfScalarPos(u8, bytes, from, '"') orelse return null;
    return bytes[from..end];
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
