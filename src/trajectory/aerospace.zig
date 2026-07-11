//! Aerospace-grade engineering action contracts (typed IR beyond shell).
//!
//! These are assurance contracts, not an autopilot. Preconditions and
//! verification lists are checked structurally; physics postconditions remain
//! the job of Strip validation/campaign gates.

const std = @import("std");
const action = @import("action.zig");

pub const Authorization = struct {
    required_roles: []const []const u8 = &.{},
};

pub const EngineeringContract = struct {
    action: action.Action,
    component: []const u8 = "",
    artifact: []const u8 = "",
    constraints: []const []const u8 = &.{},
    authorization: Authorization = .{},
    requirements_baseline: []const u8 = "",

    pub fn validate(self: EngineeringContract) !void {
        try self.action.validate();
        switch (self.action.kind) {
            .modify_control_law => {
                if (self.component.len == 0) return error.MissingComponent;
                if (self.artifact.len == 0) return error.MissingArtifact;
                if (self.requirements_baseline.len == 0) return error.MissingRequirementsBaseline;
                if (self.action.risk != .safety_critical) return error.ControlLawMustBeSafetyCritical;
                if (self.authorization.required_roles.len == 0) return error.MissingAuthorizationRoles;
                if (self.constraints.len == 0) return error.MissingConstraints;
            },
            .run_monte_carlo, .run_hil_protocol, .seal_flight_package => {
                if (self.action.verification.len == 0) return error.MissingVerification;
            },
            else => {},
        }
    }
};

pub fn pitchControllerContract() EngineeringContract {
    return .{
        .action = .{
            .kind = .modify_control_law,
            .action_id = "mod-pitch-gain-001",
            .objective = "Adjust pitch-loop gain under isolated branch with HIL+MC gates",
            .target = "src/control/pid.zig",
            .risk = .safety_critical,
            .preconditions = &.{
                "requirements_baseline == FC-2.3",
                "branch_is_isolated == true",
            },
            .expected_effects = &.{
                "pitch_controller gain updated",
                "no unreviewed requirement changes",
            },
            .verification = &.{
                "unit_tests",
                "monte_carlo_envelope",
                "hil_bench_protocol",
            },
        },
        .component = "pitch_controller",
        .artifact = "src/control/pid.zig",
        .constraints = &.{
            "phase_margin_deg >= 45",
            "actuator_saturation_probability <= 1e-6",
            "no_unreviewed_requirement_changes",
        },
        .authorization = .{ .required_roles = &.{ "controls_engineer", "safety_engineer" } },
        .requirements_baseline = "FC-2.3",
    };
}

test "pitch controller contract validates" {
    try pitchControllerContract().validate();
}

test "control law without roles is rejected" {
    var c = pitchControllerContract();
    c.authorization.required_roles = &.{};
    try std.testing.expectError(error.MissingAuthorizationRoles, c.validate());
}
