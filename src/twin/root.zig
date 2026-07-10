//! Digital-twin synchronization metadata; no physical fidelity claim.
const std = @import("std");

pub const SyncState = struct {
    model_revision: u64,
    observation_time_ns: u64,
    ingest_time_ns: u64,
    source_digest: [32]u8,

    pub fn ageAt(self: SyncState, now_ns: u64) error{ClockRegression}!u64 {
        if (now_ns < self.observation_time_ns) return error.ClockRegression;
        return now_ns - self.observation_time_ns;
    }

    pub fn isFresh(self: SyncState, now_ns: u64, maximum_age_ns: u64) bool {
        const age = self.ageAt(now_ns) catch return false;
        return age <= maximum_age_ns and self.ingest_time_ns >= self.observation_time_ns;
    }
};

test "freshness rejects clock regressions and invalid ingest ordering" {
    const state: SyncState = .{
        .model_revision = 1,
        .observation_time_ns = 10,
        .ingest_time_ns = 9,
        .source_digest = [_]u8{0} ** 32,
    };
    try std.testing.expect(!state.isFresh(11, 5));
    try std.testing.expectError(error.ClockRegression, state.ageAt(8));
}
