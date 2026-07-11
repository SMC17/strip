//! Load assurance dependency graphs from JSON fixtures.
const std = @import("std");
const root = @import("root.zig");

pub const JsonDependency = struct {
    id: []const u8,
    required_revision: u64 = 0,
};

pub const JsonNode = struct {
    id: []const u8,
    kind: []const u8 = "claim",
    strength: []const u8,
    evidence_revision: u64,
    dependencies: []const JsonDependency = &.{},
};

pub const AssuranceGraphDocument = struct {
    schema: []const u8,
    nodes: []const JsonNode,

    pub fn validate(self: AssuranceGraphDocument) !void {
        if (!std.mem.eql(u8, self.schema, "strip.assurance.graph.v0"))
            return error.UnsupportedSchema;
        if (self.nodes.len == 0 or self.nodes.len > 64) return error.InvalidNodeCount;
        for (self.nodes, 0..) |node, index| {
            if (node.id.len == 0 or node.id.len > 96) return error.InvalidNodeId;
            for (self.nodes[0..index]) |prior| {
                if (std.mem.eql(u8, prior.id, node.id)) return error.DuplicateNodeId;
            }
        }
    }
};

pub fn parseStrength(tag: []const u8) error{InvalidStrength}!root.Strength {
    if (std.mem.eql(u8, tag, "unsupported")) return .unsupported;
    if (std.mem.eql(u8, tag, "claimed")) return .claimed;
    if (std.mem.eql(u8, tag, "implemented")) return .implemented;
    if (std.mem.eql(u8, tag, "unit_tested")) return .unit_tested;
    if (std.mem.eql(u8, tag, "integration_tested")) return .integration_tested;
    return error.InvalidStrength;
}

pub fn parseKind(tag: []const u8) error{InvalidNodeKind}!root.NodeKind {
    if (std.mem.eql(u8, tag, "requirement")) return .requirement;
    if (std.mem.eql(u8, tag, "hazard")) return .hazard;
    if (std.mem.eql(u8, tag, "mitigation")) return .mitigation;
    if (std.mem.eql(u8, tag, "model")) return .model;
    if (std.mem.eql(u8, tag, "test_case")) return .test_case;
    if (std.mem.eql(u8, tag, "test_result")) return .test_result;
    if (std.mem.eql(u8, tag, "claim")) return .claim;
    if (std.mem.eql(u8, tag, "reviewer")) return .reviewer;
    return error.InvalidNodeKind;
}

pub fn loadGraph(
    allocator: std.mem.Allocator,
    comptime max_nodes: usize,
    comptime max_diagnostics: usize,
    document: AssuranceGraphDocument,
) !root.Graph(max_nodes, max_diagnostics) {
    try document.validate();
    if (document.nodes.len > max_nodes) return error.CapacityExceeded;
    var graph: root.Graph(max_nodes, max_diagnostics) = .{};
    for (document.nodes) |json_node| {
        const deps = try allocator.alloc(root.Dependency, json_node.dependencies.len);
        for (json_node.dependencies, 0..) |dependency, index| {
            deps[index] = .{
                .id = dependency.id,
                .required_revision = dependency.required_revision,
            };
        }
        try graph.add(.{
            .id = json_node.id,
            .kind = try parseKind(json_node.kind),
            .strength = try parseStrength(json_node.strength),
            .evidence_revision = json_node.evidence_revision,
            .dependencies = deps,
        });
    }
    return graph;
}

pub fn parseDocument(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(AssuranceGraphDocument) {
    if (bytes.len > 64 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(AssuranceGraphDocument, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 512,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

test "reference assurance graph loads and inspects cleanly" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/assurance/link-loss-graph.json",
        std.testing.allocator,
        .limited(32 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var parsed = try parseDocument(std.testing.allocator, bytes);
    defer parsed.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var graph = try loadGraph(arena.allocator(), 8, 8, parsed.value);
    const report = graph.inspect();
    try std.testing.expectEqual(@as(usize, 0), report.len);
    const strength = try graph.weakestDependency("claim:bounded-link-loss-simulation");
    try std.testing.expectEqual(root.Strength.unit_tested, strength);
}
