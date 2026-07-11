//! Load primary-source manifests and join validation reports to cases.
//!
//! Default path uses the US76 atmosphere case/report (green coverage).
//! Pass `--negative` to exercise the intentional comparator-perturbed failure fixture.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    var negative = false;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--negative")) negative = true else return 2;
    }

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

    const case_path = if (negative)
        "fixtures/schemas/validation-case.valid.json"
    else
        "fixtures/validation/uas/us76-atmosphere-case.json";
    const report_path = if (negative)
        "reports/validation/comparator-perturbed.json"
    else
        "reports/validation/us76-atmosphere.json";

    const case_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        case_path,
        allocator,
        .limited(128 * 1024),
    );
    defer allocator.free(case_bytes);
    var validation_case = try strip.validation.types.parseCase(allocator, case_bytes);
    defer validation_case.deinit();

    const report_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        report_path,
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
        "{{\"schema\":\"strip.validation.cli.v0\",\"mode\":\"{s}\",\"case\":\"{s}\",\"report\":\"{s}\",\"primary_sources\":{d},\"report_status\":\"{s}\",\"case_joined\":{},\"expected_dimensions_complete\":{},\"source_ids_resolved\":{},\"coverage_complete\":{},\"cross_implementation\":\"{s}\",\"operational_qualification_claimed\":false}}\n",
        .{
            if (negative) "negative_comparator" else "us76_atmosphere",
            case_path,
            report_path,
            sources.value.records.len,
            @tagName(validated.report_status),
            validated.joined,
            validated.all_expected_dimensions_present,
            validated.all_source_ids_resolved,
            validated.coverage.allPassed(),
            @tagName(validated.coverage.status(.cross_implementation).?),
        },
    );
    if (negative) {
        // Negative mode succeeds as a process if join is complete (failure is in coverage).
        return if (validated.joined and validated.all_expected_dimensions_present) 0 else 2;
    }
    return if (validated.joined and validated.all_expected_dimensions_present and validated.coverage.allPassed())
        0
    else
        2;
}
