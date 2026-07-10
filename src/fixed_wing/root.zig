//! Bounded fixed-wing primitives.

pub const types = @import("types.zig");
pub const airdata = @import("airdata.zig");
pub const coefficients = @import("coefficients.zig");
pub const forces = @import("forces.zig");
pub const propulsion = @import("propulsion.zig");
pub const provider = @import("provider.zig");
pub const source_metadata = @import("source_metadata.zig");
pub const synthetic_fixture = @import("synthetic_fixture.zig");

test {
    _ = types;
    _ = airdata;
    _ = coefficients;
    _ = forces;
    _ = propulsion;
    _ = provider;
    _ = source_metadata;
    _ = synthetic_fixture;
}
