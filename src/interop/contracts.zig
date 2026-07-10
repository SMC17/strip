//! Typed adapter contracts. No external runtime is linked by this module.
const std = @import("std");
const common = @import("common.zig");
const fmi3 = @import("fmi3.zig");

pub const AdapterKind = enum {
    jsbsim,
    openvsp,
    su2,
    openfoam,
    fmi_3_model_exchange,
    fmi_3_co_simulation,
    fmi_3_scheduled_execution,
    mavlink,
    ros2_dds,
    hla,
    dis,
    project_airsim,
    unreal,
    openusd,
    weather,
    airspace,
    ulog,
    rosbag,
    csv,
};

pub const Availability = union(enum) {
    unavailable: []const u8,
    available: struct {
        implementation: []const u8,
        version: common.Version,
    },
};

pub const Descriptor = struct {
    kind: AdapterKind,
    availability: Availability,

    pub fn unavailable(kind: AdapterKind) Descriptor {
        return .{
            .kind = kind,
            .availability = .{ .unavailable = "external implementation not linked" },
        };
    }

    pub fn requireAvailable(self: Descriptor) common.InteropError!void {
        switch (self.availability) {
            .unavailable => return error.AdapterUnavailable,
            .available => {},
        }
    }
};

pub fn Contract(comptime Request: type, comptime Response: type) type {
    return struct {
        descriptor: Descriptor,
        context: ?*anyopaque = null,
        exchange_fn: ?*const fn (*anyopaque, Request) anyerror!Response = null,

        const Self = @This();

        pub fn exchange(self: Self, request: Request) !Response {
            try self.descriptor.requireAvailable();
            const function = self.exchange_fn orelse return error.AdapterUnavailable;
            const context = self.context orelse return error.AdapterUnavailable;
            return function(context, request);
        }
    };
}

pub const FlightState = struct {
    time: common.Timestamp,
    frame: common.SpatialFrame,
    units: common.UnitContract,
    position: [3]f64,
    velocity: [3]f64,
    attitude_quaternion_wxyz: [4]f64,
};

pub const ControlInputs = struct {
    throttle: f32,
    aileron: f32,
    elevator: f32,
    rudder: f32,
};

pub const Jsbsim = struct {
    contract: Contract(Request, Response) = .{
        .descriptor = Descriptor.unavailable(.jsbsim),
    },

    pub const Request = struct { dt_ns: u64, controls: ControlInputs };
    pub const Response = FlightState;
};

pub const OpenVsp = struct {
    contract: Contract(Request, Response) = .{
        .descriptor = Descriptor.unavailable(.openvsp),
    },

    pub const Request = struct {
        artifact: common.Provenance,
        tessellation_tolerance_m: f64,
    };
    pub const Response = struct {
        geometry_digest: [32]u8,
        component_count: u32,
    };
};

pub const CfdSolver = enum { su2, openfoam };
pub const Cfd = struct {
    solver: CfdSolver,
    contract: Contract(Request, Response),

    pub const Request = struct {
        mesh_digest: [32]u8,
        mach: f64,
        reynolds: f64,
        angle_of_attack_rad: f64,
    };
    pub const Response = struct {
        force_body_newtons: [3]f64,
        moment_body_newton_meters: [3]f64,
        converged: bool,
        iterations: u32,
    };

    pub fn unavailable(solver: CfdSolver) Cfd {
        return .{
            .solver = solver,
            .contract = .{ .descriptor = Descriptor.unavailable(
                if (solver == .su2) .su2 else .openfoam,
            ) },
        };
    }
};

pub const Fmi3 = struct {
    kind: fmi3.InterfaceKind,
    contract: Contract(Request, Response),

    pub const Request = union(enum) {
        read: struct { value_reference: u32 },
        write_float64: struct { value_reference: u32, value: f64 },
        do_step: struct { step_ns: u64 },
        activate_partition: struct {
            clock_reference: u32,
            model_partition: u32,
            activation_time_ns: i64,
        },
    };
    pub const Response = union(enum) {
        float64: f64,
        completed,
        activation: fmi3.ClockActivation,
    };

    pub fn unavailable(kind: fmi3.InterfaceKind) Fmi3 {
        return .{
            .kind = kind,
            .contract = .{ .descriptor = Descriptor.unavailable(switch (kind) {
                .model_exchange => .fmi_3_model_exchange,
                .co_simulation => .fmi_3_co_simulation,
                .scheduled_execution => .fmi_3_scheduled_execution,
            }) },
        };
    }
};

pub const Mavlink = struct {
    contract: Contract(Request, Response) = .{
        .descriptor = Descriptor.unavailable(.mavlink),
    },

    pub const Request = struct {
        channel: u8,
        bytes: []const u8,
        deadline: common.Timestamp,
    };
    pub const Response = struct { accepted_bytes: usize };
};

pub const Reliability = enum { best_effort, reliable };
pub const Durability = enum { volatile_data, transient_local };
pub const Ros2Dds = struct {
    contract: Contract(Request, Response) = .{
        .descriptor = Descriptor.unavailable(.ros2_dds),
    },

    pub const Qos = struct {
        reliability: Reliability,
        durability: Durability,
        history_depth: u32,
        deadline_ns: u64,
    };
    pub const Request = struct {
        topic: []const u8,
        type_name: []const u8,
        qos: Qos,
        payload: []const u8,
    };
    pub const Response = struct { publication_sequence: u64 };
};

pub const FederationProtocol = enum { hla, dis };
pub const Federation = struct {
    protocol: FederationProtocol,
    contract: Contract(Request, Response),

    pub const Request = struct {
        object_class: []const u8,
        logical_time_ns: i64,
        payload: []const u8,
    };
    pub const Response = struct { accepted_logical_time_ns: i64 };

    pub fn unavailable(protocol: FederationProtocol) Federation {
        return .{
            .protocol = protocol,
            .contract = .{ .descriptor = Descriptor.unavailable(
                if (protocol == .hla) .hla else .dis,
            ) },
        };
    }
};

pub const SceneRuntime = enum { project_airsim, unreal };
pub const SceneSimulation = struct {
    runtime: SceneRuntime,
    contract: Contract(Request, Response),

    pub const Request = struct {
        actor: []const u8,
        pose_frame: common.SpatialFrame,
        position_m: [3]f64,
        quaternion_wxyz: [4]f64,
    };
    pub const Response = struct { applied_at: common.Timestamp };

    pub fn unavailable(runtime: SceneRuntime) SceneSimulation {
        return .{
            .runtime = runtime,
            .contract = .{ .descriptor = Descriptor.unavailable(
                if (runtime == .project_airsim) .project_airsim else .unreal,
            ) },
        };
    }
};

pub const OpenUsd = struct {
    contract: Contract(Request, Response) = .{
        .descriptor = Descriptor.unavailable(.openusd),
    },

    pub const Request = struct {
        stage_identifier: []const u8,
        time_code: f64,
        meters_per_unit: f64,
        up_axis: enum { y, z },
    };
    pub const Response = struct { stage_digest: [32]u8 };
};

pub const PublicDataKind = enum { weather, airspace };
pub const PublicData = struct {
    kind: PublicDataKind,
    contract: Contract(Request, Response),

    pub const Request = struct {
        valid_at: common.Timestamp,
        latitude_rad: f64,
        longitude_rad: f64,
        radius_m: f64,
    };
    pub const Response = struct {
        payload: []const u8,
        provenance: common.Provenance,
    };

    pub fn unavailable(kind: PublicDataKind) PublicData {
        return .{
            .kind = kind,
            .contract = .{ .descriptor = Descriptor.unavailable(
                if (kind == .weather) .weather else .airspace,
            ) },
        };
    }
};

pub const LogFormat = enum { ulog, rosbag, csv };
pub const LogReader = struct {
    format: LogFormat,
    contract: Contract(Request, Response),

    pub const Request = struct {
        bytes: []const u8,
        expected_units: common.UnitContract,
        expected_frame: common.SpatialFrame,
    };
    pub const Response = struct {
        record_count: u64,
        first_timestamp: common.Timestamp,
        last_timestamp: common.Timestamp,
    };

    pub fn unavailable(format: LogFormat) LogReader {
        return .{
            .format = format,
            .contract = .{ .descriptor = Descriptor.unavailable(switch (format) {
                .ulog => .ulog,
                .rosbag => .rosbag,
                .csv => .csv,
            }) },
        };
    }
};

pub const default_catalog = [_]Descriptor{
    Descriptor.unavailable(.jsbsim),
    Descriptor.unavailable(.openvsp),
    Descriptor.unavailable(.su2),
    Descriptor.unavailable(.openfoam),
    Descriptor.unavailable(.fmi_3_model_exchange),
    Descriptor.unavailable(.fmi_3_co_simulation),
    Descriptor.unavailable(.fmi_3_scheduled_execution),
    Descriptor.unavailable(.mavlink),
    Descriptor.unavailable(.ros2_dds),
    Descriptor.unavailable(.hla),
    Descriptor.unavailable(.dis),
    Descriptor.unavailable(.project_airsim),
    Descriptor.unavailable(.unreal),
    Descriptor.unavailable(.openusd),
    Descriptor.unavailable(.weather),
    Descriptor.unavailable(.airspace),
    Descriptor.unavailable(.ulog),
    Descriptor.unavailable(.rosbag),
    Descriptor.unavailable(.csv),
};

test "all external implementations remain unavailable by default" {
    try std.testing.expectEqual(
        @as(usize, @typeInfo(AdapterKind).@"enum".fields.len),
        default_catalog.len,
    );
    for (default_catalog) |descriptor|
        try std.testing.expectError(error.AdapterUnavailable, descriptor.requireAvailable());
}
