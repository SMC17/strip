# Strip Status

Date: 2026-07-11

**Programme:** [ROADMAP-1.0.md](ROADMAP-1.0.md) — reference UAS vertical slice only until Month 6 exit.  
**Category:** [docs/CATEGORY.md](docs/CATEGORY.md) — trust and evidence OS thesis.  
**Docs site:** `/home/stax/sovereign-physics/strip/website` — `cd` there, then `npm ci && npm start` (not `~/website`; `d` may be a docker alias).  
**Reference UAS:** [docs/REFERENCE-UAS.md](docs/REFERENCE-UAS.md) — US76 + UIUC real validation inputs; SIL faults synthetic.  
**Domain map:** [docs/domain/README.md](docs/domain/README.md) — AIM/GNSS/PBN, WeatherNext, ZJX, Part 91/135/121 dispatch gaps (non-authoritative).  
**CI:** `verify` runs tests, verification-gates, strip-verify, evidence compiler, and campaign scaffold (64-run cap). Separate `campaign-10k` job runs the full 10k Monte Carlo with Ed25519 attestation and SIL/HIL/flight tier ladder. Actions pinned by commit SHA; OpenVSP deb SHA-256 checked in CI.

## Executable surface

- evidence kernel, canonical JSON subset, strict schemas, and public-use policy
- typed math, WGS84 transforms, simulation time, RNG, identity, and replay
- coupled 6-DOF rigid-body dynamics with RK4 load callbacks and Earth/gravity
- US76 atmosphere through 86 km, Dryden/von Kármán turbulence, wind, and weather contracts
- fixed-wing aerodynamics, propulsion, trim, linearization, maneuvers, and contact
- multirotor rotor/motor/battery physics, allocation, control, and estimation
- deterministic multi-rate runtime, scene composition, collision/CCD, and sensor timing
- perception timing, human-factor primitives, terrain, airports, and landing gear
- validation envelopes, source manifests (23 primary sources, content-hashed), coverage matrix, comparators
- flight-test telemetry, regression, residuals, maneuvers, physical HIL protocol, sealed flight packages
- certification-delta + model-passport engines; navigation/dispatch schema scaffolds
- typed interop contracts (FMI 3.0, MAVLink, HLA/DIS) and frontier adapter catalog
- assurance graph JSON ingest, model-package + run-manifest schemas, and product inventory
- experimental frontier modules only via `strip.experimental.*` (see [EXPERIMENTAL.md](EXPERIMENTAL.md))

Proof level: `integration-tested` (gates + engines); operational qualification: **false**

Verification:

```sh
zig build verify
zig build test -Doptimize=ReleaseSafe
./zig-out/bin/strip atmosphere 1000 preliminary_design
./zig-out/bin/strip-validation
./zig-out/bin/strip-evidence build programs/reference-uas.toml
./zig-out/bin/strip-campaign run campaigns/reference-uas-contingency.toml
./zig-out/bin/strip-fidelity
./zig-out/bin/strip-hil-bench
./zig-out/bin/strip-flight-seal build --out /tmp/strip-flight-seal --require-holdout
STRIP_FLIGHT_PACKAGE=/tmp/strip-flight-seal ./zig-out/bin/strip-verification-gates
./zig-out/bin/strip-mavlink-sitl selftest
./zig-out/bin/strip-trajectory selftest
./zig-out/bin/strip-trajectory frontier
./zig-out/bin/strip-trajectory hil-stream --out trajectory.evidence
./zig-out/bin/strip-trajectory receipt --out trajectory.evidence
./zig-out/bin/strip-certification-delta diff <baseline.json> <candidate.json>
./zig-out/bin/strip-model-passport issue strip.atmosphere.us76-layered
```

Latest local gate: unit tests plus UAS, assurance, platform, validation (US76 green),
fidelity, evidence compiler, campaign bundle, verification-gates v3 (with sealed
held-out flight package → `flight_test: passed`), HIL bench, flight-seal,
MAVLink SITL loopback, certification-delta, and model-passport. Authoritative
`NumericalResult` paths and evidence/campaign manifests carry `execution_identity`.
`zig build verify` seals `flight.evidence` and sets `STRIP_FLIGHT_PACKAGE` for gates;
campaign-10k without that env still expects `flight_test: missing`.

## Verification gates (v3)

| Gate | Evidence tier | Honest limit |
|------|---------------|--------------|
| JSBSim atmosphere | `cross_implementation` via pip `jsbsim` | US76-class atmosphere; weather-balloon host |
| JSBSim fixed-wing | `cross_implementation` via F-16 short integration | JSBSim vehicle host; not Strip native aero tables |
| JSBSim coefficients | `cross_implementation` on shared linear-aero model | Not F-16; synthetic shared grid only |
| OpenVSP digest | pinned geometry manifest v3.42.0 | Canonical description; no linked OpenVSP runtime required |
| OpenVSP tessellation | analytic box-wing mesher | Mesh digest/area/count regression |
| OpenVSP export | `OPENSP_CMD` via `openvsp_box_wing.vspscript` or `analytic_stl_exporter` | Nonzero vsp exit fails; structural mesh bounds; analytic exact digest pin |
| Replay | pinned per-arch (`pending_count: 0`); fails if any case pending | Five ReleaseSafe/Debug legs; same RK4 fingerprint across current matrix |
| Uncertainty analytic/MC | affine propagation + calibration | Synthetic affine + campaign holdout coverage |
| Flight evidence (Gate 5) | `software_only` → `hardware_in_loop` → `flight_test` (sealed held-out package in verify) | Held-out sensor-model CSV, not aircraft log; `operational_qualification_claimed: false` |

Verification gate runner:

```sh
JSBSIM_CMD=tools/jsbsim_cmd.sh zig build run-verification-gates
./zig-out/bin/strip-record-replay-baseline
cat baseline.json | ./zig-out/bin/strip-promote-replay-baseline > fixtures/validation/replay/rk4-cross-target.json
tools/promote_replay_from_ci.sh baseline.json
```

## Next proof work

- Optional live router path behind explicit intent (still never from verify)
- Persist worker assignments across process restarts
- Embeddings-backed analogy lane (separate from structural MAC/FAC)
- Couple world-model loop to Strip rigid-body / atmosphere states
- Serial/UART HIL device → JSONL (API ready; stream today is in-process)
- Auto-attach `trajectory.evidence/receipt.json` into `stax-experiment` verdict `--evidence`
- Replace held-out sensor-model CSV with a real flight/ulog export before Month-6 flight claim
- Wire UDP MAVLink to a live `px4-sitl` binary
- WeatherNext live against a real Vertex/WeatherLab endpoint when credentials exist

## CI (`verify` workflow)

| Job | Runner | Purpose |
|-----|--------|---------|
| `zig-and-schemas` | `ubuntu-latest` | fmt, tests, schema fixtures (incl. run-manifest), x86_64-linux Debug replay artifact |
| `replay-baseline-matrix` | `ubuntu-24.04-arm`, `macos-latest` (aarch64 + Rosetta x86_64) | ReleaseSafe verification-gates + per-arch replay baseline |
| `replay-baseline-collect` | `ubuntu-latest` | merge baselines; assert `pending_count == 0` |
| `openvsp-real-export` | `ubuntu-24.04` | OpenVSP 3.42.0 deb (SHA-256 pinned), xvfb, `STRIP_REQUIRE_OPENSP_CMD=1`, Gate 2d real mesh |
| `campaign-10k` | `ubuntu-latest` | Full 10k Monte Carlo + execution_identity + tier ladder |

## Scaffold-level contracts

- JSBSim, OpenVSP, OpenMDAO, ROS 2/DDS, CARLA, PhysX, OpenUSD, Project AirSim,
  PX4/ArduPilot adapters
- WorldForge generation, DesignEvolve search, rare-event sampling,
  multi-fidelity scheduling, live digital twins, and learned models
- browser product interfaces
- WeatherNext / dispatch AI / navigation capability declarations (domain docs + schemas)

These contracts compile and have boundary tests; no linked external system or
validated frontier model is claimed as operationally qualified.
