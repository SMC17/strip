# Strip ROADMAP 1.0

Date: 2026-07-10  
Status: **Foundation reset** — single programme until Month 6 exit criteria.

## North star

Strip is the **trust and evidence operating system** for computational aerospace engineering.

The simulator is one evidence producer. Assurance, HIL, flight test, and external tools (JSBSim, FMI, OpenMDAO, PX4) are others. The asset is the machine-verifiable link between a decision, the models used, their valid domains, uncertainties, dependencies, and supporting evidence.

**Not the goal:** another generic 6-DOF simulator, digital-twin dashboard, or “push-button certification” fiction.

## Honest scorecard (2026-07-10)

| Dimension | Score | Notes |
|-----------|-------|-------|
| Core research thesis | Strong | Evidence-bearing results; not yet type-enforced |
| Scope discipline | Poor | ~50 public modules; many are contracts only |
| Numerical kernel | Promising | RK4 + tests; no adaptive suite yet |
| Software verification | Early | 211 unit tests; CI green on `main` |
| Physical validation | Minimal | Synthetic fixtures dominate |
| Evidence semantics | Prototype | Ordinal proof levels; no credibility vector |
| Reproducibility | Partial | Zig/JSBSim pinned; OpenVSP deb not checksummed |
| Operational/cert relevance | None | By design |

**As a disciplined prototype:** ~6/10.  
**As a validated aerospace platform:** ~2/10.

## Frozen programme (only top-level work until Month 6)

**Reference vertical slice:** electric fixed-wing UAS — one vehicle, one mission envelope, one assurance case.

```
takeoff → climb → waypoint → descent → landing
+ wind/gust/turbulence + GNSS degradation + link loss + energy reserve + geofence/RTH
→ SIL → PIL → HIL → held-out flight validation
```

**Exit (Month 6):** declared validation envelope, per-variable acceptance metrics, uncertainty budget, benchmark report from one command, no synthetic data labeled as flight evidence.

## Architecture (three planes + substrate)

```
┌─────────────────────────────────────────────────────────────┐
│  Strip Lab (platform) — campaigns, registry, reports, HIL   │
│  MAY use network, Python, DB, OpenRouter (non-authoritative)│
├─────────────────────────────────────────────────────────────┤
│  Strip Assurance — requirements, hazards, claims, reviews │
├─────────────────────────────────────────────────────────────┤
│  Strip Sim — deterministic executive, models, sensors       │
│  NO network, NO LLM, NO mutable remote config               │
├─────────────────────────────────────────────────────────────┤
│  Evidence substrate — units, frames, time, identity, UQ,    │
│  validity domains, canonical serialization, audit log       │
└─────────────────────────────────────────────────────────────┘
```

## Stage 1 — Stop the bleeding (Months 0–3)

### P0 defects

| ID | Issue | Status |
|----|-------|--------|
| P0.1 | Subprocess JSON string lifetime (JSBSim integrate/coeff, OpenVSP export) | **Fixed** 2026-07-10 |
| P0.2 | OpenVSP “real” gate is coarse smoke test (area/triangle bands only) | **Partial** — claims split: invocation / mesh_valid / geometry_conformance |
| P0.3 | Stale STL / nonzero vsp exit accepted | **Partial** — delete-before-export; exit policy still relaxed |
| P0.4 | `watertight_required` ignored | **Fixed** 2026-07-10 |
| P0.5 | Canonical buffer heuristics | **Fixed** 2026-07-10 — streaming encoder hashes coordinates in place |
| P0.6 | Duplicate atmosphere (`atmosphere.zig` 0–11 km vs `weather` 0–86 km) | **Fixed** 2026-07-10 — `strip.atmosphere` delegates to `weather.atmosphere` |
| P0.7 | Global JSBSim tolerance (50 K, 50 m/s on all vars) | **Fixed** 2026-07-10 — per-variable `MetricAcceptance` |
| P0.8 | Validation report not joined to case `expected_dimensions` | **Open** |
| P0.9 | 18-source manifest hashes URLs not document content | **Open** — extraction provenance |
| P0.10 | `proof_gates` name overclaims | **Open** — rename to `verification_gates` |

### Stage 1 exit criteria

- [x] No dangling subprocess string escapes
- [x] One authoritative atmosphere implementation
- [x] Streaming canonical encoder → SHA-256 (no size heuristics)
- [x] Per-variable JSBSim acceptance metrics
- [x] Strip Verify credibility step in `zig build verify`
- [ ] `model-package` schema v1 + `run-manifest` schema v1
- [ ] Per-variable comparator tolerances with documented rationale
- [ ] Experimental modules removed from primary product claims (see `EXPERIMENTAL.md`)
- [ ] Public license file
- [ ] CI deps pinned by digest/commit (actions SHAs, jsonschema, OpenVSP deb)
- [ ] Reproducible Linux build documented
- [ ] Every authoritative output carries execution identity

## Stage 2 — Enforce the thesis in types (Months 3–6)

Make naked `f64` returns impossible for authoritative models:

```zig
pub fn Result(comptime T: type) type {
    return struct {
        value: T,
        model: ModelInstanceId,
        configuration: ArtifactId,
        intended_use: IntendedUse,
        envelope: EvaluatedEnvelope,
        uncertainty: UncertaintyBudget,
        evidence: EvidenceSetId,
    };
}
```

Replace scalar proof level with credibility vector **C = (P, V, E, R, G)** per NASA-STD-7009B posture.

## Stage 3 — Evidence quality over test count (Months 6–9)

Manufactured solutions, convergence order, metamorphic tests, differential twin implementations, calibration/holdout separation, mutation testing on fixtures.

## Stage 4 — One vehicle properly (Months 6–12)

One source-traced UAS: aero tables, propulsion, mass, trim, controllers, sensors, mission, JSBSim differential campaign, held-out validation.

## Frozen experimental surface

Do **not** expand or market until Stage 1 exit:

`worldforge`, `design_evolve`, `rare_event`, `multifidelity`, `twin`, `agent`, `aeroir`, `public_defense`, `runtime_assurance`, `state_graph`, most external adapter names.

See [EXPERIMENTAL.md](EXPERIMENTAL.md).

## External integrations (compose, don't clone)

| Tool | Role | Strip owns |
|------|------|------------|
| JSBSim | Independent dynamics comparator | Protocol, campaigns, disagreement reporting |
| FMI 3.0 | Co-simulation boundary | Conformance tests, evidence on exchange |
| OpenMDAO | MDO / calibration orchestration | Authoritative model execution + evidence |
| PX4 / ArduPilot | SITL autopilot | Timing, faults, replay, evidence ingest |
| OpenVSP | CAD export oracle | Invocation audit, mesh structural checks |
| OpenRouter | **Platform plane only** — draft scenarios, summarize reports | Nothing in sim hot path; all outputs non-authoritative until assurance |

See [docs/PLATFORM-EXTERNAL.md](docs/PLATFORM-EXTERNAL.md).

## Product wedges (ranked)

1. **Strip Verify** — CI credibility compiler for UAS teams (now)
2. **Evidence compiler** — `strip evidence build` → signed package (now)
3. **Certification-delta engine** — what must be redone on change (now)
4. **Model credibility passports** — machine-readable applicability (now)
5. **Validation campaign compiler** — declarative DOE/Monte Carlo/holdout (early)
6. **Flight-test foundry** — telemetry → discrepancy → test cards (early)
7. **HIL-in-a-box** — appliance after software wedge (later)
8. **Supplier evidence exchange** — network moat (later)

## Decisive benchmark command (Month 18–24 target)

```sh
strip campaign run campaigns/reference-uas-contingency.toml
```

Produces immutable bundle: 10k runs, fault scenarios, SIL/HIL/flight comparisons, UQ, sensitivity, coverage, counterexamples, defects/waivers, claim graph, reproducible report.

## Hard rule

**Every new feature must increase evidence density, reduce revalidation cost, improve interoperability, or close the loop with physical reality.** Otherwise it stays in `experimental/` or does not ship.

## References

- [STATUS.md](STATUS.md) — current executable surface
- [VALIDATION.md](VALIDATION.md) — proof level and limitations
- [EXPERIMENTAL.md](EXPERIMENTAL.md) — frozen contracts
- [docs/PLATFORM-EXTERNAL.md](docs/PLATFORM-EXTERNAL.md) — OpenRouter and external wiring policy
