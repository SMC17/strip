//! Executable inventory for Strip product and frontier-research surfaces.

const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const ir = strip.aeroir.Model{
        .entities = &.{
            .{ .id = 1, .kind = .vehicle },
            .{ .id = 2, .kind = .environment },
            .{ .id = 3, .kind = .sensor },
            .{ .id = 4, .kind = .communication_link },
        },
        .connections = &.{
            .{ .source_id = 2, .target_id = 1 },
            .{ .source_id = 1, .target_id = 3 },
            .{ .source_id = 3, .target_id = 4 },
        },
    };
    try ir.validate();

    var grants: strip.tools.GrantSet = .{};
    grants.grant(.read_scenario);
    grants.grant(.run_simulation);
    const simulation_decision = strip.agent.authorize(grants, .{
        .id = .simulator,
        .capability = .run_simulation,
        .risk = .execution,
    });
    const publication_decision = strip.agent.authorize(grants, .{
        .id = .report_exporter,
        .capability = .export_public_report,
        .risk = .publication,
    });
    const assurance_selection = strip.runtime_assurance.select(.{
        .safety_margin = 0.5,
        .minimum_margin = 1.0,
        .state_fresh = true,
    });
    const resilience_response = strip.public_defense.boundedResponse(.{
        .class = .anomalous,
        .confidence = 0.7,
        .source_count = 2,
    });

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.platform.surface.v0\",\"products\":[\"consumer_lab\",\"civil_assurance\",\"mission_engineering\"],\"aeroir\":\"valid\",\"ai_simulation\":\"{s}\",\"ai_publication\":\"{s}\",\"runtime_controller\":\"{s}\",\"public_resilience_response\":\"{s}\",\"adapter_contracts\":{d},\"authoritative_external_adapters\":0,\"frontier_modules\":[\"state_graph\",\"worldforge\",\"design_evolve\",\"rare_event\",\"multifidelity\",\"runtime_assurance\",\"twin\"]}}\n",
        .{
            @tagName(simulation_decision),
            @tagName(publication_decision),
            @tagName(assurance_selection.controller),
            @tagName(resilience_response),
            strip.adapters.public_catalog.len,
        },
    );
    return 0;
}
