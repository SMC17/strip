//! Evidence compiler skeleton: `strip evidence build <program.toml>`
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
};

const AssuranceFixture = struct {
    schema: []const u8,
    claim: []const u8,
    requirement: []const u8,
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
    };
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = trimValue(line[0..eq]);
        const value = trimValue(line[eq + 1 ..]);
        if (std.mem.eql(u8, key, "schema")) program.schema = value
        else if (std.mem.eql(u8, key, "id")) program.id = value
        else if (std.mem.eql(u8, key, "sources")) program.sources = value
        else if (std.mem.eql(u8, key, "validation_case")) program.validation_case = value
        else if (std.mem.eql(u8, key, "validation_report")) program.validation_report = value
        else if (std.mem.eql(u8, key, "campaign")) program.campaign = value
        else if (std.mem.eql(u8, key, "assurance_fixture")) program.assurance_fixture = value;
    }
    if (!std.mem.eql(u8, program.schema, "strip.program.v0") or program.id.len == 0)
        return error.InvalidProgram;
    return program;
}

fn writeBundleArtifact(io: std.Io, name: []const u8, data: []const u8) !void {
    const path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ output_dir, name });
    defer std.heap.page_allocator.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

fn buildReferenceAssuranceGraph(fixture: AssuranceFixture) !strip.assurance.Graph(8, 8) {
    if (!std.mem.eql(u8, fixture.schema, "strip.assurance.fixture.v0"))
        return error.InvalidAssuranceFixture;
    var graph: strip.assurance.Graph(8, 8) = .{};
    try graph.add(.{
        .id = "model:uas-simulation",
        .kind = .model,
        .strength = .unit_tested,
        .evidence_revision = 3,
    });
    try graph.add(.{
        .id = "test:loss-of-link",
        .kind = .test_case,
        .strength = .integration_tested,
        .evidence_revision = 2,
        .dependencies = &.{.{ .id = "model:uas-simulation", .required_revision = 3 }},
    });
    try graph.add(.{
        .id = "result:loss-of-link",
        .kind = .test_result,
        .strength = .integration_tested,
        .evidence_revision = 2,
        .dependencies = &.{.{ .id = "test:loss-of-link", .required_revision = 2 }},
    });
    try graph.add(.{
        .id = fixture.requirement,
        .kind = .requirement,
        .strength = .integration_tested,
        .evidence_revision = 1,
        .dependencies = &.{.{ .id = "result:loss-of-link", .required_revision = 2 }},
    });
    try graph.add(.{
        .id = fixture.claim,
        .kind = .claim,
        .strength = .integration_tested,
        .evidence_revision = 1,
        .dependencies = &.{.{ .id = fixture.requirement, .required_revision = 1 }},
    });
    return graph;
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
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

    const validated = try strip.validation.join.validateReportAgainstCase(
        validation_case.value,
        report.value,
        sources.value,
    );

    var graph = try buildReferenceAssuranceGraph(assurance_parsed.value);
    const assurance_report = graph.inspect();
    const assurance_strength = graph.weakestDependency(assurance_parsed.value.claim) catch |err| switch (err) {
        else => return err,
    };
    const assurance_consistent = assurance_report.len == 0;

    try std.Io.Dir.cwd().createDirPath(init.io, output_dir);
    try writeBundleArtifact(init.io, "sources.json", source_bytes);
    try writeBundleArtifact(init.io, "validation-case.json", case_bytes);
    try writeBundleArtifact(init.io, "validation-report.json", report_bytes);
    try writeBundleArtifact(init.io, "campaign.toml", campaign_bytes);
    try writeBundleArtifact(init.io, "assurance-fixture.json", assurance_bytes);

    const manifest_json = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"strip.evidence.bundle.v0\",\"program_id\":\"{s}\",\"output_dir\":\"{s}\",\"sources\":\"{s}\",\"validation_case\":\"{s}\",\"validation_report\":\"{s}\",\"campaign\":\"{s}\",\"assurance_fixture\":\"{s}\",\"source_count\":{d},\"case_joined\":{},\"expected_dimensions_complete\":{},\"source_ids_resolved\":{},\"report_status\":\"{s}\",\"assurance_claim\":\"{s}\",\"assurance_internally_consistent\":{},\"assurance_limiting_strength\":\"{s}\",\"assurance_diagnostic_count\":{d},\"operational_qualification_claimed\":false}}\n",
        .{
            program.id,
            output_dir,
            program.sources,
            program.validation_case,
            program.validation_report,
            program.campaign,
            program.assurance_fixture,
            sources.value.records.len,
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

    var buffer: [8192]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(manifest_json);

    const validation_ok = validated.joined and validated.all_source_ids_resolved;
    const assurance_ok = assurance_consistent;
    return if (validation_ok and assurance_ok) 0 else 2;
}
