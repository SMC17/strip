//! Load primary-source manifests and join validation reports to cases.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    const source_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "sources/primary-sources.json",
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(source_bytes);
    var sources = try strip.validation.source.parse(allocator, source_bytes);
    defer sources.deinit();
    for (sources.value.records) |record| {
        try record.validateWithFilesystem(init.io);
    }

    const case_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fixtures/schemas/validation-case.valid.json",
        allocator,
        .limited(128 * 1024),
    );
    defer allocator.free(case_bytes);
    var validation_case = try strip.validation.types.parseCase(allocator, case_bytes);
    defer validation_case.deinit();

    const report_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "reports/validation/comparator-perturbed.json",
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(report_bytes);
    var report = try strip.validation.types.parseReport(allocator, report_bytes);
    defer report.deinit();

    const validated = try strip.validation.join.validateReportAgainstCase(
        validation_case.value,
        report.value,
        sources.value,
    );

    var buffer: [3072]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.validation.cli.v0\",\"primary_sources\":{d},\"report_status\":\"{s}\",\"case_joined\":{},\"expected_dimensions_complete\":{},\"source_ids_resolved\":{},\"coverage_complete\":{},\"cross_implementation\":\"{s}\",\"operational_qualification_claimed\":false}}\n",
        .{
            sources.value.records.len,
            @tagName(validated.report_status),
            validated.joined,
            validated.all_expected_dimensions_present,
            validated.all_source_ids_resolved,
            validated.coverage.allPassed(),
            @tagName(validated.coverage.status(.cross_implementation).?),
        },
    );
    return if (validated.joined and validated.all_expected_dimensions_present) 0 else 2;
}
