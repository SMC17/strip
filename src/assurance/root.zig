//! Small assurance dependency graph with explicit invalidity diagnostics.
const std = @import("std");

pub const load = @import("load.zig");

pub const Strength = enum(u8) {
    unsupported,
    claimed,
    implemented,
    unit_tested,
    integration_tested,

    pub fn weakest(a: Strength, b: Strength) Strength {
        return @enumFromInt(@min(@intFromEnum(a), @intFromEnum(b)));
    }
};

pub const Dependency = struct {
    id: []const u8,
    required_revision: u64 = 0,
};

pub const NodeKind = enum {
    requirement,
    hazard,
    mitigation,
    model,
    test_case,
    test_result,
    claim,
    reviewer,
};

pub const Node = struct {
    id: []const u8,
    kind: NodeKind = .claim,
    strength: Strength,
    evidence_revision: u64,
    dependencies: []const Dependency = &.{},
};

pub const Diagnostic = union(enum) {
    missing: struct { node: []const u8, dependency: []const u8 },
    stale: struct { node: []const u8, dependency: []const u8, have: u64, required: u64 },
    cycle: struct { node: []const u8 },
};

pub fn Graph(comptime max_nodes: usize, comptime max_diagnostics: usize) type {
    return struct {
        const Self = @This();
        nodes: [max_nodes]Node = undefined,
        len: usize = 0,

        pub fn add(self: *Self, node: Node) error{ CapacityExceeded, DuplicateId }!void {
            if (self.find(node.id) != null) return error.DuplicateId;
            if (self.len == max_nodes) return error.CapacityExceeded;
            self.nodes[self.len] = node;
            self.len += 1;
        }

        pub fn find(self: *const Self, id: []const u8) ?usize {
            for (self.nodes[0..self.len], 0..) |node, index| {
                if (std.mem.eql(u8, node.id, id)) return index;
            }
            return null;
        }

        pub const Report = struct {
            diagnostics: [max_diagnostics]Diagnostic = undefined,
            len: usize = 0,
            truncated: bool = false,

            fn append(self: *@This(), diagnostic: Diagnostic) void {
                if (self.len == max_diagnostics) {
                    self.truncated = true;
                    return;
                }
                self.diagnostics[self.len] = diagnostic;
                self.len += 1;
            }
        };

        pub fn inspect(self: *const Self) Report {
            var report: Report = .{};
            var state = [_]u2{0} ** max_nodes;
            for (0..self.len) |index| self.visit(index, &state, &report);
            return report;
        }

        fn visit(self: *const Self, index: usize, state: *[max_nodes]u2, report: *Report) void {
            if (state[index] == 1) {
                report.append(.{ .cycle = .{ .node = self.nodes[index].id } });
                return;
            }
            if (state[index] == 2) return;
            state[index] = 1;
            const node = self.nodes[index];
            for (node.dependencies) |dependency| {
                const child = self.find(dependency.id) orelse {
                    report.append(.{ .missing = .{
                        .node = node.id,
                        .dependency = dependency.id,
                    } });
                    continue;
                };
                if (self.nodes[child].evidence_revision < dependency.required_revision) {
                    report.append(.{ .stale = .{
                        .node = node.id,
                        .dependency = dependency.id,
                        .have = self.nodes[child].evidence_revision,
                        .required = dependency.required_revision,
                    } });
                }
                self.visit(child, state, report);
            }
            state[index] = 2;
        }

        pub fn weakestDependency(self: *const Self, id: []const u8) error{
            MissingNode,
            MissingDependency,
            StaleDependency,
            Cycle,
        }!Strength {
            const index = self.find(id) orelse return error.MissingNode;
            var visiting = [_]bool{false} ** max_nodes;
            return self.resolve(index, &visiting);
        }

        fn resolve(
            self: *const Self,
            index: usize,
            visiting: *[max_nodes]bool,
        ) error{ MissingDependency, StaleDependency, Cycle }!Strength {
            if (visiting[index]) return error.Cycle;
            visiting[index] = true;
            defer visiting[index] = false;
            const node = self.nodes[index];
            var result = node.strength;
            for (node.dependencies) |dependency| {
                const child = self.find(dependency.id) orelse return error.MissingDependency;
                if (self.nodes[child].evidence_revision < dependency.required_revision)
                    return error.StaleDependency;
                result = Strength.weakest(result, try self.resolve(child, visiting));
            }
            return result;
        }
    };
}

test "weakest transitive dependency bounds assurance strength" {
    var graph: Graph(4, 4) = .{};
    try graph.add(.{ .id = "test", .strength = .unit_tested, .evidence_revision = 2 });
    try graph.add(.{
        .id = "claim",
        .strength = .integration_tested,
        .evidence_revision = 1,
        .dependencies = &.{.{ .id = "test", .required_revision = 2 }},
    });
    try std.testing.expectEqual(Strength.unit_tested, try graph.weakestDependency("claim"));
}

test "inspection detects missing stale and cyclic dependencies" {
    var graph: Graph(4, 8) = .{};
    try graph.add(.{
        .id = "a",
        .strength = .claimed,
        .evidence_revision = 1,
        .dependencies = &.{ .{ .id = "b", .required_revision = 2 }, .{ .id = "absent" } },
    });
    try graph.add(.{
        .id = "b",
        .strength = .implemented,
        .evidence_revision = 1,
        .dependencies = &.{.{ .id = "a" }},
    });
    const report = graph.inspect();
    var missing = false;
    var stale = false;
    var cycle = false;
    for (report.diagnostics[0..report.len]) |diagnostic| switch (diagnostic) {
        .missing => missing = true,
        .stale => stale = true,
        .cycle => cycle = true,
    };
    try std.testing.expect(missing and stale and cycle);
    try std.testing.expectError(error.StaleDependency, graph.weakestDependency("a"));
}

test {
    _ = load;
}
