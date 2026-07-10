//! Promote a recorded replay baseline into the cross-target manifest.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(init.io, &stdin_buffer);
    const line = try stdin.interface.takeDelimiterInclusive('\n');
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return 2;

    const Baseline = struct {
        schema: []const u8,
        id: []const u8,
        target: strip.replay.TargetTriple,
        status: []const u8,
        fingerprint_hex: []const u8,
        fields: []const f64,
    };

    var baseline = try std.json.parseFromSlice(Baseline, allocator, trimmed, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    defer baseline.deinit();
    if (!std.mem.eql(u8, baseline.value.schema, "strip.replay-baseline.v0")) return 2;

    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fixtures/validation/replay/rk4-cross-target.json",
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(manifest_bytes);
    var manifest = try strip.replay.parseManifest(allocator, manifest_bytes);
    defer manifest.deinit();

    var cases = try std.ArrayList(strip.replay.ReplayCase).initCapacity(allocator, manifest.value.cases.len);
    defer cases.deinit(allocator);
    var replaced = false;
    for (manifest.value.cases) |replay_case| {
        if (std.mem.eql(u8, replay_case.target.arch, baseline.value.target.arch) and
            std.mem.eql(u8, replay_case.target.os, baseline.value.target.os) and
            std.mem.eql(u8, replay_case.target.optimize, baseline.value.target.optimize))
        {
            const id = try allocator.dupe(u8, baseline.value.id);
            const fp = try allocator.dupe(u8, baseline.value.fingerprint_hex);
            const fields = try allocator.alloc(f64, baseline.value.fields.len);
            @memcpy(fields, baseline.value.fields);
            try cases.append(allocator, .{
                .id = id,
                .target = baseline.value.target,
                .status = "pinned",
                .fingerprint_hex = fp,
                .fields = fields,
            });
            replaced = true;
        } else {
            const id = try allocator.dupe(u8, replay_case.id);
            const fp = try allocator.dupe(u8, replay_case.fingerprint_hex);
            const fields = try allocator.alloc(f64, replay_case.fields.len);
            @memcpy(fields, replay_case.fields);
            try cases.append(allocator, .{
                .id = id,
                .target = replay_case.target,
                .status = replay_case.status,
                .fingerprint_hex = fp,
                .fields = fields,
            });
        }
    }
    if (!replaced) return 2;

    var out_buffer: [8192]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &out_buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll("{\"schema\":\"strip.replay-manifest.v1\",\"id\":\"");
    try writer.writeAll(manifest.value.id);
    try writer.writeAll("\",\"proof_scope\":\"");
    try writer.writeAll(manifest.value.proof_scope);
    try writer.writeAll("\",\"cases\":[");
    for (cases.items, 0..) |replay_case, index| {
        if (index > 0) try writer.writeAll(",");
        try strip.replay.formatReplayCaseJson(replay_case.id, replay_case.target, replay_case.fields, writer);
    }
    try writer.writeAll("]}\n");
    return 0;
}
