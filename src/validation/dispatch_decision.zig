//! Dispatch decision evidence engine (advisory; never operationally qualified).

const std = @import("std");

pub const schema = "strip.dispatch-decision-evidence.v0";

pub const CarrierPart = enum {
    @"91",
    @"135",
    @"121",
    uas,
};

pub const GapCategory = enum {
    fragmented_systems,
    duty_legality,
    weather_windows,
    escalation_authority,
    static_frat,
    external_pressure,
    maintenance_patterns,
    institutional_memory,
    broker_comms,
    sms_compliance,
};

pub const WeatherSourceClass = enum {
    opsspec_approved,
    platform_candidate,
    unapproved_ai,
};

pub const DecisionInput = struct {
    decision_id: []const u8,
    carrier_part: CarrierPart,
    role: []const u8,
    requested_go: bool,
    weather_source_class: WeatherSourceClass,
    explicit_gaps: []const GapCategory = &.{},
    duty_near_limit: bool = false,
    weather_marginal: bool = false,
    owner_pressure: bool = false,
    mel_pattern_risk: bool = false,
    ai_participation: []const u8 = "advisory engine only; human retains release authority",
};

pub const Decision = struct {
    schema: []const u8 = schema,
    decision_id: []const u8,
    carrier_part: CarrierPart,
    gap_categories: []const GapCategory,
    role: []const u8,
    final_go_no_go: bool,
    weather_source_class: WeatherSourceClass,
    ai_participation: []const u8,
    operational_qualification_claimed: bool = false,
    recommendation: []const u8,
};

pub fn decide(allocator: std.mem.Allocator, input: DecisionInput) !struct {
    decision: Decision,
    gaps_owned: []GapCategory,
} {
    var gaps: std.ArrayList(GapCategory) = .empty;
    errdefer gaps.deinit(allocator);

    const add = struct {
        fn call(list: *std.ArrayList(GapCategory), alloc: std.mem.Allocator, gap: GapCategory) !void {
            for (list.items) |existing| if (existing == gap) return;
            try list.append(alloc, gap);
        }
    }.call;

    for (input.explicit_gaps) |gap| try add(&gaps, allocator, gap);
    if (input.duty_near_limit) try add(&gaps, allocator, .duty_legality);
    if (input.weather_marginal) try add(&gaps, allocator, .weather_windows);
    if (input.owner_pressure) try add(&gaps, allocator, .external_pressure);
    if (input.mel_pattern_risk) try add(&gaps, allocator, .maintenance_patterns);
    if (input.weather_source_class == .unapproved_ai) try add(&gaps, allocator, .sms_compliance);

    if (gaps.items.len == 0) try add(&gaps, allocator, .escalation_authority);

    var go = input.requested_go;
    var recommendation: []const u8 = if (go) "go" else "no_go";

    // Hard advisory rails — never claim qualification; block unsafe weather class.
    if (input.weather_source_class == .unapproved_ai) {
        go = false;
        recommendation = "no_go_unapproved_weather";
    } else if (input.owner_pressure and input.requested_go) {
        recommendation = "escalate_external_pressure";
        // Keep human-requested go only if weather is OpsSpec-approved and duty ok.
        if (input.weather_source_class != .opsspec_approved or input.duty_near_limit) {
            go = false;
            recommendation = "no_go_pressure_with_risk";
        }
    } else if (input.duty_near_limit and input.requested_go) {
        go = false;
        recommendation = "no_go_duty_limit";
    } else if (input.weather_marginal and input.requested_go and input.weather_source_class == .platform_candidate) {
        recommendation = "escalate_weather_window";
    }

    const owned = try gaps.toOwnedSlice(allocator);
    return .{
        .decision = .{
            .decision_id = input.decision_id,
            .carrier_part = input.carrier_part,
            .gap_categories = owned,
            .role = input.role,
            .final_go_no_go = go,
            .weather_source_class = input.weather_source_class,
            .ai_participation = input.ai_participation,
            .operational_qualification_claimed = false,
            .recommendation = recommendation,
        },
        .gaps_owned = owned,
    };
}

pub fn formatJson(allocator: std.mem.Allocator, decision: Decision) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    const head = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"{s}\",\"decision_id\":\"{s}\",\"carrier_part\":\"{s}\",\"gap_categories\":[",
        .{ decision.schema, decision.decision_id, @tagName(decision.carrier_part) },
    );
    defer allocator.free(head);
    try list.appendSlice(allocator, head);
    for (decision.gap_categories, 0..) |gap, i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(allocator, "\"{s}\"", .{@tagName(gap)});
        defer allocator.free(item);
        try list.appendSlice(allocator, item);
    }
    const tail = try std.fmt.allocPrint(
        allocator,
        "],\"human_authority\":{{\"role\":\"{s}\",\"final_go_no_go\":{}}},\"weather_source_class\":\"{s}\",\"ai_participation\":\"{s}\",\"recommendation\":\"{s}\",\"operational_qualification_claimed\":false}}\n",
        .{
            decision.role,
            decision.final_go_no_go,
            @tagName(decision.weather_source_class),
            decision.ai_participation,
            decision.recommendation,
        },
    );
    defer allocator.free(tail);
    try list.appendSlice(allocator, tail);
    return try list.toOwnedSlice(allocator);
}

test "unapproved AI weather forces no-go" {
    const got = try decide(std.testing.allocator, .{
        .decision_id = "test-1",
        .carrier_part = .@"135",
        .role = "dispatcher",
        .requested_go = true,
        .weather_source_class = .unapproved_ai,
    });
    defer std.testing.allocator.free(got.gaps_owned);
    try std.testing.expect(!got.decision.final_go_no_go);
    try std.testing.expect(!got.decision.operational_qualification_claimed);
    try std.testing.expectEqualStrings("no_go_unapproved_weather", got.decision.recommendation);
}

test "duty near limit blocks go" {
    const got = try decide(std.testing.allocator, .{
        .decision_id = "test-2",
        .carrier_part = .@"135",
        .role = "director_of_ops",
        .requested_go = true,
        .weather_source_class = .opsspec_approved,
        .duty_near_limit = true,
    });
    defer std.testing.allocator.free(got.gaps_owned);
    try std.testing.expect(!got.decision.final_go_no_go);
    try std.testing.expectEqualStrings("no_go_duty_limit", got.decision.recommendation);
}
