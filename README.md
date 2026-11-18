# Strip

**[Status](STATUS.md) · [Roadmap](ROADMAP.md) · [Contributing](CONTRIBUTING.md) · [Issues](https://github.com/SMC17/strip/issues) · [Public roadmap](https://github.com/users/SMC17/projects/16)**

[![Verify](https://github.com/SMC17/strip/actions/workflows/verify.yml/badge.svg)](https://github.com/SMC17/strip/actions/workflows/verify.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Zig: 0.16](https://img.shields.io/badge/Zig-0.16-orange.svg)](https://ziglang.org/)

**Trust and evidence OS** for computational aerospace engineering — in Zig.

Strip starts with one invariant: a numerical result is incomplete unless it
identifies its model, units, intended use, validity envelope, and proof.

See [docs/CATEGORY.md](docs/CATEGORY.md) for the category thesis and [ROADMAP-1.0.md](ROADMAP-1.0.md) for the frozen programme.

## What exists

- evidence, provenance, dependency, uncertainty, schema, and public-use types
- typed vector/frame math and WGS84 geodetic/ECEF/NED transforms
- deterministic time, event ordering, named RNG streams, identities, and replay
- a unified US76 atmosphere API (layered 0–86 km; troposphere envelope variant) and coupled rigid-body 6-DOF flight kernel
- fixed-wing aerodynamics, multirotor propulsion, trim, and analysis primitives
- weather/turbulence through 86 km, terrain, perception timing, and human factors
- deterministic multi-rate runtime, scene composition, collision, and sensor timing
- validation envelopes, 18-source manifests, coverage matrix, and flight-test analytics
- typed interop contracts (FMI 3.0, MAVLink, HLA/DIS) and frontier adapter catalog
- mass, aerodynamic-table, actuator, PID, IMU, and GNSS primitives
- deterministic scenario, Monte Carlo, UAS contingency, and simulation modules
- an executable requirement-to-evidence graph
- typed AeroIR, agent, frontier-research, adapter, twin, and public-safe
  resilience contracts
- CLI surfaces for atmosphere, UAS range, assurance, platform inventory,
- validation coverage, coupled fidelity demo, verification gates, evidence compiler, and campaigns

## Quickstart

```sh
# Requires Zig 0.16.0
git clone https://github.com/SMC17/strip.git
cd strip
zig build verify
zig build
./zig-out/bin/strip atmosphere 1000 preliminary_design
./zig-out/bin/strip-uas-range
./zig-out/bin/strip-assurance
./zig-out/bin/strip-platform
./zig-out/bin/strip-validation
./zig-out/bin/strip-fidelity
./zig-out/bin/strip-verification-gates
./zig-out/bin/strip-evidence build programs/reference-uas.toml
./zig-out/bin/strip-campaign run campaigns/reference-uas-contingency.toml
./zig-out/bin/strip-verify
./zig-out/bin/strip-record-replay-baseline
./zig-out/bin/strip-promote-replay-baseline
```

Verification gates v3 cover atmosphere, F-16 fixed-wing, shared-model coefficients, OpenVSP export,
campaign calibration, and the flight tier ladder. Local runs without `OPENSP_CMD` pass Gate 2c
via `analytic_stl_exporter`, and `replay-baseline-collect` merges cross-target replay baselines
in `fixtures/validation/replay/rk4-cross-target.json`.

### Verification gates v3 — honest limits

| Row | What passes | What is *not* claimed |
|-----|-------------|---------------------|
| JSBSim coefficients (1c) | Shared `linear-aero` model agreement | F-16 or measured aircraft data |
| OpenVSP export (2d) | Real `vsp -script` STL + triangle/area bands | Aerodynamic certification or analytic mesh equality |
| Replay (3) | Per-arch pinned fingerprints; global `pending_count: 0` | Cross-arch bitwise equality as a requirement |
| Flight evidence (5) | `software_only` + tier ladder (`partial` HIL) | `operational_qualification_claimed` (always false) |

Promote replay baselines with `tools/promote_replay_from_ci.sh` or the `rk4-cross-target-promoted` CI artifact.

Valid intended-use values are `education`, `research`,
`preliminary_design`, and `simulation_training`.

An out-of-envelope query returns structured JSON with `"result": null` and
exit status 2:

```sh
./zig-out/bin/strip atmosphere 90000 research
```

## Architecture

1. evidence kernel: units, frames, provenance, validity, uncertainty, identity
2. deterministic primitives: atmosphere through 86 km, geodesy, mass properties, coupled 6-DOF
3. vehicle physics: fixed-wing, multirotor, propulsion, trim, contact, and energy
4. scenario runtime: multi-rate scheduler, rollback structures, collision, scene composition
5. environment: weather/turbulence, terrain, airports, perception timing, human factors
6. validation: envelopes, source manifests, coverage matrix, comparators, flight-test analytics
7. composition: reference vehicles, controls, sensors, links, and UAS workflow
8. assurance: requirements, tests, evidence dependencies, stale/cycle checks
9. constrained intelligence: typed tools, permissions, replay, evaluator contracts
10. product surfaces: consumer lab, civil assurance, mission engineering

The executable UAS fixture composes 6-DOF translation, hover thrust, wind,
GNSS sampling, link loss, geofence state, and deterministic contingency policy.
It is intentionally low fidelity. Frontier learned models may propose
scenarios, render observations, or accelerate bounded models; they do not
silently replace authoritative state or validation.

External adapter names are contracts only until a linked implementation,
version, conformance test, and evidence record exist.

See [PLATFORM.md](PLATFORM.md), [GOVERNANCE.md](GOVERNANCE.md), and
[SECURITY.md](SECURITY.md) for architecture, promotion, and use boundaries.

## Regulatory boundary

Strip is not approved for operational flight, is not certification evidence,
and is not an accredited defense simulation. ICAO harmonizes international
standards; national authorities such as the FAA regulate within their
jurisdictions. The NTSB is an independent accident-investigation and
safety-recommendation agency with a limited appellate role for certain FAA
actions—not a branch of the FAA.

FAA advisory circulars describe acceptable means of compliance, not a blanket
certification of tools or outputs. Strip will represent objectives and
evidence links without claiming that checklist completion equals approval.

## Primary grounding

- [U.S. Standard Atmosphere, 1976](https://ntrs.nasa.gov/citations/19770009539)
- [FAA AC 20-174 — Development of Civil Aircraft and Systems](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1019527)
- [FAA AC 20-115D — Airborne Software Development Assurance](https://www.faa.gov/airports/resources/advisory_circulars/index.cfm/go/document.information/documentNumber/20-115D)
- [NTSB — Who We Are and What We Do](https://www.ntsb.gov/pages/default.aspx)

Current proof and limitations are recorded in [VALIDATION.md](VALIDATION.md).

## License

[Apache-2.0](LICENSE).
