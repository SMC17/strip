//! Typed intermediate representation for bounded aerospace studies.
const std = @import("std");

pub const EntityKind = enum { vehicle, environment, sensor, communication_link };
pub const Entity = struct { id: u64, kind: EntityKind };
pub const Connection = struct { source_id: u64, target_id: u64 };

pub const Model = struct {
    entities: []const Entity,
    connections: []const Connection,

    pub fn validate(self: Model) error{ DuplicateEntity, MissingEndpoint }!void {
        for (self.entities, 0..) |entity, i| {
            for (self.entities[i + 1 ..]) |other|
                if (entity.id == other.id) return error.DuplicateEntity;
        }
        for (self.connections) |connection| {
            var source = false;
            var target = false;
            for (self.entities) |entity| {
                source = source or entity.id == connection.source_id;
                target = target or entity.id == connection.target_id;
            }
            if (!source or !target) return error.MissingEndpoint;
        }
    }
};

test "IR validation rejects dangling connections" {
    const model: Model = .{
        .entities = &.{.{ .id = 1, .kind = .vehicle }},
        .connections = &.{.{ .source_id = 1, .target_id = 2 }},
    };
    try std.testing.expectError(error.MissingEndpoint, model.validate());
}
