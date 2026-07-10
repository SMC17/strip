//! Deterministic perception contracts and sensor-error primitives. Scene
//! rendering, RF propagation, calibration, and hardware qualification are
//! outside this module's envelope.

const std = @import("std");

pub const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };
    pub fn isFinite(v: Vec3) bool {
        return std.math.isFinite(v.x) and std.math.isFinite(v.y) and std.math.isFinite(v.z);
    }
    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub fn scale(a: Vec3, s: f64) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    pub fn norm(a: Vec3) f64 {
        return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    }
};

pub const Quaternion = struct {
    w: f64,
    x: f64,
    y: f64,
    z: f64,

    fn validate(q: Quaternion) error{InvalidMount}!void {
        const n2 = q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z;
        if (!std.math.isFinite(n2) or @abs(n2 - 1.0) > 1e-9) return error.InvalidMount;
    }

    pub fn rotate(q: Quaternion, v: Vec3) error{InvalidMount}!Vec3 {
        try q.validate();
        const u = Vec3{ .x = q.x, .y = q.y, .z = q.z };
        const uv = Vec3{ .x = u.y * v.z - u.z * v.y, .y = u.z * v.x - u.x * v.z, .z = u.x * v.y - u.y * v.x };
        const uuv = Vec3{ .x = u.y * uv.z - u.z * uv.y, .y = u.z * uv.x - u.x * uv.z, .z = u.x * uv.y - u.y * uv.x };
        return v.add(uv.scale(2.0 * q.w)).add(uuv.scale(2.0));
    }
};

pub const MountTransform = struct {
    translation_body_m: Vec3,
    sensor_to_body: Quaternion,

    pub fn pointToBody(self: MountTransform, point_sensor_m: Vec3) error{InvalidMount}!Vec3 {
        if (!self.translation_body_m.isFinite() or !point_sensor_m.isFinite()) return error.InvalidMount;
        return self.translation_body_m.add(try self.sensor_to_body.rotate(point_sensor_m));
    }

    pub fn vectorToBody(self: MountTransform, vector_sensor: Vec3) error{InvalidMount}!Vec3 {
        if (!vector_sensor.isFinite()) return error.InvalidMount;
        return self.sensor_to_body.rotate(vector_sensor);
    }
};

pub const SourceMetadata = struct {
    model_id: []const u8,
    source: []const u8,
    locator: []const u8,
    assumptions: []const u8,
    qualification: bool = false,
};

pub const sources = struct {
    pub const allan = SourceMetadata{
        .model_id = "allan-power-law-primitives",
        .source = "IEEE Std 952-2020",
        .locator = "Allan variance noise-process terminology",
        .assumptions = "discrete white noise plus first-order bias correlation; coefficients require measured identification",
    };
    pub const radar = SourceMetadata{
        .model_id = "monostatic-range-contract",
        .source = "Skolnik, Introduction to Radar Systems",
        .locator = "range and radial-velocity sign conventions",
        .assumptions = "detections are supplied by an external scene/propagation model",
    };
};

pub const SourceTick = struct {
    sequence: u64,
    simulation_time_s: f64,
    frame_id: []const u8,

    pub fn validate(self: SourceTick) error{InvalidTick}!void {
        if (!std.math.isFinite(self.simulation_time_s) or self.simulation_time_s < 0.0 or self.frame_id.len == 0)
            return error.InvalidTick;
    }
};

pub const Delivery = struct {
    source: SourceTick,
    available_time_s: f64,
};

pub const ChannelStatus = enum { valid, saturated_low, saturated_high, dropped };

pub const ScalarSample = struct {
    value: ?f64,
    status: ChannelStatus,
    delivery: Delivery,
};

pub fn quantize(value: f64, quantum: f64) error{InvalidChannel}!f64 {
    if (!std.math.isFinite(value) or !std.math.isFinite(quantum) or quantum < 0.0)
        return error.InvalidChannel;
    return if (quantum == 0.0) value else @round(value / quantum) * quantum;
}

pub const Channel = struct {
    minimum: f64,
    maximum: f64,
    quantum: f64 = 0.0,
    latency_s: f64 = 0.0,
    dropout_probability: f64 = 0.0,
    dropout_seed: u64 = 0,

    fn unitAt(seed: u64, tick: u64) f64 {
        var x = seed ^ tick +% 0x9e3779b97f4a7c15;
        x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
        x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
        x ^= x >> 31;
        return @as(f64, @floatFromInt(x >> 11)) * 0x1.0p-53;
    }

    pub fn sample(self: Channel, truth: f64, tick: SourceTick) error{ InvalidChannel, InvalidTick }!ScalarSample {
        try tick.validate();
        const config = [_]f64{ self.minimum, self.maximum, self.quantum, self.latency_s, self.dropout_probability };
        for (config) |x| if (!std.math.isFinite(x)) return error.InvalidChannel;
        if (self.maximum < self.minimum or self.quantum < 0.0 or self.latency_s < 0.0 or
            self.dropout_probability < 0.0 or self.dropout_probability > 1.0 or !std.math.isFinite(truth))
            return error.InvalidChannel;
        const delivery = Delivery{ .source = tick, .available_time_s = tick.simulation_time_s + self.latency_s };
        if (unitAt(self.dropout_seed, tick.sequence) < self.dropout_probability)
            return .{ .value = null, .status = .dropped, .delivery = delivery };
        var status: ChannelStatus = .valid;
        var bounded = truth;
        if (truth < self.minimum) {
            bounded = self.minimum;
            status = .saturated_low;
        } else if (truth > self.maximum) {
            bounded = self.maximum;
            status = .saturated_high;
        }
        return .{ .value = try quantize(bounded, self.quantum), .status = status, .delivery = delivery };
    }
};

pub const AllanCoefficients = struct {
    angle_random_walk_per_sqrt_s: f64 = 0.0,
    bias_instability: f64 = 0.0,
    bias_correlation_time_s: f64 = 1.0,
    rate_random_walk_per_s_sqrt_s: f64 = 0.0,

    pub fn validate(self: AllanCoefficients) error{InvalidNoise}!void {
        const values = [_]f64{ self.angle_random_walk_per_sqrt_s, self.bias_instability, self.bias_correlation_time_s, self.rate_random_walk_per_s_sqrt_s };
        for (values) |x| if (!std.math.isFinite(x)) return error.InvalidNoise;
        if (self.angle_random_walk_per_sqrt_s < 0.0 or self.bias_instability < 0.0 or
            !(self.bias_correlation_time_s > 0.0) or self.rate_random_walk_per_s_sqrt_s < 0.0)
            return error.InvalidNoise;
    }
};

pub const AllanNoise = struct {
    coefficients: AllanCoefficients,
    bias: f64 = 0.0,
    rate_walk: f64 = 0.0,

    /// `white`, `bias_drive`, and `walk_drive` are caller-owned deterministic
    /// unit-normal draws, keeping stream ownership explicit and replayable.
    pub fn step(self: *AllanNoise, dt_s: f64, white: f64, bias_drive: f64, walk_drive: f64) error{InvalidNoise}!f64 {
        try self.coefficients.validate();
        const inputs = [_]f64{ dt_s, white, bias_drive, walk_drive };
        for (inputs) |x| if (!std.math.isFinite(x)) return error.InvalidNoise;
        if (!(dt_s > 0.0)) return error.InvalidNoise;
        const decay = @exp(-dt_s / self.coefficients.bias_correlation_time_s);
        self.bias = decay * self.bias + self.coefficients.bias_instability * @sqrt(1.0 - decay * decay) * bias_drive;
        self.rate_walk += self.coefficients.rate_random_walk_per_s_sqrt_s * @sqrt(dt_s) * walk_drive;
        return self.bias + self.rate_walk + self.coefficients.angle_random_walk_per_sqrt_s / @sqrt(dt_s) * white;
    }
};

pub const AirdataTruth = struct {
    static_pressure_pa: f64,
    total_pressure_pa: f64,
    static_temperature_k: f64,
    angle_of_attack_rad: f64,
    sideslip_rad: f64,
};

pub const AirdataSample = struct {
    indicated_airspeed_mps: ScalarSample,
    static_pressure_pa: ScalarSample,
    static_temperature_k: ScalarSample,
    angle_of_attack_rad: ScalarSample,
    sideslip_rad: ScalarSample,
};

pub const Airdata = struct {
    pressure: Channel,
    temperature: Channel,
    angle: Channel,
    airspeed: Channel,

    /// Incompressible pitot relation, explicitly bounded to nonnegative dynamic
    /// pressure. Compressible/Mach corrections are outside this primitive.
    pub fn sample(self: Airdata, truth: AirdataTruth, density_kg_m3: f64, tick: SourceTick) error{ InvalidTruth, InvalidChannel, InvalidTick }!AirdataSample {
        if (!std.math.isFinite(density_kg_m3) or !(density_kg_m3 > 0.0) or
            !std.math.isFinite(truth.static_pressure_pa) or !std.math.isFinite(truth.total_pressure_pa) or
            truth.total_pressure_pa < truth.static_pressure_pa or !(truth.static_temperature_k > 0.0))
            return error.InvalidTruth;
        const speed = @sqrt(2.0 * (truth.total_pressure_pa - truth.static_pressure_pa) / density_kg_m3);
        return .{
            .indicated_airspeed_mps = try self.airspeed.sample(speed, tick),
            .static_pressure_pa = try self.pressure.sample(truth.static_pressure_pa, tick),
            .static_temperature_k = try self.temperature.sample(truth.static_temperature_k, tick),
            .angle_of_attack_rad = try self.angle.sample(truth.angle_of_attack_rad, tick),
            .sideslip_rad = try self.angle.sample(truth.sideslip_rad, tick),
        };
    }
};

pub const Magnetometer = struct {
    mount: MountTransform,
    hard_iron_sensor_t: Vec3 = Vec3.zero,
    range_t: f64,
    quantum_t: f64 = 0.0,

    pub fn sample(self: Magnetometer, field_body_t: Vec3) error{ InvalidMount, InvalidSensor, InvalidChannel }!Vec3 {
        if (!field_body_t.isFinite() or !self.hard_iron_sensor_t.isFinite() or
            !std.math.isFinite(self.range_t) or !(self.range_t > 0.0))
            return error.InvalidSensor;
        // Conjugate of a unit quaternion maps body vectors into sensor axes.
        const q = self.mount.sensor_to_body;
        const sensor = try (Quaternion{ .w = q.w, .x = -q.x, .y = -q.y, .z = -q.z }).rotate(field_body_t);
        const biased = sensor.add(self.hard_iron_sensor_t);
        return .{
            .x = try quantize(std.math.clamp(biased.x, -self.range_t, self.range_t), self.quantum_t),
            .y = try quantize(std.math.clamp(biased.y, -self.range_t, self.range_t), self.quantum_t),
            .z = try quantize(std.math.clamp(biased.z, -self.range_t, self.range_t), self.quantum_t),
        };
    }
};

pub const Detection = struct {
    object_id: u64,
    position_sensor_m: Vec3,
    radial_velocity_mps: ?f64,
    signal_to_noise_ratio: ?f64,
};

pub const RadarScan = struct {
    source: SourceTick,
    mount: MountTransform,
    detections: []const Detection,
    minimum_range_m: f64,
    maximum_range_m: f64,
    range_resolution_m: f64,
};

pub const LidarReturn = struct {
    azimuth_rad: f64,
    elevation_rad: f64,
    range_m: f64,
    intensity: ?f64,
};

pub const LidarScan = struct {
    source: SourceTick,
    mount: MountTransform,
    returns: []const LidarReturn,
    minimum_range_m: f64,
    maximum_range_m: f64,
};

pub const ImagePlane = struct {
    width_px: u32,
    height_px: u32,
    horizontal_fov_rad: f64,
    vertical_fov_rad: f64,
};

pub const CameraFrame = struct {
    source: SourceTick,
    mount: MountTransform,
    image: ImagePlane,
    exposure_s: f64,
    pixels: []const u8,
    encoding: enum { gray8, rgb8, bayer8 },
};

pub const InfraredFrame = struct {
    source: SourceTick,
    mount: MountTransform,
    image: ImagePlane,
    integration_time_s: f64,
    apparent_temperature_k: []const f32,
    spectral_band_m: struct { minimum: f64, maximum: f64 },
};

pub fn validateRadar(scan: RadarScan) error{InvalidContract}!void {
    scan.source.validate() catch return error.InvalidContract;
    if (!(scan.minimum_range_m >= 0.0) or !(scan.maximum_range_m > scan.minimum_range_m) or !(scan.range_resolution_m > 0.0))
        return error.InvalidContract;
    for (scan.detections) |detection| {
        if (!detection.position_sensor_m.isFinite()) return error.InvalidContract;
        const range = detection.position_sensor_m.norm();
        if (range < scan.minimum_range_m or range > scan.maximum_range_m) return error.InvalidContract;
    }
}

pub fn validateLidar(scan: LidarScan) error{InvalidContract}!void {
    scan.source.validate() catch return error.InvalidContract;
    if (!(scan.minimum_range_m >= 0.0) or !(scan.maximum_range_m > scan.minimum_range_m))
        return error.InvalidContract;
    for (scan.returns) |sample| {
        if (!std.math.isFinite(sample.azimuth_rad) or !std.math.isFinite(sample.elevation_rad) or
            !std.math.isFinite(sample.range_m) or sample.range_m < scan.minimum_range_m or sample.range_m > scan.maximum_range_m)
            return error.InvalidContract;
        if (sample.intensity) |intensity| if (!std.math.isFinite(intensity) or intensity < 0.0) return error.InvalidContract;
    }
}

pub fn validateCamera(frame: CameraFrame) error{InvalidContract}!void {
    frame.source.validate() catch return error.InvalidContract;
    if (frame.image.width_px == 0 or frame.image.height_px == 0 or !(frame.exposure_s > 0.0) or
        !(frame.image.horizontal_fov_rad > 0.0 and frame.image.horizontal_fov_rad <= std.math.pi) or
        !(frame.image.vertical_fov_rad > 0.0 and frame.image.vertical_fov_rad <= std.math.pi))
        return error.InvalidContract;
    const channels: usize = if (frame.encoding == .rgb8) 3 else 1;
    const expected = @as(usize, frame.image.width_px) * @as(usize, frame.image.height_px) * channels;
    if (frame.pixels.len != expected) return error.InvalidContract;
}

pub fn validateInfrared(frame: InfraredFrame) error{InvalidContract}!void {
    frame.source.validate() catch return error.InvalidContract;
    const expected = @as(usize, frame.image.width_px) * @as(usize, frame.image.height_px);
    if (frame.image.width_px == 0 or frame.image.height_px == 0 or frame.apparent_temperature_k.len != expected or
        !(frame.integration_time_s > 0.0) or !(frame.spectral_band_m.minimum > 0.0) or
        !(frame.spectral_band_m.maximum > frame.spectral_band_m.minimum))
        return error.InvalidContract;
    for (frame.apparent_temperature_k) |temperature| if (!std.math.isFinite(temperature) or !(temperature > 0.0))
        return error.InvalidContract;
}

test "channel exposes latency saturation dropout and deterministic tick behavior" {
    const tick = SourceTick{ .sequence = 4, .simulation_time_s = 10, .frame_id = "airdata" };
    const saturated = try (Channel{ .minimum = 0, .maximum = 100, .quantum = 0.5, .latency_s = 0.2 }).sample(120, tick);
    try std.testing.expectEqual(ChannelStatus.saturated_high, saturated.status);
    try std.testing.expectEqual(@as(f64, 100), saturated.value.?);
    try std.testing.expectEqual(@as(f64, 10.2), saturated.delivery.available_time_s);
    const dropped = try (Channel{ .minimum = 0, .maximum = 1, .dropout_probability = 1 }).sample(0.5, tick);
    try std.testing.expectEqual(ChannelStatus.dropped, dropped.status);
    try std.testing.expect(dropped.value == null);
}

test "mount transform and magnetometer preserve identity orientation" {
    const mount = MountTransform{ .translation_body_m = .{ .x = 1, .y = 2, .z = 3 }, .sensor_to_body = .{ .w = 1, .x = 0, .y = 0, .z = 0 } };
    try std.testing.expectEqualDeep(Vec3{ .x = 2, .y = 2, .z = 3 }, try mount.pointToBody(.{ .x = 1, .y = 0, .z = 0 }));
    const mag = Magnetometer{ .mount = mount, .range_t = 100e-6 };
    try std.testing.expectEqualDeep(Vec3{ .x = 20e-6, .y = 0, .z = 40e-6 }, try mag.sample(.{ .x = 20e-6, .y = 0, .z = 40e-6 }));
}

test "airdata computes pitot speed and retains source tick" {
    const channel = Channel{ .minimum = -1.0e6, .maximum = 1.0e6 };
    const sensor = Airdata{ .pressure = channel, .temperature = channel, .angle = channel, .airspeed = channel };
    const tick = SourceTick{ .sequence = 7, .simulation_time_s = 3, .frame_id = "airdata-1" };
    const sample = try sensor.sample(.{
        .static_pressure_pa = 100_000,
        .total_pressure_pa = 100_050,
        .static_temperature_k = 280,
        .angle_of_attack_rad = 0.1,
        .sideslip_rad = -0.02,
    }, 1.0, tick);
    try std.testing.expectApproxEqAbs(@as(f64, 10), sample.indicated_airspeed_mps.value.?, 1e-12);
    try std.testing.expectEqual(@as(u64, 7), sample.indicated_airspeed_mps.delivery.source.sequence);
}

test "Allan primitive is replayable for caller-owned forcing" {
    const coefficients = AllanCoefficients{ .angle_random_walk_per_sqrt_s = 0.01, .bias_instability = 0.001, .bias_correlation_time_s = 10, .rate_random_walk_per_s_sqrt_s = 0.0001 };
    var a = AllanNoise{ .coefficients = coefficients };
    var b = AllanNoise{ .coefficients = coefficients };
    for (0..8) |i| {
        const drive: f64 = @floatFromInt(i);
        try std.testing.expectEqual(try a.step(0.01, drive, -drive, 0.5), try b.step(0.01, drive, -drive, 0.5));
    }
}

test "active and imaging sensor contracts retain source ticks" {
    const tick = SourceTick{ .sequence = 1, .simulation_time_s = 2, .frame_id = "sensor-1" };
    const mount = MountTransform{ .translation_body_m = Vec3.zero, .sensor_to_body = .{ .w = 1, .x = 0, .y = 0, .z = 0 } };
    const detections = [_]Detection{.{ .object_id = 1, .position_sensor_m = .{ .x = 10, .y = 0, .z = 0 }, .radial_velocity_mps = 2, .signal_to_noise_ratio = null }};
    try validateRadar(.{ .source = tick, .mount = mount, .detections = &detections, .minimum_range_m = 1, .maximum_range_m = 20, .range_resolution_m = 0.5 });
    const returns = [_]LidarReturn{.{ .azimuth_rad = 0, .elevation_rad = 0, .range_m = 5, .intensity = 0.8 }};
    try validateLidar(.{ .source = tick, .mount = mount, .returns = &returns, .minimum_range_m = 0.1, .maximum_range_m = 10 });
    const pixels = [_]u8{ 0, 1, 2, 3 };
    try validateCamera(.{ .source = tick, .mount = mount, .image = .{ .width_px = 2, .height_px = 2, .horizontal_fov_rad = 1, .vertical_fov_rad = 1 }, .exposure_s = 0.01, .pixels = &pixels, .encoding = .gray8 });
    const temperatures = [_]f32{ 280, 281, 282, 283 };
    try validateInfrared(.{ .source = tick, .mount = mount, .image = .{ .width_px = 2, .height_px = 2, .horizontal_fov_rad = 1, .vertical_fov_rad = 1 }, .integration_time_s = 0.01, .apparent_temperature_k = &temperatures, .spectral_band_m = .{ .minimum = 8e-6, .maximum = 12e-6 } });
}
