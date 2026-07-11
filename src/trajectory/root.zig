//! Assurance-carrying agent trajectories: typed actions, append-only events, claim audit.
//!
//! Clean-room design inspired by the general agent-OS pattern (model proposes,
//! runtime authorizes/executes, evidence backs claims). Not a Cursor protocol clone.

pub const action = @import("action.zig");
pub const events = @import("events.zig");
pub const store = @import("store.zig");
pub const jsonl = @import("jsonl.zig");

test {
    _ = action;
    _ = events;
    _ = store;
    _ = jsonl;
}
