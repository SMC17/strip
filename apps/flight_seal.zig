//! `strip-flight-seal build` — seal a flight evidence package with Ed25519.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        std.debug.print("usage: strip-flight-seal build [--out DIR] [--telemetry PATH] [--require-holdout]\n", .{});
        return 2;
    };
    if (!std.mem.eql(u8, sub, "build")) return 2;
    var out_dir: []const u8 = "flight.evidence";
    var telemetry_src: []const u8 = "fixtures/validation/flight-test/px4-ulog-export.csv";
    var require_holdout = false;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out")) {
            out_dir = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--telemetry")) {
            telemetry_src = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--require-holdout")) {
            require_holdout = true;
        } else return 2;
    }

    const telemetry_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        telemetry_src,
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(telemetry_bytes);

    var holdout_passed = false;
    var holdout_coverage: f64 = 0;
    var residual_sigma: f64 = 0;
    if (require_holdout) {
        const campaign_bytes = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            "fixtures/validation/flight-test/synthetic-campaign.json",
            allocator,
            .limited(512 * 1024),
        );
        defer allocator.free(campaign_bytes);
        var campaign_parsed = try strip.flight_test.campaign.parseCampaign(allocator, campaign_bytes);
        defer campaign_parsed.deinit();
        const rows = try strip.flight_test.telemetry_csv.loadCsv(allocator, telemetry_bytes);
        defer {
            for (rows) |row| allocator.free(row.channel);
            allocator.free(rows);
        }
        const report = try strip.uncertainty.campaign_calibration.evaluateSyntheticCampaign(
            campaign_parsed.value,
            rows,
        );
        holdout_passed = report.holdout_passed;
        holdout_coverage = report.holdout_coverage_one_sigma;
        residual_sigma = report.residual_standard_deviation;
        if (!holdout_passed) {
            std.debug.print("holdout residual coverage failed: {d}\n", .{holdout_coverage});
            return 1;
        }
    }

    var telem_digest: [64]u8 = undefined;
    strip.flight_test.flight_seal.digestHexOf(telemetry_bytes, &telem_digest);

    var package_material: [256]u8 = undefined;
    const material = try std.fmt.bufPrint(
        &package_material,
        "telemetry/run.csv:{s}:{d}",
        .{ &telem_digest, telemetry_bytes.len },
    );
    var package_digest: [64]u8 = undefined;
    strip.flight_test.flight_seal.digestHexOf(material, &package_digest);

    const manifest_json = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"strip.flight-test-evidence.v1\",\"package_id\":\"px4-ulog-export-package-001\",\"created_utc\":\"2026-07-11T05:30:00Z\",\"test_card_id\":\"fw-pitch-doublet-001\",\"configuration_id\":\"clean-light-cg-mid\",\"split_policy_id\":\"synthetic-split-001\",\"toolchain\":\"Zig 0.16; strip-flight-seal; tools/ulog_to_strip_csv.py\",\"artifacts\":[{{\"relative_path\":\"telemetry/run.csv\",\"media_type\":\"text/csv\",\"bytes\":{d},\"sha256\":\"{s}\"}}],\"package_sha256\":\"{s}\",\"sealed\":true,\"operational_qualification_claimed\":false,\"limitations\":[\"Telemetry derived from public PX4 ULog sample (px4_ulog_export); NOT operator-owned aircraft clearance.\",\"Replace with operator flight/ulog before claiming Month-6 operational flight validation.\",\"flight_test tier may pass only when this package is loaded via STRIP_FLIGHT_PACKAGE.\"]}}\n",
        .{ telemetry_bytes.len, &telem_digest, &package_digest },
    );
    defer allocator.free(manifest_json);

    var manifest_parsed = try strip.flight_test.evidence.parseManifest(allocator, manifest_json);
    defer manifest_parsed.deinit();
    const key_pair = try strip.serialization.signing.resolveKeyPair(init.environ_map);
    const signature = try strip.flight_test.flight_seal.sealManifest(key_pair, manifest_parsed.value);
    var sig_buf: [512]u8 = undefined;
    const attestation = try signature.formatJson(&sig_buf);

    try std.Io.Dir.cwd().createDirPath(init.io, out_dir);
    var telem_dir_buf: [512]u8 = undefined;
    const telem_dir = try std.fmt.bufPrint(&telem_dir_buf, "{s}/telemetry", .{out_dir});
    try std.Io.Dir.cwd().createDirPath(init.io, telem_dir);
    var telem_path_buf: [512]u8 = undefined;
    const telem_path = try std.fmt.bufPrint(&telem_path_buf, "{s}/telemetry/run.csv", .{out_dir});
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = telem_path, .data = telemetry_bytes });
    var man_path_buf: [512]u8 = undefined;
    const man_path = try std.fmt.bufPrint(&man_path_buf, "{s}/manifest.json", .{out_dir});
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = man_path, .data = manifest_json });
    var att_path_buf: [512]u8 = undefined;
    const att_path = try std.fmt.bufPrint(&att_path_buf, "{s}/attestation.json", .{out_dir});
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = att_path, .data = attestation });

    var buffer: [2048]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.flight-seal.v1\",\"output_dir\":\"{s}\",\"telemetry_src\":\"{s}\",\"package_sha256\":\"sha256:{s}\",\"holdout_required\":{},\"holdout_passed\":{},\"holdout_coverage_1sigma\":{d:.6},\"residual_sigma\":{d:.6},\"sealed\":true,\"operational_qualification_claimed\":false}}\n",
        .{ out_dir, telemetry_src, &package_digest, require_holdout, holdout_passed, holdout_coverage, residual_sigma },
    );
    return 0;
}
