//! Authoritative integer state, input journals, rollback, and render snapshots.
const std = @import("std");
const storage = @import("storage.zig");

pub const Vec3i64 = struct {
    x: i64,
    y: i64,
    z: i64,

    pub fn add(a: Vec3i64, b: Vec3i64) error{Overflow}!Vec3i64 {
        return .{
            .x = try std.math.add(i64, a.x, b.x),
            .y = try std.math.add(i64, a.y, b.y),
            .z = try std.math.add(i64, a.z, b.z),
        };
    }
};

/// Millimetres in an application-declared Earth-fixed/georeferenced frame.
pub const AbsolutePosition = Vec3i64;
pub const VelocityPerTick = Vec3i64;
pub const LocalOrigin = AbsolutePosition;

pub const LocalPosition = struct { x: f64, y: f64, z: f64 };

pub fn toLocal(position: AbsolutePosition, origin: LocalOrigin) LocalPosition {
    // Convert before subtraction so opposite i64 extrema remain representable.
    return .{
        .x = (@as(f64, @floatFromInt(position.x)) - @as(f64, @floatFromInt(origin.x))) / 1000.0,
        .y = (@as(f64, @floatFromInt(position.y)) - @as(f64, @floatFromInt(origin.y))) / 1000.0,
        .z = (@as(f64, @floatFromInt(position.z)) - @as(f64, @floatFromInt(origin.z))) / 1000.0,
    };
}

pub const ExternalInput = struct {
    target: storage.Entity,
    source_id: u32,
    tick: u64,
    sequence: u64 = 0,
    acceleration_per_tick: Vec3i64,
};

pub fn InputRecorder(comptime capacity: usize) type {
    return struct {
        entries: [capacity]ExternalInput = undefined,
        len: usize = 0,
        next_sequence: u64 = 0,

        const Self = @This();
        pub const Error = error{ InputCapacityExceeded, SequenceExhausted };

        pub fn record(self: *Self, input_value: ExternalInput) Error!void {
            if (self.len == capacity) return error.InputCapacityExceeded;
            if (self.next_sequence == std.math.maxInt(u64)) return error.SequenceExhausted;
            var input = input_value;
            input.sequence = self.next_sequence;
            self.next_sequence += 1;
            self.entries[self.len] = input;
            self.len += 1;
        }
    };
}

pub fn AuthoritativeWorld(comptime entity_capacity: usize) type {
    return struct {
        entities: storage.EntityPool(entity_capacity) = .{},
        positions: storage.ComponentStore(AbsolutePosition, entity_capacity, entity_capacity) = .{},
        velocities: storage.ComponentStore(VelocityPerTick, entity_capacity, entity_capacity) = .{},
        tick: u64 = 0,

        const Self = @This();
        pub const Error = error{ MissingComponent, Overflow, InvalidTick };

        pub fn spawn(self: *Self, position: AbsolutePosition, velocity: VelocityPerTick) !storage.Entity {
            const entity = try self.entities.create();
            errdefer _ = self.entities.destroy(entity);
            try self.positions.put(entity, position);
            try self.velocities.put(entity, velocity);
            return entity;
        }

        pub fn stepEntity(self: *Self, entity: storage.Entity, acceleration: Vec3i64) Error!void {
            const velocity = self.velocities.get(entity) orelse return error.MissingComponent;
            velocity.* = velocity.add(acceleration) catch return error.Overflow;
            const position = self.positions.get(entity) orelse return error.MissingComponent;
            position.* = position.add(velocity.*) catch return error.Overflow;
        }

        pub fn step(self: *Self, inputs: []const ExternalInput) Error!void {
            const next_tick = std.math.add(u64, self.tick, 1) catch return error.Overflow;
            // Inputs are recorded in a total order. Multiple inputs for one
            // entity accumulate before the single integration update.
            for (self.positions.entities[0..self.positions.len]) |entity| {
                var acceleration = Vec3i64{ .x = 0, .y = 0, .z = 0 };
                for (inputs) |input| {
                    if (input.tick != next_tick or !std.meta.eql(input.target, entity)) continue;
                    acceleration = acceleration.add(input.acceleration_per_tick) catch return error.Overflow;
                }
                try self.stepEntity(entity, acceleration);
            }
            self.tick = next_tick;
        }
    };
}

pub fn RollbackBuffer(
    comptime entity_capacity: usize,
    comptime checkpoint_capacity: usize,
    comptime input_capacity: usize,
) type {
    const World = AuthoritativeWorld(entity_capacity);
    return struct {
        checkpoints: [checkpoint_capacity]World = undefined,
        checkpoint_ticks: [checkpoint_capacity]u64 = undefined,
        checkpoint_count: usize = 0,
        next_checkpoint: usize = 0,
        inputs: InputRecorder(input_capacity) = .{},

        const Self = @This();
        pub const Error = error{ CheckpointNotFound, TargetBeforeCheckpoint, MissingComponent } ||
            World.Error || InputRecorder(input_capacity).Error;

        pub fn checkpoint(self: *Self, world: *const World) void {
            self.checkpoints[self.next_checkpoint] = world.*;
            self.checkpoint_ticks[self.next_checkpoint] = world.tick;
            self.next_checkpoint = (self.next_checkpoint + 1) % checkpoint_capacity;
            self.checkpoint_count = @min(self.checkpoint_count + 1, checkpoint_capacity);
        }

        /// Restores and resimulates only `entity`; unrelated current state is
        /// untouched. The checkpoint tick must be exact to avoid hidden drift.
        pub fn rollbackEntity(
            self: *const Self,
            world: *World,
            entity: storage.Entity,
            checkpoint_tick: u64,
            target_tick: u64,
        ) Error!void {
            if (target_tick < checkpoint_tick) return error.TargetBeforeCheckpoint;
            const saved = self.findCheckpoint(checkpoint_tick) orelse return error.CheckpointNotFound;
            const saved_position = saved.positions.getConst(entity) orelse return error.MissingComponent;
            const saved_velocity = saved.velocities.getConst(entity) orelse return error.MissingComponent;
            const position = world.positions.get(entity) orelse return error.MissingComponent;
            const velocity = world.velocities.get(entity) orelse return error.MissingComponent;
            position.* = saved_position.*;
            velocity.* = saved_velocity.*;

            if (target_tick == checkpoint_tick) {
                world.tick = @max(world.tick, target_tick);
                return;
            }
            var tick = checkpoint_tick + 1;
            while (true) {
                var acceleration = Vec3i64{ .x = 0, .y = 0, .z = 0 };
                for (self.inputs.entries[0..self.inputs.len]) |input| {
                    if (input.tick == tick and std.meta.eql(input.target, entity))
                        acceleration = acceleration.add(input.acceleration_per_tick) catch return error.Overflow;
                }
                try world.stepEntity(entity, acceleration);
                if (tick == target_tick) break;
                tick += 1;
            }
            world.tick = @max(world.tick, target_tick);
        }

        fn findCheckpoint(self: *const Self, tick: u64) ?*const World {
            for (0..self.checkpoint_count) |i|
                if (self.checkpoint_ticks[i] == tick) return &self.checkpoints[i];
            return null;
        }
    };
}

pub fn RenderSnapshots(comptime capacity: usize) type {
    return struct {
        previous_tick: u64 = 0,
        current_tick: u64 = 0,
        previous: [capacity]AbsolutePosition = [_]AbsolutePosition{.{ .x = 0, .y = 0, .z = 0 }} ** capacity,
        current: [capacity]AbsolutePosition = [_]AbsolutePosition{.{ .x = 0, .y = 0, .z = 0 }} ** capacity,
        present: [capacity]bool = [_]bool{false} ** capacity,
        initialized: bool = false,

        const Self = @This();

        pub fn capture(self: *Self, world: *const AuthoritativeWorld(capacity)) void {
            if (self.initialized) {
                self.previous = self.current;
                self.previous_tick = self.current_tick;
            }
            self.current_tick = world.tick;
            self.present = [_]bool{false} ** capacity;
            for (world.positions.entities[0..world.positions.len], world.positions.values[0..world.positions.len]) |entity, value| {
                self.current[entity.index] = value;
                self.present[entity.index] = true;
            }
            if (!self.initialized) {
                self.previous = self.current;
                self.previous_tick = self.current_tick;
                self.initialized = true;
            }
        }

        /// Perceptual output is derived and never fed into authoritative state.
        pub fn interpolate(self: *const Self, entity: storage.Entity, origin: LocalOrigin, alpha: f64) ?LocalPosition {
            if (entity.index >= capacity or !self.present[entity.index]) return null;
            const clamped = std.math.clamp(alpha, 0.0, 1.0);
            const a = toLocal(self.previous[entity.index], origin);
            const b = toLocal(self.current[entity.index], origin);
            return .{
                .x = a.x + (b.x - a.x) * clamped,
                .y = a.y + (b.y - a.y) * clamped,
                .z = a.z + (b.z - a.z) * clamped,
            };
        }
    };
}

test "rollback resimulation equals uninterrupted authoritative execution" {
    const World = AuthoritativeWorld(2);
    const History = RollbackBuffer(2, 2, 8);
    var expected = World{};
    const entity = try expected.spawn(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 });
    const unrelated = try expected.spawn(.{ .x = 10, .y = 0, .z = 0 }, .{ .x = 0, .y = 0, .z = 0 });
    var history = History{};
    history.checkpoint(&expected);
    try history.inputs.record(.{ .target = entity, .source_id = 7, .tick = 2, .acceleration_per_tick = .{ .x = 2, .y = 0, .z = 0 } });
    while (expected.tick < 4) try expected.step(history.inputs.entries[0..history.inputs.len]);

    var corrected = expected;
    corrected.positions.get(entity).?.x = 999;
    corrected.velocities.get(entity).?.x = 999;
    corrected.positions.get(unrelated).?.x = 777;
    try history.rollbackEntity(&corrected, entity, 0, 4);
    try std.testing.expectEqual(expected.positions.get(entity).?.*, corrected.positions.get(entity).?.*);
    try std.testing.expectEqual(expected.velocities.get(entity).?.*, corrected.velocities.get(entity).?.*);
    try std.testing.expectEqual(@as(i64, 777), corrected.positions.get(unrelated).?.x);
}

test "origin rebasing changes local coordinates but preserves separation" {
    const a = AbsolutePosition{ .x = 6_378_137_000, .y = 2000, .z = -3000 };
    const b = AbsolutePosition{ .x = 6_378_138_250, .y = 4000, .z = 1000 };
    const origin_one = LocalOrigin{ .x = 6_378_137_000, .y = 0, .z = 0 };
    const origin_two = LocalOrigin{ .x = 6_378_000_000, .y = -9000, .z = 5000 };
    const a1 = toLocal(a, origin_one);
    const b1 = toLocal(b, origin_one);
    const a2 = toLocal(a, origin_two);
    const b2 = toLocal(b, origin_two);
    try std.testing.expectApproxEqAbs(b1.x - a1.x, b2.x - a2.x, 1e-9);
    try std.testing.expectApproxEqAbs(b1.y - a1.y, b2.y - a2.y, 1e-9);
    try std.testing.expectApproxEqAbs(b1.z - a1.z, b2.z - a2.z, 1e-9);
}

test "render interpolation remains separate from authoritative positions" {
    var world = AuthoritativeWorld(1){};
    const entity = try world.spawn(.{ .x = 1000, .y = 0, .z = 0 }, .{ .x = 1000, .y = 0, .z = 0 });
    var snapshots = RenderSnapshots(1){};
    snapshots.capture(&world);
    try world.step(&.{});
    snapshots.capture(&world);
    const rendered = snapshots.interpolate(entity, .{ .x = 0, .y = 0, .z = 0 }, 0.5).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), rendered.x, 1e-12);
    try std.testing.expectEqual(@as(i64, 2000), world.positions.get(entity).?.x);
}
