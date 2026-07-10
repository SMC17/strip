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
pub const replay = @import("replay/root.zig");

pub const dynamics = @import("dynamics/mod.zig");
pub const environment = @import("environment/mod.zig");
pub const weather = @import("weather/root.zig");
pub const terrain = @import("terrain/root.zig");
pub const aero = @import("aero/mod.zig");
pub const vehicle = @import("vehicle/mod.zig");
pub const control = @import("control/mod.zig");
pub const sensor = @import("sensor/mod.zig");
pub const perception = @import("perception/root.zig");
pub const human_factors = @import("human_factors/root.zig");
pub const airports = @import("airports/root.zig");

pub const validation = @import("validation/root.zig");
pub const fixed_wing = @import("fixed_wing/root.zig");
pub const multirotor = @import("multirotor/root.zig");
pub const analysis = @import("analysis/root.zig");
pub const contact = @import("contact/root.zig");
pub const energy = @import("energy/root.zig");

pub const runtime = @import("runtime/root.zig");
pub const scene = @import("scene/root.zig");
pub const collision = @import("collision/root.zig");
pub const interop = @import("interop/root.zig");
pub const flight_test = @import("flight_test/root.zig");

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
    _ = replay;
    _ = dynamics;
    _ = environment;
    _ = weather;
    _ = terrain;
    _ = aero;
    _ = vehicle;
    _ = control;
    _ = sensor;
    _ = perception;
    _ = human_factors;
    _ = airports;
    _ = validation;
    _ = fixed_wing;
    _ = multirotor;
    _ = analysis;
    _ = contact;
    _ = energy;
    _ = runtime;
    _ = scene;
    _ = collision;
    _ = interop;
    _ = flight_test;
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
