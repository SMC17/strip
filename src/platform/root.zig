//! Platform-plane modules (non-authoritative external clients).
pub const weathernext = @import("weathernext.zig");

test {
    _ = weathernext;
}
