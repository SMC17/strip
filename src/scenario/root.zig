//! Deterministic scenario event scheduling.
const std = @import("std");

pub const EventKind = enum { command, environment, link, fault, observation };

pub const Event = struct {
    time_ns: u64,
    priority: u16 = 0,
    sequence: u64,
    kind: EventKind,
    payload_id: u64,

    pub fn lessThan(_: void, a: Event, b: Event) bool {
        if (a.time_ns != b.time_ns) return a.time_ns < b.time_ns;
        if (a.priority != b.priority) return a.priority < b.priority;
        return a.sequence < b.sequence;
    }
};

pub fn Scheduler(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        events: [capacity]Event = undefined,
        len: usize = 0,
        next_sequence: u64 = 0,

        pub const Error = error{CapacityExceeded};

        pub fn schedule(
            self: *Self,
            time_ns: u64,
            priority: u16,
            kind: EventKind,
            payload_id: u64,
        ) Error!u64 {
            if (self.len == capacity) return error.CapacityExceeded;
            const sequence = self.next_sequence;
            self.next_sequence += 1;
            self.events[self.len] = .{
                .time_ns = time_ns,
                .priority = priority,
                .sequence = sequence,
                .kind = kind,
                .payload_id = payload_id,
            };
            self.len += 1;
            return sequence;
        }

        pub fn sort(self: *Self) void {
            std.mem.sort(Event, self.events[0..self.len], {}, Event.lessThan);
        }

        pub fn ordered(self: *const Self) []const Event {
            return self.events[0..self.len];
        }
    };
}

test "events are ordered by time priority then insertion sequence" {
    var scheduler: Scheduler(4) = .{};
    _ = try scheduler.schedule(20, 0, .observation, 4);
    _ = try scheduler.schedule(10, 2, .fault, 2);
    _ = try scheduler.schedule(10, 1, .link, 1);
    _ = try scheduler.schedule(10, 1, .command, 3);
    scheduler.sort();
    const ordered = scheduler.ordered();
    try std.testing.expectEqualSlices(u64, &.{ 1, 3, 2, 4 }, &.{
        ordered[0].payload_id,
        ordered[1].payload_id,
        ordered[2].payload_id,
        ordered[3].payload_id,
    });
}

test "capacity refusal does not consume sequence" {
    var scheduler: Scheduler(1) = .{};
    try std.testing.expectEqual(@as(u64, 0), try scheduler.schedule(0, 0, .command, 0));
    try std.testing.expectError(error.CapacityExceeded, scheduler.schedule(1, 0, .command, 1));
    try std.testing.expectEqual(@as(u64, 1), scheduler.next_sequence);
}
