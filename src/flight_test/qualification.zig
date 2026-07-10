//! Flight-qualification evidence framework (structure only — never operational claims).

const std = @import("std");
const evidence = @import("evidence.zig");
const campaign = @import("campaign.zig");
const campaign_calibration = @import("../uncertainty/campaign_calibration.zig");
const telemetry_csv = @import("telemetry_csv.zig");
const hil = @import("hil.zig");

pub const Tier = enum {
    software_only,
    hardware_in_loop,
    flight_test,
};

pub const DimensionStatus = enum {
    passed,
    partial,
    pending,
    missing,
};

pub const TierLadder = struct {
    software_only: DimensionStatus,
    hardware_in_loop: DimensionStatus,
    flight_test: DimensionStatus,
};

pub const Report = struct {
    tier: Tier,
    tier_ladder: TierLadder,
    evidence_manifest_passed: bool,
    campaign_passed: bool,
    holdout_calibration_passed: bool,
    hil_progression_passed: bool,
    operational_qualification_claimed: bool,
    passed: bool,
};

pub const HilProgressionFixture = struct {
    schema: []const u8,
    id: []const u8,
    deadline_ns: u64,
    records: []const HilRecordFixture,
};

pub const HilRecordFixture = struct {
    stage: hil.Stage,
    evidence_id: []const u8,
    functional_checks_passed: bool,
    latency_samples_ns: []const u64,
};

pub fn parseHilProgressionFixture(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(HilProgressionFixture) {
    if (bytes.len > 512 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(HilProgressionFixture, allocator, bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, "strip.flight-test-hil-progression.v1"))
        return error.UnsupportedSchema;
    if (parsed.value.records.len == 0 or parsed.value.deadline_ns == 0)
        return error.InvalidHilFixture;
    return parsed;
}

pub const HilEval = struct {
    passed: bool,
    can_enter_io_loopback: bool,
    can_enter_integrated_hil: bool,
};

pub fn evaluateHilProgression(fixture: HilProgressionFixture) !HilEval {
    var records = try std.ArrayList(hil.StageRecord).initCapacity(std.heap.page_allocator, fixture.records.len);
    defer records.deinit(std.heap.page_allocator);
    for (fixture.records) |record_fixture| {
        const latency = try hil.summarizeLatency(record_fixture.latency_samples_ns, fixture.deadline_ns);
        try records.append(std.heap.page_allocator, .{
            .stage = record_fixture.stage,
            .evidence_id = record_fixture.evidence_id,
            .functional_checks_passed = record_fixture.functional_checks_passed,
            .latency = latency,
        });
    }
    const progression: hil.Progression = .{ .records = records.items };
    const can_enter_io = try progression.canEnter(.io_loopback);
    const can_enter_integrated = try progression.canEnter(.integrated_hil);
    var passed = true;
    for (records.items) |record| {
        if (!record.passed()) passed = false;
    }
    return .{
        .passed = passed,
        .can_enter_io_loopback = can_enter_io,
        .can_enter_integrated_hil = can_enter_integrated,
    };
}

pub fn evaluateTierLadder(
    software_report: Report,
    hil_eval: HilEval,
) TierLadder {
    const hil_status: DimensionStatus = if (hil_eval.passed and hil_eval.can_enter_io_loopback)
        .partial
    else if (hil_eval.passed)
        .pending
    else
        .missing;
    return .{
        .software_only = if (software_report.passed) .passed else .missing,
        .hardware_in_loop = hil_status,
        .flight_test = .missing,
    };
}

pub fn evaluateSoftwareOnly(
    manifest: evidence.Manifest,
    campaign_fixture: campaign.Campaign,
    calibration_report: campaign_calibration.CalibrationReport,
    hil_eval: HilEval,
) !Report {
    try manifest.validate();
    try campaign_fixture.validate();
    const evidence_manifest_passed = manifest.sealed and !manifest.operational_qualification_claimed;
    const campaign_passed = campaign_fixture.test_cards.len > 0 and
        campaign_fixture.split_policy.calibration_run_ids.len > 0 and
        campaign_fixture.split_policy.blinded_holdout_run_ids.len > 0;
    const holdout_calibration_passed = calibration_report.holdout_passed;
    const base = evidence_manifest_passed and campaign_passed and holdout_calibration_passed;
    const tier_ladder = evaluateTierLadder(.{
        .tier = .software_only,
        .tier_ladder = .{ .software_only = .missing, .hardware_in_loop = .missing, .flight_test = .missing },
        .evidence_manifest_passed = evidence_manifest_passed,
        .campaign_passed = campaign_passed,
        .holdout_calibration_passed = holdout_calibration_passed,
        .hil_progression_passed = hil_eval.passed,
        .operational_qualification_claimed = false,
        .passed = base,
    }, hil_eval);
    const passed = base and hil_eval.passed and !hil_eval.can_enter_integrated_hil;
    return .{
        .tier = .software_only,
        .tier_ladder = tier_ladder,
        .evidence_manifest_passed = evidence_manifest_passed,
        .campaign_passed = campaign_passed,
        .holdout_calibration_passed = holdout_calibration_passed,
        .hil_progression_passed = hil_eval.passed,
        .operational_qualification_claimed = false,
        .passed = passed,
    };
}

pub fn evaluateFromFixtures(
    allocator: std.mem.Allocator,
    io: std.Io,
) !Report {
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "reports/validation/flight-test/synthetic-evidence-manifest.json",
        allocator,
        .limited(1024 * 1024),
    );
    defer allocator.free(manifest_bytes);
    var manifest_parsed = try evidence.parseManifest(allocator, manifest_bytes);
    defer manifest_parsed.deinit();

    const campaign_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "fixtures/validation/flight-test/synthetic-campaign.json",
        allocator,
        .limited(512 * 1024),
    );
    defer allocator.free(campaign_bytes);
    var campaign_parsed = try campaign.parseCampaign(allocator, campaign_bytes);
    defer campaign_parsed.deinit();

    const csv_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "fixtures/validation/flight-test/synthetic-telemetry.csv",
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(csv_bytes);
    const rows = try telemetry_csv.loadCsv(allocator, csv_bytes);
    defer {
        for (rows) |row| allocator.free(row.channel);
        allocator.free(rows);
    }

    const hil_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "fixtures/validation/flight-test/synthetic-hil-progression.json",
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(hil_bytes);
    var hil_parsed = try parseHilProgressionFixture(allocator, hil_bytes);
    defer hil_parsed.deinit();
    const hil_eval = try evaluateHilProgression(hil_parsed.value);

    const calibration_report = try campaign_calibration.evaluateSyntheticCampaign(
        campaign_parsed.value,
        rows,
    );
    return try evaluateSoftwareOnly(manifest_parsed.value, campaign_parsed.value, calibration_report, hil_eval);
}

test "software-only qualification framework passes synthetic fixtures" {
    const report = try evaluateFromFixtures(std.testing.allocator, std.testing.io);
    try std.testing.expect(report.passed);
    try std.testing.expect(!report.operational_qualification_claimed);
    try std.testing.expectEqual(DimensionStatus.passed, report.tier_ladder.software_only);
    try std.testing.expectEqual(DimensionStatus.partial, report.tier_ladder.hardware_in_loop);
    try std.testing.expectEqual(DimensionStatus.missing, report.tier_ladder.flight_test);
}
