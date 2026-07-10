//! Contract for scenario synthesis; no generator implementation is implied.
const std = @import("std");

pub const Request = struct {
    seed: u64,
    event_budget: u32,
    horizon_ns: u64,
};

pub const Artifact = struct {
    scenario_digest: [32]u8,
    generator_id: []const u8,
    generator_version: []const u8,
};

pub const Generator = struct {
    context: *anyopaque,
    generateFn: *const fn (*anyopaque, Request) anyerror!Artifact,

    pub fn generate(self: Generator, request: Request) !Artifact {
        if (request.event_budget == 0 or request.horizon_ns == 0) return error.InvalidRequest;
        return self.generateFn(self.context, request);
    }
};

test "generator contract refuses an empty scenario request before delegation" {
    var called = false;
    const Stub = struct {
        fn generate(context: *anyopaque, _: Request) !Artifact {
            const value: *bool = @ptrCast(@alignCast(context));
            value.* = true;
            return .{
                .scenario_digest = [_]u8{0} ** 32,
                .generator_id = "test-only",
                .generator_version = "0",
            };
        }
    };
    const generator: Generator = .{ .context = &called, .generateFn = Stub.generate };
    try std.testing.expectError(
        error.InvalidRequest,
        generator.generate(.{ .seed = 1, .event_budget = 0, .horizon_ns = 1 }),
    );
    try std.testing.expect(!called);
}
