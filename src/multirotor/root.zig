//! Executable low-order multirotor primitives.
//! These models support deterministic simulation tests, not flight qualification.

pub const math = @import("math.zig");
pub const propulsion = @import("propulsion.zig");
pub const allocation = @import("allocation.zig");
pub const control = @import("control.zig");
pub const estimator = @import("estimator.zig");

test {
    _ = math;
    _ = propulsion;
    _ = allocation;
    _ = control;
    _ = estimator;
}
