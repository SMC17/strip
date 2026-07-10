//! Strip: evidence-bearing aerospace computation primitives.

pub const atmosphere = @import("atmosphere.zig");
pub const evidence = @import("evidence.zig");
pub const frames = @import("frames.zig");
pub const units = @import("units.zig");

test {
    _ = atmosphere;
    _ = evidence;
    _ = frames;
    _ = units;
}
