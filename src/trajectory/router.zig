//! Multi-model router: intent × cost × latency × risk selection.
//!
//! "Live" means registry + env capability probes (API key present). Verify never
//! calls external model APIs — selection is deterministic over a fixture registry.

const std = @import("std");

pub const Intent = enum {
    ask,
    plan,
    agent,
    research,
    validation,
    hil,
    long_horizon,
};

pub const Provider = enum {
    strip_local,
    openrouter,
    grok,
    claude,
    gpt,
    gemini,
    ollama,
};

pub const ModelConfig = struct {
    id: []const u8,
    provider: Provider,
    intents: []const Intent,
    /// Higher is better expected success (0..1).
    p_success: f64,
    /// Relative cost units.
    cost: f64,
    /// Relative latency units.
    latency: f64,
    /// Operational/security risk units.
    risk: f64,
    /// True when env suggests credentials exist (never used to call out in verify).
    live_capable: bool = false,
};

pub const Weights = struct {
    lambda_cost: f64 = 0.2,
    mu_latency: f64 = 0.2,
    nu_risk: f64 = 0.3,
};

pub const Selection = struct {
    model_id: []const u8,
    provider: Provider,
    score: f64,
    intent: Intent,
    candidates_considered: usize,
    live_capable: bool,
};

fn supportsIntent(model: ModelConfig, intent: Intent) bool {
    for (model.intents) |i| if (i == intent) return true;
    return false;
}

pub fn score(model: ModelConfig, w: Weights) f64 {
    return model.p_success - w.lambda_cost * model.cost - w.mu_latency * model.latency - w.nu_risk * model.risk;
}

pub fn select(models: []const ModelConfig, intent: Intent, w: Weights) !Selection {
    var best: ?Selection = null;
    var considered: usize = 0;
    for (models) |m| {
        if (!supportsIntent(m, intent)) continue;
        considered += 1;
        const s = score(m, w);
        if (best == null or s > best.?.score) {
            best = .{
                .model_id = m.id,
                .provider = m.provider,
                .score = s,
                .intent = intent,
                .candidates_considered = 0,
                .live_capable = m.live_capable,
            };
        }
    }
    var result = best orelse return error.NoModelForIntent;
    result.candidates_considered = considered;
    return result;
}

/// Fixture registry used by verify (no network).
pub fn probeLive(environ: anytype) struct { gemini: bool, openrouter: bool } {
    const gemini = environ.get("GOOGLE_API_KEY") != null or environ.get("GEMINI_API_KEY") != null;
    const openrouter = environ.get("OPENROUTER_API_KEY") != null;
    return .{ .gemini = gemini, .openrouter = openrouter };
}

pub fn fixtureRegistry(live_gemini: bool, live_openrouter: bool) [5]ModelConfig {
    return .{
        .{
            .id = "strip-trajectory-local",
            .provider = .strip_local,
            .intents = &.{ .ask, .plan, .agent, .validation, .hil },
            .p_success = 0.72,
            .cost = 0.05,
            .latency = 0.1,
            .risk = 0.05,
            .live_capable = true,
        },
        .{
            .id = "grok-4.5",
            .provider = .grok,
            .intents = &.{ .ask, .plan, .agent, .research, .long_horizon },
            .p_success = 0.88,
            .cost = 0.7,
            .latency = 0.5,
            .risk = 0.25,
            .live_capable = live_openrouter,
        },
        .{
            .id = "claude-opus",
            .provider = .claude,
            .intents = &.{ .ask, .plan, .agent, .research },
            .p_success = 0.9,
            .cost = 0.85,
            .latency = 0.55,
            .risk = 0.2,
            .live_capable = live_openrouter,
        },
        .{
            .id = "gpt-flagship",
            .provider = .gpt,
            .intents = &.{ .ask, .plan, .agent },
            .p_success = 0.86,
            .cost = 0.8,
            .latency = 0.5,
            .risk = 0.22,
            .live_capable = live_openrouter,
        },
        .{
            .id = "gemini-3.5-flash",
            .provider = .gemini,
            .intents = &.{ .ask, .plan, .research },
            .p_success = 0.8,
            .cost = 0.35,
            .latency = 0.35,
            .risk = 0.3,
            .live_capable = live_gemini,
        },
    };
}

pub fn selftest() !Selection {
    const models = fixtureRegistry(false, false);
    const for_hil = try select(&models, .hil, .{});
    if (!std.mem.eql(u8, for_hil.model_id, "strip-trajectory-local")) return error.RouterHilExpectedLocal;
    const for_research = try select(&models, .research, .{});
    // claude 0.9 - 0.2*0.85 - 0.2*0.55 - 0.3*0.2 = 0.9 - 0.17 - 0.11 - 0.06 = 0.56
    // grok 0.88 - 0.14 - 0.1 - 0.075 = 0.565
    if (for_research.candidates_considered < 2) return error.RouterResearchTooFew;
    return for_hil;
}

test "router prefers local for hil intent" {
    const sel = try selftest();
    try std.testing.expectEqualStrings("strip-trajectory-local", sel.model_id);
}

test "router rejects unsupported intent" {
    const models = [_]ModelConfig{.{
        .id = "only-ask",
        .provider = .ollama,
        .intents = &.{.ask},
        .p_success = 1.0,
        .cost = 0,
        .latency = 0,
        .risk = 0,
    }};
    try std.testing.expectError(error.NoModelForIntent, select(&models, .hil, .{}));
}
