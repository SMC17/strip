//! Strip: evidence-bearing aerospace computation primitives.

pub const atmosphere = @import("atmosphere.zig");
pub const evidence = @import("evidence.zig");
pub const frames = @import("frames.zig");
pub const units = @import("units.zig");
pub const safety = @import("safety.zig");
pub const serialization = @import("serialization/root.zig");
pub const uncertainty = @import("uncertainty/root.zig");

pub const math = @import("math/mod.zig");
pub const geodesy = @import("geodesy/mod.zig");
pub const time = @import("time/mod.zig");
pub const random = @import("random/mod.zig");
pub const trace = @import("trace/mod.zig");

pub const dynamics = @import("dynamics/mod.zig");
pub const environment = @import("environment/mod.zig");
pub const aero = @import("aero/mod.zig");
pub const vehicle = @import("vehicle/mod.zig");
pub const control = @import("control/mod.zig");
pub const sensor = @import("sensor/mod.zig");

pub const scenario = @import("scenario/root.zig");
pub const monte_carlo = @import("monte_carlo/root.zig");
pub const uas = @import("uas/root.zig");
pub const assurance = @import("assurance/root.zig");
pub const tools = @import("tools/root.zig");
pub const agent = @import("agent/root.zig");

pub const aeroir = @import("aeroir/root.zig");
pub const state_graph = @import("state_graph/root.zig");
pub const worldforge = @import("worldforge/root.zig");
pub const design_evolve = @import("design_evolve/root.zig");
pub const rare_event = @import("rare_event/root.zig");
pub const multifidelity = @import("multifidelity/root.zig");
pub const runtime_assurance = @import("runtime_assurance/root.zig");
pub const twin = @import("twin/root.zig");
pub const adapters = @import("adapters/root.zig");
pub const public_defense = @import("public_defense/root.zig");

test {
    _ = atmosphere;
    _ = evidence;
    _ = frames;
    _ = units;
    _ = safety;
    _ = serialization;
    _ = uncertainty;
    _ = math;
    _ = geodesy;
    _ = time;
    _ = random;
    _ = trace;
    _ = dynamics;
    _ = environment;
    _ = aero;
    _ = vehicle;
    _ = control;
    _ = sensor;
    _ = scenario;
    _ = monte_carlo;
    _ = uas;
    _ = assurance;
    _ = tools;
    _ = agent;
    _ = aeroir;
    _ = state_graph;
    _ = worldforge;
    _ = design_evolve;
    _ = rare_event;
    _ = multifidelity;
    _ = runtime_assurance;
    _ = twin;
    _ = adapters;
    _ = public_defense;
}
