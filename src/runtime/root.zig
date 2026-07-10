//! Bounded simulation runtime primitives.
//!
//! Ordering is deterministic for a fixed executable and identical recorded
//! inputs. Strict cross-platform floating-point determinism is not claimed.
pub const storage = @import("storage.zig");
pub const scheduler = @import("scheduler.zig");
pub const state = @import("state.zig");
pub const sensors = @import("sensors.zig");

test {
    _ = storage;
    _ = scheduler;
    _ = state;
    _ = sensors;
}
