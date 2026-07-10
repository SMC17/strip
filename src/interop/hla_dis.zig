//! Deterministic HLA logical-time ordering and DIS entity identity.
const std = @import("std");

pub const Error = error{
    InvalidLookahead,
    TimeWentBackwards,
    TimeAdvanceAlreadyPending,
    NoTimeAdvancePending,
    GrantBeforeRequest,
    InvalidEntityIdentity,
    MalformedEntityIdentity,
};

pub const LogicalTime = struct {
    nanoseconds: i64,

    pub fn order(a: LogicalTime, b: LogicalTime) std.math.Order {
        return std.math.order(a.nanoseconds, b.nanoseconds);
    }
};

pub const EventKey = struct {
    time: LogicalTime,
    federate: u32,
    serial: u64,

    pub fn lessThan(_: void, a: EventKey, b: EventKey) bool {
        if (a.time.nanoseconds != b.time.nanoseconds)
            return a.time.nanoseconds < b.time.nanoseconds;
        if (a.federate != b.federate) return a.federate < b.federate;
        return a.serial < b.serial;
    }
};

pub const TimeManager = struct {
    granted: LogicalTime = .{ .nanoseconds = 0 },
    lookahead_ns: u64,
    requested: ?LogicalTime = null,

    pub fn init(lookahead_ns: u64) Error!TimeManager {
        if (lookahead_ns == 0) return error.InvalidLookahead;
        return .{ .lookahead_ns = lookahead_ns };
    }

    pub fn requestAdvance(self: *TimeManager, requested: LogicalTime) Error!void {
        if (self.requested != null) return error.TimeAdvanceAlreadyPending;
        if (requested.nanoseconds < self.granted.nanoseconds) return error.TimeWentBackwards;
        self.requested = requested;
    }

    pub fn grant(self: *TimeManager, granted: LogicalTime) Error!void {
        const requested = self.requested orelse return error.NoTimeAdvancePending;
        if (granted.nanoseconds < self.granted.nanoseconds) return error.TimeWentBackwards;
        if (granted.nanoseconds < requested.nanoseconds) return error.GrantBeforeRequest;
        self.granted = granted;
        self.requested = null;
    }

    pub fn earliestSendTime(self: TimeManager) LogicalTime {
        const lookahead: i64 = @intCast(@min(
            self.lookahead_ns,
            @as(u64, @intCast(std.math.maxInt(i64))),
        ));
        return .{
            .nanoseconds = std.math.add(i64, self.granted.nanoseconds, lookahead) catch
                std.math.maxInt(i64),
        };
    }
};

/// IEEE 1278 DIS Entity Identifier: site, application, entity.
pub const EntityId = struct {
    site: u16,
    application: u16,
    entity: u16,

    pub fn init(site: u16, application: u16, entity: u16) Error!EntityId {
        if (site == 0 or application == 0 or entity == 0)
            return error.InvalidEntityIdentity;
        return .{ .site = site, .application = application, .entity = entity };
    }

    pub fn encodeNetwork(self: EntityId) [6]u8 {
        return .{
            @truncate(self.site >> 8),
            @truncate(self.site),
            @truncate(self.application >> 8),
            @truncate(self.application),
            @truncate(self.entity >> 8),
            @truncate(self.entity),
        };
    }

    pub fn decodeNetwork(bytes: []const u8) Error!EntityId {
        if (bytes.len != 6) return error.MalformedEntityIdentity;
        return init(
            (@as(u16, bytes[0]) << 8) | bytes[1],
            (@as(u16, bytes[2]) << 8) | bytes[3],
            (@as(u16, bytes[4]) << 8) | bytes[5],
        );
    }
};

test "HLA time grants are monotonic and ordered" {
    var manager = try TimeManager.init(10);
    try manager.requestAdvance(.{ .nanoseconds = 100 });
    try std.testing.expectError(
        error.TimeAdvanceAlreadyPending,
        manager.requestAdvance(.{ .nanoseconds = 200 }),
    );
    try std.testing.expectError(error.GrantBeforeRequest, manager.grant(.{ .nanoseconds = 99 }));
    try manager.grant(.{ .nanoseconds = 100 });
    try std.testing.expectEqual(@as(i64, 110), manager.earliestSendTime().nanoseconds);
    try std.testing.expectError(
        error.TimeWentBackwards,
        manager.requestAdvance(.{ .nanoseconds = 50 }),
    );

    const first = EventKey{
        .time = .{ .nanoseconds = 100 },
        .federate = 2,
        .serial = 8,
    };
    var second = first;
    second.serial += 1;
    try std.testing.expect(EventKey.lessThan({}, first, second));
}

test "DIS entity identity validates and round trips network order" {
    const identity = try EntityId.init(0x0102, 0x0304, 0x0506);
    const encoded = identity.encodeNetwork();
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6 }, &encoded);
    try std.testing.expectEqual(identity, try EntityId.decodeNetwork(&encoded));
    try std.testing.expectError(
        error.InvalidEntityIdentity,
        EntityId.init(1, 2, 0),
    );
    try std.testing.expectError(
        error.MalformedEntityIdentity,
        EntityId.decodeNetwork(&.{ 1, 2 }),
    );
}
