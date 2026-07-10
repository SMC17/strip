//! Flight-qualification evidence framework (structure only — never operational claims).

const std = @import("std");
const evidence = @import("evidence.zig");
const campaign = @import("campaign.zig");
const campaign_calibration = @import("../uncertainty/campaign_calibration.zig");
const telemetry_csv = @import("telemetry_csv.zig");

pub const Tier = enum {
    software_only,
    hardware_in_loop,
    flight_test,
};

pub const DimensionStatus = enum {
    passed,
    pending,
    missing,
};

pub const Report = struct {
    tier: Tier,
    evidence_manifest_passed: bool,
    campaign_passed: bool,
    holdout_calibration_passed: bool,
    operational_qualification_claimed: bool,
    passed: bool,
};

pub fn evaluateSoftwareOnly(
    manifest: evidence.Manifest,
    campaign_fixture: campaign.Campaign,
    calibration_report: campaign_calibration.CalibrationReport,
) !Report {
    try manifest.validate();
    try campaign_fixture.validate();
    const evidence_manifest_passed = manifest.sealed and !manifest.operational_qualification_claimed;
    const campaign_passed = campaign_fixture.test_cards.len > 0 and
        campaign_fixture.split_policy.calibration_run_ids.len > 0 and
        campaign_fixture.split_policy.blinded_holdout_run_ids.len > 0;
    const holdout_calibration_passed = calibration_report.holdout_passed;
    const passed = evidence_manifest_passed and campaign_passed and holdout_calibration_passed;
    return .{
        .tier = .software_only,
        .evidence_manifest_passed = evidence_manifest_passed,
        .campaign_passed = campaign_passed,
        .holdout_calibration_passed = holdout_calibration_passed,
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

    const calibration_report = try campaign_calibration.evaluateSyntheticCampaign(
        campaign_parsed.value,
        rows,
    );
    return try evaluateSoftwareOnly(manifest_parsed.value, campaign_parsed.value, calibration_report);
}

test "software-only qualification framework passes synthetic fixtures" {
    const report = try evaluateFromFixtures(std.testing.allocator, std.testing.io);
    try std.testing.expect(report.passed);
    try std.testing.expect(!report.operational_qualification_claimed);
}
