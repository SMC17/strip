//! Stateless counter-based deterministic random generation with named streams.

const std = @import("std");

pub const Stream = struct {
    id: u64,

    pub fn named(name: []const u8) Stream {
        var hash: u64 = 0xcbf29ce484222325;
        for (name) |byte| {
            hash ^= byte;
            hash *%= 0x100000001b3;
        }
        return .{ .id = hash };
    }
};

pub const CounterRng = struct {
    seed: u64,
    stream: Stream,
    counter: u64 = 0,

    pub fn init(seed: u64, stream_name: []const u8) CounterRng {
        return .{ .seed = seed, .stream = .named(stream_name) };
    }

    /// Random access: output depends only on seed, stream, and index.
    pub fn at(self: CounterRng, index: u64) u64 {
        return mix(self.seed ^ mix(self.stream.id) ^ mix(index));
    }

    pub fn next(self: *CounterRng) error{CounterExhausted}!u64 {
        if (self.counter == std.math.maxInt(u64)) return error.CounterExhausted;
        const result = self.at(self.counter);
        self.counter += 1;
        return result;
    }

    pub fn unitF64At(self: CounterRng, index: u64) f64 {
        const significand = self.at(index) >> 11;
        return @as(f64, @floatFromInt(significand)) * 0x1.0p-53;
    }

    pub fn fork(self: CounterRng, child_name: []const u8) CounterRng {
        return .{
            .seed = self.seed,
            .stream = .{ .id = mix(self.stream.id ^ Stream.named(child_name).id) },
        };
    }
};

fn mix(input: u64) u64 {
    var value = input +% 0x9e3779b97f4a7c15;
    value = (value ^ (value >> 30)) *% 0xbf58476d1ce4e5b9;
    value = (value ^ (value >> 27)) *% 0x94d049bb133111eb;
    return value ^ (value >> 31);
}

test "counter output is deterministic and random-access" {
    var sequential = CounterRng.init(0x1234, "sensor-noise");
    const random_access = CounterRng.init(0x1234, "sensor-noise");
    var index: u64 = 0;
    while (index < 64) : (index += 1)
        try std.testing.expectEqual(random_access.at(index), try sequential.next());
}

test "named streams are separated and unit values are bounded" {
    const dynamics = CounterRng.init(42, "dynamics");
    const weather = CounterRng.init(42, "weather");
    try std.testing.expect(dynamics.at(0) != weather.at(0));
    var index: u64 = 0;
    while (index < 128) : (index += 1) {
        const value = dynamics.unitF64At(index);
        try std.testing.expect(value >= 0.0 and value < 1.0);
    }
}
