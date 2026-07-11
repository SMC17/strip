//! Deterministic local-Cartesian GNSS observation model with fixed cadence and
//! independent Gaussian white error. It omits satellite geometry, atmosphere,
//! multipath, clock states, outages, latency, and geodetic conversion.

const std = @import("std");
const math = @import("../dynamics/math.zig");
const noise = @import("noise.zig");
const evidence = @import("../evidence.zig");
const numerical_result = @import("../result.zig");

pub const manifest = evidence.ModelManifest{
    .id = "strip.sensor.gnss-local-cartesian",
    .version = "0.1.0",
    .proof_level = .unit_tested,
    .source = "Local-Cartesian GNSS observation model with fixed cadence",
    .assumptions = &.{
        "no satellite geometry",
        "no atmosphere or multipath",
        "no clock states or outages",
    },
    .valid_min = 0.0,
    .valid_max = 86400.0,
    .valid_unit = "s",
    .proof = .{
        .implementation = .implemented,
        .testing = .unit_tested,
        .analysis = .none,
        .comparison = .none,
        .validation = .none,
    },
};

pub const Config = struct {
    update_period_s: f64,
    position_noise_std_m: f64 = 0.0,
    velocity_noise_std_mps: f64 = 0.0,
    position_quantization_m: f64 = 0.0,
    velocity_quantization_mps: f64 = 0.0,

    pub fn validate(self: Config) error{InvalidConfiguration}!void {
        const values = [_]f64{
            self.update_period_s,
            self.position_noise_std_m,
            self.velocity_noise_std_mps,
            self.position_quantization_m,
            self.velocity_quantization_mps,
        };
        for (values) |value| if (!std.math.isFinite(value)) return error.InvalidConfiguration;
        if (!(self.update_period_s > 0.0) or self.position_noise_std_m < 0.0 or
            self.velocity_noise_std_mps < 0.0 or self.position_quantization_m < 0.0 or
            self.velocity_quantization_mps < 0.0)
        {
            return error.InvalidConfiguration;
        }
    }
};

pub const Fix = struct {
    sample_time_s: f64,
    position_local_m: math.Vec3,
    velocity_local_mps: math.Vec3,
};

pub const Gnss = struct {
    config: Config,
    generator: noise.Generator,
    next_sample_time_s: f64 = 0.0,

    pub fn init(config: Config, seed: u64) error{InvalidConfiguration}!Gnss {
        try config.validate();
        return .{ .config = config, .generator = noise.Generator.init(seed) };
    }

    fn noisyVector(generator: *noise.Generator, truth: math.Vec3, sigma: f64, quantum: f64) math.Vec3 {
        var result = math.Vec3{
            .x = truth.x + generator.normal(sigma),
            .y = truth.y + generator.normal(sigma),
            .z = truth.z + generator.normal(sigma),
        };
        if (quantum > 0.0) {
            result.x = @round(result.x / quantum) * quantum;
            result.y = @round(result.y / quantum) * quantum;
            result.z = @round(result.z / quantum) * quantum;
        }
        return result;
    }

    /// Returns null between scheduled epochs. If calls skip epochs, one fix is
    /// emitted at the supplied truth time and the cadence advances past it.
    pub fn sample(
        self: *Gnss,
        time_s: f64,
        true_position_local_m: math.Vec3,
        true_velocity_local_mps: math.Vec3,
    ) error{InvalidInput}!?Fix {
        if (!std.math.isFinite(time_s) or time_s < 0.0 or
            !true_position_local_m.isFinite() or !true_velocity_local_mps.isFinite())
        {
            return error.InvalidInput;
        }
        if (time_s + 8.0 * std.math.floatEps(f64) < self.next_sample_time_s) return null;

        while (self.next_sample_time_s <= time_s) {
            self.next_sample_time_s += self.config.update_period_s;
        }
        return .{
            .sample_time_s = time_s,
            .position_local_m = noisyVector(
                &self.generator,
                true_position_local_m,
                self.config.position_noise_std_m,
                self.config.position_quantization_m,
            ),
            .velocity_local_mps = noisyVector(
                &self.generator,
                true_velocity_local_mps,
                self.config.velocity_noise_std_mps,
                self.config.velocity_quantization_mps,
            ),
        };
    }

    pub fn sampleResult(
        self: *Gnss,
        context: evidence.Context,
        time_s: f64,
        true_position_local_m: math.Vec3,
        true_velocity_local_mps: math.Vec3,
    ) error{InvalidInput}!numerical_result.NumericalResult(?Fix) {
        const envelope = manifest.effectiveEnvelope("time_s");
        const fix = try self.sample(time_s, true_position_local_m, true_velocity_local_mps);
        return .{
            .value = fix,
            .model = manifest,
            .context = context,
            .validity = if (envelope.contains(time_s)) .valid else .outside_envelope,
            .evaluated_point = .{
                .variable = "time_s",
                .value = time_s,
                .unit = "s",
            },
            .envelope = envelope,
            .execution_identity = .fromModel(manifest),
            .credibility = .fromProof(manifest.effectiveProof()),
        };
    }
};

test "GNSS cadence is fixed and ideal fixes pass local truth" {
    var gnss = try Gnss.init(.{ .update_period_s = 0.2 }, 7);
    const position = math.Vec3{ .x = 10.0, .y = -4.0, .z = 2.0 };
    const velocity = math.Vec3{ .x = 1.0, .y = 0.0, .z = -0.5 };
    const first = (try gnss.sample(0.0, position, velocity)).?;
    try std.testing.expectEqualDeep(position, first.position_local_m);
    try std.testing.expect((try gnss.sample(0.1, position, velocity)) == null);
    try std.testing.expect((try gnss.sample(0.2, position, velocity)) != null);
}

test "same GNSS seed produces identical fixes" {
    const config = Config{
        .update_period_s = 1.0,
        .position_noise_std_m = 2.0,
        .velocity_noise_std_mps = 0.1,
    };
    var first = try Gnss.init(config, 99);
    var second = try Gnss.init(config, 99);
    const position = math.Vec3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    const velocity = math.Vec3.zero;
    for (0..5) |index| {
        const time_s: f64 = @floatFromInt(index);
        try std.testing.expectEqualDeep(
            try first.sample(time_s, position, velocity),
            try second.sample(time_s, position, velocity),
        );
    }
}
