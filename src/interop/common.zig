//! Typed invariants shared by every external interoperability boundary.
const std = @import("std");

pub const InteropError = error{
    MalformedMessage,
    InvalidVersionRange,
    VersionMismatch,
    MissingCapability,
    UnitMismatch,
    FrameMismatch,
    TimeReferenceMismatch,
    InvalidTimestamp,
    InvalidProvenance,
    InvalidTimeout,
    QueueFull,
    QueueEmpty,
    Backpressure,
    AdapterUnavailable,
    InvalidConnectionTransition,
};

pub const Version = struct {
    major: u16,
    minor: u16,
    patch: u16,

    pub fn order(a: Version, b: Version) std.math.Order {
        if (a.major != b.major) return std.math.order(a.major, b.major);
        if (a.minor != b.minor) return std.math.order(a.minor, b.minor);
        return std.math.order(a.patch, b.patch);
    }
};

pub const VersionRange = struct {
    minimum: Version,
    maximum: Version,

    pub fn validate(self: VersionRange) InteropError!void {
        if (self.minimum.order(self.maximum) == .gt) return error.InvalidVersionRange;
    }
};

/// Strict negotiation permits one major version and chooses the newest common
/// version. A peer cannot silently downgrade across an incompatible major.
pub fn negotiateVersion(local: VersionRange, remote: VersionRange) InteropError!Version {
    try local.validate();
    try remote.validate();
    if (local.minimum.major != local.maximum.major or
        remote.minimum.major != remote.maximum.major or
        local.minimum.major != remote.minimum.major)
        return error.VersionMismatch;

    const lower = if (local.minimum.order(remote.minimum) == .gt) local.minimum else remote.minimum;
    const upper = if (local.maximum.order(remote.maximum) == .lt) local.maximum else remote.maximum;
    if (lower.order(upper) == .gt) return error.VersionMismatch;
    return upper;
}

pub const Capability = enum(u6) {
    state_read,
    state_write,
    step,
    rollback,
    clock_activation,
    events,
    telemetry,
    commands,
    geometry,
    mesh,
    weather,
    airspace,
    provenance,
    reconnect,
};

pub const CapabilitySet = struct {
    bits: u64 = 0,

    pub fn of(values: []const Capability) CapabilitySet {
        var result = CapabilitySet{};
        for (values) |value| result.insert(value);
        return result;
    }

    pub fn insert(self: *CapabilitySet, value: Capability) void {
        self.bits |= @as(u64, 1) << @intFromEnum(value);
    }

    pub fn containsAll(self: CapabilitySet, required: CapabilitySet) bool {
        return self.bits & required.bits == required.bits;
    }
};

pub const UnitSystem = enum { si };
pub const AngleUnit = enum { radians, degrees };
pub const LengthUnit = enum { meters, feet };
pub const SpeedUnit = enum { meters_per_second, knots };
pub const TemperatureUnit = enum { kelvin, celsius };

pub const UnitContract = struct {
    system: UnitSystem = .si,
    angle: AngleUnit = .radians,
    length: LengthUnit = .meters,
    speed: SpeedUnit = .meters_per_second,
    temperature: TemperatureUnit = .kelvin,

    pub fn eql(a: UnitContract, b: UnitContract) bool {
        return std.meta.eql(a, b);
    }
};

pub const SpatialFrame = enum {
    wgs84_geodetic,
    ecef,
    ned,
    enu,
    body_frd,
    body_flu,
    wind,
    stability,
    sensor,
    world_unreal,
    stage_usd,
};

pub const TimeReference = enum {
    simulation_monotonic,
    utc,
    tai,
    gps,
    hla_logical,
};

pub const Timestamp = struct {
    nanoseconds: i64,
    reference: TimeReference,

    pub fn init(nanoseconds: i64, reference: TimeReference) InteropError!Timestamp {
        if (reference == .simulation_monotonic and nanoseconds < 0)
            return error.InvalidTimestamp;
        return .{ .nanoseconds = nanoseconds, .reference = reference };
    }

    pub fn compare(a: Timestamp, b: Timestamp) InteropError!std.math.Order {
        if (a.reference != b.reference) return error.TimeReferenceMismatch;
        return std.math.order(a.nanoseconds, b.nanoseconds);
    }
};

pub const Provenance = struct {
    source: []const u8,
    artifact_digest: [32]u8,
    sequence: u64,

    pub fn validate(self: Provenance) InteropError!void {
        if (self.source.len == 0) return error.InvalidProvenance;
        var any_nonzero = false;
        for (self.artifact_digest) |byte| any_nonzero = any_nonzero or byte != 0;
        if (!any_nonzero) return error.InvalidProvenance;
    }
};

pub const TimeoutPolicy = struct {
    handshake_ns: u64,
    operation_ns: u64,
    heartbeat_ns: u64,

    pub fn validate(self: TimeoutPolicy) InteropError!void {
        if (self.handshake_ns == 0 or self.operation_ns == 0 or self.heartbeat_ns == 0)
            return error.InvalidTimeout;
    }
};

pub const Handshake = struct {
    protocol: []const u8,
    versions: VersionRange,
    supported: CapabilitySet,
    required: CapabilitySet,
    units: UnitContract,
    frame: SpatialFrame,
    time_reference: TimeReference,
};

pub const hello_wire_size = 16;
pub const WireHello = struct {
    version: Version,
    capabilities: CapabilitySet,
    units: UnitContract,
    frame: SpatialFrame,
    time_reference: TimeReference,

    pub fn encode(self: WireHello) InteropError![hello_wire_size]u8 {
        if (self.capabilities.bits > std.math.maxInt(u16)) return error.MalformedMessage;
        if (!self.units.eql(.{})) return error.UnitMismatch;
        return .{
            'S',                               'T',                                'I',                           'P',
            1,                                 @truncate(self.version.major >> 8), @truncate(self.version.major), @truncate(self.version.minor >> 8),
            @truncate(self.version.minor),     @truncate(self.version.patch >> 8), @truncate(self.version.patch), @truncate(self.capabilities.bits >> 8),
            @truncate(self.capabilities.bits), 0,                                  @intFromEnum(self.frame),      @intFromEnum(self.time_reference),
        };
    }

    pub fn decode(bytes: []const u8) InteropError!WireHello {
        if (bytes.len != hello_wire_size or !std.mem.eql(u8, bytes[0..4], "STIP"))
            return error.MalformedMessage;
        if (bytes[4] != 1 or bytes[13] != 0) return error.MalformedMessage;
        const frame = std.enums.fromInt(SpatialFrame, bytes[14]) orelse
            return error.MalformedMessage;
        const time_reference = std.enums.fromInt(TimeReference, bytes[15]) orelse
            return error.MalformedMessage;
        const version = Version{
            .major = readU16(bytes[5..7]),
            .minor = readU16(bytes[7..9]),
            .patch = readU16(bytes[9..11]),
        };
        if (version.major == 0) return error.MalformedMessage;
        return .{
            .version = version,
            .capabilities = .{ .bits = readU16(bytes[11..13]) },
            .units = .{},
            .frame = frame,
            .time_reference = time_reference,
        };
    }
};

fn readU16(bytes: *const [2]u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

pub const Negotiated = struct {
    version: Version,
    capabilities: CapabilitySet,
    units: UnitContract,
    frame: SpatialFrame,
    time_reference: TimeReference,
};

pub fn negotiate(local: Handshake, remote: Handshake) InteropError!Negotiated {
    if (local.protocol.len == 0 or !std.mem.eql(u8, local.protocol, remote.protocol))
        return error.MalformedMessage;
    const version = try negotiateVersion(local.versions, remote.versions);
    if (!remote.supported.containsAll(local.required) or
        !local.supported.containsAll(remote.required))
        return error.MissingCapability;
    if (!local.units.eql(remote.units)) return error.UnitMismatch;
    if (local.frame != remote.frame) return error.FrameMismatch;
    if (local.time_reference != remote.time_reference) return error.TimeReferenceMismatch;
    return .{
        .version = version,
        .capabilities = .{ .bits = local.supported.bits & remote.supported.bits },
        .units = local.units,
        .frame = local.frame,
        .time_reference = local.time_reference,
    };
}

pub const ConnectionState = enum {
    disconnected,
    connecting,
    handshaking,
    connected,
    backpressured,
    reconnect_wait,
    closed,
};

pub const Connection = struct {
    state: ConnectionState = .disconnected,
    reconnect_attempts: u16 = 0,

    pub fn transition(self: *Connection, next: ConnectionState) InteropError!void {
        const allowed = switch (self.state) {
            .disconnected => next == .connecting or next == .closed,
            .connecting => next == .handshaking or next == .reconnect_wait or next == .closed,
            .handshaking => next == .connected or next == .reconnect_wait or next == .closed,
            .connected => next == .backpressured or next == .reconnect_wait or next == .closed,
            .backpressured => next == .connected or next == .reconnect_wait or next == .closed,
            .reconnect_wait => next == .connecting or next == .closed,
            .closed => false,
        };
        if (!allowed) return error.InvalidConnectionTransition;
        if (next == .reconnect_wait) {
            self.reconnect_attempts = std.math.add(u16, self.reconnect_attempts, 1) catch
                std.math.maxInt(u16);
        }
        self.state = next;
    }
};

pub fn BoundedQueue(comptime T: type, comptime capacity: usize) type {
    if (capacity == 0) @compileError("bounded queue capacity must be non-zero");
    return struct {
        storage: [capacity]T = undefined,
        head: usize = 0,
        len: usize = 0,

        const Self = @This();

        pub fn push(self: *Self, value: T) InteropError!void {
            if (self.len == capacity) return error.QueueFull;
            self.storage[(self.head + self.len) % capacity] = value;
            self.len += 1;
        }

        pub fn pushOrBackpressure(self: *Self, value: T) InteropError!void {
            self.push(value) catch |err| switch (err) {
                error.QueueFull => return error.Backpressure,
                else => return err,
            };
        }

        pub fn pop(self: *Self) InteropError!T {
            if (self.len == 0) return error.QueueEmpty;
            const value = self.storage[self.head];
            self.head = (self.head + 1) % capacity;
            self.len -= 1;
            return value;
        }

        pub fn remaining(self: Self) usize {
            return capacity - self.len;
        }
    };
}

test "strict negotiation rejects versions, units, frames, and time mismatches" {
    const capabilities = CapabilitySet.of(&.{ .state_read, .step });
    const base = Handshake{
        .protocol = "strip-interop",
        .versions = .{
            .minimum = .{ .major = 1, .minor = 0, .patch = 0 },
            .maximum = .{ .major = 1, .minor = 2, .patch = 0 },
        },
        .supported = capabilities,
        .required = CapabilitySet.of(&.{.state_read}),
        .units = .{},
        .frame = .ned,
        .time_reference = .simulation_monotonic,
    };
    var peer = base;
    peer.versions.minimum.major = 2;
    peer.versions.maximum.major = 2;
    try std.testing.expectError(error.VersionMismatch, negotiate(base, peer));
    peer = base;
    peer.units.length = .feet;
    try std.testing.expectError(error.UnitMismatch, negotiate(base, peer));
    peer = base;
    peer.frame = .enu;
    try std.testing.expectError(error.FrameMismatch, negotiate(base, peer));
    peer = base;
    peer.time_reference = .utc;
    try std.testing.expectError(error.TimeReferenceMismatch, negotiate(base, peer));
}

test "wire hello round trips and rejects malformed input" {
    const hello = WireHello{
        .version = .{ .major = 1, .minor = 2, .patch = 3 },
        .capabilities = CapabilitySet.of(&.{ .step, .provenance }),
        .units = .{},
        .frame = .ned,
        .time_reference = .simulation_monotonic,
    };
    const encoded = try hello.encode();
    const decoded = try WireHello.decode(&encoded);
    try std.testing.expectEqual(hello.version, decoded.version);
    try std.testing.expectEqual(hello.capabilities.bits, decoded.capabilities.bits);
    try std.testing.expectError(
        error.MalformedMessage,
        WireHello.decode("not-a-valid-handshake"),
    );
}

test "timestamps cannot compare unlike references" {
    const simulation = try Timestamp.init(42, .simulation_monotonic);
    const utc = try Timestamp.init(42, .utc);
    try std.testing.expectError(error.TimeReferenceMismatch, simulation.compare(utc));
    try std.testing.expectError(
        error.InvalidTimestamp,
        Timestamp.init(-1, .simulation_monotonic),
    );
}

test "bounded queue reports overflow and preserves FIFO across wrap" {
    var queue = BoundedQueue(u8, 2){};
    try queue.push(1);
    try queue.push(2);
    try std.testing.expectError(error.QueueFull, queue.push(3));
    try std.testing.expectError(error.Backpressure, queue.pushOrBackpressure(3));
    try std.testing.expectEqual(@as(u8, 1), try queue.pop());
    try queue.push(3);
    try std.testing.expectEqual(@as(u8, 2), try queue.pop());
    try std.testing.expectEqual(@as(u8, 3), try queue.pop());
    try std.testing.expectError(error.QueueEmpty, queue.pop());
}

test "connection state tracks reconnect and rejects invalid recovery" {
    var connection = Connection{};
    try connection.transition(.connecting);
    try connection.transition(.reconnect_wait);
    try std.testing.expectEqual(@as(u16, 1), connection.reconnect_attempts);
    try connection.transition(.connecting);
    try connection.transition(.handshaking);
    try connection.transition(.connected);
    try std.testing.expectError(
        error.InvalidConnectionTransition,
        connection.transition(.disconnected),
    );
}
