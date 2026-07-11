//! Counterfactual branch: same prefix, alternate suffix / policy.

const std = @import("std");
const jsonl = @import("jsonl.zig");

pub const Compare = struct {
    branch_at: u64,
    baseline_claims_supported: usize,
    alternate_claims_supported: usize,
    baseline_actions_executed: usize,
    alternate_actions_executed: usize,
    baseline_policy_denied: usize,
    alternate_policy_denied: usize,
    divergence: bool,
    passed: bool,
};

/// Branch the reference atmosphere trajectory at `branch_at`: baseline continues
/// approved path; alternate injects policy denial and skips claim.
pub fn comparePolicyDenial(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    branch_at: u64,
) !Compare {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024));
    defer allocator.free(bytes);

    const baseline = try jsonl.foldJsonl(allocator, bytes);
    defer jsonl.freeFold(allocator, baseline);

    var alt_lines: std.ArrayList(u8) = .empty;
    defer alt_lines.deinit(allocator);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        const key = "\"sequence\":";
        const idx = std.mem.indexOf(u8, trimmed, key) orelse continue;
        var n: u64 = 0;
        var i = idx + key.len;
        while (i < trimmed.len and trimmed[i] >= '0' and trimmed[i] <= '9') : (i += 1) {
            n = n * 10 + (trimmed[i] - '0');
        }
        if (n <= branch_at) {
            try alt_lines.appendSlice(allocator, trimmed);
            try alt_lines.append(allocator, '\n');
        }
    }
    const suffix = try std.fmt.allocPrint(
        allocator,
        "{{\"sequence\":{d},\"event_id\":\"alt-policy\",\"kind\":\"policy_evaluated\",\"delivery_id\":\"alt-d-policy\",\"policy\":\"denied\",\"detail\":\"counterfactual denial\"}}\n{{\"sequence\":{d},\"event_id\":\"alt-done\",\"kind\":\"run_completed\",\"delivery_id\":\"alt-d-done\",\"detail\":\"alternate closed without claim\"}}\n",
        .{ branch_at + 1, branch_at + 2 },
    );
    defer allocator.free(suffix);
    try alt_lines.appendSlice(allocator, suffix);

    const alternate = try jsonl.foldJsonl(allocator, alt_lines.items);
    defer jsonl.freeFold(allocator, alternate);

    const b = baseline.store.state;
    const a = alternate.store.state;
    const divergence = b.claims_supported != a.claims_supported or
        b.actions_executed != a.actions_executed or
        b.policy_denied != a.policy_denied;
    const passed = divergence and a.policy_denied > b.policy_denied and a.claims_supported < b.claims_supported;

    return .{
        .branch_at = branch_at,
        .baseline_claims_supported = b.claims_supported,
        .alternate_claims_supported = a.claims_supported,
        .baseline_actions_executed = b.actions_executed,
        .alternate_actions_executed = a.actions_executed,
        .baseline_policy_denied = b.policy_denied,
        .alternate_policy_denied = a.policy_denied,
        .divergence = divergence,
        .passed = passed,
    };
}

test "counterfactual policy denial diverges" {
    const cmp = try comparePolicyDenial(
        std.testing.allocator,
        std.testing.io,
        "fixtures/trajectory/reference-uas-atmosphere.jsonl",
        3,
    );
    try std.testing.expect(cmp.passed);
    try std.testing.expect(cmp.divergence);
}
