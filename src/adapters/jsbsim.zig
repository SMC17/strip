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
        .temperature_k = parsed.value.temperature_k,
        .pressure_pa = parsed.value.pressure_pa,
        .density_kg_m3 = parsed.value.density_kg_m3,
        .speed_of_sound_mps = parsed.value.speed_of_sound_mps,
        .backend = if (resolved_backend == .unavailable) backend.kind else resolved_backend,
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
) !struct { summary: validation.Summary, acceptance: types.Acceptance } {
    const acceptance = acceptanceForBackend(subprocess.backend);
    const summary = try compareAtmosphere(native, subprocess, acceptance);
    return .{ .summary = summary, .acceptance = acceptance };
}

pub fn compareAtmosphere(
    native: AtmosphereResult,
    reference: AtmosphereResult,
    acceptance: types.Acceptance,
) !validation.Summary {
    const validity: envelope.Envelope = .{ .axes = &.{
        .{ .variable = "altitude", .unit = "m", .minimum = -1.0e6, .maximum = 1.0e6 },
    } };
    const samples = [_]validation.Sample{
        .{ .coordinates = &.{0}, .variable = "temperature_k", .reference = reference.temperature_k, .observed = native.temperature_k },
        .{ .coordinates = &.{0}, .variable = "pressure_pa", .reference = reference.pressure_pa, .observed = native.pressure_pa },
        .{ .coordinates = &.{0}, .variable = "density_kg_m3", .reference = reference.density_kg_m3, .observed = native.density_kg_m3 },
        .{ .coordinates = &.{0}, .variable = "speed_of_sound_mps", .reference = reference.speed_of_sound_mps, .observed = native.speed_of_sound_mps },
    };
    return validation.compare(validity, acceptance, &samples);
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
    const native = try @import("../weather/root.zig").atmosphere.evaluate(altitude_m);
    const subprocess = try queryAtmosphereSubprocess(
        std.testing.io,
        std.testing.allocator,
        backend,
        .{ .geopotential_altitude_m = altitude_m },
    );
    const evaluation = try evaluateAtmosphereGate(
        .{
            .temperature_k = native.temperature_k,
            .pressure_pa = native.pressure_pa,
            .density_kg_m3 = native.density_kg_m3,
            .speed_of_sound_mps = native.speed_of_sound_mps,
            .backend = .published_fixture,
        },
        subprocess,
    );
    try std.testing.expect(evaluation.summary.allPassed());
}
