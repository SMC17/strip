//! Fixed-capacity entity and sparse component storage.
const std = @import("std");

pub const Entity = struct {
    index: u32,
    generation: u32,
};

pub fn EntityPool(comptime capacity: usize) type {
    return struct {
        generations: [capacity]u32 = [_]u32{1} ** capacity,
        alive: [capacity]bool = [_]bool{false} ** capacity,
        count: usize = 0,

        const Self = @This();
        pub const Error = error{EntityCapacityExceeded};

        pub fn create(self: *Self) Error!Entity {
            for (0..capacity) |i| {
                if (!self.alive[i]) {
                    self.alive[i] = true;
                    self.count += 1;
                    return .{ .index = @intCast(i), .generation = self.generations[i] };
                }
            }
            return error.EntityCapacityExceeded;
        }

        pub fn destroy(self: *Self, entity: Entity) bool {
            const i: usize = entity.index;
            if (i >= capacity or !self.alive[i] or self.generations[i] != entity.generation)
                return false;
            self.alive[i] = false;
            self.count -= 1;
            self.generations[i] +%= 1;
            if (self.generations[i] == 0) self.generations[i] = 1;
            return true;
        }

        pub fn contains(self: *const Self, entity: Entity) bool {
            const i: usize = entity.index;
            return i < capacity and self.alive[i] and self.generations[i] == entity.generation;
        }
    };
}

/// Sparse-set storage. Dense iteration follows insertion order; removal uses a
/// swap and therefore has explicit, deterministic (but not stable) ordering.
pub fn ComponentStore(comptime T: type, comptime entity_capacity: usize, comptime component_capacity: usize) type {
    return struct {
        values: [component_capacity]T = undefined,
        entities: [component_capacity]Entity = undefined,
        sparse: [entity_capacity]usize = [_]usize{none} ** entity_capacity,
        len: usize = 0,

        const Self = @This();
        const none = std.math.maxInt(usize);
        pub const Error = error{ ComponentCapacityExceeded, EntityOutOfRange };

        pub fn put(self: *Self, entity: Entity, value: T) Error!void {
            const slot: usize = entity.index;
            if (slot >= entity_capacity) return error.EntityOutOfRange;
            if (self.indexOf(entity)) |dense| {
                self.values[dense] = value;
                return;
            }
            if (self.len == component_capacity) return error.ComponentCapacityExceeded;
            self.values[self.len] = value;
            self.entities[self.len] = entity;
            self.sparse[slot] = self.len;
            self.len += 1;
        }

        pub fn get(self: *Self, entity: Entity) ?*T {
            const dense = self.indexOf(entity) orelse return null;
            return &self.values[dense];
        }

        pub fn getConst(self: *const Self, entity: Entity) ?*const T {
            const dense = self.indexOf(entity) orelse return null;
            return &self.values[dense];
        }

        pub fn remove(self: *Self, entity: Entity) bool {
            const dense = self.indexOf(entity) orelse return false;
            const last = self.len - 1;
            self.sparse[entity.index] = none;
            if (dense != last) {
                self.values[dense] = self.values[last];
                self.entities[dense] = self.entities[last];
                self.sparse[self.entities[dense].index] = dense;
            }
            self.len = last;
            return true;
        }

        fn indexOf(self: *const Self, entity: Entity) ?usize {
            const slot: usize = entity.index;
            if (slot >= entity_capacity) return null;
            const dense = self.sparse[slot];
            if (dense == none or dense >= self.len) return null;
            if (self.entities[dense].generation != entity.generation) return null;
            return dense;
        }
    };
}

test "entity and component capacity is bounded and stale handles fail" {
    var entities = EntityPool(2){};
    const a = try entities.create();
    const b = try entities.create();
    try std.testing.expectError(error.EntityCapacityExceeded, entities.create());

    var values = ComponentStore(u32, 2, 1){};
    try values.put(a, 10);
    try std.testing.expectError(error.ComponentCapacityExceeded, values.put(b, 20));
    try std.testing.expect(entities.destroy(a));
    try std.testing.expect(values.remove(a));
    const replacement = try entities.create();
    try std.testing.expect(replacement.generation != a.generation);
    try std.testing.expect(values.get(a) == null);
}
