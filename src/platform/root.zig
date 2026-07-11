//! Platform-plane modules (non-authoritative external clients).
pub const weathernext = @import("weathernext.zig");
pub const weather_open_stack = @import("weather_open_stack.zig");
pub const gemini = @import("gemini.zig");
pub const openrouter = @import("openrouter.zig");
pub const google_catalog = @import("google_catalog.zig");
pub const api_key = @import("api_key.zig");

test {
    _ = weathernext;
    _ = weather_open_stack;
    _ = gemini;
    _ = openrouter;
    _ = google_catalog;
    _ = api_key;
}
