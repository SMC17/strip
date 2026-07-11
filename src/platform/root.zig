//! Platform-plane modules (non-authoritative external clients).
pub const weathernext = @import("weathernext.zig");
pub const gemini = @import("gemini.zig");
pub const google_catalog = @import("google_catalog.zig");

test {
    _ = weathernext;
    _ = gemini;
    _ = google_catalog;
}
