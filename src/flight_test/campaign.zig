//! Flight-test campaign fixture loader for calibration and holdout gates.

const std = @import("std");
const cards = @import("cards.zig");

pub const Campaign = struct {
    schema: []const u8,
    campaign_id: []const u8,
    configuration: cards.ConfigurationIdentity,
    test_cards: []const CampaignCard,
    split_policy: CampaignSplitPolicy,
    limitations: []const []const u8,

    pub fn validate(self: Campaign) !void {
        if (!std.mem.eql(u8, self.schema, "strip.flight-test-campaign.v1"))
            return error.UnsupportedSchema;
        try bounded(self.campaign_id, 1, 96);
        try self.configuration.validate();
        if (self.test_cards.len == 0 or self.test_cards.len > 256) return error.InvalidCardCount;
        for (self.test_cards, 0..) |card, index| {
            try card.validate();
            for (self.test_cards[0..index]) |prior|
                if (std.mem.eql(u8, prior.card_id, card.card_id)) return error.DuplicateCardId;
        }
        try self.split_policy.validate();
        if (self.limitations.len == 0) return error.MissingLimitations;
    }

    pub fn splitPolicy(self: Campaign, allocator: std.mem.Allocator) !cards.SplitPolicy {
        var runs = try std.ArrayList(cards.RunIdentity).initCapacity(allocator, self.split_policy.calibration_run_ids.len + self.split_policy.blinded_holdout_run_ids.len);
        defer runs.deinit(allocator);
        for (self.split_policy.calibration_run_ids) |run_id| {
            try runs.append(allocator, .{ .run_id = run_id, .split = .calibration });
        }
        for (self.split_policy.blinded_holdout_run_ids) |run_id| {
            try runs.append(allocator, .{ .run_id = run_id, .split = .blinded_holdout });
        }
        return .{
            .policy_id = self.split_policy.policy_id,
            .sealed_before_analysis_utc = self.split_policy.sealed_before_analysis_utc,
            .runs = try runs.toOwnedSlice(allocator),
        };
    }
};

pub const CampaignCard = struct {
    card_id: []const u8,
    vehicle: []const u8,
    maneuver: []const u8,
    axis: []const u8,

    pub fn validate(self: CampaignCard) !void {
        try bounded(self.card_id, 1, 64);
        try bounded(self.vehicle, 1, 32);
        try bounded(self.maneuver, 1, 32);
        try bounded(self.axis, 1, 32);
    }
};

pub const CampaignSplitPolicy = struct {
    policy_id: []const u8,
    sealed_before_analysis_utc: []const u8,
    calibration_run_ids: []const []const u8,
    blinded_holdout_run_ids: []const []const u8,

    pub fn validate(self: CampaignSplitPolicy) !void {
        try bounded(self.policy_id, 1, 64);
        if (self.sealed_before_analysis_utc.len < 20 or self.sealed_before_analysis_utc[self.sealed_before_analysis_utc.len - 1] != 'Z')
            return error.InvalidSealTime;
        if (self.calibration_run_ids.len == 0 or self.blinded_holdout_run_ids.len == 0)
            return error.IncompleteSplit;
    }
};

pub fn parseCampaign(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Campaign) {
    if (bytes.len > 512 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(Campaign, allocator, bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

fn bounded(value: []const u8, min: usize, max: usize) !void {
    if (value.len < min or value.len > max) return error.InvalidBoundedString;
}

test "synthetic campaign fixture parses" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/flight-test/synthetic-campaign.json",
        std.testing.allocator,
        .limited(512 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var parsed = try parseCampaign(std.testing.allocator, bytes);
    defer parsed.deinit();
    const policy = try parsed.value.splitPolicy(std.testing.allocator);
    defer std.testing.allocator.free(policy.runs);
    try policy.validate();
}
