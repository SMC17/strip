//! Validation contracts, evidence coverage, provenance, and comparators.
pub const envelope = @import("envelope.zig");
pub const source = @import("source.zig");
pub const types = @import("types.zig");
pub const coverage = @import("coverage.zig");
pub const comparator = @import("comparator.zig");

test {
    _ = envelope;
    _ = source;
    _ = types;
    _ = coverage;
    _ = comparator;
}
