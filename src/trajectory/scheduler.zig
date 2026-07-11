//! Typed multi-agent task objects (hierarchical scheduler substrate).

const std = @import("std");

pub const TaskStatus = enum { pending, running, blocked, completed, failed, cancelled };

pub const ResourceBudget = struct {
    max_events: u32 = 256,
    max_wall_ms: u32 = 60_000,
    max_workers: u8 = 1,
};

pub const Task = struct {
    id: []const u8,
    objective: []const u8,
    dependencies: []const []const u8 = &.{},
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    verification: []const []const u8 = &.{},
    budget: ResourceBudget = .{},
    status: TaskStatus = .pending,

    pub fn validate(self: Task) !void {
        if (self.id.len == 0) return error.MissingTaskId;
        if (self.objective.len == 0) return error.MissingObjective;
        if (self.verification.len == 0) return error.MissingVerification;
        if (self.budget.max_workers == 0) return error.InvalidBudget;
    }
};

pub const Schedule = struct {
    tasks: []Task,
    len: usize = 0,

    pub fn init(buf: []Task) Schedule {
        return .{ .tasks = buf };
    }

    pub fn add(self: *Schedule, task: Task) !void {
        try task.validate();
        if (self.len == self.tasks.len) return error.CapacityExceeded;
        // Reject unknown dependencies.
        for (task.dependencies) |dep| {
            var found = false;
            for (self.tasks[0..self.len]) |t| {
                if (std.mem.eql(u8, t.id, dep)) {
                    found = true;
                    break;
                }
            }
            if (!found) return error.UnknownDependency;
        }
        self.tasks[self.len] = task;
        self.len += 1;
    }

    pub fn readyCount(self: *const Schedule) usize {
        var n: usize = 0;
        for (self.tasks[0..self.len]) |t| {
            if (t.status != .pending) continue;
            var ready = true;
            for (t.dependencies) |dep| {
                for (self.tasks[0..self.len]) |d| {
                    if (std.mem.eql(u8, d.id, dep) and d.status != .completed) {
                        ready = false;
                        break;
                    }
                }
            }
            if (ready) n += 1;
        }
        return n;
    }
};

test "schedule enforces dependencies" {
    var buf: [4]Task = undefined;
    var sched = Schedule.init(&buf);
    try sched.add(.{
        .id = "build",
        .objective = "compile",
        .verification = &.{"unit_tests"},
    });
    try std.testing.expectError(error.UnknownDependency, sched.add(.{
        .id = "test",
        .objective = "run tests",
        .dependencies = &.{"missing"},
        .verification = &.{"unit_tests"},
    }));
    try sched.add(.{
        .id = "test",
        .objective = "run tests",
        .dependencies = &.{"build"},
        .verification = &.{"unit_tests"},
    });
    try std.testing.expectEqual(@as(usize, 1), sched.readyCount());
    sched.tasks[0].status = .completed;
    try std.testing.expectEqual(@as(usize, 1), sched.readyCount());
}
