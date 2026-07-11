//! Google / DeepMind platform catalog (non-authoritative).
//!
//! Maps public product families to Strip platform-plane access paths.
//! Nothing here is simulation truth or operational qualification.

const std = @import("std");

pub const AccessClass = enum {
    /// Google AI Studio / Gemini API key (`GEMINI_API_KEY` / `GOOGLE_API_KEY`).
    gemini_api_key,
    /// Google Cloud Vertex / Model Garden (project + IAM; often EAP).
    vertex_cloud,
    /// Public science page / datasets; no Strip live client yet.
    science_portal,
    /// Open-weight / local-capable (e.g. Gemma).
    open_weights,
    /// Research preview / limited access.
    research_preview,
    /// Not wired; catalog only.
    catalog_only,
};

pub const Entry = struct {
    id: []const u8,
    family: []const u8,
    access: AccessClass,
    strip_surface: []const u8,
    notes: []const u8,
};

pub const catalog = [_]Entry{
    .{ .id = "gemini", .family = "Models", .access = .gemini_api_key, .strip_surface = "strip-google gemini --model gemini-3.5-flash", .notes = "Default live model gemini-3.5-flash" },
    .{ .id = "gemini-3.1-flash-lite", .family = "Models", .access = .gemini_api_key, .strip_surface = "strip-google gemini --model gemini-3.1-flash-lite", .notes = "Fast/cheap text path" },
    .{ .id = "gemini-omni-flash-preview", .family = "Models", .access = .gemini_api_key, .strip_surface = "strip-google gemini --model gemini-omni-flash-preview", .notes = "Omni preview; may hit free-tier quota 0" },
    .{ .id = "nano-banana-pro-preview", .family = "Models", .access = .gemini_api_key, .strip_surface = "strip-google gemini --model nano-banana-pro-preview", .notes = "Image/gen preview id from Model Garden list" },
    .{ .id = "gemma-4-26b-a4b-it", .family = "Models", .access = .gemini_api_key, .strip_surface = "strip-google gemini --model gemma-4-26b-a4b-it", .notes = "Gemma 4 via Gemini API" },
    .{ .id = "lyria-3-clip-preview", .family = "Models", .access = .gemini_api_key, .strip_surface = "catalog", .notes = "Music clip preview; generateContent may not apply" },
    .{ .id = "lyria-3-pro-preview", .family = "Models", .access = .gemini_api_key, .strip_surface = "catalog", .notes = "Music pro preview" },
    .{ .id = "veo", .family = "Models", .access = .vertex_cloud, .strip_surface = "catalog", .notes = "Video generation; typically Vertex" },
    .{ .id = "genie", .family = "Models", .access = .research_preview, .strip_surface = "catalog", .notes = "World model research; no Strip live client" },
    .{ .id = "gemini-robotics-er-1.6-preview", .family = "Research", .access = .gemini_api_key, .strip_surface = "strip-google gemini --model gemini-robotics-er-1.6-preview", .notes = "Robotics ER preview; not Strip HIL" },
    .{ .id = "alphafold", .family = "Science", .access = .science_portal, .strip_surface = "catalog", .notes = "Protein structure; out of aviation scope" },
    .{ .id = "alphagenome", .family = "Science", .access = .science_portal, .strip_surface = "catalog", .notes = "Genomics science portal" },
    .{ .id = "weathernext", .family = "Science", .access = .vertex_cloud, .strip_surface = "strip-weathernext", .notes = "Forecast candidate; Vertex EAP / custom endpoint" },
    .{ .id = "alphaearth", .family = "Science", .access = .science_portal, .strip_surface = "catalog", .notes = "Earth observation science" },
    .{ .id = "alphaevolve", .family = "Science", .access = .research_preview, .strip_surface = "catalog", .notes = "Algorithm discovery research" },
};

pub fn formatCatalogJson(allocator: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, "{\"schema\":\"strip.google.catalog.v0\",\"plane\":\"platform\",\"authoritative\":false,\"operational_qualification_claimed\":false,\"default_gemini_model\":\"gemini-3.5-flash\",\"entries\":[");
    for (catalog, 0..) |entry, i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(
            allocator,
            "{{\"id\":\"{s}\",\"family\":\"{s}\",\"access\":\"{s}\",\"strip_surface\":\"{s}\",\"notes\":\"{s}\"}}",
            .{ entry.id, entry.family, @tagName(entry.access), entry.strip_surface, entry.notes },
        );
        defer allocator.free(item);
        try list.appendSlice(allocator, item);
    }
    try list.appendSlice(allocator, "]}\n");
    return try list.toOwnedSlice(allocator);
}

test "catalog includes weathernext and gemini" {
    var saw_gemini = false;
    var saw_wn = false;
    for (catalog) |e| {
        if (std.mem.eql(u8, e.id, "gemini")) saw_gemini = true;
        if (std.mem.eql(u8, e.id, "weathernext")) saw_wn = true;
    }
    try std.testing.expect(saw_gemini and saw_wn);
}
