//! Replayable agent decisions. Tool execution belongs to an external host.
const std = @import("std");
const tools = @import("../tools/root.zig");

pub const Decision = enum { proposed, approved, denied, completed, failed };

pub const ReplayEntry = struct {
    sequence: u64,
    invocation: tools.Invocation,
    decision: Decision,
    output_digest: ?[32]u8 = null,
};

pub fn ReplayLog(comptime capacity: usize) type {
    return struct {
        entries: [capacity]ReplayEntry = undefined,
        len: usize = 0,

        pub fn append(self: *@This(), entry: ReplayEntry) error{
            CapacityExceeded,
            NonMonotonicSequence,
        }!void {
            if (self.len == capacity) return error.CapacityExceeded;
            if (self.len > 0 and entry.sequence <= self.entries[self.len - 1].sequence)
                return error.NonMonotonicSequence;
            self.entries[self.len] = entry;
            self.len += 1;
        }

        pub fn slice(self: *const @This()) []const ReplayEntry {
            return self.entries[0..self.len];
        }
    };
}

pub fn authorize(grants: tools.GrantSet, spec: tools.ToolSpec) Decision {
    return if (grants.permits(spec)) .approved else .denied;
}

test "replay log rejects reordered decisions" {
    var log: ReplayLog(2) = .{};
    const invocation: tools.Invocation = .{
        .tool = .scenario_reader,
        .input_digest = [_]u8{0} ** 32,
        .sequence = 4,
    };
    try log.append(.{ .sequence = 4, .invocation = invocation, .decision = .approved });
    try std.testing.expectError(
        error.NonMonotonicSequence,
        log.append(.{ .sequence = 3, .invocation = invocation, .decision = .completed }),
    );
}
