//! Platform-plane modules (non-authoritative external clients).
pub const weathernext = @import("weathernext.zig");
pub const gemini = @import("gemini.zig");
pub const openrouter = @import("openrouter.zig");
pub const google_catalog = @import("google_catalog.zig");
pub const api_key = @import("api_key.zig");

test {
    _ = weathernext;
    _ = gemini;
    _ = openrouter;
    _ = google_catalog;
    _ = api_key;
}
