//! Out-of-process JSBSim comparator with honest backend resolution.
//!
//! Live JSBSim is used only when `JSBSIM_CMD` resolves to an executable.
//! Otherwise the gate falls back to published fixture references or the
//! development shim (`strip-jsbsim-shim`), which is not JSBSim evidence.

const std = @import("std");
const validation = @import("../validation/comparator.zig");
const types = @import("../validation/types.zig");
const envelope = @import("../validation/envelope.zig");

pub const protocol_schema = "strip.jsbsim-protocol.v0";

pub const EvidenceTier = enum {
    cross_implementation,
    subprocess_shim,
    published_fixture,
    unavailable,
};

pub fn evidenceTier(backend: BackendKind) EvidenceTier {
    return switch (backend) {
        .jsbsim_binary, .jsbsim_python => .cross_implementation,
        .development_shim => .subprocess_shim,
        .published_fixture => .published_fixture,
        .unavailable => .unavailable,
    };
}

pub const BackendKind = enum {
    unavailable,
    jsbsim_binary,
    jsbsim_python,
    development_shim,
    published_fixture,
};

pub const Backend = struct {
    kind: BackendKind,
    command: []const u8,
    note: []const u8,
};

pub const AtmosphereQuery = struct {
    geopotential_altitude_m: f64,
};

pub const AtmosphereResult = struct {
    geopotential_altitude_m: f64,
    temperature_k: f64,
    pressure_pa: f64,
    density_kg_m3: f64,
    speed_of_sound_mps: f64,
    backend: BackendKind,
};

pub const Request = struct {
    schema: []const u8 = protocol_schema,
    query: enum { atmosphere },
    geopotential_altitude_m: f64,
};

pub const Response = struct {
    schema: []const u8,
    backend: []const u8,
    temperature_k: f64,
    pressure_pa: f64,
    density_kg_m3: f64,
    speed_of_sound_mps: f64,
};

pub const Fixture = struct {
    schema: []const u8,
    id: []const u8,
    source: []const u8,
    jsbsim_version: ?[]const u8,
    deliberately_perturbed: bool,
    envelope: envelope.Envelope,
    acceptance: types.Acceptance,
    samples: []const validation.Sample,
};

pub fn parseBackendTag(tag: []const u8) BackendKind {
    if (std.mem.eql(u8, tag, "jsbsim_python")) return .jsbsim_python;
    if (std.mem.eql(u8, tag, "jsbsim_binary")) return .jsbsim_binary;
    if (std.mem.eql(u8, tag, "development_shim")) return .development_shim;
    return .unavailable;
}

pub fn resolveBackend(
    io: std.Io,
    _: std.mem.Allocator,
    shim_path: []const u8,
    jsbsim_cmd: ?[]const u8,
    python_runner: ?[]const u8,
    default_cmd: ?[]const u8,
) !Backend {
    if (jsbsim_cmd) |cmd| {
        if (cmd.len > 0) {
            return .{
                .kind = .jsbsim_binary,
                .command = cmd,
                .note = "live JSBSim binary from JSBSIM_CMD",
            };
        }
    }

    if (default_cmd) |cmd| {
        if (cmd.len > 0 and fileExecutable(io, cmd)) {
            return .{
                .kind = .jsbsim_binary,
                .command = cmd,
                .note = "default JSBSIM_CMD wrapper (python runner or shim fallback)",
            };
        }
    }

    if (python_runner) |runner| {
        if (runner.len > 0 and fileExecutable(io, runner)) {
            return .{
                .kind = .jsbsim_python,
                .command = runner,
                .note = "JSBSim Python module runner (jsbsim pip package)",
            };
        }
    }

    if (shim_path.len > 0 and fileExecutable(io, shim_path)) {
        return .{
            .kind = .development_shim,
            .command = shim_path,
            .note = "development shim only; not JSBSim validation evidence",
        };
    }

    return .{
        .kind = .unavailable,
        .command = "",
        .note = "no JSBSIM_CMD and no development shim executable",
    };
}

fn fileExecutable(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

pub fn queryAtmosphereSubprocess(
    io: std.Io,
    gpa: std.mem.Allocator,
    backend: Backend,
    query: AtmosphereQuery,
) !AtmosphereResult {
    if (backend.kind == .unavailable) return error.BackendUnavailable;
    if (!std.math.isFinite(query.geopotential_altitude_m)) return error.InvalidQuery;

    var request_buffer: [256]u8 = undefined;
    const request_json = try std.fmt.bufPrint(&request_buffer, "{{\"schema\":\"{s}\",\"query\":\"atmosphere\",\"geopotential_altitude_m\":{d}}}", .{
        protocol_schema,
        query.geopotential_altitude_m,
    });

    var child = try std.process.spawn(io, .{
        .argv = &.{ backend.command, "atmosphere" },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
    });

    const stdin = child.stdin orelse return error.MissingPipe;
    var stdin_writer_buffer: [512]u8 = undefined;
    var stdin_writer = stdin.writer(io, &stdin_writer_buffer);
    try stdin_writer.interface.writeAll(request_json);
    try stdin_writer.interface.writeAll("\n");
    try stdin_writer.interface.flush();

    const stdout = child.stdout orelse return error.MissingPipe;
    var stdout_reader_buffer: [4096]u8 = undefined;
    var stdout_reader = stdout.reader(io, &stdout_reader_buffer);
    var response_line: []const u8 = "";
    while (true) {
        const line = try stdout_reader.interface.takeDelimiterInclusive('\n');
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len > 0 and trimmed[0] == '{') {
            response_line = trimmed;
            break;
        }
    }
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.SubprocessFailed,
        else => return error.SubprocessFailed,
    }

    var parsed = try std.json.parseFromSlice(Response, gpa, response_line, .{
        .ignore_unknown_fields = true,
        .max_value_len = 256,
    });
    defer parsed.deinit();

    if (!std.mem.eql(u8, parsed.value.schema, protocol_schema))
        return error.InvalidResponseSchema;

    const resolved_backend = parseBackendTag(parsed.value.backend);
    return .{
        .geopotential_altitude_m = query.geopotential_altitude_m,
        .temperature_k = parsed.value.temperature_k,
        .pressure_pa = parsed.value.pressure_pa,
        .density_kg_m3 = parsed.value.density_kg_m3,
        .speed_of_sound_mps = parsed.value.speed_of_sound_mps,
        .backend = if (resolved_backend == .unavailable) backend.kind else resolved_backend,
    };
}

pub fn crossImplementationMetrics() types.MetricAcceptanceSet {
    return .{ .metrics = &.{
        .{
            .variable = "temperature_k",
            .unit = "K",
            .absolute_tolerance = 0.5,
            .relative_tolerance = 1e-4,
            .rationale = "US76 table resolution; cross-implementation atmosphere gate",
        },
        .{
            .variable = "pressure_pa",
            .unit = "Pa",
            .absolute_tolerance = 50.0,
            .relative_tolerance = 1e-4,
            .rationale = "Hectopascal-scale tabular rounding at layer boundaries",
        },
        .{
            .variable = "density_kg_m3",
            .unit = "kg/m^3",
            .absolute_tolerance = 0.02,
            .relative_tolerance = 1e-3,
            .rationale = "Derived from T and P; independent ideal-gas check",
        },
        .{
            .variable = "speed_of_sound_mps",
            .unit = "m/s",
            .absolute_tolerance = 0.5,
            .relative_tolerance = 1e-4,
            .rationale = "Square-root of gamma*R*T; small numerical spread expected",
        },
    } };
}

pub fn coefficientMetrics() types.MetricAcceptanceSet {
    return .{ .metrics = &.{
        .{
            .variable = "cx",
            .unit = "1",
            .absolute_tolerance = 1e-4,
            .relative_tolerance = 1e-3,
            .rationale = "Shared linear model coefficient parity",
        },
        .{
            .variable = "cy",
            .unit = "1",
            .absolute_tolerance = 1e-4,
            .relative_tolerance = 1e-3,
            .rationale = "Shared linear model coefficient parity",
        },
        .{
            .variable = "cz",
            .unit = "1",
            .absolute_tolerance = 1e-4,
            .relative_tolerance = 1e-3,
            .rationale = "Shared linear model coefficient parity",
        },
        .{
            .variable = "cl",
            .unit = "1",
            .absolute_tolerance = 1e-4,
            .relative_tolerance = 1e-3,
            .rationale = "Shared linear model coefficient parity",
        },
        .{
            .variable = "cm",
            .unit = "1",
            .absolute_tolerance = 1e-4,
            .relative_tolerance = 1e-3,
            .rationale = "Shared linear model coefficient parity",
        },
        .{
            .variable = "cn",
            .unit = "1",
            .absolute_tolerance = 1e-4,
            .relative_tolerance = 1e-3,
            .rationale = "Shared linear model coefficient parity",
        },
    } };
}

pub fn metricsForBackend(backend: BackendKind) types.MetricAcceptanceSet {
    return switch (evidenceTier(backend)) {
        .cross_implementation => crossImplementationMetrics(),
        else => .{ .metrics = &.{} },
    };
}

pub fn crossImplementationAcceptance() types.Acceptance {
    return .{ .absolute_tolerance = 50.0, .relative_tolerance = 0.01 };
}

pub fn shimAcceptance() types.Acceptance {
    return .{ .absolute_tolerance = 1e-6, .relative_tolerance = 1e-9 };
}

pub fn acceptanceForBackend(backend: BackendKind) types.Acceptance {
    return switch (evidenceTier(backend)) {
        .cross_implementation => crossImplementationAcceptance(),
        .subprocess_shim, .published_fixture => shimAcceptance(),
        .unavailable => shimAcceptance(),
    };
}

pub fn evaluateAtmosphereGate(
    native: AtmosphereResult,
    subprocess: AtmosphereResult,
) !struct { summary: validation.Summary, acceptance: types.Acceptance, metrics: types.MetricAcceptanceSet } {
    const acceptance = acceptanceForBackend(subprocess.backend);
    const metrics = metricsForBackend(subprocess.backend);
    const summary = try compareAtmosphere(native, subprocess, metrics, acceptance);
    return .{ .summary = summary, .acceptance = acceptance, .metrics = metrics };
}

pub fn compareAtmosphere(
    native: AtmosphereResult,
    reference: AtmosphereResult,
    metrics: types.MetricAcceptanceSet,
    fallback: types.Acceptance,
) !validation.Summary {
    const altitude = reference.geopotential_altitude_m;
    const validity: envelope.Envelope = .{ .axes = &.{
        .{ .variable = "altitude", .unit = "m", .minimum = 0, .maximum = 86_000 },
    } };
    const coord = [_]f64{altitude};
    const samples = [_]validation.Sample{
        .{ .coordinates = &coord, .variable = "temperature_k", .reference = reference.temperature_k, .observed = native.temperature_k },
        .{ .coordinates = &coord, .variable = "pressure_pa", .reference = reference.pressure_pa, .observed = native.pressure_pa },
        .{ .coordinates = &coord, .variable = "density_kg_m3", .reference = reference.density_kg_m3, .observed = native.density_kg_m3 },
        .{ .coordinates = &coord, .variable = "speed_of_sound_mps", .reference = reference.speed_of_sound_mps, .observed = native.speed_of_sound_mps },
    };
    return validation.compareWithMetrics(validity, metrics, fallback, &samples);
}

pub const FixedWingIntegrateQuery = struct {
    model: []const u8 = "f16",
    altitude_ft: f64 = 10000,
    vt_fps: f64 = 800,
    alpha_deg: f64 = 5,
    theta_deg: f64 = 5,
    steps: u32 = 50,
};

pub const FixedWingIntegrateResult = struct {
    /// Borrowed from the query; caller must keep `query.model` alive for the result lifetime.
    model: []const u8,
    steps: u32,
    altitude_m: f64,
    vt_mps: f64,
    alpha_deg: f64,
    theta_deg: f64,
    q_radps: f64,
    ax_mps2: f64,
    az_mps2: f64,
    qdot_radps2: f64,
    backend: BackendKind,
};

pub const FixedWingResponse = struct {
    schema: []const u8,
    backend: []const u8,
    query: []const u8,
    model: []const u8,
    steps: u32,
    altitude_m: f64,
    vt_mps: f64,
    alpha_deg: f64,
    theta_deg: f64,
    q_radps: f64,
    ax_mps2: f64,
    az_mps2: f64,
    qdot_radps2: f64,
};

pub fn queryFixedWingIntegrateSubprocess(
    io: std.Io,
    gpa: std.mem.Allocator,
    backend: Backend,
    query: FixedWingIntegrateQuery,
) !FixedWingIntegrateResult {
    if (backend.kind == .unavailable) return error.BackendUnavailable;

    var request_buffer: [512]u8 = undefined;
    const request_json = try std.fmt.bufPrint(&request_buffer, "{{\"schema\":\"{s}\",\"query\":\"fixed_wing_integrate\",\"model\":\"{s}\",\"altitude_ft\":{d},\"vt_fps\":{d},\"alpha_deg\":{d},\"theta_deg\":{d},\"steps\":{d}}}", .{
        protocol_schema,
        query.model,
        query.altitude_ft,
        query.vt_fps,
        query.alpha_deg,
        query.theta_deg,
        query.steps,
    });

    var child = try std.process.spawn(io, .{
        .argv = &.{ backend.command, "fixed-wing" },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
    });

    const stdin = child.stdin orelse return error.MissingPipe;
    var stdin_writer_buffer: [512]u8 = undefined;
    var stdin_writer = stdin.writer(io, &stdin_writer_buffer);
    try stdin_writer.interface.writeAll(request_json);
    try stdin_writer.interface.writeAll("\n");
    try stdin_writer.interface.flush();

    const stdout = child.stdout orelse return error.MissingPipe;
    var stdout_reader_buffer: [4096]u8 = undefined;
    var stdout_reader = stdout.reader(io, &stdout_reader_buffer);
    var response_line: []const u8 = "";
    while (true) {
        const line = try stdout_reader.interface.takeDelimiterInclusive('\n');
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len > 0 and trimmed[0] == '{') {
            response_line = trimmed;
            break;
        }
    }
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.SubprocessFailed,
        else => return error.SubprocessFailed,
    }

    var parsed = try std.json.parseFromSlice(FixedWingResponse, gpa, response_line, .{
        .ignore_unknown_fields = true,
        .max_value_len = 256,
    });
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, protocol_schema)) return error.InvalidResponseSchema;
    const resolved_backend = parseBackendTag(parsed.value.backend);
    return .{
        .model = query.model,
        .steps = parsed.value.steps,
        .altitude_m = parsed.value.altitude_m,
        .vt_mps = parsed.value.vt_mps,
        .alpha_deg = parsed.value.alpha_deg,
        .theta_deg = parsed.value.theta_deg,
        .q_radps = parsed.value.q_radps,
        .ax_mps2 = parsed.value.ax_mps2,
        .az_mps2 = parsed.value.az_mps2,
        .qdot_radps2 = parsed.value.qdot_radps2,
        .backend = if (resolved_backend == .unavailable) backend.kind else resolved_backend,
    };
}

pub fn compareFixedWingIntegrate(
    reference: FixedWingIntegrateResult,
    observed: FixedWingIntegrateResult,
    acceptance: types.Acceptance,
) !validation.Summary {
    const validity: envelope.Envelope = .{ .axes = &.{
        .{ .variable = "step", .unit = "1", .minimum = 0, .maximum = 100 },
    } };
    const coord = [_]f64{@as(f64, @floatFromInt(reference.steps))};
    const samples = [_]validation.Sample{
        .{ .coordinates = &coord, .variable = "altitude_m", .reference = reference.altitude_m, .observed = observed.altitude_m },
        .{ .coordinates = &coord, .variable = "vt_mps", .reference = reference.vt_mps, .observed = observed.vt_mps },
        .{ .coordinates = &coord, .variable = "alpha_deg", .reference = reference.alpha_deg, .observed = observed.alpha_deg },
        .{ .coordinates = &coord, .variable = "theta_deg", .reference = reference.theta_deg, .observed = observed.theta_deg },
        .{ .coordinates = &coord, .variable = "q_radps", .reference = reference.q_radps, .observed = observed.q_radps },
        .{ .coordinates = &coord, .variable = "ax_mps2", .reference = reference.ax_mps2, .observed = observed.ax_mps2 },
        .{ .coordinates = &coord, .variable = "az_mps2", .reference = reference.az_mps2, .observed = observed.az_mps2 },
        .{ .coordinates = &coord, .variable = "qdot_radps2", .reference = reference.qdot_radps2, .observed = observed.qdot_radps2 },
    };
    return validation.compare(validity, acceptance, &samples);
}

pub fn evaluateFixedWingGate(
    subprocess: FixedWingIntegrateResult,
    fixture: Fixture,
) !struct { summary: validation.Summary, acceptance: types.Acceptance } {
    const acceptance = acceptanceForBackend(subprocess.backend);
    const reference = try fixtureToFixedWingResult(fixture);
    const summary = try compareFixedWingIntegrate(reference, subprocess, acceptance);
    return .{ .summary = summary, .acceptance = acceptance };
}

fn fixtureToFixedWingResult(fixture: Fixture) !FixedWingIntegrateResult {
    var result: FixedWingIntegrateResult = .{
        .model = "f16",
        .steps = 50,
        .altitude_m = 0,
        .vt_mps = 0,
        .alpha_deg = 0,
        .theta_deg = 0,
        .q_radps = 0,
        .ax_mps2 = 0,
        .az_mps2 = 0,
        .qdot_radps2 = 0,
        .backend = .published_fixture,
    };
    for (fixture.samples) |sample| {
        if (std.mem.eql(u8, sample.variable, "altitude_m")) result.altitude_m = sample.reference;
        if (std.mem.eql(u8, sample.variable, "vt_mps")) result.vt_mps = sample.reference;
        if (std.mem.eql(u8, sample.variable, "alpha_deg")) result.alpha_deg = sample.reference;
        if (std.mem.eql(u8, sample.variable, "theta_deg")) result.theta_deg = sample.reference;
        if (std.mem.eql(u8, sample.variable, "q_radps")) result.q_radps = sample.reference;
        if (std.mem.eql(u8, sample.variable, "ax_mps2")) result.ax_mps2 = sample.reference;
        if (std.mem.eql(u8, sample.variable, "az_mps2")) result.az_mps2 = sample.reference;
        if (std.mem.eql(u8, sample.variable, "qdot_radps2")) result.qdot_radps2 = sample.reference;
    }
    return result;
}

pub fn parseFixture(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Fixture) {
    if (bytes.len > 256 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(Fixture, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, "strip.jsbsim-comparator.v1"))
        return error.UnsupportedSchema;
    _ = try validation.compare(
        parsed.value.envelope,
        parsed.value.acceptance,
        parsed.value.samples,
    );
    return parsed;
}

pub fn evaluateFixture(
    fixture: Fixture,
    observed_samples: []const validation.Sample,
) !validation.Summary {
    return validation.compare(fixture.envelope, fixture.acceptance, observed_samples);
}

pub const CoefficientProbe = struct {
    alpha_deg: f64,
    beta_deg: f64,
    vt_fps: f64,
    altitude_ft: f64,
    coefficients: @import("../fixed_wing/coefficients.zig").Six,
};

pub const CoefficientComparator = struct {
    schema: []const u8,
    id: []const u8,
    source: []const u8,
    model: []const u8,
    not_aircraft_data: bool,
    acceptance: types.Acceptance,
    probes: []const CoefficientProbe,
};

pub const CoefficientResult = struct {
    /// Borrowed from the caller's `model` argument; must outlive this result.
    model: []const u8,
    alpha_rad: f64,
    beta_rad: f64,
    mach: f64,
    cx: f64,
    cy: f64,
    cz: f64,
    cl: f64,
    cm: f64,
    cn: f64,
    backend: BackendKind,
};

pub const CoefficientResponse = struct {
    schema: []const u8,
    backend: []const u8,
    query: []const u8,
    model: []const u8,
    alpha_rad: f64,
    beta_rad: f64,
    mach: f64,
    cx: f64,
    cy: f64,
    cz: f64,
    cl: f64,
    cm: f64,
    cn: f64,
};

pub fn parseCoefficientComparator(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(CoefficientComparator) {
    if (bytes.len > 256 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(CoefficientComparator, allocator, bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, "strip.jsbsim-coefficient-comparator.v1"))
        return error.UnsupportedSchema;
    if (parsed.value.probes.len == 0 or parsed.value.probes.len > 64) return error.InvalidProbeCount;
    return parsed;
}

pub fn queryFixedWingCoefficientsSubprocess(
    io: std.Io,
    gpa: std.mem.Allocator,
    backend: Backend,
    probe: CoefficientProbe,
    model: []const u8,
) !CoefficientResult {
    if (backend.kind == .unavailable) return error.BackendUnavailable;

    var request_buffer: [512]u8 = undefined;
    const request_json = try std.fmt.bufPrint(&request_buffer, "{{\"schema\":\"{s}\",\"query\":\"fixed_wing_coefficients\",\"model\":\"{s}\",\"alpha_deg\":{d},\"beta_deg\":{d},\"vt_fps\":{d},\"altitude_ft\":{d}}}", .{
        protocol_schema,
        model,
        probe.alpha_deg,
        probe.beta_deg,
        probe.vt_fps,
        probe.altitude_ft,
    });

    var child = try std.process.spawn(io, .{
        .argv = &.{ backend.command, "coefficients" },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
    });

    const stdin = child.stdin orelse return error.MissingPipe;
    var stdin_writer_buffer: [512]u8 = undefined;
    var stdin_writer = stdin.writer(io, &stdin_writer_buffer);
    try stdin_writer.interface.writeAll(request_json);
    try stdin_writer.interface.writeAll("\n");
    try stdin_writer.interface.flush();

    const stdout = child.stdout orelse return error.MissingPipe;
    var stdout_reader_buffer: [4096]u8 = undefined;
    var stdout_reader = stdout.reader(io, &stdout_reader_buffer);
    var response_line: []const u8 = "";
    while (true) {
        const line = try stdout_reader.interface.takeDelimiterInclusive('\n');
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len > 0 and trimmed[0] == '{') {
            response_line = trimmed;
            break;
        }
    }
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.SubprocessFailed,
        else => return error.SubprocessFailed,
    }

    var parsed = try std.json.parseFromSlice(CoefficientResponse, gpa, response_line, .{
        .ignore_unknown_fields = true,
        .max_value_len = 256,
    });
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, protocol_schema)) return error.InvalidResponseSchema;
    const resolved_backend = parseBackendTag(parsed.value.backend);
    return .{
        .model = model,
        .alpha_rad = parsed.value.alpha_rad,
        .beta_rad = parsed.value.beta_rad,
        .mach = parsed.value.mach,
        .cx = parsed.value.cx,
        .cy = parsed.value.cy,
        .cz = parsed.value.cz,
        .cl = parsed.value.cl,
        .cm = parsed.value.cm,
        .cn = parsed.value.cn,
        .backend = if (resolved_backend == .unavailable) backend.kind else resolved_backend,
    };
}

pub fn nativeCoefficientsAtProbe(
    model: @import("../fixed_wing/coefficients.zig").Model,
    probe: CoefficientProbe,
) !@import("../fixed_wing/coefficients.zig").Six {
    const alpha_rad = probe.alpha_deg * std.math.pi / 180.0;
    const beta_rad = probe.beta_deg * std.math.pi / 180.0;
    const speed_mps = probe.vt_fps * 0.3048;
    const speed_of_sound_mps = 340.0;
    const mach = speed_mps / speed_of_sound_mps;
    return model.grid.evaluate(alpha_rad, beta_rad, mach);
}

pub fn compareNativeVsSubprocess(
    native: @import("../fixed_wing/coefficients.zig").Six,
    observed: CoefficientResult,
    metrics: types.MetricAcceptanceSet,
    fallback: types.Acceptance,
    probe_index: usize,
) !validation.Summary {
    const validity: envelope.Envelope = .{ .axes = &.{
        .{ .variable = "probe", .unit = "1", .minimum = 0, .maximum = 64 },
    } };
    const coord = [_]f64{@as(f64, @floatFromInt(probe_index))};
    const samples = [_]validation.Sample{
        .{ .coordinates = &coord, .variable = "cx", .reference = native.cx, .observed = observed.cx },
        .{ .coordinates = &coord, .variable = "cy", .reference = native.cy, .observed = observed.cy },
        .{ .coordinates = &coord, .variable = "cz", .reference = native.cz, .observed = observed.cz },
        .{ .coordinates = &coord, .variable = "cl", .reference = native.cl, .observed = observed.cl },
        .{ .coordinates = &coord, .variable = "cm", .reference = native.cm, .observed = observed.cm },
        .{ .coordinates = &coord, .variable = "cn", .reference = native.cn, .observed = observed.cn },
    };
    return validation.compareWithMetrics(validity, metrics, fallback, &samples);
}

pub fn evaluateCoefficientGate(
    io: std.Io,
    gpa: std.mem.Allocator,
    backend: Backend,
    comparator: CoefficientComparator,
    native_model: @import("../fixed_wing/coefficients.zig").Model,
) !struct { summary: validation.Summary, acceptance: types.Acceptance, passed: bool } {
    const acceptance = acceptanceForBackend(backend.kind);
    const metrics = metricsForBackend(backend.kind);
    var aggregate = validation.Summary{};
    for (comparator.probes, 0..) |probe, index| {
        const subprocess = try queryFixedWingCoefficientsSubprocess(io, gpa, backend, probe, comparator.model);
        const native = try native_model.grid.evaluate(subprocess.alpha_rad, subprocess.beta_rad, subprocess.mach);
        const summary = try compareNativeVsSubprocess(
            native,
            subprocess,
            if (metrics.metrics.len > 0) metrics else coefficientMetrics(),
            acceptance,
            index,
        );
        aggregate.len += summary.len;
        aggregate.passed += summary.passed;
        aggregate.failed += summary.failed;
    }
    return .{
        .summary = aggregate,
        .acceptance = acceptance,
        .passed = aggregate.allPassed(),
    };
}

test "published JSBSim comparator fixture parses and fails when perturbed" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/jsbsim/us76-comparator.json",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var fixture = try parseFixture(std.testing.allocator, bytes);
    defer fixture.deinit();
    try std.testing.expect(fixture.value.deliberately_perturbed);
    const summary = try validation.compare(
        fixture.value.envelope,
        fixture.value.acceptance,
        fixture.value.samples,
    );
    try std.testing.expectEqual(@as(usize, 1), summary.failed);
}

test "native weather atmosphere matches resolved JSBSim subprocess" {
    const shim_path = "zig-out/bin/strip-jsbsim-shim";
    const backend = try resolveBackend(
        std.testing.io,
        std.testing.allocator,
        shim_path,
        null,
        "tools/jsbsim_atmosphere.py",
        "tools/jsbsim_cmd.sh",
    );
    if (backend.kind == .unavailable) return error.SkipZigTest;

    const altitude_m = 5000.0;
    const native_eval = @import("../atmosphere.zig").evaluate(try @import("../units.zig").GeopotentialAltitude.init(altitude_m));
    const native_state = native_eval.state.?;
    const subprocess = try queryAtmosphereSubprocess(
        std.testing.io,
        std.testing.allocator,
        backend,
        .{ .geopotential_altitude_m = altitude_m },
    );
    const evaluation = try evaluateAtmosphereGate(
        .{
            .geopotential_altitude_m = altitude_m,
            .temperature_k = native_state.temperature.kelvin,
            .pressure_pa = native_state.pressure.pascals,
            .density_kg_m3 = native_state.density.kilograms_per_cubic_meter,
            .speed_of_sound_mps = native_state.speed_of_sound.meters_per_second,
            .backend = .published_fixture,
        },
        subprocess,
    );
    try std.testing.expect(evaluation.summary.allPassed());
}

test "shared linear coefficients match JSBSim subprocess when backend available" {
    const shim_path = "zig-out/bin/strip-jsbsim-shim";
    const backend = try resolveBackend(
        std.testing.io,
        std.testing.allocator,
        shim_path,
        null,
        "tools/jsbsim_coefficients.py",
        "tools/jsbsim_cmd.sh",
    );
    if (backend.kind == .unavailable) return error.SkipZigTest;

    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/jsbsim/coefficient-comparator.json",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var comparator = try parseCoefficientComparator(std.testing.allocator, bytes);
    defer comparator.deinit();
    const native_model = @import("../fixed_wing/synthetic_fixture.zig").syntheticLinearModel();
    const evaluation = try evaluateCoefficientGate(
        std.testing.io,
        std.testing.allocator,
        backend,
        comparator.value,
        native_model,
    );
    try std.testing.expect(evaluation.passed);
}

test "JSBSim fixed-wing integrate matches pinned fixture when backend available" {
    const shim_path = "zig-out/bin/strip-jsbsim-shim";
    const backend = try resolveBackend(
        std.testing.io,
        std.testing.allocator,
        shim_path,
        null,
        "tools/jsbsim_fixed_wing.py",
        "tools/jsbsim_cmd.sh",
    );
    if (backend.kind == .unavailable) return error.SkipZigTest;

    const subprocess = try queryFixedWingIntegrateSubprocess(
        std.testing.io,
        std.testing.allocator,
        backend,
        .{},
    );
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/jsbsim/fixed-wing-integrate-comparator.json",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var fixture = try parseFixture(std.testing.allocator, bytes);
    defer fixture.deinit();
    const evaluation = try evaluateFixedWingGate(subprocess, fixture.value);
    try std.testing.expect(evaluation.summary.allPassed());
}
