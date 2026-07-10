//! Surveyed-surface geometry contracts for fixed runways and moving decks.
//! Coordinates and timestamps remain explicit; no landing suitability claim is
//! derived from geometry alone.

const std = @import("std");

pub const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub fn scale(a: Vec3, s: f64) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    pub fn isFinite(a: Vec3) bool {
        return std.math.isFinite(a.x) and std.math.isFinite(a.y) and std.math.isFinite(a.z);
    }
};

pub const Quaternion = struct {
    w: f64,
    x: f64,
    y: f64,
    z: f64,

    pub fn validate(self: Quaternion) error{InvalidTransform}!void {
        const n2 = self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z;
        if (!std.math.isFinite(n2) or @abs(n2 - 1.0) > 1e-9) return error.InvalidTransform;
    }

    pub fn rotate(self: Quaternion, v: Vec3) error{InvalidTransform}!Vec3 {
        try self.validate();
        const qv = Vec3{ .x = self.x, .y = self.y, .z = self.z };
        const cross1 = Vec3{
            .x = qv.y * v.z - qv.z * v.y,
            .y = qv.z * v.x - qv.x * v.z,
            .z = qv.x * v.y - qv.y * v.x,
        };
        const cross2 = Vec3{
            .x = qv.y * cross1.z - qv.z * cross1.y,
            .y = qv.z * cross1.x - qv.x * cross1.z,
            .z = qv.x * cross1.y - qv.y * cross1.x,
        };
        return v.add(cross1.scale(2.0 * self.w)).add(cross2.scale(2.0));
    }
};

pub const SurfaceSource = struct {
    id: []const u8,
    edition: []const u8,
    horizontal_reference: []const u8,
    vertical_reference: []const u8,
    survey_epoch: []const u8,
    qualification: bool = false,
};

pub const Runway = struct {
    id: []const u8,
    threshold_local_m: Vec3,
    heading_rad: f64,
    length_m: f64,
    width_m: f64,
    longitudinal_slope: f64 = 0.0,
    source: SurfaceSource,

    pub const Coordinates = struct {
        along_m: f64,
        cross_m: f64,
        above_plane_m: f64,
        inside_planform: bool,
    };

    pub fn coordinates(self: Runway, point_local_m: Vec3) error{InvalidGeometry}!Coordinates {
        const scalars = [_]f64{ self.heading_rad, self.length_m, self.width_m, self.longitudinal_slope };
        for (scalars) |x| if (!std.math.isFinite(x)) return error.InvalidGeometry;
        if (!self.threshold_local_m.isFinite() or !point_local_m.isFinite() or !(self.length_m > 0.0) or !(self.width_m > 0.0))
            return error.InvalidGeometry;
        const dx = point_local_m.x - self.threshold_local_m.x;
        const dy = point_local_m.y - self.threshold_local_m.y;
        const dz = point_local_m.z - self.threshold_local_m.z;
        const c = @cos(self.heading_rad);
        const s = @sin(self.heading_rad);
        const along = c * dx + s * dy;
        const cross = -s * dx + c * dy;
        const plane_z = self.longitudinal_slope * along;
        return .{
            .along_m = along,
            .cross_m = cross,
            .above_plane_m = dz - plane_z,
            .inside_planform = along >= 0.0 and along <= self.length_m and @abs(cross) <= self.width_m / 2.0,
        };
    }
};

pub const RigidTransform = struct {
    origin_world_m: Vec3,
    deck_to_world: Quaternion,
    source_time_s: f64,

    pub fn pointToWorld(self: RigidTransform, point_deck_m: Vec3) error{InvalidTransform}!Vec3 {
        if (!self.origin_world_m.isFinite() or !point_deck_m.isFinite() or !std.math.isFinite(self.source_time_s))
            return error.InvalidTransform;
        return self.origin_world_m.add(try self.deck_to_world.rotate(point_deck_m));
    }
};

pub const MovingDeck = struct {
    id: []const u8,
    length_m: f64,
    width_m: f64,
    transform: RigidTransform,
    linear_velocity_world_mps: Vec3,
    angular_velocity_deck_radps: Vec3,
    valid_until_s: f64,
    source: SurfaceSource,

    pub fn validate(self: MovingDeck) error{InvalidGeometry}!void {
        if (!(self.length_m > 0.0) or !(self.width_m > 0.0) or
            !std.math.isFinite(self.length_m) or !std.math.isFinite(self.width_m) or
            !self.linear_velocity_world_mps.isFinite() or !self.angular_velocity_deck_radps.isFinite() or
            !std.math.isFinite(self.valid_until_s) or self.valid_until_s < self.transform.source_time_s)
            return error.InvalidGeometry;
        self.transform.deck_to_world.validate() catch return error.InvalidGeometry;
    }

    /// Translational propagation only. Nonzero angular rates require an
    /// externally supplied attitude update and are never silently integrated.
    pub fn transformAt(self: MovingDeck, time_s: f64) error{ InvalidGeometry, OutsideValidity, AttitudePropagationRequired }!RigidTransform {
        try self.validate();
        if (!std.math.isFinite(time_s) or time_s < self.transform.source_time_s or time_s > self.valid_until_s)
            return error.OutsideValidity;
        if (self.angular_velocity_deck_radps.x != 0.0 or self.angular_velocity_deck_radps.y != 0.0 or self.angular_velocity_deck_radps.z != 0.0)
            return error.AttitudePropagationRequired;
        const dt = time_s - self.transform.source_time_s;
        return .{
            .origin_world_m = self.transform.origin_world_m.add(self.linear_velocity_world_mps.scale(dt)),
            .deck_to_world = self.transform.deck_to_world,
            .source_time_s = time_s,
        };
    }
};

const test_source = SurfaceSource{
    .id = "synthetic",
    .edition = "test",
    .horizontal_reference = "local ENU",
    .vertical_reference = "local",
    .survey_epoch = "synthetic",
};

test "runway planform includes edges and preserves signed clearance" {
    const runway = Runway{
        .id = "09",
        .threshold_local_m = .{ .x = 0, .y = 0, .z = 100 },
        .heading_rad = 0,
        .length_m = 1000,
        .width_m = 30,
        .source = test_source,
    };
    const c = try runway.coordinates(.{ .x = 500, .y = 15, .z = 103 });
    try std.testing.expect(c.inside_planform);
    try std.testing.expectEqual(@as(f64, 3), c.above_plane_m);
}

test "moving deck transform is time bounded and refuses hidden attitude propagation" {
    var deck = MovingDeck{
        .id = "deck",
        .length_m = 100,
        .width_m = 20,
        .transform = .{ .origin_world_m = .{ .x = 0, .y = 0, .z = 0 }, .deck_to_world = .{ .w = 1, .x = 0, .y = 0, .z = 0 }, .source_time_s = 10 },
        .linear_velocity_world_mps = .{ .x = 5, .y = 0, .z = 0 },
        .angular_velocity_deck_radps = .{ .x = 0, .y = 0, .z = 0 },
        .valid_until_s = 20,
        .source = test_source,
    };
    try std.testing.expectEqual(@as(f64, 25), (try deck.transformAt(15)).origin_world_m.x);
    deck.angular_velocity_deck_radps.z = 0.1;
    try std.testing.expectError(error.AttitudePropagationRequired, deck.transformAt(15));
}
