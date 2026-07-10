//! Multifidelity result contracts with explicit discrepancy bounds.
const std = @import("std");

pub const Fidelity = enum(u8) { surrogate, reduced_order, authoritative };

pub const Result = struct {
    value: f64,
    fidelity: Fidelity,
    absolute_error_bound: ?f64,

    pub fn validate(self: Result) error{InvalidResult}!void {
        if (!std.math.isFinite(self.value)) return error.InvalidResult;
        if (self.fidelity != .authoritative and self.absolute_error_bound == null)
            return error.InvalidResult;
        if (self.absolute_error_bound) |bound| {
            if (!std.math.isFinite(bound) or bound < 0) return error.InvalidResult;
        }
    }
};

pub fn agrees(low: Result, high: Result) error{InvalidResult}!bool {
    try low.validate();
    try high.validate();
    const allowance = low.absolute_error_bound orelse 0;
    return @abs(low.value - high.value) <= allowance;
}

test "non-authoritative result requires a finite discrepancy bound" {
    const low: Result = .{ .value = 10, .fidelity = .surrogate, .absolute_error_bound = null };
    try std.testing.expectError(error.InvalidResult, low.validate());
    try std.testing.expect(try agrees(
        .{ .value = 10, .fidelity = .reduced_order, .absolute_error_bound = 0.5 },
        .{ .value = 10.4, .fidelity = .authoritative, .absolute_error_bound = null },
    ));
}
