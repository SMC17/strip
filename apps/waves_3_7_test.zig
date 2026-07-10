//! Standalone test root used while root build integration remains out of scope.
test {
    _ = @import("scenario");
    _ = @import("monte_carlo");
    _ = @import("uas");
    _ = @import("assurance");
    _ = @import("tools");
    _ = @import("agent");
    _ = @import("aeroir");
    _ = @import("state_graph");
    _ = @import("worldforge");
    _ = @import("design_evolve");
    _ = @import("rare_event");
    _ = @import("multifidelity");
    _ = @import("runtime_assurance");
    _ = @import("twin");
    _ = @import("adapters");
    _ = @import("public_defense");
}
