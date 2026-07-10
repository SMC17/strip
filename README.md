# Strip

Evidence-bearing aerospace computation in Zig.

Strip starts with one invariant: a numerical result is incomplete unless it
identifies its model, units, intended use, validity envelope, and proof.

## What exists

- evidence, provenance, dependency, uncertainty, schema, and public-use types
- typed vector/frame math and WGS84 geodetic/ECEF/NED transforms
- deterministic time, event ordering, named RNG streams, identities, and replay
- a bounded atmosphere model and rigid-body 6-DOF flight kernel
- mass, aerodynamic-table, actuator, PID, IMU, and GNSS primitives
- deterministic scenario, Monte Carlo, UAS contingency, and simulation modules
- an executable requirement-to-evidence graph
- typed AeroIR, agent, frontier-research, adapter, twin, and public-safe
  resilience contracts
- CLI surfaces for atmosphere, UAS range, assurance, and platform inventory

```sh
zig build verify
zig build
./zig-out/bin/strip atmosphere 1000 preliminary_design
./zig-out/bin/strip-uas-range
./zig-out/bin/strip-assurance
./zig-out/bin/strip-platform
```

Valid intended-use values are `education`, `research`,
`preliminary_design`, and `simulation_training`.

An out-of-envelope query returns structured JSON with `"result": null` and
exit status 2:

```sh
./zig-out/bin/strip atmosphere 12000 research
```

## Architecture

1. evidence kernel: units, frames, provenance, validity, uncertainty, identity
2. deterministic primitives: atmosphere, geodesy, mass properties, 6-DOF
3. scenario runtime: events, faults, replay, Monte Carlo
4. composition: reference vehicles, controls, sensors, links, and UAS workflow
5. assurance: requirements, tests, evidence dependencies, stale/cycle checks
6. constrained intelligence: typed tools, permissions, replay, evaluator contracts
7. product surfaces: consumer lab, civil assurance, mission engineering

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
