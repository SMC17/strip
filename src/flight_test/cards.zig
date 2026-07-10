//! Test-card identities and one-way calibration/blinded-holdout partition gates.
const std = @import("std");

pub const ConfigurationIdentity = struct {
    vehicle_id: []const u8,
    configuration_id: []const u8,
    revision: []const u8,
    content_sha256: []const u8,

    pub fn validate(self: ConfigurationIdentity) !void {
        try bounded(self.vehicle_id, 1, 64);
        try bounded(self.configuration_id, 1, 64);
        try bounded(self.revision, 1, 32);
        try sha256(self.content_sha256);
    }
};

pub const TestCard = struct {
    card_id: []const u8,
    configuration: ConfigurationIdentity,
    maneuver_id: []const u8,
    objective: []const u8,
    acceptance_rule: []const u8,

    pub fn validate(self: TestCard) !void {
        try bounded(self.card_id, 1, 64);
        try self.configuration.validate();
        try bounded(self.maneuver_id, 1, 64);
        try bounded(self.objective, 1, 256);
        try bounded(self.acceptance_rule, 1, 256);
    }
};

pub const Split = enum { calibration, blinded_holdout };

pub const RunIdentity = struct {
    run_id: []const u8,
    split: Split,
};

pub const SplitPolicy = struct {
    policy_id: []const u8,
    sealed_before_analysis_utc: []const u8,
    runs: []const RunIdentity,

    pub fn validate(self: SplitPolicy) !void {
        try bounded(self.policy_id, 1, 64);
        if (self.sealed_before_analysis_utc.len < 20 or
            self.sealed_before_analysis_utc[self.sealed_before_analysis_utc.len - 1] != 'Z')
            return error.InvalidSealTime;
        if (self.runs.len < 2 or self.runs.len > 100_000) return error.InvalidRunCount;
        var calibration_count: usize = 0;
        var holdout_count: usize = 0;
        for (self.runs, 0..) |run, index| {
            try bounded(run.run_id, 1, 64);
            for (self.runs[0..index]) |prior|
                if (std.mem.eql(u8, prior.run_id, run.run_id)) return error.DuplicateRun;
            if (run.split == .calibration) calibration_count += 1 else holdout_count += 1;
        }
        if (calibration_count == 0 or holdout_count == 0) return error.IncompleteSplit;
    }

    /// Call at every fitting boundary. Holdout data is rejected, not silently omitted.
    pub fn requireCalibration(self: SplitPolicy, requested_run_ids: []const []const u8) !void {
        try self.validate();
        if (requested_run_ids.len == 0) return error.EmptyFitSet;
        for (requested_run_ids) |requested| {
            var found: ?Split = null;
            for (self.runs) |run| {
                if (std.mem.eql(u8, requested, run.run_id)) {
                    found = run.split;
                    break;
                }
            }
            const split = found orelse return error.UnknownRun;
            if (split != .calibration) return error.HoldoutLeakage;
        }
    }

    pub fn requireHoldoutEvaluation(self: SplitPolicy, requested_run_ids: []const []const u8) !void {
        try self.validate();
        if (requested_run_ids.len == 0) return error.EmptyEvaluationSet;
        for (requested_run_ids) |requested| {
            var found: ?Split = null;
            for (self.runs) |run| {
                if (std.mem.eql(u8, requested, run.run_id)) {
                    found = run.split;
                    break;
                }
            }
            const split = found orelse return error.UnknownRun;
            if (split != .blinded_holdout) return error.CalibrationContamination;
        }
    }
};

fn bounded(value: []const u8, minimum: usize, maximum: usize) !void {
    if (value.len < minimum or value.len > maximum) return error.InvalidTextLength;
}

fn sha256(value: []const u8) !void {
    if (value.len != 64) return error.InvalidSha256;
    for (value) |character| {
        if (!std.ascii.isHex(character) or std.ascii.isUpper(character))
            return error.InvalidSha256;
    }
}

test "blinded holdout cannot enter calibration fit" {
    const policy: SplitPolicy = .{
        .policy_id = "split-2026-07-a",
        .sealed_before_analysis_utc = "2026-07-10T12:00:00Z",
        .runs = &.{
            .{ .run_id = "run-cal-01", .split = .calibration },
            .{ .run_id = "run-cal-02", .split = .calibration },
            .{ .run_id = "run-blind-01", .split = .blinded_holdout },
        },
    };
    try policy.requireCalibration(&.{ "run-cal-01", "run-cal-02" });
    try std.testing.expectError(
        error.HoldoutLeakage,
        policy.requireCalibration(&.{ "run-cal-01", "run-blind-01" }),
    );
    try policy.requireHoldoutEvaluation(&.{"run-blind-01"});
    try std.testing.expectError(
        error.CalibrationContamination,
        policy.requireHoldoutEvaluation(&.{"run-cal-01"}),
    );
}
