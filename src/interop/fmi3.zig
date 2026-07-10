//! FMI 3.0 lifecycle and Scheduled Execution clock primitives.
const std = @import("std");
const common = @import("common.zig");

pub const InterfaceKind = enum {
    model_exchange,
    co_simulation,
    scheduled_execution,
};

pub const State = enum {
    instantiated,
    initialization_mode,
    event_mode,
    continuous_time_mode,
    step_mode,
    clock_activation_mode,
    terminated,
    errored,
};

pub const FmiError = error{
    InvalidStateTransition,
    WrongInterfaceKind,
    InvalidStep,
    TimeWentBackwards,
    ClockNotActive,
    InvalidPartition,
    SequenceExhausted,
};

pub const ClockActivation = struct {
    clock_reference: u32,
    model_partition: u32,
    activation_time: common.Timestamp,
    sequence: u64,

    pub fn lessThan(_: void, a: ClockActivation, b: ClockActivation) bool {
        if (a.activation_time.nanoseconds != b.activation_time.nanoseconds)
            return a.activation_time.nanoseconds < b.activation_time.nanoseconds;
        if (a.clock_reference != b.clock_reference)
            return a.clock_reference < b.clock_reference;
        return a.sequence < b.sequence;
    }
};

pub const Instance = struct {
    kind: InterfaceKind,
    state: State = .instantiated,
    logical_time_ns: i64 = 0,
    next_activation_sequence: u64 = 0,

    pub fn enterInitializationMode(self: *Instance) FmiError!void {
        try self.requireState(.instantiated);
        self.state = .initialization_mode;
    }

    pub fn exitInitializationMode(self: *Instance) FmiError!void {
        try self.requireState(.initialization_mode);
        self.state = switch (self.kind) {
            .model_exchange, .co_simulation => .event_mode,
            .scheduled_execution => .clock_activation_mode,
        };
    }

    pub fn enterContinuousTimeMode(self: *Instance) FmiError!void {
        if (self.kind != .model_exchange) return error.WrongInterfaceKind;
        try self.requireState(.event_mode);
        self.state = .continuous_time_mode;
    }

    pub fn enterEventMode(self: *Instance) FmiError!void {
        switch (self.kind) {
            .model_exchange => try self.requireState(.continuous_time_mode),
            .co_simulation => try self.requireState(.step_mode),
            .scheduled_execution => return error.WrongInterfaceKind,
        }
        self.state = .event_mode;
    }

    pub fn enterStepMode(self: *Instance) FmiError!void {
        if (self.kind != .co_simulation) return error.WrongInterfaceKind;
        try self.requireState(.event_mode);
        self.state = .step_mode;
    }

    pub fn completeIntegratorStep(self: *Instance, next_time_ns: i64) FmiError!void {
        if (self.kind != .model_exchange) return error.WrongInterfaceKind;
        try self.requireState(.continuous_time_mode);
        try self.advanceTime(next_time_ns);
    }

    pub fn doStep(self: *Instance, step_ns: u64) FmiError!void {
        if (self.kind != .co_simulation) return error.WrongInterfaceKind;
        try self.requireState(.step_mode);
        if (step_ns == 0 or step_ns > @as(u64, @intCast(std.math.maxInt(i64))))
            return error.InvalidStep;
        const next = std.math.add(i64, self.logical_time_ns, @intCast(step_ns)) catch
            return error.InvalidStep;
        try self.advanceTime(next);
    }

    pub fn activateModelPartition(
        self: *Instance,
        clock_reference: u32,
        model_partition: u32,
        activation_time_ns: i64,
    ) FmiError!ClockActivation {
        if (self.kind != .scheduled_execution) return error.WrongInterfaceKind;
        try self.requireState(.clock_activation_mode);
        if (clock_reference == 0) return error.ClockNotActive;
        if (model_partition == 0) return error.InvalidPartition;
        try self.advanceTime(activation_time_ns);
        if (self.next_activation_sequence == std.math.maxInt(u64))
            return error.SequenceExhausted;
        const activation = ClockActivation{
            .clock_reference = clock_reference,
            .model_partition = model_partition,
            .activation_time = .{
                .nanoseconds = activation_time_ns,
                .reference = .simulation_monotonic,
            },
            .sequence = self.next_activation_sequence,
        };
        self.next_activation_sequence += 1;
        return activation;
    }

    pub fn terminate(self: *Instance) FmiError!void {
        if (self.state == .terminated or self.state == .errored)
            return error.InvalidStateTransition;
        self.state = .terminated;
    }

    pub fn fail(self: *Instance) void {
        self.state = .errored;
    }

    fn requireState(self: Instance, expected: State) FmiError!void {
        if (self.state != expected) return error.InvalidStateTransition;
    }

    fn advanceTime(self: *Instance, next_time_ns: i64) FmiError!void {
        if (next_time_ns < self.logical_time_ns) return error.TimeWentBackwards;
        self.logical_time_ns = next_time_ns;
    }
};

test "model exchange follows initialization event and continuous modes" {
    var instance = Instance{ .kind = .model_exchange };
    try std.testing.expectError(error.InvalidStateTransition, instance.enterContinuousTimeMode());
    try instance.enterInitializationMode();
    try instance.exitInitializationMode();
    try std.testing.expectEqual(State.event_mode, instance.state);
    try instance.enterContinuousTimeMode();
    try instance.completeIntegratorStep(10);
    try std.testing.expectError(error.TimeWentBackwards, instance.completeIntegratorStep(9));
}

test "co-simulation step mode refuses zero step and wrong interface operations" {
    var instance = Instance{ .kind = .co_simulation };
    try instance.enterInitializationMode();
    try instance.exitInitializationMode();
    try instance.enterStepMode();
    try std.testing.expectError(error.InvalidStep, instance.doStep(0));
    try instance.doStep(20);
    try std.testing.expectEqual(@as(i64, 20), instance.logical_time_ns);
    try std.testing.expectError(
        error.WrongInterfaceKind,
        instance.completeIntegratorStep(21),
    );
}

test "scheduled execution activates ordered clocks" {
    var instance = Instance{ .kind = .scheduled_execution };
    try instance.enterInitializationMode();
    try instance.exitInitializationMode();
    const first = try instance.activateModelPartition(1, 7, 100);
    const second = try instance.activateModelPartition(1, 8, 100);
    try std.testing.expect(ClockActivation.lessThan({}, first, second));
    try std.testing.expectError(
        error.TimeWentBackwards,
        instance.activateModelPartition(1, 9, 99),
    );
    try std.testing.expectError(
        error.InvalidPartition,
        instance.activateModelPartition(1, 0, 100),
    );
}
