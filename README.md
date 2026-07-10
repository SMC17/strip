# Strip

Evidence-bearing aerospace computation in Zig.

Strip starts with one invariant: a numerical result is incomplete unless it
identifies its model, units, intended use, validity envelope, and proof level.
The first vertical slice implements that contract for the troposphere segment
of the U.S. Standard Atmosphere, 1976.

## What exists

- distinct SI quantity types at public model boundaries
- explicit spatial and time reference-frame identifiers
- model manifests and context-of-use metadata
- a 0–11,000 m geopotential-altitude atmosphere model
- refusal outside the implemented model envelope
- an evidence-bearing JSON CLI

```sh
zig build test
zig build
./zig-out/bin/strip atmosphere 1000 preliminary_design
```

Valid intended-use values are `education`, `research`,
`preliminary_design`, and `simulation_training`.

An out-of-envelope query returns structured JSON with `"result": null` and
exit status 2:

```sh
./zig-out/bin/strip atmosphere 12000 research
```

## Architecture direction

Strip will grow through narrow vertical slices:

1. evidence kernel: units, frames, time, provenance, validity, uncertainty
2. deterministic primitives: atmosphere, geodesy, mass properties, 6-DOF
3. scenario runtime: events, faults, replay, Monte Carlo
4. composition: UAS vehicle, controls, sensors, links, traffic, weather
5. assurance: requirements, hazards, tests, evidence graph
6. product surfaces: consumer lab, civil assurance, controlled defense tools

The first product workflow remains a UAS digital test range. Frontier learned
models may propose scenarios, render observations, or accelerate bounded
models; they do not silently replace authoritative state or validation.

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
