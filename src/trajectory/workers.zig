//! In-process worker fabric: labels, pools, shared vs single-use assignment.

const std = @import("std");

pub const WorkerKind = enum { shared, single_use };

pub const WorkerStatus = enum { idle, assigned, busy, drained, unhealthy };

pub const Worker = struct {
    id: []const u8,
    labels: []const []const u8,
    kind: WorkerKind,
    status: WorkerStatus = .idle,
    pool: []const u8,
    assignments: u32 = 0,
};

pub const Assignment = struct {
    worker_id: []const u8,
    task_id: []const u8,
    pool: []const u8,
};

pub const Fabric = struct {
    workers: []Worker,
    len: usize = 0,

    pub fn init(buf: []Worker) Fabric {
        return .{ .workers = buf };
    }

    pub fn register(self: *Fabric, worker: Worker) !void {
        if (worker.id.len == 0) return error.MissingWorkerId;
        if (self.len == self.workers.len) return error.CapacityExceeded;
        for (self.workers[0..self.len]) |w| {
            if (std.mem.eql(u8, w.id, worker.id)) return error.DuplicateWorker;
        }
        self.workers[self.len] = worker;
        self.len += 1;
    }

    fn hasLabel(worker: Worker, label: []const u8) bool {
        for (worker.labels) |l| if (std.mem.eql(u8, l, label)) return true;
        return false;
    }

    pub fn assign(self: *Fabric, task_id: []const u8, pool: []const u8, required_label: []const u8) !Assignment {
        for (self.workers[0..self.len]) |*w| {
            if (!std.mem.eql(u8, w.pool, pool)) continue;
            if (w.status != .idle) continue;
            if (!hasLabel(w.*, required_label)) continue;
            w.status = .assigned;
            w.assignments += 1;
            if (w.kind == .single_use) w.status = .drained;
            return .{ .worker_id = w.id, .task_id = task_id, .pool = pool };
        }
        return error.NoWorkerAvailable;
    }

    pub fn release(self: *Fabric, worker_id: []const u8) !void {
        for (self.workers[0..self.len]) |*w| {
            if (!std.mem.eql(u8, w.id, worker_id)) continue;
            if (w.kind == .single_use) {
                w.status = .drained;
                return;
            }
            w.status = .idle;
            return;
        }
        return error.UnknownWorker;
    }

    pub fn idleCount(self: *const Fabric, pool: []const u8) usize {
        var n: usize = 0;
        for (self.workers[0..self.len]) |w| {
            if (std.mem.eql(u8, w.pool, pool) and w.status == .idle) n += 1;
        }
        return n;
    }
};

pub fn selftest() !void {
    var buf: [4]Worker = undefined;
    var fabric = Fabric.init(&buf);
    try fabric.register(.{
        .id = "w-shared-1",
        .labels = &.{ "uas", "validation" },
        .kind = .shared,
        .pool = "reference-uas",
    });
    try fabric.register(.{
        .id = "w-once-1",
        .labels = &.{"hil"},
        .kind = .single_use,
        .pool = "reference-uas",
    });
    const a1 = try fabric.assign("task-validate", "reference-uas", "validation");
    if (!std.mem.eql(u8, a1.worker_id, "w-shared-1")) return error.WrongWorker;
    try fabric.release(a1.worker_id);
    if (fabric.idleCount("reference-uas") != 2) return error.ReleaseFailed;
    const a2 = try fabric.assign("task-hil", "reference-uas", "hil");
    if (!std.mem.eql(u8, a2.worker_id, "w-once-1")) return error.WrongHilWorker;
    const again = fabric.assign("task-hil-2", "reference-uas", "hil");
    if (again) |_| return error.SingleUseNotDrained else |err| {
        if (err != error.NoWorkerAvailable) return err;
    }
}

test "worker fabric shared and single-use" {
    try selftest();
}
