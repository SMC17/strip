//! Load primary-source manifests and validation reports with explicit coverage.

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

    const report_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "reports/validation/comparator-perturbed.json",
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(report_bytes);
    var report = try strip.validation.types.parseReport(allocator, report_bytes);
    defer report.deinit();

    const required = [_]strip.validation.types.EvidenceDimension{
        .unit_test,
        .cross_implementation,
        .experimental,
    };
    const matrix = try strip.validation.coverage.Matrix.build(
        &required,
        report.value.evidence,
    );

    var buffer: [2048]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.validation.cli.v0\",\"primary_sources\":{d},\"report_status\":\"{s}\",\"coverage_complete\":{},\"cross_implementation\":\"{s}\",\"operational_qualification_claimed\":false}}\n",
        .{
            sources.value.records.len,
            @tagName(report.value.status),
            matrix.allPassed(),
            @tagName(matrix.status(.cross_implementation).?),
        },
    );
    return if (report.value.status == .failed) 0 else 2;
}
