//! Human-in-the-loop recording contracts. Scores and timing fields preserve
//! provenance; they do not diagnose fitness, certify a simulator, or qualify a
//! vehicle.

const std = @import("std");

pub const SourceMetadata = struct {
    id: []const u8,
    title: []const u8,
    locator: []const u8,
    use: []const u8,
    qualification: bool = false,
};

pub const sources = struct {
    pub const nasa_tlx = SourceMetadata{
        .id = "NASA-TLX",
        .title = "NASA Task Load Index",
        .locator = "Hart and Staveland (1988), six subscales",
        .use = "workload dimension names and bounded raw ratings",
    };
    pub const latency = SourceMetadata{
        .id = "NASA-TM-2011-216454",
        .title = "Flight Simulation Training Device fidelity review",
        .locator = "visual and motion cue timing discussion",
        .use = "record separate source, onset, and display timing rather than one opaque latency",
    };
};

pub const WorkloadRating = struct {
    mental_demand: u8,
    physical_demand: u8,
    temporal_demand: u8,
    performance: u8,
    effort: u8,
    frustration: u8,
    scale_max: u8 = 100,
    recorded_time_s: f64,
    rater_id: []const u8,

    pub fn validate(self: WorkloadRating) error{InvalidRating}!void {
        if (self.scale_max == 0 or !std.math.isFinite(self.recorded_time_s) or self.recorded_time_s < 0.0 or self.rater_id.len == 0)
            return error.InvalidRating;
        const values = [_]u8{ self.mental_demand, self.physical_demand, self.temporal_demand, self.performance, self.effort, self.frustration };
        for (values) |value| if (value > self.scale_max) return error.InvalidRating;
    }

    pub fn rawMean(self: WorkloadRating) error{InvalidRating}!f64 {
        try self.validate();
        const total: u16 = @as(u16, self.mental_demand) + self.physical_demand +
            self.temporal_demand + self.performance + self.effort + self.frustration;
        return @as(f64, @floatFromInt(total)) / 6.0;
    }
};

pub const CueModality = enum { visual, auditory, tactile, proprioceptive, motion_base };
pub const CuePriority = enum { advisory, caution, warning, directive };

pub const CueEvent = struct {
    id: []const u8,
    modality: CueModality,
    priority: CuePriority,
    commanded_time_s: f64,
    onset_time_s: ?f64,
    acknowledged_time_s: ?f64,
    source_tick: u64,
    message: []const u8,

    pub fn validate(self: CueEvent) error{InvalidCue}!void {
        if (self.id.len == 0 or self.message.len == 0 or !std.math.isFinite(self.commanded_time_s) or self.commanded_time_s < 0.0)
            return error.InvalidCue;
        if (self.onset_time_s) |onset| {
            if (!std.math.isFinite(onset) or onset < self.commanded_time_s) return error.InvalidCue;
            if (self.acknowledged_time_s) |ack| if (!std.math.isFinite(ack) or ack < onset) return error.InvalidCue;
        } else if (self.acknowledged_time_s != null) return error.InvalidCue;
    }
};

pub const LatencyTrace = struct {
    source_time_s: f64,
    compute_complete_time_s: f64,
    presentation_onset_time_s: f64,
    measurement_method: enum { software_timestamp, photosensor, high_speed_video, external_instrument },
    uncertainty_s: f64,

    pub fn validate(self: LatencyTrace) error{InvalidLatency}!void {
        const values = [_]f64{ self.source_time_s, self.compute_complete_time_s, self.presentation_onset_time_s, self.uncertainty_s };
        for (values) |value| if (!std.math.isFinite(value)) return error.InvalidLatency;
        if (self.source_time_s < 0.0 or self.compute_complete_time_s < self.source_time_s or
            self.presentation_onset_time_s < self.compute_complete_time_s or self.uncertainty_s < 0.0)
            return error.InvalidLatency;
    }

    pub fn endToEndSeconds(self: LatencyTrace) error{InvalidLatency}!f64 {
        try self.validate();
        return self.presentation_onset_time_s - self.source_time_s;
    }
};

pub const MotionVisualLatency = struct {
    motion: LatencyTrace,
    visual: LatencyTrace,

    /// Positive means motion presentation follows visual presentation.
    pub fn motionMinusVisualSeconds(self: MotionVisualLatency) error{InvalidLatency}!f64 {
        try self.motion.validate();
        try self.visual.validate();
        return self.motion.presentation_onset_time_s - self.visual.presentation_onset_time_s;
    }
};

pub const TestCard = struct {
    id: []const u8,
    revision: []const u8,
    objective: []const u8,
    configuration_id: []const u8,
    initial_conditions: []const u8,
    steps: []const []const u8,
    abort_criteria: []const []const u8,
    required_channels: []const []const u8,
    planned_by: []const u8,

    pub fn validate(self: TestCard) error{InvalidTestCard}!void {
        if (self.id.len == 0 or self.revision.len == 0 or self.objective.len == 0 or
            self.configuration_id.len == 0 or self.initial_conditions.len == 0 or
            self.steps.len == 0 or self.abort_criteria.len == 0 or self.required_channels.len == 0 or self.planned_by.len == 0)
            return error.InvalidTestCard;
        for (self.steps) |step| if (step.len == 0) return error.InvalidTestCard;
        for (self.abort_criteria) |criterion| if (criterion.len == 0) return error.InvalidTestCard;
        for (self.required_channels) |channel| if (channel.len == 0) return error.InvalidTestCard;
    }
};

pub const FindingSeverity = enum { observation, minor, major, safety_stop };
pub const DebriefFinding = struct {
    time_s: ?f64,
    severity: FindingSeverity,
    statement: []const u8,
    evidence_reference: ?[]const u8,
    disposition: enum { open, accepted, corrected, rejected },
};

pub const Debrief = struct {
    test_card_id: []const u8,
    run_id: []const u8,
    participants: []const []const u8,
    findings: []const DebriefFinding,
    completed_time_s: f64,
    recorder_id: []const u8,

    pub fn validate(self: Debrief) error{InvalidDebrief}!void {
        if (self.test_card_id.len == 0 or self.run_id.len == 0 or self.participants.len == 0 or
            !std.math.isFinite(self.completed_time_s) or self.completed_time_s < 0.0 or self.recorder_id.len == 0)
            return error.InvalidDebrief;
        for (self.participants) |participant| if (participant.len == 0) return error.InvalidDebrief;
        for (self.findings) |finding| {
            if (finding.statement.len == 0) return error.InvalidDebrief;
            if (finding.time_s) |time| if (!std.math.isFinite(time) or time < 0.0) return error.InvalidDebrief;
        }
    }
};

test "workload ratings retain dimensions and reject scale overflow" {
    var rating = WorkloadRating{
        .mental_demand = 60,
        .physical_demand = 20,
        .temporal_demand = 40,
        .performance = 30,
        .effort = 50,
        .frustration = 10,
        .recorded_time_s = 12,
        .rater_id = "anonymous-1",
    };
    try std.testing.expectEqual(@as(f64, 35), try rating.rawMean());
    rating.mental_demand = 101;
    try std.testing.expectError(error.InvalidRating, rating.validate());
}

test "motion visual latency preserves sign and measurement uncertainty" {
    const motion = LatencyTrace{ .source_time_s = 1, .compute_complete_time_s = 1.01, .presentation_onset_time_s = 1.04, .measurement_method = .external_instrument, .uncertainty_s = 0.001 };
    const visual = LatencyTrace{ .source_time_s = 1, .compute_complete_time_s = 1.02, .presentation_onset_time_s = 1.03, .measurement_method = .photosensor, .uncertainty_s = 0.002 };
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), try (MotionVisualLatency{ .motion = motion, .visual = visual }).motionMinusVisualSeconds(), 1e-12);
}

test "test card requires abort criteria and debrief keeps findings attributable" {
    const steps = [_][]const u8{"establish trim"};
    const aborts = [_][]const u8{"loss of telemetry"};
    const channels = [_][]const u8{"pitch-rate"};
    const card = TestCard{ .id = "TC-1", .revision = "A", .objective = "collect response", .configuration_id = "cfg-1", .initial_conditions = "trimmed", .steps = &steps, .abort_criteria = &aborts, .required_channels = &channels, .planned_by = "test-team" };
    try card.validate();
    const participants = [_][]const u8{"pilot-1"};
    const findings = [_]DebriefFinding{.{ .time_s = 4, .severity = .observation, .statement = "cue onset recorded", .evidence_reference = "trace:4", .disposition = .open }};
    try (Debrief{ .test_card_id = card.id, .run_id = "run-1", .participants = &participants, .findings = &findings, .completed_time_s = 20, .recorder_id = "recorder-1" }).validate();
}
