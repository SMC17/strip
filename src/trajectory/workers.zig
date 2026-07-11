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

/// Persist assignment ledger as JSONL (durable fabric log, not a cluster).
pub fn appendAssignmentLog(io: std.Io, path: []const u8, assignment: Assignment) !void {
    var line_buf: [256]u8 = undefined;
    const line = try std.fmt.bufPrint(
        &line_buf,
        "{{\"worker_id\":\"{s}\",\"task_id\":\"{s}\",\"pool\":\"{s}\"}}\n",
        .{ assignment.worker_id, assignment.task_id, assignment.pool },
    );
    // Append-only: read existing + write combined (Zig 0.16 cwd writeFile replaces).
    var existing: []u8 = &.{};
    defer if (existing.len != 0) std.heap.page_allocator.free(existing);
    if (std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .limited(64 * 1024))) |bytes| {
        existing = bytes;
    } else |_| {}
    const combined = try std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}", .{ existing, line });
    defer std.heap.page_allocator.free(combined);
    try std.Io.Dir.cwd().createDirPath(io, "trajectory.evidence");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = combined });
}

pub fn countLogLines(io: std.Io, path: []const u8) !usize {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .limited(64 * 1024)) catch return 0;
    defer std.heap.page_allocator.free(bytes);
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r").len > 0) n += 1;
    }
    return n;
}

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

pub fn selftestPersist(io: std.Io) !void {
    try selftest();
    const path = "trajectory.evidence/worker-assignments.jsonl";
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
    const a: Assignment = .{ .worker_id = "w-shared-1", .task_id = "t1", .pool = "reference-uas" };
    try appendAssignmentLog(io, path, a);
    try appendAssignmentLog(io, path, .{ .worker_id = "w-once-1", .task_id = "t2", .pool = "reference-uas" });
    const n = try countLogLines(io, path);
    if (n != 2) return error.PersistLogCount;
}

test "worker fabric shared and single-use" {
    try selftest();
}

test "worker assignment log persists" {
    try selftestPersist(std.testing.io);
}
