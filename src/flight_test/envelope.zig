//! Online multidimensional envelope tracking with explicit excursion records.
const std = @import("std");

pub const max_dimensions = 16;

pub const Bound = struct {
    name: []const u8,
    unit: []const u8,
    minimum: f64,
    maximum: f64,

    pub fn validate(self: Bound) !void {
        if (self.name.len == 0 or self.name.len > 64) return error.InvalidName;
        if (self.unit.len == 0 or self.unit.len > 24) return error.InvalidUnit;
        if (!std.math.isFinite(self.minimum) or !std.math.isFinite(self.maximum) or
            self.minimum > self.maximum) return error.InvalidBound;
    }
};

pub const AxisRecord = struct {
    observed_minimum: f64 = std.math.inf(f64),
    observed_maximum: f64 = -std.math.inf(f64),
    excursion_count: usize = 0,
    maximum_normalized_excursion: f64 = 0.0,
};

pub const Tracker = struct {
    bounds: [max_dimensions]Bound = undefined,
    records: [max_dimensions]AxisRecord = [_]AxisRecord{.{}} ** max_dimensions,
    dimension_count: usize = 0,
    sample_count: usize = 0,
    samples_outside: usize = 0,
    first_excursion_sequence: ?u64 = null,
    last_excursion_sequence: ?u64 = null,

    pub fn init(bounds: []const Bound) !Tracker {
        if (bounds.len == 0 or bounds.len > max_dimensions) return error.InvalidDimensionCount;
        var tracker: Tracker = .{ .dimension_count = bounds.len };
        for (bounds, 0..) |bound, index| {
            try bound.validate();
            for (bounds[0..index]) |prior|
                if (std.mem.eql(u8, prior.name, bound.name)) return error.DuplicateDimension;
            tracker.bounds[index] = bound;
        }
        return tracker;
    }

    pub fn observe(self: *Tracker, sequence: u64, values: []const f64) !bool {
        if (values.len != self.dimension_count) return error.DimensionMismatch;
        var outside = false;
        for (values, 0..) |value, index| {
            if (!std.math.isFinite(value)) return error.NonFiniteValue;
            const bound = self.bounds[index];
            var record = &self.records[index];
            record.observed_minimum = @min(record.observed_minimum, value);
            record.observed_maximum = @max(record.observed_maximum, value);
            if (value < bound.minimum or value > bound.maximum) {
                outside = true;
                record.excursion_count += 1;
                const width = bound.maximum - bound.minimum;
                const distance = if (value < bound.minimum)
                    bound.minimum - value
                else
                    value - bound.maximum;
                const normalized = if (width > 0.0) distance / width else std.math.inf(f64);
                record.maximum_normalized_excursion =
                    @max(record.maximum_normalized_excursion, normalized);
            }
        }
        self.sample_count += 1;
        if (outside) {
            self.samples_outside += 1;
            if (self.first_excursion_sequence == null) self.first_excursion_sequence = sequence;
            self.last_excursion_sequence = sequence;
        }
        return !outside;
    }
};

test "envelope tracks multidimensional excursions without double-counting samples" {
    var tracker = try Tracker.init(&.{
        .{ .name = "airspeed", .unit = "m/s", .minimum = 10, .maximum = 40 },
        .{ .name = "angle_of_attack", .unit = "deg", .minimum = -5, .maximum = 12 },
    });
    try std.testing.expect(try tracker.observe(10, &.{ 20, 2 }));
    try std.testing.expect(!try tracker.observe(11, &.{ 45, 15 }));
    try std.testing.expect(!try tracker.observe(12, &.{ 30, -6 }));
    try std.testing.expectEqual(@as(usize, 3), tracker.sample_count);
    try std.testing.expectEqual(@as(usize, 2), tracker.samples_outside);
    try std.testing.expectEqual(@as(usize, 1), tracker.records[0].excursion_count);
    try std.testing.expectEqual(@as(u64, 11), tracker.first_excursion_sequence.?);
}
