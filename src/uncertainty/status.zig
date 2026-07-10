//! Explicit uncertainty state; absence of a number is never silently treated as zero.

const std = @import("std");

pub const Status = enum {
    quantified,
    bounded,
    estimated,
    unknown,
    not_applicable,
};

pub const Kind = enum {
    standard_deviation,
    confidence_interval,
    absolute_bound,
    relative_bound,
};

pub const Uncertainty = struct {
    status: Status,
    kind: ?Kind = null,
    value: ?f64 = null,
    unit: ?[]const u8 = null,
    confidence: ?f64 = null,

    pub fn validate(self: Uncertainty) error{InvalidUncertainty}!void {
        switch (self.status) {
            .quantified, .bounded, .estimated => {
                const value = self.value orelse return error.InvalidUncertainty;
                if (!std.math.isFinite(value) or value < 0.0 or self.kind == null)
                    return error.InvalidUncertainty;
            },
            .unknown, .not_applicable => {
                if (self.value != null or self.kind != null or self.confidence != null)
                    return error.InvalidUncertainty;
            },
        }
        if (self.confidence) |confidence| {
            if (!std.math.isFinite(confidence) or confidence <= 0.0 or confidence >= 1.0)
                return error.InvalidUncertainty;
        }
    }
};

test "unknown uncertainty cannot carry a numeric value" {
    const invalid = Uncertainty{ .status = .unknown, .value = 0.0 };
    try std.testing.expectError(error.InvalidUncertainty, invalid.validate());
}

test "bounded uncertainty validates explicit kind and value" {
    const bounded = Uncertainty{
        .status = .bounded,
        .kind = .absolute_bound,
        .value = 0.5,
        .unit = "m",
    };
    try bounded.validate();
}
