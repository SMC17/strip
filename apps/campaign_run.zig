//! Campaign runner skeleton: `strip campaign run <campaign.toml>`
const std = @import("std");
const strip = @import("strip");

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
        if (std.mem.eql(u8, key, "schema")) campaign.schema = value
        else if (std.mem.eql(u8, key, "id")) campaign.id = value
        else if (std.mem.eql(u8, key, "question")) campaign.question = value
        else if (std.mem.eql(u8, key, "monte_carlo_runs")) campaign.monte_carlo_runs = try parseU32(value);
    }
    if (!std.mem.eql(u8, campaign.schema, "strip.campaign.v0") or campaign.id.len == 0)
        return error.InvalidCampaign;
    return campaign;
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
    const runs_completed = @min(campaign.monte_carlo_runs, 8);
    var seed: u64 = 42;
    var i: u32 = 0;
    while (i < runs_completed) : (i += 1) {
        seed = seed *% 6364136223846793005 +% 1;
    }
    _ = atmosphere.isAuthoritative();

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.campaign.bundle.v0\",\"campaign_id\":\"{s}\",\"question\":\"{s}\",\"monte_carlo_runs\":{d},\"runs_completed\":{d},\"atmosphere_model\":\"{s}\",\"atmosphere_authoritative\":{},\"uas_fixture\":\"strip-uas-range\",\"deterministic_seed\":42,\"final_prng_state\":{d},\"operational_qualification_claimed\":false,\"status\":\"scaffold_passed\"}}\n",
        .{
            campaign.id,
            campaign.question,
            campaign.monte_carlo_runs,
            runs_completed,
            strip.atmosphere.manifest.id,
            atmosphere.isAuthoritative(),
            seed,
        },
    );
    return 0;
}
