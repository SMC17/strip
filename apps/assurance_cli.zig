//! Demonstrate executable requirement-to-evidence traceability.

const std = @import("std");
const assurance = @import("strip").assurance;

pub fn main(init: std.process.Init) !u8 {
    var graph: assurance.Graph(8, 8) = .{};
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
        .id = "requirement:bounded-link-loss",
        .kind = .requirement,
        .strength = .integration_tested,
        .evidence_revision = 1,
        .dependencies = &.{.{ .id = "result:loss-of-link", .required_revision = 2 }},
    });
    try graph.add(.{
        .id = "claim:bounded-link-loss-simulation",
        .kind = .claim,
        .strength = .integration_tested,
        .evidence_revision = 1,
        .dependencies = &.{.{ .id = "requirement:bounded-link-loss", .required_revision = 1 }},
    });

    const report = graph.inspect();
    const strength = try graph.weakestDependency("claim:bounded-link-loss-simulation");

    var buffer: [1024]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.assurance.report.v0\",\"claim\":\"claim:bounded-link-loss-simulation\",\"status\":\"{s}\",\"limiting_strength\":\"{s}\",\"diagnostic_count\":{d},\"external_acceptance\":false}}\n",
        .{
            if (report.len == 0) "internally_consistent" else "invalid",
            @tagName(strength),
            report.len,
        },
    );
    return if (report.len == 0) 0 else 2;
}
