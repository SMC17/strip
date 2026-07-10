//! Datum-explicit regular-grid terrain sampling. No datum conversion, void
//! filling, obstacle database, or contact response is implied.

const std = @import("std");

pub const VerticalDatum = union(enum) {
    wgs84_ellipsoid,
    egm96_geoid,
    egm2008_geoid,
    local: []const u8,

    pub fn eql(a: VerticalDatum, b: VerticalDatum) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .local => |name| std.mem.eql(u8, name, b.local),
            else => true,
        };
    }
};

pub const SourceMetadata = struct {
    dataset_id: []const u8,
    edition: []const u8,
    horizontal_crs: []const u8,
    vertical_datum: VerticalDatum,
    resolution_m: f64,
    void_policy: enum { refuse, externally_filled },
    qualification: bool = false,
};

pub const Grid = struct {
    origin_east_m: f64,
    origin_north_m: f64,
    spacing_east_m: f64,
    spacing_north_m: f64,
    width: usize,
    height: usize,
    elevations_m: []const ?f64,
    metadata: SourceMetadata,

    pub const Error = error{
        InvalidGrid,
        NonFiniteQuery,
        OutsideGrid,
        DatumMismatch,
        VoidCell,
    };

    pub fn validate(self: Grid) Error!void {
        const values = [_]f64{
            self.origin_east_m,
            self.origin_north_m,
            self.spacing_east_m,
            self.spacing_north_m,
            self.metadata.resolution_m,
        };
        for (values) |scalar| if (!std.math.isFinite(scalar)) return error.InvalidGrid;
        if (!(self.spacing_east_m > 0.0) or !(self.spacing_north_m > 0.0) or
            !(self.metadata.resolution_m > 0.0) or self.width < 2 or self.height < 2 or
            self.width > std.math.maxInt(usize) / self.height or
            self.elevations_m.len != self.width * self.height)
            return error.InvalidGrid;
        for (self.elevations_m) |maybe_height| if (maybe_height) |height| {
            if (!std.math.isFinite(height)) return error.InvalidGrid;
        };
    }

    fn value(self: Grid, x: usize, y: usize) Error!f64 {
        return self.elevations_m[y * self.width + x] orelse error.VoidCell;
    }

    /// Bilinear interpolation in the grid's declared projected horizontal CRS.
    /// Every contributing corner must be present; voids are never fabricated.
    pub fn elevation(
        self: Grid,
        east_m: f64,
        north_m: f64,
        requested_datum: VerticalDatum,
    ) Error!f64 {
        try self.validate();
        if (!std.math.isFinite(east_m) or !std.math.isFinite(north_m)) return error.NonFiniteQuery;
        if (!self.metadata.vertical_datum.eql(requested_datum)) return error.DatumMismatch;
        const fx = (east_m - self.origin_east_m) / self.spacing_east_m;
        const fy = (north_m - self.origin_north_m) / self.spacing_north_m;
        if (fx < 0.0 or fy < 0.0 or fx > @as(f64, @floatFromInt(self.width - 1)) or
            fy > @as(f64, @floatFromInt(self.height - 1)))
            return error.OutsideGrid;

        const x0: usize = @intFromFloat(@floor(fx));
        const y0: usize = @intFromFloat(@floor(fy));
        const x1 = @min(x0 + 1, self.width - 1);
        const y1 = @min(y0 + 1, self.height - 1);
        const tx = fx - @as(f64, @floatFromInt(x0));
        const ty = fy - @as(f64, @floatFromInt(y0));
        const z00 = try self.value(x0, y0);
        const z10 = try self.value(x1, y0);
        const z01 = try self.value(x0, y1);
        const z11 = try self.value(x1, y1);
        return (1.0 - ty) * ((1.0 - tx) * z00 + tx * z10) +
            ty * ((1.0 - tx) * z01 + tx * z11);
    }
};

pub const Clearance = struct {
    terrain_elevation_m: f64,
    vehicle_reference_elevation_m: f64,
    clearance_m: f64,
    datum: VerticalDatum,
};

/// Geometric clearance only. It does not create contact forces or infer a
/// collision from the sign of the result.
pub fn clearanceAboveTerrain(
    grid: Grid,
    east_m: f64,
    north_m: f64,
    vehicle_reference_elevation_m: f64,
    vehicle_datum: VerticalDatum,
) Grid.Error!Clearance {
    if (!std.math.isFinite(vehicle_reference_elevation_m)) return error.NonFiniteQuery;
    const terrain_height = try grid.elevation(east_m, north_m, vehicle_datum);
    return .{
        .terrain_elevation_m = terrain_height,
        .vehicle_reference_elevation_m = vehicle_reference_elevation_m,
        .clearance_m = vehicle_reference_elevation_m - terrain_height,
        .datum = vehicle_datum,
    };
}

fn fixture(values: []const ?f64) Grid {
    return .{
        .origin_east_m = 0,
        .origin_north_m = 0,
        .spacing_east_m = 10,
        .spacing_north_m = 10,
        .width = 2,
        .height = 2,
        .elevations_m = values,
        .metadata = .{
            .dataset_id = "synthetic-2x2",
            .edition = "test-only",
            .horizontal_crs = "local ENU metres",
            .vertical_datum = .egm96_geoid,
            .resolution_m = 10,
            .void_policy = .refuse,
        },
    };
}

test "bilinear DEM interpolation and clearance share explicit datum" {
    const values = [_]?f64{ 0, 10, 20, 30 };
    const grid = fixture(&values);
    try std.testing.expectApproxEqAbs(@as(f64, 15), try grid.elevation(5, 5, .egm96_geoid), 1e-12);
    const result = try clearanceAboveTerrain(grid, 5, 5, 100, .egm96_geoid);
    try std.testing.expectApproxEqAbs(@as(f64, 85), result.clearance_m, 1e-12);
}

test "DEM refuses datum mismatch void and extrapolation" {
    const complete = [_]?f64{ 0, 10, 20, 30 };
    const grid = fixture(&complete);
    try std.testing.expectError(error.DatumMismatch, grid.elevation(5, 5, .wgs84_ellipsoid));
    try std.testing.expectError(error.OutsideGrid, grid.elevation(-1, 5, .egm96_geoid));
    const voided = [_]?f64{ 0, null, 20, 30 };
    try std.testing.expectError(error.VoidCell, fixture(&voided).elevation(5, 5, .egm96_geoid));
}
