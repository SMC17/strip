//! Validation contracts, evidence coverage, provenance, and comparators.
pub const envelope = @import("envelope.zig");
pub const source = @import("source.zig");
pub const types = @import("types.zig");
pub const coverage = @import("coverage.zig");
pub const comparator = @import("comparator.zig");

pub const join = @import("join.zig");
pub const certification_delta = @import("certification_delta.zig");
pub const model_passport = @import("model_passport.zig");
pub const dispatch_decision = @import("dispatch_decision.zig");

test {
    _ = envelope;
    _ = source;
    _ = types;
    _ = coverage;
    _ = comparator;
    _ = join;
    _ = certification_delta;
    _ = model_passport;
    _ = dispatch_decision;
}
