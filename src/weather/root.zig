//! Bounded, deterministic environmental primitives. These equations are model
//! contracts and test fixtures, not a weather product or qualification claim.

const std = @import("std");

pub const Source = struct {
    id: []const u8,
    title: []const u8,
    edition: []const u8,
    locator: []const u8,
    use: []const u8,
    qualification: bool = false,
};

pub const sources = struct {
    pub const atmosphere = Source{
        .id = "USSA1976",
        .title = "U.S. Standard Atmosphere, 1976",
        .edition = "NOAA-S/T 76-1562",
        .locator = "Part 1, equations 23a/23b and tables 3/4",
        .use = "hydrostatic layer equations through the lower mesosphere",
    };
    pub const turbulence = Source{
        .id = "MIL-F-8785C",
        .title = "Flying Qualities of Piloted Airplanes",
        .edition = "1980",
        .locator = "paragraph 3.7.2 and figures 7-8",
        .use = "Dryden spectral shapes and forming-filter conventions",
    };
    pub const von_karman = Source{
        .id = "MIL-HDBK-1797",
        .title = "Flying Qualities of Piloted Aircraft",
        .edition = "1997",
        .locator = "atmospheric turbulence model spectral equations",
        .use = "von Karman one-dimensional spectral shapes",
    };
};

pub const atmosphere = struct {
    pub const min_geopotential_altitude_m = 0.0;
    pub const earth_radius_m = 6_356_766.0;
    pub const max_geometric_altitude_m = 86_000.0;
    pub const max_geopotential_altitude_m =
        earth_radius_m * max_geometric_altitude_m / (earth_radius_m + max_geometric_altitude_m);
    pub const g0_mps2 = 9.80665;
    pub const gas_constant_j_per_kg_k = 287.05287;
    pub const gamma_air = 1.4;

    pub const Envelope = struct {
        minimum_geometric_altitude_m: f64,
        maximum_geometric_altitude_m: f64,
        minimum_geopotential_altitude_m: f64,
        maximum_geopotential_altitude_m: f64,
        altitude_relation: []const u8,
        composition_model: []const u8,
    };

    pub const envelope = Envelope{
        .minimum_geometric_altitude_m = 0.0,
        .maximum_geometric_altitude_m = max_geometric_altitude_m,
        .minimum_geopotential_altitude_m = min_geopotential_altitude_m,
        .maximum_geopotential_altitude_m = max_geopotential_altitude_m,
        .altitude_relation = "H = r0*z/(r0+z), US76 effective Earth radius",
        .composition_model = "homogeneous dry-air hydrostatic lower-atmosphere model only",
    };

    pub const Layer = struct {
        base_geopotential_m: f64,
        top_geopotential_m: f64,
        base_temperature_k: f64,
        base_pressure_pa: f64,
        lapse_k_per_m: f64,
    };

    /// Base values are rounded published US76 table values. The final
    /// geopotential boundary corresponds to 86 km geometric altitude;
    /// molecular-scale composition above this envelope is not represented.
    pub const layers = [_]Layer{
        .{ .base_geopotential_m = 0, .top_geopotential_m = 11_000, .base_temperature_k = 288.15, .base_pressure_pa = 101_325.0, .lapse_k_per_m = -0.0065 },
        .{ .base_geopotential_m = 11_000, .top_geopotential_m = 20_000, .base_temperature_k = 216.65, .base_pressure_pa = 22_632.06, .lapse_k_per_m = 0.0 },
        .{ .base_geopotential_m = 20_000, .top_geopotential_m = 32_000, .base_temperature_k = 216.65, .base_pressure_pa = 5_474.889, .lapse_k_per_m = 0.001 },
        .{ .base_geopotential_m = 32_000, .top_geopotential_m = 47_000, .base_temperature_k = 228.65, .base_pressure_pa = 868.0187, .lapse_k_per_m = 0.0028 },
        .{ .base_geopotential_m = 47_000, .top_geopotential_m = 51_000, .base_temperature_k = 270.65, .base_pressure_pa = 110.9063, .lapse_k_per_m = 0.0 },
        .{ .base_geopotential_m = 51_000, .top_geopotential_m = 71_000, .base_temperature_k = 270.65, .base_pressure_pa = 66.93887, .lapse_k_per_m = -0.0028 },
        .{ .base_geopotential_m = 71_000, .top_geopotential_m = max_geopotential_altitude_m, .base_temperature_k = 214.65, .base_pressure_pa = 3.956420, .lapse_k_per_m = -0.0020 },
    };

    pub const State = struct {
        geopotential_altitude_m: f64,
        temperature_k: f64,
        pressure_pa: f64,
        density_kg_m3: f64,
        speed_of_sound_mps: f64,
        layer_index: u8,
    };

    pub const Error = error{ NonFiniteAltitude, OutsideEnvelope };

    pub fn evaluate(h_m: f64) Error!State {
        if (!std.math.isFinite(h_m)) return error.NonFiniteAltitude;
        if (h_m < min_geopotential_altitude_m or h_m > max_geopotential_altitude_m)
            return error.OutsideEnvelope;
        for (layers, 0..) |layer, index| {
            if (h_m <= layer.top_geopotential_m) {
                const dh = h_m - layer.base_geopotential_m;
                const temperature = layer.base_temperature_k + layer.lapse_k_per_m * dh;
                const pressure = if (layer.lapse_k_per_m == 0.0)
                    layer.base_pressure_pa * @exp(-g0_mps2 * dh / (gas_constant_j_per_kg_k * layer.base_temperature_k))
                else
                    layer.base_pressure_pa * std.math.pow(
                        f64,
                        layer.base_temperature_k / temperature,
                        g0_mps2 / (gas_constant_j_per_kg_k * layer.lapse_k_per_m),
                    );
                return .{
                    .geopotential_altitude_m = h_m,
                    .temperature_k = temperature,
                    .pressure_pa = pressure,
                    .density_kg_m3 = pressure / (gas_constant_j_per_kg_k * temperature),
                    .speed_of_sound_mps = @sqrt(gamma_air * gas_constant_j_per_kg_k * temperature),
                    .layer_index = @intCast(index),
                };
            }
        }
        unreachable;
    }

    pub fn evaluateGeometric(z_m: f64) Error!State {
        if (!std.math.isFinite(z_m)) return error.NonFiniteAltitude;
        if (z_m < 0.0 or z_m > max_geometric_altitude_m) return error.OutsideEnvelope;
        return evaluate(earth_radius_m * z_m / (earth_radius_m + z_m));
    }
};

pub const turbulence = struct {
    pub const Parameters = struct {
        sigma_mps: f64,
        scale_length_m: f64,
        airspeed_mps: f64,

        pub fn validate(self: Parameters) error{InvalidParameters}!void {
            if (!std.math.isFinite(self.sigma_mps) or !std.math.isFinite(self.scale_length_m) or
                !std.math.isFinite(self.airspeed_mps) or self.sigma_mps < 0.0 or
                !(self.scale_length_m > 0.0) or !(self.airspeed_mps > 0.0))
                return error.InvalidParameters;
        }
    };

    /// One-sided longitudinal Dryden spatial-frequency PSD.
    pub fn drydenLongitudinalPsd(omega_rad_per_m: f64, p: Parameters) error{InvalidParameters}!f64 {
        try p.validate();
        const x = p.scale_length_m * omega_rad_per_m;
        return 2.0 * p.sigma_mps * p.sigma_mps * p.scale_length_m /
            (std.math.pi * (1.0 + x * x));
    }

    /// One-sided lateral/vertical Dryden spatial-frequency PSD.
    pub fn drydenTransversePsd(omega_rad_per_m: f64, p: Parameters) error{InvalidParameters}!f64 {
        try p.validate();
        const x2 = std.math.pow(f64, p.scale_length_m * omega_rad_per_m, 2);
        return p.sigma_mps * p.sigma_mps * p.scale_length_m / std.math.pi *
            (1.0 + 3.0 * x2) / std.math.pow(f64, 1.0 + x2, 2);
    }

    pub fn vonKarmanLongitudinalPsd(omega_rad_per_m: f64, p: Parameters) error{InvalidParameters}!f64 {
        try p.validate();
        const x2 = std.math.pow(f64, 1.339 * p.scale_length_m * omega_rad_per_m, 2);
        return 2.0 * p.sigma_mps * p.sigma_mps * p.scale_length_m /
            (std.math.pi * std.math.pow(f64, 1.0 + x2, 5.0 / 6.0));
    }

    pub fn vonKarmanTransversePsd(omega_rad_per_m: f64, p: Parameters) error{InvalidParameters}!f64 {
        try p.validate();
        const x2 = std.math.pow(f64, 1.339 * p.scale_length_m * omega_rad_per_m, 2);
        return p.sigma_mps * p.sigma_mps * p.scale_length_m / std.math.pi *
            (1.0 + (8.0 / 3.0) * x2) / std.math.pow(f64, 1.0 + x2, 11.0 / 6.0);
    }

    /// Exact zero-order-hold update of the first-order longitudinal Dryden
    /// forming filter. Input is unit-variance white excitation per update.
    pub const DrydenLongitudinalFilter = struct {
        parameters: Parameters,
        state_mps: f64 = 0.0,

        pub fn step(self: *DrydenLongitudinalFilter, dt_s: f64, white: f64) error{InvalidParameters}!f64 {
            try self.parameters.validate();
            if (!std.math.isFinite(dt_s) or !std.math.isFinite(white) or !(dt_s > 0.0))
                return error.InvalidParameters;
            const rate = self.parameters.airspeed_mps / self.parameters.scale_length_m;
            const decay = @exp(-rate * dt_s);
            self.state_mps = decay * self.state_mps +
                self.parameters.sigma_mps * @sqrt(1.0 - decay * decay) * white;
            return self.state_mps;
        }
    };
};

pub const wind = struct {
    pub const Vec3 = struct { x: f64, y: f64, z: f64 };

    pub fn powerProfile(speed_reference_mps: f64, height_m: f64, reference_height_m: f64, exponent: f64) error{InvalidInput}!f64 {
        const v = [_]f64{ speed_reference_mps, height_m, reference_height_m, exponent };
        for (v) |x| if (!std.math.isFinite(x)) return error.InvalidInput;
        if (speed_reference_mps < 0.0 or height_m < 0.0 or !(reference_height_m > 0.0) or exponent < 0.0)
            return error.InvalidInput;
        return speed_reference_mps * std.math.pow(f64, height_m / reference_height_m, exponent);
    }

    pub const OneMinusCosineGust = struct {
        start_time_s: f64,
        duration_s: f64,
        peak_ned_mps: Vec3,

        pub fn at(self: OneMinusCosineGust, time_s: f64) error{InvalidInput}!Vec3 {
            if (!std.math.isFinite(time_s) or !std.math.isFinite(self.start_time_s) or
                !std.math.isFinite(self.duration_s) or !(self.duration_s > 0.0))
                return error.InvalidInput;
            const tau = time_s - self.start_time_s;
            if (tau <= 0.0 or tau >= self.duration_s) return .{ .x = 0, .y = 0, .z = 0 };
            const shape = 0.5 * (1.0 - @cos(2.0 * std.math.pi * tau / self.duration_s));
            return .{ .x = shape * self.peak_ned_mps.x, .y = shape * self.peak_ned_mps.y, .z = shape * self.peak_ned_mps.z };
        }
    };
};

pub const phenomena = struct {
    pub const IcingKind = enum { none, rime, clear, mixed, unknown };
    pub const IcingState = struct {
        kind: IcingKind,
        liquid_water_content_kg_m3: ?f64,
        median_volume_diameter_m: ?f64,
        ambient_temperature_k: f64,
        exposure_s: f64,
        source_time_s: f64,
    };
    pub const PrecipitationKind = enum { none, rain, snow, sleet, hail, unknown };
    pub const PrecipitationState = struct {
        kind: PrecipitationKind,
        rate_kg_m2_s: ?f64,
        particle_diameter_m: ?f64,
        source_time_s: f64,
    };
    pub const VisibilityState = struct {
        meteorological_range_m: ?f64,
        extinction_coefficient_per_m: ?f64,
        obscurant: enum { none, fog, cloud, dust, smoke, precipitation, unknown },
        source_time_s: f64,
    };
    pub const EnvironmentState = struct {
        icing: IcingState,
        precipitation: PrecipitationState,
        visibility: VisibilityState,
        valid_from_s: f64,
        valid_until_s: f64,

        pub fn validate(self: EnvironmentState) error{InvalidState}!void {
            const times = [_]f64{ self.valid_from_s, self.valid_until_s, self.icing.source_time_s, self.precipitation.source_time_s, self.visibility.source_time_s };
            for (times) |x| if (!std.math.isFinite(x)) return error.InvalidState;
            if (self.valid_until_s < self.valid_from_s or !(self.icing.ambient_temperature_k > 0.0) or self.icing.exposure_s < 0.0)
                return error.InvalidState;
            if (self.visibility.meteorological_range_m) |x| if (!(x > 0.0)) return error.InvalidState;
            if (self.visibility.extinction_coefficient_per_m) |x| if (x < 0.0) return error.InvalidState;
        }
    };
};

test "US76 layer boundaries and envelope are explicit" {
    try std.testing.expectEqual(@as(usize, 7), atmosphere.layers.len);
    const sea = try atmosphere.evaluate(0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 101_325.0), sea.pressure_pa, 1e-8);
    const h86 = try atmosphere.evaluateGeometric(86_000.0);
    try std.testing.expect(h86.pressure_pa > 0.0 and h86.layer_index == 6);
    try std.testing.expectApproxEqAbs(atmosphere.max_geopotential_altitude_m, h86.geopotential_altitude_m, 1e-9);
    try std.testing.expectError(error.OutsideEnvelope, atmosphere.evaluateGeometric(86_000.1));
}

test "spectra are nonnegative and seeded excitation can be replayed" {
    const p = turbulence.Parameters{ .sigma_mps = 2, .scale_length_m = 100, .airspeed_mps = 40 };
    try std.testing.expect((try turbulence.drydenLongitudinalPsd(0.1, p)) >= 0);
    try std.testing.expect((try turbulence.vonKarmanTransversePsd(0.1, p)) >= 0);
    var a = turbulence.DrydenLongitudinalFilter{ .parameters = p };
    var b = turbulence.DrydenLongitudinalFilter{ .parameters = p };
    const forcing = [_]f64{ 0.2, -1.0, 0.3, 0.8 };
    for (forcing) |x| try std.testing.expectEqual(try a.step(0.02, x), try b.step(0.02, x));
}

test "gust and weather state contracts refuse invalid values" {
    const gust = wind.OneMinusCosineGust{ .start_time_s = 2, .duration_s = 4, .peak_ned_mps = .{ .x = 10, .y = 0, .z = -2 } };
    try std.testing.expectApproxEqAbs(@as(f64, 10), (try gust.at(4)).x, 1e-12);
    var state = phenomena.EnvironmentState{
        .icing = .{ .kind = .none, .liquid_water_content_kg_m3 = null, .median_volume_diameter_m = null, .ambient_temperature_k = 280, .exposure_s = 0, .source_time_s = 0 },
        .precipitation = .{ .kind = .none, .rate_kg_m2_s = null, .particle_diameter_m = null, .source_time_s = 0 },
        .visibility = .{ .meteorological_range_m = 10_000, .extinction_coefficient_per_m = null, .obscurant = .none, .source_time_s = 0 },
        .valid_from_s = 0,
        .valid_until_s = 1,
    };
    try state.validate();
    state.visibility.meteorological_range_m = -1;
    try std.testing.expectError(error.InvalidState, state.validate());
}
