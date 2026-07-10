//! Typed tool declarations and least-authority permission checks.
const std = @import("std");

pub const Capability = enum { read_scenario, write_scenario, run_simulation, export_public_report };
pub const Risk = enum { read_only, reversible_write, execution, publication };

pub const ToolId = enum { scenario_reader, scenario_editor, simulator, report_exporter };

pub const ToolSpec = struct {
    id: ToolId,
    capability: Capability,
    risk: Risk,
};

pub const GrantSet = struct {
    bits: std.EnumSet(Capability) = .initEmpty(),

    pub fn grant(self: *GrantSet, capability: Capability) void {
        self.bits.insert(capability);
    }

    pub fn permits(self: GrantSet, tool: ToolSpec) bool {
        return self.bits.contains(tool.capability);
    }
};

pub const Invocation = struct {
    tool: ToolId,
    input_digest: [32]u8,
    sequence: u64,
};

test "grant is capability-specific rather than tool-name based" {
    var grants: GrantSet = .{};
    grants.grant(.read_scenario);
    try std.testing.expect(grants.permits(.{
        .id = .scenario_reader,
        .capability = .read_scenario,
        .risk = .read_only,
    }));
    try std.testing.expect(!grants.permits(.{
        .id = .simulator,
        .capability = .run_simulation,
        .risk = .execution,
    }));
}
