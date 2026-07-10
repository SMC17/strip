//! Explicitly seeded deterministic pseudo-random noise for repeatable simulation.
//! This generator is not cryptographic and does not model colored noise.

const std = @import("std");

pub const Generator = struct {
    state: u64,
    spare_normal: ?f64 = null,

    pub fn init(seed: u64) Generator {
        return .{ .state = if (seed == 0) 0x9e3779b97f4a7c15 else seed };
    }

    pub fn nextU64(self: *Generator) u64 {
        var x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        return x *% 0x2545f4914f6cdd1d;
    }

    pub fn uniformOpen01(self: *Generator) f64 {
        const mantissa = self.nextU64() >> 11;
        return (@as(f64, @floatFromInt(mantissa)) + 0.5) / 9_007_199_254_740_992.0;
    }

    /// Standard normal via Box-Muller. Identical seeds and call sequences
    /// produce identical values for a given Zig target and math implementation.
    pub fn standardNormal(self: *Generator) f64 {
        if (self.spare_normal) |spare| {
            self.spare_normal = null;
            return spare;
        }
        const radius = @sqrt(-2.0 * @log(self.uniformOpen01()));
        const angle = 2.0 * std.math.pi * self.uniformOpen01();
        self.spare_normal = radius * @sin(angle);
        return radius * @cos(angle);
    }

    pub fn normal(self: *Generator, standard_deviation: f64) f64 {
        return standard_deviation * self.standardNormal();
    }
};

test "same seed and call sequence produce same noise" {
    var first = Generator.init(42);
    var second = Generator.init(42);
    for (0..20) |_| {
        try std.testing.expectEqual(first.nextU64(), second.nextU64());
        try std.testing.expectEqual(first.standardNormal(), second.standardNormal());
    }
}
