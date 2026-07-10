//! WGS84 geodetic, Earth-centered Earth-fixed, and local NED transforms.

const std = @import("std");
const math3 = @import("../math/mod.zig");

pub const Wgs84 = struct {
    pub const semi_major_axis_m = 6_378_137.0;
    pub const flattening = 1.0 / 298.257_223_563;
    pub const semi_minor_axis_m = semi_major_axis_m * (1.0 - flattening);
    pub const eccentricity_squared = flattening * (2.0 - flattening);
    pub const second_eccentricity_squared =
        (semi_major_axis_m * semi_major_axis_m - semi_minor_axis_m * semi_minor_axis_m) /
        (semi_minor_axis_m * semi_minor_axis_m);
};

pub const EcefFrame = enum { ecef };
pub const NedFrame = enum { north_east_down };
pub const Ecef = math3.Vector3(EcefFrame);
pub const Ned = math3.Vector3(NedFrame);

pub const Geodetic = struct {
    latitude_radians: f64,
    longitude_radians: f64,
    altitude_meters: f64,

    pub const Error = error{ InvalidLatitude, NonFinite };

    pub fn init(latitude_radians: f64, longitude_radians: f64, altitude_meters: f64) Error!Geodetic {
        if (!std.math.isFinite(latitude_radians) or
            !std.math.isFinite(longitude_radians) or
            !std.math.isFinite(altitude_meters)) return error.NonFinite;
        if (@abs(latitude_radians) > std.math.pi / 2.0) return error.InvalidLatitude;
        return .{
            .latitude_radians = latitude_radians,
            .longitude_radians = normalizeLongitude(longitude_radians),
            .altitude_meters = altitude_meters,
        };
    }
};

pub fn normalizeLongitude(longitude_radians: f64) f64 {
    const two_pi = 2.0 * std.math.pi;
    var result = @mod(longitude_radians + std.math.pi, two_pi) - std.math.pi;
    if (result == -std.math.pi and longitude_radians > 0.0) result = std.math.pi;
    return result;
}

pub fn geodeticToEcef(point: Geodetic) Ecef {
    const sin_lat = @sin(point.latitude_radians);
    const cos_lat = @cos(point.latitude_radians);
    const sin_lon = @sin(point.longitude_radians);
    const cos_lon = @cos(point.longitude_radians);
    const prime_vertical = Wgs84.semi_major_axis_m /
        @sqrt(1.0 - Wgs84.eccentricity_squared * sin_lat * sin_lat);
    return .init(
        (prime_vertical + point.altitude_meters) * cos_lat * cos_lon,
        (prime_vertical + point.altitude_meters) * cos_lat * sin_lon,
        (prime_vertical * (1.0 - Wgs84.eccentricity_squared) + point.altitude_meters) * sin_lat,
    );
}

pub fn ecefToGeodetic(point: Ecef) Geodetic {
    const p = @sqrt(point.x * point.x + point.y * point.y);
    if (p < 1e-12) {
        const latitude: f64 = if (point.z < 0.0) -std.math.pi / 2.0 else std.math.pi / 2.0;
        return .{
            .latitude_radians = latitude,
            .longitude_radians = 0.0,
            .altitude_meters = @abs(point.z) - Wgs84.semi_minor_axis_m,
        };
    }

    const theta = std.math.atan2(
        point.z * Wgs84.semi_major_axis_m,
        p * Wgs84.semi_minor_axis_m,
    );
    const sin_theta = @sin(theta);
    const cos_theta = @cos(theta);
    const latitude = std.math.atan2(
        point.z + Wgs84.second_eccentricity_squared * Wgs84.semi_minor_axis_m *
            sin_theta * sin_theta * sin_theta,
        p - Wgs84.eccentricity_squared * Wgs84.semi_major_axis_m *
            cos_theta * cos_theta * cos_theta,
    );
    const longitude = std.math.atan2(point.y, point.x);
    const sin_lat = @sin(latitude);
    const prime_vertical = Wgs84.semi_major_axis_m /
        @sqrt(1.0 - Wgs84.eccentricity_squared * sin_lat * sin_lat);
    const altitude = p / @cos(latitude) - prime_vertical;
    return .{
        .latitude_radians = latitude,
        .longitude_radians = longitude,
        .altitude_meters = altitude,
    };
}

pub const LocalNed = struct {
    origin: Geodetic,
    origin_ecef: Ecef,
    ecef_to_ned: math3.Matrix3(EcefFrame, NedFrame),

    pub fn init(origin: Geodetic) LocalNed {
        const latitude = origin.latitude_radians;
        const longitude = origin.longitude_radians;
        const sin_lat = @sin(latitude);
        const cos_lat = @cos(latitude);
        const sin_lon = @sin(longitude);
        const cos_lon = @cos(longitude);
        return .{
            .origin = origin,
            .origin_ecef = geodeticToEcef(origin),
            .ecef_to_ned = .{ .elements = .{
                .{ -sin_lat * cos_lon, -sin_lat * sin_lon, cos_lat },
                .{ -sin_lon, cos_lon, 0.0 },
                .{ -cos_lat * cos_lon, -cos_lat * sin_lon, -sin_lat },
            } },
        };
    }

    pub fn fromEcef(self: LocalNed, point: Ecef) Ned {
        return self.ecef_to_ned.apply(point.sub(self.origin_ecef));
    }

    pub fn toEcef(self: LocalNed, point: Ned) Ecef {
        return self.origin_ecef.add(self.ecef_to_ned.transpose().apply(point));
    }

    pub fn fromGeodetic(self: LocalNed, point: Geodetic) Ned {
        return self.fromEcef(geodeticToEcef(point));
    }
};

test "known WGS84 equator and pole coordinates" {
    const equator = try Geodetic.init(0.0, 0.0, 0.0);
    try std.testing.expect(geodeticToEcef(equator).approxEqAbs(
        Ecef.init(Wgs84.semi_major_axis_m, 0.0, 0.0),
        1e-9,
    ));
    const north_pole = try Geodetic.init(std.math.pi / 2.0, 0.0, 0.0);
    const pole_ecef = geodeticToEcef(north_pole);
    try std.testing.expectApproxEqAbs(Wgs84.semi_minor_axis_m, pole_ecef.z, 1e-8);
}

test "geodetic ECEF round trips over representative points" {
    const samples = [_]Geodetic{
        try .init(0.0, 0.0, 0.0),
        try .init(0.7, -2.1, 1234.5),
        try .init(-1.2, 2.9, -50.0),
        try .init(1.55, 0.2, 35_000.0),
    };
    for (samples) |sample| {
        const recovered = ecefToGeodetic(geodeticToEcef(sample));
        try std.testing.expectApproxEqAbs(sample.latitude_radians, recovered.latitude_radians, 2e-12);
        try std.testing.expectApproxEqAbs(sample.longitude_radians, recovered.longitude_radians, 2e-12);
        try std.testing.expectApproxEqAbs(sample.altitude_meters, recovered.altitude_meters, 2e-5);
    }
}

test "NED and ECEF transforms are inverse" {
    const origin = try Geodetic.init(0.6, -1.3, 250.0);
    const local = LocalNed.init(origin);
    const displacement = Ned.init(120.0, -35.0, 8.0);
    const recovered = local.fromEcef(local.toEcef(displacement));
    try std.testing.expect(recovered.approxEqAbs(displacement, 1e-9));
}
