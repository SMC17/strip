# Strip-UAS-v0 — parametric wing / UAS design-search gym

**Status:** scaffold v0 · 2026-09-10 (America/New_York)  
**Product line:** SMC17/strip (aerospace trust/evidence OS)  
**Twin:** Yard-Sea-v0 (naval hull gym) — same env / monitor / evidence / assurance patterns  
**Honesty:** not certification · not operational · not FAA AI assurance approval ·
not ARP6983 process conformance (vocabulary only, public OSINT)

## Purpose

Offline, evidence-coupled **design search** over a simple trapezoidal wing /
small-UAS planform. Every step emits a JSON evidence pack with ODD limits,
claims, a GSN stub, and a Strip assurance overlay so agents cannot silently
promote L1 ranks into cert language.

## Assurance ladder

| Gate | Module | Role |
|------|--------|------|
| L0 reject | `wing.evaluate_l0` + `monitors` | Geometric / algebraic filter |
| L1 rank | `aero_l1.estimate_aero` | NeuralFoil section (+ induced) or analytic polar |
| L2 panel | *(next)* OpenVSP / VSPAERO | Geometry + panel — stubbed teacher only today |
| L3 CFD | *(later)* | Out of scope for v0 |
| L4 ops | — | Explicitly out of scope (`learning_in_ops=False`) |

Strip overlay fields of note:

- `not_certification`, `not_operational`
- `not_faa_ai_assurance_approval`, `not_arp6983_conformance`
- `vocabulary.faa_ai_assurance` / `vocabulary.arp6983` = `terms_only_public_osint`

## Action / observation

- **Action** `Box(7)` ∈ [-1, 1]: relative/additive deltas for
  `[span, chord_root, taper, sweep_deg, tc, twist_deg, alpha_deg]`
- **Observation** `Box(12)`: wing vector (7) + `[CL, CD, LD, area_norm, step_frac]`

## Teachers

Protocol matches Yard-Sea (`detect` / `run` / skip-cleanly):

| Teacher | Role |
|---------|------|
| `teachers.neuralfoil_stub` | L1 section CL/CD/CM when `pip install neuralfoil` |
| `teachers.openvsp_stub` | Geometry CLI smoke (POD); VSPAERO not wired |
| `teachers.jsbsim_stub` | FDM integrate smoke |

## CLI

```sh
pip install -r requirements.txt
pytest -q
python -m strip_uas_v0 detect-teachers
python -m strip_uas_v0 run-search --parents 5 --steps 40 --out out/gallery
```

## Non-goals

Dual sea+air coupled vehicle · CREATE binaries · cert artifacts · learning in ops ·
claiming FAA Part 23/25/107 approval or ARP6983 ML assurance cases.
