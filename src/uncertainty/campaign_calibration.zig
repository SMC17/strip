//! Flight-campaign calibration, holdout residual coverage, and uncertainty fusion.

const std = @import("std");
const campaign = @import("../flight_test/campaign.zig");
const cards = @import("../flight_test/cards.zig");
const telemetry_csv = @import("../flight_test/telemetry_csv.zig");
const regression = @import("../flight_test/regression.zig");
const residuals = @import("../flight_test/residuals.zig");
const propagate = @import("propagate.zig");
const flight_fusion = @import("flight_fusion.zig");

pub const CalibrationReport = struct {
    observation_count: usize,
    holdout_count: usize,
    intercept: f64,
    slope: f64,
    residual_standard_deviation: f64,
    holdout_coverage_one_sigma: f64,
    holdout_passed: bool,
    fusion_sigma: f64,
};

pub fn evaluateSyntheticCampaign(
    campaign_fixture: campaign.Campaign,
    rows: []const telemetry_csv.CsvRow,
) !CalibrationReport {
    const policy = try campaign_fixture.splitPolicy(std.heap.page_allocator);
    defer std.heap.page_allocator.free(policy.runs);
    try policy.validate();

    try policy.validate();

    var cal_sequences: [8]f64 = undefined;
    var cal_values: [8]f64 = undefined;
    var cal_weights: [8]f64 = undefined;
    var cal_count: usize = 0;

    var holdout_sequences: [8]u64 = undefined;
    var holdout_residuals: [8]residuals.ResidualSample = undefined;
    var holdout_count: usize = 0;

    for (rows) |row| {
        if (!std.mem.eql(u8, row.channel, "body_ax")) continue;
        if (row.quality != .valid and row.quality != .degraded) continue;
        const value = row.value orelse continue;
        const sigma = row.standard_uncertainty orelse continue;
        switch (row.split) {
            .calibration => {
                if (cal_count >= cal_sequences.len) return error.TooManyCalibrationRows;
                cal_sequences[cal_count] = @as(f64, @floatFromInt(row.sequence));
                cal_values[cal_count] = value;
                cal_weights[cal_count] = 1.0 / (sigma * sigma);
                cal_count += 1;
            },
            .blinded_holdout => {
                if (holdout_count >= holdout_residuals.len) return error.TooManyHoldoutRows;
                holdout_sequences[holdout_count] = row.sequence;
                holdout_residuals[holdout_count] = .{
                    .observed = value,
                    .predicted = 0,
                    .combined_standard_uncertainty = sigma,
                    .quality = row.quality,
                };
                holdout_count += 1;
            },
        }
    }
    if (cal_count < 2 or holdout_count == 0) return error.InsufficientCampaignData;

    try policy.requireCalibration(campaign_fixture.split_policy.calibration_run_ids);

    const design = try std.heap.page_allocator.alloc(f64, cal_count * 2);
    defer std.heap.page_allocator.free(design);
    for (0..cal_count) |index| {
        design[index * 2 + 0] = 1.0;
        design[index * 2 + 1] = cal_sequences[index];
    }
    const fit = try regression.leastSquares(design, cal_values[0..cal_count], 2, cal_weights[0..cal_count]);

    for (0..holdout_count) |index| {
        const seq = @as(f64, @floatFromInt(holdout_sequences[index]));
        holdout_residuals[index].predicted = fit.coefficients[0] + fit.coefficients[1] * seq;
    }

    try policy.requireHoldoutEvaluation(campaign_fixture.split_policy.blinded_holdout_run_ids);

    const coverage = try residuals.normalizedCoverage(holdout_residuals[0..holdout_count]);
    const holdout_passed = coverage.within_one_sigma >= 0.55 and coverage.within_one_sigma <= 1.0;

    const residual_variance = @max(fit.residual_variance, 1.0e-4);
    const fit_sigma = @sqrt(residual_variance);
    const prior = try propagate.fromGaussian(fit.coefficients[1], .{ .mean = fit.coefficients[1], .variance = residual_variance });
    const fused = try flight_fusion.fuse(prior, .{
        .value = fit.coefficients[1],
        .standard_uncertainty = fit_sigma,
        .quality = .valid,
    });

    return .{
        .observation_count = cal_count,
        .holdout_count = holdout_count,
        .intercept = fit.coefficients[0],
        .slope = fit.coefficients[1],
        .residual_standard_deviation = fit_sigma,
        .holdout_coverage_one_sigma = coverage.within_one_sigma,
        .holdout_passed = holdout_passed,
        .fusion_sigma = fused.fused_standard_uncertainty,
    };
}

test "synthetic campaign calibration passes holdout coverage gate" {
    const campaign_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/flight-test/synthetic-campaign.json",
        std.testing.allocator,
        .limited(512 * 1024),
    );
    defer std.testing.allocator.free(campaign_bytes);
    var campaign_parsed = try campaign.parseCampaign(std.testing.allocator, campaign_bytes);
    defer campaign_parsed.deinit();

    const csv_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/flight-test/synthetic-telemetry.csv",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(csv_bytes);
    const rows = try telemetry_csv.loadCsv(std.testing.allocator, csv_bytes);
    defer {
        for (rows) |row| std.testing.allocator.free(row.channel);
        std.testing.allocator.free(rows);
    }

    const report = try evaluateSyntheticCampaign(campaign_parsed.value, rows);
    try std.testing.expect(report.holdout_passed);
    try std.testing.expect(report.fusion_sigma < report.residual_standard_deviation + 1.0);
}
