//! Staged HIL evidence and bounded latency/deadline summaries.
const std = @import("std");

pub const max_latency_samples = 2048;

pub const Stage = enum(u8) {
    software_in_loop,
    processor_in_loop,
    io_loopback,
    actuator_sensor_loop,
    integrated_hil,
};

pub const LatencySummary = struct {
    sample_count: usize,
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    maximum_ns: u64,
    deadline_ns: u64,
    deadline_misses: usize,

    pub fn meetsDeadline(self: LatencySummary) bool {
        return self.sample_count > 0 and self.deadline_ns > 0 and self.deadline_misses == 0;
    }
};

pub fn summarizeLatency(samples_ns: []const u64, deadline_ns: u64) !LatencySummary {
    if (samples_ns.len == 0 or samples_ns.len > max_latency_samples)
        return error.InvalidLatencySampleCount;
    if (deadline_ns == 0) return error.InvalidDeadline;
    var ordered: [max_latency_samples]u64 = undefined;
    @memcpy(ordered[0..samples_ns.len], samples_ns);
    // Bounded insertion sort avoids allocator and dependency requirements.
    for (ordered[0..samples_ns.len], 0..) |value, index| {
        var cursor = index;
        while (cursor > 0 and ordered[cursor - 1] > value) : (cursor -= 1)
            ordered[cursor] = ordered[cursor - 1];
        ordered[cursor] = value;
    }
    var misses: usize = 0;
    for (samples_ns) |sample| if (sample > deadline_ns) {
        misses += 1;
    };
    return .{
        .sample_count = samples_ns.len,
        .p50_ns = percentile(ordered[0..samples_ns.len], 50),
        .p95_ns = percentile(ordered[0..samples_ns.len], 95),
        .p99_ns = percentile(ordered[0..samples_ns.len], 99),
        .maximum_ns = ordered[samples_ns.len - 1],
        .deadline_ns = deadline_ns,
        .deadline_misses = misses,
    };
}

fn percentile(sorted: []const u64, percentage: usize) u64 {
    // Nearest-rank percentile, rank ceil(p*n/100), clamped to [1,n].
    const rank = @max(@as(usize, 1), (percentage * sorted.len + 99) / 100);
    return sorted[@min(rank, sorted.len) - 1];
}

pub const StageRecord = struct {
    stage: Stage,
    evidence_id: []const u8,
    functional_checks_passed: bool,
    latency: LatencySummary,

    pub fn passed(self: StageRecord) bool {
        return self.evidence_id.len > 0 and self.evidence_id.len <= 128 and
            self.functional_checks_passed and self.latency.meetsDeadline();
    }
};

pub const Progression = struct {
    records: []const StageRecord,

    pub fn validate(self: Progression) !void {
        if (self.records.len > @typeInfo(Stage).@"enum".fields.len)
            return error.TooManyStageRecords;
        for (self.records, 0..) |record, index| {
            for (self.records[0..index]) |prior|
                if (prior.stage == record.stage) return error.DuplicateStage;
        }
    }

    pub fn canEnter(self: Progression, target: Stage) !bool {
        try self.validate();
        if (target == .software_in_loop) return true;
        const target_index = @intFromEnum(target);
        for (0..target_index) |required_index| {
            const required: Stage = @enumFromInt(required_index);
            var passed = false;
            for (self.records) |record| {
                if (record.stage == required) {
                    passed = record.passed();
                    break;
                }
            }
            if (!passed) return false;
        }
        return true;
    }
};

test "HIL progression blocks missing and deadline-failing stages" {
    const healthy = try summarizeLatency(&.{ 100, 110, 120, 130, 140 }, 200);
    const late = try summarizeLatency(&.{ 100, 110, 250 }, 200);
    try std.testing.expectEqual(@as(u64, 140), healthy.p95_ns);
    try std.testing.expectEqual(@as(usize, 1), late.deadline_misses);
    const records = [_]StageRecord{
        .{ .stage = .software_in_loop, .evidence_id = "hil:sil:1", .functional_checks_passed = true, .latency = healthy },
        .{ .stage = .processor_in_loop, .evidence_id = "hil:pil:1", .functional_checks_passed = true, .latency = late },
    };
    const progression: Progression = .{ .records = &records };
    try std.testing.expect(try progression.canEnter(.processor_in_loop));
    try std.testing.expect(!(try progression.canEnter(.io_loopback)));
    try std.testing.expect(!(try progression.canEnter(.integrated_hil)));
}
