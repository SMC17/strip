//! Evidence compiler: `strip evidence build <program.toml>`
const std = @import("std");
const strip = @import("strip");

const output_dir = "program.evidence";

const Program = struct {
    schema: []const u8,
    id: []const u8,
    sources: []const u8,
    validation_case: []const u8,
    validation_report: []const u8,
    campaign: []const u8,
    assurance_fixture: []const u8,
    assurance_graph: []const u8,
    model_package: []const u8,
};

const AssuranceFixture = struct {
    schema: []const u8,
    claim: []const u8,
    requirement: []const u8,
};

const ModelPackage = struct {
    schema: []const u8,
    id: []const u8,
    version: []const u8,
    models: []const std.json.Value,
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

fn parseProgramToml(bytes: []const u8) !Program {
    var program: Program = .{
        .schema = "",
        .id = "",
        .sources = "",
        .validation_case = "",
        .validation_report = "",
        .campaign = "",
        .assurance_fixture = "",
        .assurance_graph = "",
        .model_package = "",
    };
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = trimValue(line[0..eq]);
        const value = trimValue(line[eq + 1 ..]);
        if (std.mem.eql(u8, key, "schema")) program.schema = value else if (std.mem.eql(u8, key, "id")) program.id = value else if (std.mem.eql(u8, key, "sources")) program.sources = value else if (std.mem.eql(u8, key, "validation_case")) program.validation_case = value else if (std.mem.eql(u8, key, "validation_report")) program.validation_report = value else if (std.mem.eql(u8, key, "campaign")) program.campaign = value else if (std.mem.eql(u8, key, "assurance_fixture")) program.assurance_fixture = value else if (std.mem.eql(u8, key, "assurance_graph")) program.assurance_graph = value else if (std.mem.eql(u8, key, "model_package")) program.model_package = value;
    }
    if (!std.mem.eql(u8, program.schema, "strip.program.v0") or program.id.len == 0)
        return error.InvalidProgram;
    if (program.assurance_graph.len == 0 or program.model_package.len == 0)
        return error.InvalidProgram;
    return program;
}

fn writeBundleArtifact(io: std.Io, name: []const u8, data: []const u8) !void {
    const path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ output_dir, name });
    defer std.heap.page_allocator.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

fn digestHex(bytes: []const u8) [64]u8 {
    var raw: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &raw, .{});
    const alphabet = "0123456789abcdef";
    var hex: [64]u8 = undefined;
    for (raw, 0..) |byte, index| {
        hex[index * 2] = alphabet[byte >> 4];
        hex[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return hex;
}

fn bundleDigest(artifact_digests: []const [64]u8) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (artifact_digests) |digest| hasher.update(&digest);
    const alphabet = "0123456789abcdef";
    var raw: [32]u8 = undefined;
    hasher.final(&raw);
    var hex: [64]u8 = undefined;
    for (raw, 0..) |byte, index| {
        hex[index * 2] = alphabet[byte >> 4];
        hex[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return hex;
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse return 1;
    const program_path = it.next() orelse return 1;
    if (!std.mem.eql(u8, sub, "build")) return 1;

    const program_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        program_path,
        allocator,
        .limited(64 * 1024),
    );
    defer allocator.free(program_bytes);
    const program = try parseProgramToml(program_bytes);

    const source_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, program.sources, allocator, .limited(512 * 1024));
    defer allocator.free(source_bytes);
    var sources = try strip.validation.source.parse(allocator, source_bytes);
    defer sources.deinit();
    for (sources.value.records) |record| try record.validateWithFilesystem(init.io);

    const case_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, program.validation_case, allocator, .limited(128 * 1024));
    defer allocator.free(case_bytes);
    var validation_case = try strip.validation.types.parseCase(allocator, case_bytes);
    defer validation_case.deinit();

    const report_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, program.validation_report, allocator, .limited(1024 * 1024));
    defer allocator.free(report_bytes);
    var report = try strip.validation.types.parseReport(allocator, report_bytes);
    defer report.deinit();

    const campaign_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, program.campaign, allocator, .limited(64 * 1024));
    defer allocator.free(campaign_bytes);

    const assurance_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, program.assurance_fixture, allocator, .limited(16 * 1024));
    defer allocator.free(assurance_bytes);
    var assurance_parsed = try std.json.parseFromSlice(AssuranceFixture, allocator, assurance_bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 256,
    });
    defer assurance_parsed.deinit();

    const graph_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, program.assurance_graph, allocator, .limited(64 * 1024));
    defer allocator.free(graph_bytes);
    var graph_doc = try strip.assurance.load.parseDocument(allocator, graph_bytes);
    defer graph_doc.deinit();
    var graph = try strip.assurance.load.loadGraph(arena_alloc, 16, 16, graph_doc.value);

    const model_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, program.model_package, allocator, .limited(256 * 1024));
    defer allocator.free(model_bytes);
    var model_package = try std.json.parseFromSlice(ModelPackage, allocator, model_bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    defer model_package.deinit();
    if (!std.mem.eql(u8, model_package.value.schema, "strip.model-package.v1"))
        return error.InvalidModelPackage;

    const validated = try strip.validation.join.validateReportAgainstCase(
        validation_case.value,
        report.value,
        sources.value,
    );

    const assurance_report = graph.inspect();
    const assurance_strength = graph.weakestDependency(assurance_parsed.value.claim) catch |err| switch (err) {
        else => return err,
    };
    const assurance_consistent = assurance_report.len == 0;

    const source_digest = digestHex(source_bytes);
    const case_digest = digestHex(case_bytes);
    const report_digest = digestHex(report_bytes);
    const campaign_digest = digestHex(campaign_bytes);
    const assurance_digest = digestHex(assurance_bytes);
    const graph_digest = digestHex(graph_bytes);
    const model_digest = digestHex(model_bytes);
    const artifact_digests = [_][64]u8{
        source_digest,
        case_digest,
        report_digest,
        campaign_digest,
        assurance_digest,
        graph_digest,
        model_digest,
    };
    const bundle_digest_hex = bundleDigest(&artifact_digests);
    const key_pair = try strip.serialization.signing.resolveKeyPair(init.environ_map);
    const signature = try strip.serialization.signing.signDigestHex(key_pair, &bundle_digest_hex);
    var signature_json_buf: [512]u8 = undefined;
    const signature_json = try signature.formatJson(&signature_json_buf);

    try std.Io.Dir.cwd().createDirPath(init.io, output_dir);
    try writeBundleArtifact(init.io, "sources.json", source_bytes);
    try writeBundleArtifact(init.io, "validation-case.json", case_bytes);
    try writeBundleArtifact(init.io, "validation-report.json", report_bytes);
    try writeBundleArtifact(init.io, "campaign.toml", campaign_bytes);
    try writeBundleArtifact(init.io, "assurance-fixture.json", assurance_bytes);
    try writeBundleArtifact(init.io, "assurance-graph.json", graph_bytes);
    try writeBundleArtifact(init.io, "model-package.json", model_bytes);

    const manifest_json = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"strip.evidence.bundle.v1\",\"program_id\":\"{s}\",\"output_dir\":\"{s}\",\"bundle_digest\":\"sha256:{s}\",\"execution_identity\":{{\"content_sha256\":\"sha256:{s}\",\"program_id\":\"{s}\"}},\"signature\":{s},\"artifact_digests\":{{\"sources\":\"sha256:{s}\",\"validation_case\":\"sha256:{s}\",\"validation_report\":\"sha256:{s}\",\"campaign\":\"sha256:{s}\",\"assurance_fixture\":\"sha256:{s}\",\"assurance_graph\":\"sha256:{s}\",\"model_package\":\"sha256:{s}\"}},\"source_count\":{d},\"model_count\":{d},\"case_joined\":{},\"expected_dimensions_complete\":{},\"source_ids_resolved\":{},\"report_status\":\"{s}\",\"assurance_claim\":\"{s}\",\"assurance_internally_consistent\":{},\"assurance_limiting_strength\":\"{s}\",\"assurance_diagnostic_count\":{d},\"operational_qualification_claimed\":false}}\n",
        .{
            program.id,
            output_dir,
            &bundle_digest_hex,
            &bundle_digest_hex,
            program.id,
            signature_json,
            &source_digest,
            &case_digest,
            &report_digest,
            &campaign_digest,
            &assurance_digest,
            &graph_digest,
            &model_digest,
            sources.value.records.len,
            model_package.value.models.len,
            validated.joined,
            validated.all_expected_dimensions_present,
            validated.all_source_ids_resolved,
            @tagName(validated.report_status),
            assurance_parsed.value.claim,
            assurance_consistent,
            @tagName(assurance_strength),
            assurance_report.len,
        },
    );
    defer allocator.free(manifest_json);
    try writeBundleArtifact(init.io, "manifest.json", manifest_json);
    try strip.serialization.signing.verifyDigestHex(signature, &bundle_digest_hex);

    var buffer: [12288]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(manifest_json);

    const validation_ok = validated.joined and validated.all_source_ids_resolved;
    const assurance_ok = assurance_consistent;
    return if (validation_ok and assurance_ok) 0 else 2;
}
