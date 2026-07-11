//! `strip-flight-seal build` — seal a flight evidence package with Ed25519.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        std.debug.print("usage: strip-flight-seal build [--out DIR]\n", .{});
        return 2;
    };
    if (!std.mem.eql(u8, sub, "build")) return 2;
    var out_dir: []const u8 = "flight.evidence";
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out")) {
            out_dir = it.next() orelse return 2;
        }
    }

    const telemetry_src = "fixtures/validation/flight-test/synthetic-telemetry.csv";
    const telemetry_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        telemetry_src,
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(telemetry_bytes);

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
        "{{\"schema\":\"strip.flight-test-evidence.v1\",\"package_id\":\"sealed-flight-package-001\",\"created_utc\":\"2026-07-11T04:30:00Z\",\"test_card_id\":\"fw-pitch-doublet-001\",\"configuration_id\":\"clean-light-cg-mid\",\"split_policy_id\":\"synthetic-split-001\",\"toolchain\":\"Zig 0.16; strip-flight-seal\",\"artifacts\":[{{\"relative_path\":\"telemetry/run.csv\",\"media_type\":\"text/csv\",\"bytes\":{d},\"sha256\":\"{s}\"}}],\"package_sha256\":\"{s}\",\"sealed\":true,\"operational_qualification_claimed\":false,\"limitations\":[\"Sealed package built from held-out telemetry bytes; not an operational clearance.\",\"flight_test tier may pass only when this package is loaded via STRIP_FLIGHT_PACKAGE.\"]}}\n",
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
        "{{\"schema\":\"strip.flight-seal.v1\",\"output_dir\":\"{s}\",\"package_sha256\":\"sha256:{s}\",\"sealed\":true,\"operational_qualification_claimed\":false}}\n",
        .{ out_dir, &package_digest },
    );
    return 0;
}
