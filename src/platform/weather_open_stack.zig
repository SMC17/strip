//! Open multi-model stack that substitutes for WeatherNext 2 (Vertex EAP).
//!
//! Platform plane only. No member is OpsSpec weather or simulation truth.
//! Honest bottom line (2026-07-11): no public apples-to-apples proof that any
//! single open model beats WeatherNext 2 overall — build a multi-model stack.

const std = @import("std");

pub const schema_catalog = "strip.weather.open-stack.catalog.v0";
pub const schema_plan = "strip.weather.open-stack.plan.v0";

pub const Tier = enum {
    tier1_wn2_competitor,
    tier2_specialist,
    tier3_supporting,
    proprietary_not_open,
};

pub const Deployability = enum {
    open_weights_commercial,
    open_weights_noncommercial,
    operational_open_data,
    code_only,
    paper_or_data_only,
    proprietary,
    interim_http_bridge,
};

pub const Role = enum {
    operational_anchor,
    frontier_ensemble,
    large_ensemble_engine,
    deterministic_detail,
    regional_refinement,
    nowcast,
    calibration_target,
    reference_baseline,
    research_only,
};

pub const Entry = struct {
    id: []const u8,
    name: []const u8,
    tier: Tier,
    role: Role,
    deployability: Deployability,
    license_note: []const u8,
    resolution: []const u8,
    horizon: []const u8,
    strip_surface: []const u8,
    verdict: []const u8,
};

/// Tier-1 + key Tier-2 catalog. Not an inference runtime — doctrine + routing map.
pub const catalog = [_]Entry{
    .{
        .id = "atlas",
        .name = "NVIDIA Earth-2 / Atlas",
        .tier = .tier1_wn2_competitor,
        .role = .frontier_ensemble,
        .deployability = .open_weights_commercial,
        .license_note = "NVIDIA Open Model License (commercial allowed)",
        .resolution = "0.25°",
        .horizon = "15d ensemble",
        .strip_surface = "catalog; Earth2Studio adapter deferred",
        .verdict = "Closest open-weight WN2 alternative; no published direct WN2 bake-off",
    },
    .{
        .id = "aifs_ens_v2",
        .name = "ECMWF AIFS ENS v2",
        .tier = .tier1_wn2_competitor,
        .role = .operational_anchor,
        .deployability = .operational_open_data,
        .license_note = "Weights CC BY 4.0; scripts Apache-2.0",
        .resolution = "~31 km",
        .horizon = "15d / 51-member / 6h / 4x daily",
        .strip_surface = "strip-weathernext fetch --live --interim aifs",
        .verdict = "Best operationally grounded open model; live via Open-Meteo ecmwf_aifs025",
    },
    .{
        .id = "fourcastnet3",
        .name = "NVIDIA FourCastNet 3",
        .tier = .tier1_wn2_competitor,
        .role = .large_ensemble_engine,
        .deployability = .open_weights_commercial,
        .license_note = "Apache-2.0 code+weights",
        .resolution = "0.25°",
        .horizon = "6h steps; long rollouts demonstrated",
        .strip_surface = "catalog; Earth2Studio adapter deferred",
        .verdict = "Best permissive scalable ensemble engine",
    },
    .{
        .id = "gencast",
        .name = "Google GenCast",
        .tier = .tier1_wn2_competitor,
        .role = .reference_baseline,
        .deployability = .open_weights_noncommercial,
        .license_note = "Apache-2.0 code; weights CC BY-NC-SA 4.0",
        .resolution = "0.25°",
        .horizon = "15d / 12h steps",
        .strip_surface = "catalog",
        .verdict = "Clean predecessor architecture; WN2 reported ~10–20% better; NC weights",
    },
    .{
        .id = "u_cast",
        .name = "U-Cast",
        .tier = .tier1_wn2_competitor,
        .role = .research_only,
        .deployability = .code_only,
        .license_note = "Source public; verify license before commercial",
        .resolution = "principally 1.5°",
        .horizon = "15d (seconds-scale)",
        .strip_surface = "catalog",
        .verdict = "Efficiency research; too coarse for direct WN2 replacement",
    },
    .{
        .id = "archesweathergen",
        .name = "ArchesWeatherGen",
        .tier = .tier1_wn2_competitor,
        .role = .research_only,
        .deployability = .code_only,
        .license_note = "BSD-3 reproducible stack",
        .resolution = "1.5°",
        .horizon = "15d / 24h steps",
        .strip_surface = "catalog",
        .verdict = "Best low-budget reproducible academic system; resolution gap vs WN2",
    },
    .{
        .id = "neuralgcm_ens",
        .name = "NeuralGCM ENS",
        .tier = .tier1_wn2_competitor,
        .role = .research_only,
        .deployability = .open_weights_commercial,
        .license_note = "Apache-2.0 code; CC BY-SA 4.0 weights",
        .resolution = "hybrid physics-ML",
        .horizon = "climate + probabilistic",
        .strip_surface = "catalog",
        .verdict = "Physics-aware / climate experiments; not strongest 0.25° ops forecaster",
    },
    .{
        .id = "fuxi_ens",
        .name = "FuXi-ENS",
        .tier = .tier1_wn2_competitor,
        .role = .research_only,
        .deployability = .paper_or_data_only,
        .license_note = "Paper/datasets; full deployable weights not verified",
        .resolution = "0.25°",
        .horizon = "15d / 6h ensemble",
        .strip_surface = "catalog",
        .verdict = "Competitive published CRPS; not treated as deployable yet",
    },
    .{
        .id = "aurora",
        .name = "Microsoft Aurora",
        .tier = .tier2_specialist,
        .role = .deterministic_detail,
        .deployability = .open_weights_commercial,
        .license_note = "Public code+weights; contact Microsoft for commercial terms",
        .resolution = "multi-modality foundation",
        .horizon = "weather / waves / composition variants",
        .strip_surface = "catalog",
        .verdict = "Foundation adaptation + multi-Earth-system modalities",
    },
    .{
        .id = "fuxi_2_1",
        .name = "FuXi 2.1",
        .tier = .tier2_specialist,
        .role = .deterministic_detail,
        .deployability = .open_weights_commercial,
        .license_note = "CC BY 4.0 (Jun 2026)",
        .resolution = "0.25°",
        .horizon = "10d / 6h deterministic",
        .strip_surface = "catalog",
        .verdict = "Sharp fields / extremes; evaluation sample still limited",
    },
    .{
        .id = "oneforecast",
        .name = "OneForecast",
        .tier = .tier2_specialist,
        .role = .regional_refinement,
        .deployability = .open_weights_commercial,
        .license_note = "MIT",
        .resolution = "global-to-regional nested",
        .horizon = "trainable refinement",
        .strip_surface = "catalog",
        .verdict = "Nested regional high-frequency structure",
    },
    .{
        .id = "graphcast",
        .name = "GraphCast",
        .tier = .tier3_supporting,
        .role = .reference_baseline,
        .deployability = .open_weights_noncommercial,
        .license_note = "Apache-2.0 code; CC BY-NC-SA weights",
        .resolution = "0.25°",
        .horizon = "10d / 6h deterministic",
        .strip_surface = "catalog",
        .verdict = "Important baseline; materially behind GenCast/Atlas/AIFS/WN2",
    },
    .{
        .id = "weathernext_2",
        .name = "Google WeatherNext 2",
        .tier = .proprietary_not_open,
        .role = .research_only,
        .deployability = .proprietary,
        .license_note = "Proprietary; Vertex EAP; no public REST weights",
        .resolution = "0.25°",
        .horizon = "15d / 6h / 64-member",
        .strip_surface = "strip-weathernext (EAP blocked)",
        .verdict = "Target competitor — not open; forecasts via Google products only",
    },
    .{
        .id = "open_meteo_bridge",
        .name = "Open-Meteo HTTP bridge",
        .tier = .tier3_supporting,
        .role = .calibration_target,
        .deployability = .interim_http_bridge,
        .license_note = "Open-Meteo ToS; aggregates ECMWF/AIFS/etc.",
        .resolution = "varies by model",
        .horizon = "varies",
        .strip_surface = "strip-weathernext fetch --live --interim open-meteo|aifs|ifs",
        .verdict = "Interim live member until Earth2Studio/local weights land",
    },
    .{
        .id = "nws_bridge",
        .name = "NOAA/NWS points",
        .tier = .tier3_supporting,
        .role = .calibration_target,
        .deployability = .interim_http_bridge,
        .license_note = "US Gov public data; User-Agent required",
        .resolution = "point metadata → grid forecast",
        .horizon = "short-range NWS",
        .strip_surface = "strip-weathernext fetch --live --interim nws",
        .verdict = "Observation/nowcast calibration rail; not a WN2 ensemble",
    },
};

/// Production plan: concurrent members + regional/calibration layers.
pub const PlanMember = struct {
    id: []const u8,
    role: Role,
    required: bool,
};

pub const production_plan = [_]PlanMember{
    .{ .id = "aifs_ens_v2", .role = .operational_anchor, .required = true },
    .{ .id = "atlas", .role = .frontier_ensemble, .required = true },
    .{ .id = "fourcastnet3", .role = .large_ensemble_engine, .required = true },
    .{ .id = "fuxi_2_1", .role = .deterministic_detail, .required = false },
    .{ .id = "aurora", .role = .deterministic_detail, .required = false },
    .{ .id = "oneforecast", .role = .regional_refinement, .required = false },
    .{ .id = "nws_bridge", .role = .calibration_target, .required = false },
};

pub const framework_note =
    "Earth2Studio is the preferred integration layer (GraphCast/Pangu/Aurora/FuXi/AIFS/U-Cast). Local weight runners are deferred; Open-Meteo+NWS are interim HTTP bridges only.";

pub const killer_stack_blurb =
    "AIFS ENS v2 + Atlas + FourCastNet 3 + regional OneForecast/StormScope + local calibration — more open/auditable than WN2 even without a single-model CRPS win.";

fn escapeJson(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (s) |c| {
        switch (c) {
            '"' => try list.appendSlice(allocator, "\\\""),
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\n' => try list.appendSlice(allocator, "\\n"),
            else => try list.append(allocator, c),
        }
    }
    return try list.toOwnedSlice(allocator);
}

pub fn formatCatalogJson(allocator: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, "{\"schema\":\"");
    try list.appendSlice(allocator, schema_catalog);
    try list.appendSlice(allocator, "\",\"plane\":\"platform\",\"authoritative\":false,\"operational_qualification_claimed\":false,\"weathernext_2_status\":\"eap_no_public_rest\",\"bottom_line\":\"no_single_open_model_proven_to_beat_wn2_overall\",\"entries\":[");
    for (catalog, 0..) |e, i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        const verdict = try escapeJson(allocator, e.verdict);
        defer allocator.free(verdict);
        const license = try escapeJson(allocator, e.license_note);
        defer allocator.free(license);
        const item = try std.fmt.allocPrint(
            allocator,
            "{{\"id\":\"{s}\",\"name\":\"{s}\",\"tier\":\"{s}\",\"role\":\"{s}\",\"deployability\":\"{s}\",\"license_note\":\"{s}\",\"resolution\":\"{s}\",\"horizon\":\"{s}\",\"strip_surface\":\"{s}\",\"verdict\":\"{s}\"}}",
            .{ e.id, e.name, @tagName(e.tier), @tagName(e.role), @tagName(e.deployability), license, e.resolution, e.horizon, e.strip_surface, verdict },
        );
        defer allocator.free(item);
        try list.appendSlice(allocator, item);
    }
    try list.appendSlice(allocator, "]}\n");
    return try list.toOwnedSlice(allocator);
}

pub fn formatPlanJson(allocator: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, "{\"schema\":\"");
    try list.appendSlice(allocator, schema_plan);
    try list.appendSlice(allocator, "\",\"plane\":\"platform\",\"authoritative\":false,\"operational_qualification_claimed\":false,\"framework\":\"");
    const fw = try escapeJson(allocator, framework_note);
    defer allocator.free(fw);
    try list.appendSlice(allocator, fw);
    try list.appendSlice(allocator, "\",\"killer_stack\":\"");
    const ks = try escapeJson(allocator, killer_stack_blurb);
    defer allocator.free(ks);
    try list.appendSlice(allocator, ks);
    try list.appendSlice(allocator, "\",\"members\":[");
    for (production_plan, 0..) |m, i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(
            allocator,
            "{{\"id\":\"{s}\",\"role\":\"{s}\",\"required\":{}}}",
            .{ m.id, @tagName(m.role), m.required },
        );
        defer allocator.free(item);
        try list.appendSlice(allocator, item);
    }
    try list.appendSlice(allocator, "],\"calibration\":[\"EMOS\",\"isotonic\",\"learned_quantile_mapping\"],\"regional\":[\"oneforecast\",\"stormscope\",\"wrf_or_mpas_or_fv3\"]}\n");
    return try list.toOwnedSlice(allocator);
}

pub fn requireCoreIds() bool {
    var saw_atlas = false;
    var saw_aifs = false;
    var saw_fcn = false;
    for (catalog) |e| {
        if (std.mem.eql(u8, e.id, "atlas")) saw_atlas = true;
        if (std.mem.eql(u8, e.id, "aifs_ens_v2")) saw_aifs = true;
        if (std.mem.eql(u8, e.id, "fourcastnet3")) saw_fcn = true;
    }
    return saw_atlas and saw_aifs and saw_fcn;
}

test "open stack catalog includes WN2 killer core" {
    try std.testing.expect(requireCoreIds());
}

test "production plan requires AIFS+Atlas+FCN3" {
    var req: usize = 0;
    for (production_plan) |m| {
        if (m.required) req += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), req);
}
