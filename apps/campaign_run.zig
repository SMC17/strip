//! Campaign runner: `strip campaign run <campaign.toml>`
const std = @import("std");
const strip = @import("strip");

const output_dir = "campaign.evidence";

const Campaign = struct {
    schema: []const u8,
    id: []const u8,
    question: []const u8,
    monte_carlo_runs: u32,
};

fn trimValue(raw: []const u8) []const u8 {
    var start: usize = 0;
    while (start < raw.len and (raw[start] == ' ' or raw[start] == '\t')) start += 1;
    var end = raw.len;
    while (end > start and (raw[end - 1] == ' ' or raw[end - 1] == '\t' or raw[end - 1] == '\r')) end -= 1;
    if (start < end and raw[start] == '"' and raw[end - 1] == '"') {
        start += 1;
        end -= 1;
    }
    return raw[start..end];
}

fn parseU32(value: []const u8) !u32 {
    return std.fmt.parseInt(u32, value, 10);
}

fn parseCampaignToml(bytes: []const u8) !Campaign {
    var campaign: Campaign = .{
        .schema = "",
        .id = "",
        .question = "",
        .monte_carlo_runs = 0,
    };
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = trimValue(line[0..eq]);
        const value = trimValue(line[eq + 1 ..]);
        if (std.mem.eql(u8, key, "schema")) campaign.schema = value else if (std.mem.eql(u8, key, "id")) campaign.id = value else if (std.mem.eql(u8, key, "question")) campaign.question = value else if (std.mem.eql(u8, key, "monte_carlo_runs")) campaign.monte_carlo_runs = try parseU32(value);
    }
    if (!std.mem.eql(u8, campaign.schema, "strip.campaign.v0") or campaign.id.len == 0)
        return error.InvalidCampaign;
    return campaign;
}

fn writeBundleArtifact(io: std.Io, name: []const u8, data: []const u8) !void {
    const path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ output_dir, name });
    defer std.heap.page_allocator.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

fn lcgSeed(seed: u64) u64 {
    return seed *% 6364136223846793005 +% 1;
}

fn runCap(campaign: Campaign, environ: *std.process.Environ.Map) u32 {
    if (environ.get("STRIP_CAMPAIGN_RUN_ALL")) |_| return campaign.monte_carlo_runs;
    const verify_cap: u32 = 64;
    return @min(campaign.monte_carlo_runs, verify_cap);
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse return 1;
    const campaign_path = it.next() orelse return 1;
    if (!std.mem.eql(u8, sub, "run")) return 1;

    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, campaign_path, allocator, .limited(64 * 1024));
    defer allocator.free(bytes);
    const campaign = try parseCampaignToml(bytes);

    const context = try strip.evidence.Context.init(.preliminary_design);
    const altitude = try strip.units.GeopotentialAltitude.init(500.0);
    const atmosphere = try strip.atmosphere.evaluateResult(context, altitude);

    const runs_executed = runCap(campaign, init.environ_map);
    var aggregate: strip.monte_carlo.Aggregate = .{};
    var seed: u64 = 42;
    var runs_json = std.ArrayList(u8).empty;
    defer runs_json.deinit(allocator);
    try runs_json.appendSlice(allocator, "[\n");

    var i: u32 = 0;
    while (i < runs_executed) : (i += 1) {
        seed = lcgSeed(seed);
        const wind: f64 = 0.5 + @as(f64, @floatFromInt(seed % 1000)) / 100.0;
        const link_loss_at: f64 = if (seed % 3 == 0) @as(f64, 2.5) else @as(f64, 3.0);
        const simulation = try strip.uas.simulation.run(.{
            .duration_s = 6.0,
            .step_s = 0.02,
            .seed = seed,
            .wind_force_north_n = wind,
            .link_loss_at_s = link_loss_at,
        });
        var identity_hex: [64]u8 = undefined;
        const failed = simulation.final_decision.action == .land_at_designated_site;
        try aggregate.add(simulation.maximum_north_displacement_m, failed);
        if (i > 0) try runs_json.appendSlice(allocator, ",\n");
        const run_line = try std.fmt.allocPrint(
            allocator,
            "{{\"run\":{d},\"seed\":{d},\"action\":\"{s}\",\"max_north_m\":{d:.12},\"scenario_sha256\":\"{s}\",\"failed\":{}}}",
            .{
                i,
                seed,
                @tagName(simulation.final_decision.action),
                simulation.maximum_north_displacement_m,
                simulation.scenario_identity.formatHex(&identity_hex),
                failed,
            },
        );
        defer allocator.free(run_line);
        try runs_json.appendSlice(allocator, run_line);
    }
    try runs_json.appendSlice(allocator, "\n]\n");

    const summary_json = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"strip.campaign.summary.v0\",\"campaign_id\":\"{s}\",\"monte_carlo_runs\":{d},\"runs_executed\":{d},\"deterministic_seed\":42,\"failure_rate\":{d:.12},\"mean_max_north_m\":{d:.12},\"minimum_max_north_m\":{d:.12},\"maximum_max_north_m\":{d:.12}}}\n",
        .{
            campaign.id,
            campaign.monte_carlo_runs,
            runs_executed,
            aggregate.failureRate() orelse 0.0,
            aggregate.mean,
            aggregate.minimum,
            aggregate.maximum,
        },
    );
    defer allocator.free(summary_json);

    var runs_digest_raw: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(runs_json.items, &runs_digest_raw, .{});
    var summary_digest_raw: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(summary_json, &summary_digest_raw, .{});
    const alphabet = "0123456789abcdef";
    var runs_hex: [64]u8 = undefined;
    var summary_hex: [64]u8 = undefined;
    for (runs_digest_raw, 0..) |byte, index| {
        runs_hex[index * 2] = alphabet[byte >> 4];
        runs_hex[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    for (summary_digest_raw, 0..) |byte, index| {
        summary_hex[index * 2] = alphabet[byte >> 4];
        summary_hex[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    var bundle_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    bundle_hasher.update(&runs_hex);
    bundle_hasher.update(&summary_hex);
    var bundle_raw: [32]u8 = undefined;
    bundle_hasher.final(&bundle_raw);
    var bundle_hex: [64]u8 = undefined;
    for (bundle_raw, 0..) |byte, index| {
        bundle_hex[index * 2] = alphabet[byte >> 4];
        bundle_hex[index * 2 + 1] = alphabet[byte & 0x0f];
    }

    const qualification = try strip.flight_test.qualification.evaluateFromFixtures(allocator, init.io);
    const key_pair = try strip.serialization.signing.resolveKeyPair(init.environ_map);
    const signature = try strip.serialization.signing.signDigestHex(key_pair, &bundle_hex);
    var signature_json_buf: [512]u8 = undefined;
    const signature_json = try signature.formatJson(&signature_json_buf);

    const manifest_json = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"strip.campaign.bundle.v1\",\"campaign_id\":\"{s}\",\"question\":\"{s}\",\"output_dir\":\"{s}\",\"monte_carlo_runs\":{d},\"runs_executed\":{d},\"atmosphere_model\":\"{s}\",\"atmosphere_authoritative\":{},\"uas_fixture\":\"strip.uas.contingency-simulation\",\"deterministic_seed\":42,\"bundle_digest\":\"sha256:{s}\",\"artifact_digests\":{{\"runs\":\"sha256:{s}\",\"summary\":\"sha256:{s}\"}},\"signature\":{s},\"tier_ladder\":{{\"software_only\":\"{s}\",\"hardware_in_loop\":\"{s}\",\"flight_test\":\"{s}\"}},\"qualification_tier\":\"{s}\",\"operational_qualification_claimed\":false,\"status\":\"bundle_emitted\"}}\n",
        .{
            campaign.id,
            campaign.question,
            output_dir,
            campaign.monte_carlo_runs,
            runs_executed,
            strip.atmosphere.manifest.id,
            atmosphere.isAuthoritative(),
            &bundle_hex,
            &runs_hex,
            &summary_hex,
            signature_json,
            @tagName(qualification.tier_ladder.software_only),
            @tagName(qualification.tier_ladder.hardware_in_loop),
            @tagName(qualification.tier_ladder.flight_test),
            @tagName(qualification.tier),
        },
    );
    defer allocator.free(manifest_json);
    try strip.serialization.signing.verifyDigestHex(signature, &bundle_hex);

    try std.Io.Dir.cwd().createDirPath(init.io, output_dir);
    try writeBundleArtifact(init.io, "campaign.toml", bytes);
    try writeBundleArtifact(init.io, "runs.json", runs_json.items);
    try writeBundleArtifact(init.io, "summary.json", summary_json);
    try writeBundleArtifact(init.io, "manifest.json", manifest_json);

    var buffer: [8192]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(manifest_json);
    return 0;
}
