# Experimental modules

These compile and have boundary tests. They are **proposed interfaces**, not implemented capabilities.

They must not appear in product claims, assurance evidence, or “what exists” lists until promoted through Stage 1–4 exit criteria in [ROADMAP-1.0.md](ROADMAP-1.0.md).

## Modules

| Module | Path | What it actually is today |
|--------|------|-------------------------|
| WorldForge | `src/worldforge/` | Scenario generation contract + one test |
| DesignEvolve | `src/design_evolve/` | Candidate struct + constraint margin |
| Rare event | `src/rare_event/` | Weighted outcome average |
| Multifidelity | `src/multifidelity/` | Scalar + error bound |
| Twin | `src/twin/` | Interface stub |
| Agent | `src/agent/` | Replay log + permission check |
| AeroIR | `src/aeroir/` | Typed contract |
| Public defense | `src/public_defense/` | Resilience response contract |
| Runtime assurance | `src/runtime_assurance/` | Monitor contract |
| State graph | `src/state_graph/` | Graph contract |

## External adapter contracts (not linked)

`src/adapters/` names JSBSim, OpenVSP, OpenMDAO, ROS 2, CARLA, PhysX, OpenUSD, Project AirSim, PX4 — only JSBSim and OpenVSP have executable subprocess paths today.

## Promotion policy

A module graduates from experimental when it has:

1. Model-package manifest with verification and validation domains
2. At least one independent implementation or physical referent
3. Signed evidence artifacts tied to claims
4. Independent review record
5. Explicit intended-use and prohibited-use lists

Until then: **do not demo, sell, or cite in papers as shipped capability.**
