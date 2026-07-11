//! Assurance-carrying agent trajectories (frontier agent OS substrate).

pub const action = @import("action.zig");
pub const aerospace = @import("aerospace.zig");
pub const analogy = @import("analogy.zig");
pub const causal = @import("causal.zig");
pub const counterfactual = @import("counterfactual.zig");
pub const events = @import("events.zig");
pub const fault_lab = @import("fault_lab.zig");
pub const frontier = @import("frontier.zig");
pub const hil_stream = @import("hil_stream.zig");
pub const jsonl = @import("jsonl.zig");
pub const memory = @import("memory.zig");
pub const receipt = @import("receipt.zig");
pub const router = @import("router.zig");
pub const scheduler = @import("scheduler.zig");
pub const store = @import("store.zig");
pub const workers = @import("workers.zig");
pub const world_model = @import("world_model.zig");

test {
    _ = action;
    _ = aerospace;
    _ = analogy;
    _ = causal;
    _ = counterfactual;
    _ = events;
    _ = fault_lab;
    _ = frontier;
    _ = hil_stream;
    _ = jsonl;
    _ = memory;
    _ = receipt;
    _ = router;
    _ = scheduler;
    _ = store;
    _ = workers;
    _ = world_model;
}
