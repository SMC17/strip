//! Analogical trajectory memory (MAC/FAC-style structural retrieval).
//!
//! Not embeddings. Episodes carry discrete structural features; retrieval ranks
//! by feature overlap (MAC) then optional deeper structure score (FAC stub).
//!
//! `EmbeddingLane` is an explicit not-wired stub — do not fake vectors.
//! Structural MAC/FAC remains authoritative.

const std = @import("std");

/// Embedding retrieval lane — **not wired**.
/// Structural MAC/FAC (`Store.retrieve`) remains authoritative until a real
/// embedding backend is integrated. Do not fake embeddings.
pub const EmbeddingLane = struct {
    pub const status_note =
        "not wired; structural MAC/FAC remains authoritative";

    pub const Status = enum { not_wired };

    status: Status = .not_wired,

    pub fn isWired(self: EmbeddingLane) bool {
        _ = self;
        return false;
    }

    /// Always fails — embeddings are not faked.
    pub fn retrieve(_: *const EmbeddingLane, _: []const u8, _: []Hit) error{EmbeddingLaneNotWired}!usize {
        return error.EmbeddingLaneNotWired;
    }
};

pub const Feature = enum {
    parser_edit,
    control_gain,
    atmosphere_table,
    hil_loop,
    claim_overreach,
    test_pass_hidden_fail,
    policy_denial,
    duplicate_delivery,
};

pub const Episode = struct {
    id: []const u8,
    features: []const Feature,
    outcome: []const u8,
    recovery: []const u8 = "",
};

pub const Hit = struct {
    episode_id: []const u8,
    overlap: usize,
    fac_score: f64,
};

pub const Store = struct {
    episodes: []Episode,
    len: usize = 0,

    pub fn init(buf: []Episode) Store {
        return .{ .episodes = buf };
    }

    pub fn add(self: *Store, episode: Episode) !void {
        if (episode.id.len == 0 or episode.features.len == 0) return error.InvalidEpisode;
        if (self.len == self.episodes.len) return error.CapacityExceeded;
        self.episodes[self.len] = episode;
        self.len += 1;
    }

    fn overlapCount(a: []const Feature, b: []const Feature) usize {
        var n: usize = 0;
        for (a) |fa| {
            for (b) |fb| {
                if (fa == fb) {
                    n += 1;
                    break;
                }
            }
        }
        return n;
    }

    /// FAC: ordered pairwise feature adjacency bonus + recovery preference.
    fn facScore(episode: Episode, query: []const Feature, want_recovery: bool) f64 {
        var order_bonus: f64 = 0;
        if (query.len >= 2 and episode.features.len >= 2) {
            var qi: usize = 0;
            while (qi + 1 < query.len) : (qi += 1) {
                const a = query[qi];
                const b = query[qi + 1];
                var ei: usize = 0;
                while (ei + 1 < episode.features.len) : (ei += 1) {
                    if (episode.features[ei] == a and episode.features[ei + 1] == b) order_bonus += 0.5;
                }
            }
        }
        const recovery_bonus: f64 = if (want_recovery and episode.recovery.len > 0) 1.25 else if (want_recovery) 0.75 else 1.0;
        return recovery_bonus + order_bonus;
    }

    pub fn retrieve(self: *const Store, query: []const Feature, want_recovery: bool, out: []Hit) !usize {
        if (query.len == 0) return error.EmptyQuery;
        var n: usize = 0;
        for (self.episodes[0..self.len]) |ep| {
            const ov = overlapCount(query, ep.features);
            if (ov == 0) continue;
            if (n == out.len) break;
            out[n] = .{
                .episode_id = ep.id,
                .overlap = ov,
                .fac_score = @as(f64, @floatFromInt(ov)) * facScore(ep, query, want_recovery),
            };
            n += 1;
        }
        // Sort by fac_score descending (simple insertion).
        var i: usize = 1;
        while (i < n) : (i += 1) {
            var j = i;
            while (j > 0 and out[j].fac_score > out[j - 1].fac_score) : (j -= 1) {
                const tmp = out[j - 1];
                out[j - 1] = out[j];
                out[j] = tmp;
            }
        }
        return n;
    }
};

pub fn seedCorpus(buf: []Episode) !Store {
    var store = Store.init(buf);
    try store.add(.{
        .id = "ep-us76-coverage",
        .features = &.{ .atmosphere_table, .claim_overreach },
        .outcome = "unsupported claim rejected",
        .recovery = "require verification_completed passed",
    });
    try store.add(.{
        .id = "ep-hil-latency",
        .features = &.{ .hil_loop, .duplicate_delivery },
        .outcome = "idempotent delivery",
        .recovery = "dedupe by delivery_id",
    });
    try store.add(.{
        .id = "ep-pitch-gain",
        .features = &.{ .control_gain, .test_pass_hidden_fail },
        .outcome = "gain change without MC/HIL",
        .recovery = "safety_critical contract + monte_carlo",
    });
    try store.add(.{
        .id = "ep-policy-deny",
        .features = &.{ .policy_denial, .claim_overreach },
        .outcome = "counterfactual denial path",
        .recovery = "no claim without approval",
    });
    return store;
}

pub fn selftest() !Hit {
    // Embedding lane must stay unwired; structural MAC/FAC wins.
    var lane = EmbeddingLane{};
    if (lane.isWired()) return error.EmbeddingLaneUnexpectedlyWired;
    var emb_hits: [1]Hit = undefined;
    if (lane.retrieve("atmosphere claim overreach", &emb_hits)) |_| {
        return error.EmbeddingLaneMustNotReturnHits;
    } else |err| {
        if (err != error.EmbeddingLaneNotWired) return error.UnexpectedEmbeddingError;
    }

    var buf: [8]Episode = undefined;
    const store = try seedCorpus(&buf);
    var hits: [4]Hit = undefined;
    const n = try store.retrieve(&.{ .atmosphere_table, .claim_overreach }, true, &hits);
    if (n == 0) return error.NoAnalogicalHit;
    if (!std.mem.eql(u8, hits[0].episode_id, "ep-us76-coverage")) return error.WrongTopHit;
    return hits[0];
}

test "analogical retrieval ranks US76 episode" {
    const hit = try selftest();
    try std.testing.expectEqualStrings("ep-us76-coverage", hit.episode_id);
}

test "EmbeddingLane stub yields to structural MAC/FAC" {
    var lane = EmbeddingLane{};
    try std.testing.expect(!lane.isWired());
    try std.testing.expectEqualStrings(
        EmbeddingLane.status_note,
        "not wired; structural MAC/FAC remains authoritative",
    );
    var emb_hits: [1]Hit = undefined;
    try std.testing.expectError(error.EmbeddingLaneNotWired, lane.retrieve("probe", &emb_hits));
    const structural = try selftest();
    try std.testing.expectEqualStrings("ep-us76-coverage", structural.episode_id);
}
