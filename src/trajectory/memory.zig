//! Explicit memory classes for long-horizon agent context (virtual memory map).
//!
//! Scaffold: classification + retention policy only. Not a vector store.

const std = @import("std");

pub const Class = enum {
    working,
    episodic,
    semantic,
    procedural,
    causal,
    normative,
};

pub const Entry = struct {
    class: Class,
    id: []const u8,
    content_digest_hex: []const u8,
    provenance: []const u8 = "",
};

pub const Retention = struct {
    class: Class,
    keep_in_prompt: bool,
    pageable: bool,
    requires_provenance: bool,

    pub fn forClass(class: Class) Retention {
        return switch (class) {
            .working => .{ .class = class, .keep_in_prompt = true, .pageable = false, .requires_provenance = false },
            .episodic => .{ .class = class, .keep_in_prompt = false, .pageable = true, .requires_provenance = true },
            .semantic => .{ .class = class, .keep_in_prompt = false, .pageable = true, .requires_provenance = true },
            .procedural => .{ .class = class, .keep_in_prompt = false, .pageable = true, .requires_provenance = true },
            .causal => .{ .class = class, .keep_in_prompt = false, .pageable = true, .requires_provenance = true },
            .normative => .{ .class = class, .keep_in_prompt = true, .pageable = false, .requires_provenance = true },
        };
    }
};

pub fn validateEntry(entry: Entry) !void {
    if (entry.id.len == 0) return error.MissingId;
    if (entry.content_digest_hex.len != 64) return error.BadDigest;
    const ret = Retention.forClass(entry.class);
    if (ret.requires_provenance and entry.provenance.len == 0) return error.MissingProvenance;
}

test "normative memory requires provenance" {
    try std.testing.expectError(error.MissingProvenance, validateEntry(.{
        .class = .normative,
        .id = "policy-1",
        .content_digest_hex = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    }));
}

test "working memory may omit provenance" {
    try validateEntry(.{
        .class = .working,
        .id = "plan-step",
        .content_digest_hex = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    });
}
