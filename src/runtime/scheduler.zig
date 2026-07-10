//! Deterministic fixed-tick, multi-rate scheduling with bounded catch-up.
const std = @import("std");

pub const Task = struct {
    id: u16,
    period_ticks: u32,
    phase_ticks: u32 = 0,
    priority: i16 = 0,
    deadline_ns: u64,
    registration_order: u16 = 0,
};

pub const Dispatch = struct {
    tick: u64,
    task_id: u16,
    deadline_ns: u64,
};

pub const Profile = struct {
    invocations: u64 = 0,
    total_ns: u64 = 0,
    maximum_ns: u64 = 0,
    deadline_misses: u64 = 0,
};

pub const AdvanceEvidence = struct {
    ticks_executed: u32,
    catch_up_limited: bool,
    discarded_ns: u64,
    emitted: []const Dispatch,
};

pub fn Scheduler(comptime max_tasks: usize, comptime max_dispatches: usize) type {
    return struct {
        tick_ns: u64,
        max_catch_up_ticks: u32,
        authoritative_tick: u64 = 0,
        accumulator_ns: u64 = 0,
        tasks: [max_tasks]Task = undefined,
        profiles: [max_tasks]Profile = [_]Profile{.{}} ** max_tasks,
        task_count: usize = 0,
        dispatches: [max_dispatches]Dispatch = undefined,
        dispatch_count: usize = 0,

        const Self = @This();
        pub const Error = error{
            InvalidTick,
            InvalidRate,
            TaskCapacityExceeded,
            DuplicateTask,
            DispatchCapacityExceeded,
            UnknownTask,
            TimeOverflow,
        };

        pub fn init(tick_ns: u64, max_catch_up_ticks: u32) Error!Self {
            if (tick_ns == 0 or max_catch_up_ticks == 0) return error.InvalidTick;
            return .{ .tick_ns = tick_ns, .max_catch_up_ticks = max_catch_up_ticks };
        }

        pub fn register(self: *Self, task_value: Task) Error!void {
            if (task_value.period_ticks == 0 or task_value.phase_ticks >= task_value.period_ticks)
                return error.InvalidRate;
            for (self.tasks[0..self.task_count]) |task|
                if (task.id == task_value.id) return error.DuplicateTask;
            if (self.task_count == max_tasks) return error.TaskCapacityExceeded;
            var task = task_value;
            task.registration_order = @intCast(self.task_count);
            self.tasks[self.task_count] = task;
            self.task_count += 1;
            // Insertion sort makes ordering explicit: priority, then registration.
            var i = self.task_count - 1;
            while (i > 0 and taskBefore(self.tasks[i], self.tasks[i - 1])) : (i -= 1) {
                std.mem.swap(Task, &self.tasks[i], &self.tasks[i - 1]);
                std.mem.swap(Profile, &self.profiles[i], &self.profiles[i - 1]);
            }
        }

        pub fn advance(self: *Self, elapsed_ns: u64) Error!AdvanceEvidence {
            self.dispatch_count = 0;
            self.accumulator_ns = std.math.add(u64, self.accumulator_ns, elapsed_ns) catch
                return error.TimeOverflow;
            const available = self.accumulator_ns / self.tick_ns;
            const run_ticks: u32 = @intCast(@min(available, self.max_catch_up_ticks));
            const limited = available > self.max_catch_up_ticks;
            var discarded: u64 = 0;

            for (0..run_ticks) |_| {
                self.authoritative_tick = std.math.add(u64, self.authoritative_tick, 1) catch
                    return error.TimeOverflow;
                for (self.tasks[0..self.task_count]) |task| {
                    if ((self.authoritative_tick % task.period_ticks) != task.phase_ticks) continue;
                    if (self.dispatch_count == max_dispatches) return error.DispatchCapacityExceeded;
                    self.dispatches[self.dispatch_count] = .{
                        .tick = self.authoritative_tick,
                        .task_id = task.id,
                        .deadline_ns = task.deadline_ns,
                    };
                    self.dispatch_count += 1;
                }
            }
            self.accumulator_ns -= @as(u64, run_ticks) * self.tick_ns;
            if (limited) {
                // Retain only the sub-tick remainder; stale wall time cannot
                // produce an unbounded catch-up spiral on the next call.
                discarded = self.accumulator_ns - (self.accumulator_ns % self.tick_ns);
                self.accumulator_ns %= self.tick_ns;
            }
            return .{
                .ticks_executed = run_ticks,
                .catch_up_limited = limited,
                .discarded_ns = discarded,
                .emitted = self.dispatches[0..self.dispatch_count],
            };
        }

        pub fn recordDuration(self: *Self, task_id: u16, duration_ns: u64) Error!void {
            for (self.tasks[0..self.task_count], 0..) |task, i| {
                if (task.id != task_id) continue;
                const total = std.math.add(u64, self.profiles[i].total_ns, duration_ns) catch
                    return error.TimeOverflow;
                self.profiles[i].invocations += 1;
                self.profiles[i].total_ns = total;
                self.profiles[i].maximum_ns = @max(self.profiles[i].maximum_ns, duration_ns);
                if (duration_ns > task.deadline_ns) self.profiles[i].deadline_misses += 1;
                return;
            }
            return error.UnknownTask;
        }

        pub fn profile(self: *const Self, task_id: u16) ?Profile {
            for (self.tasks[0..self.task_count], 0..) |task, i|
                if (task.id == task_id) return self.profiles[i];
            return null;
        }

        fn taskBefore(a: Task, b: Task) bool {
            if (a.priority != b.priority) return a.priority < b.priority;
            return a.registration_order < b.registration_order;
        }
    };
}

test "multi-rate ordering and bounded catch-up are deterministic" {
    var scheduler = try Scheduler(4, 16).init(10, 2);
    try scheduler.register(.{ .id = 1, .period_ticks = 1, .priority = 2, .deadline_ns = 5 });
    try scheduler.register(.{ .id = 2, .period_ticks = 2, .priority = 1, .deadline_ns = 5 });
    const first = try scheduler.advance(20);
    try std.testing.expectEqual(@as(usize, 3), first.emitted.len);
    try std.testing.expectEqual(@as(u16, 1), first.emitted[0].task_id);
    try std.testing.expectEqual(@as(u16, 2), first.emitted[1].task_id);
    try std.testing.expectEqual(@as(u16, 1), first.emitted[2].task_id);

    const limited = try scheduler.advance(51);
    try std.testing.expect(limited.catch_up_limited);
    try std.testing.expectEqual(@as(u32, 2), limited.ticks_executed);
    try std.testing.expectEqual(@as(u64, 30), limited.discarded_ns);
    try scheduler.recordDuration(1, 8);
    try std.testing.expectEqual(@as(u64, 1), scheduler.profile(1).?.deadline_misses);
}
