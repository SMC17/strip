//! Assurance-carrying agent trajectories: typed actions, append-only events,
//! claim audit, counterfactual branch, causal provenance, fault lab, receipts.

pub const action = @import("action.zig");
pub const aerospace = @import("aerospace.zig");
pub const causal = @import("causal.zig");
pub const counterfactual = @import("counterfactual.zig");
pub const events = @import("events.zig");
pub const fault_lab = @import("fault_lab.zig");
pub const frontier = @import("frontier.zig");
pub const jsonl = @import("jsonl.zig");
pub const memory = @import("memory.zig");
pub const receipt = @import("receipt.zig");
pub const scheduler = @import("scheduler.zig");
pub const store = @import("store.zig");

test {
    _ = action;
    _ = aerospace;
    _ = causal;
    _ = counterfactual;
    _ = events;
    _ = fault_lab;
    _ = frontier;
    _ = jsonl;
    _ = memory;
    _ = receipt;
    _ = scheduler;
    _ = store;
}
