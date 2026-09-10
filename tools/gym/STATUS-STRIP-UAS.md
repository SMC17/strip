# Strip-UAS-v0 status

Date: 2026-09-10 (America/New_York)

Aerospace twin of Yard-Sea-v0 for **SMC17/strip** (trust/evidence OS). Hard
**not-cert / not-operational**. FAA AI assurance and ARP6983 appear as
**vocabulary honesty only** — not process claims.

## Implemented (local `/workspace/strip-uas-v0`, branch target `feat/strip-uas-v0-gym`)

- `DesignSearchEnv` — 7-D parametric wing morph (span, chord_root, taper, sweep, t/c, twist, alpha)
- L0 geometric monitors (`wing.evaluate_l0` + `monitors.monitor_action`)
- L1 aero rank (`aero_l1.estimate_aero`) — NeuralFoil when available, analytic polar fallback
- Evidence packs: ODD / claims / GSN stub / **Strip assurance overlay**
  (`not_faa_ai_assurance_approval`, `not_arp6983_conformance`)
- Teachers (copied lightly from Yard-Sea): `neuralfoil_stub`, `jsbsim_stub`, `openvsp_stub`
- Random + hill-climb gallery CLI (`python -m strip_uas_v0 run-search`)
- Pytest suite under `tests/`

## Repo layout (push to SMC17/strip)

Mirror Yard-Sea gym placement:

- `tools/gym/strip_uas_v0/` — package
- `tools/gym/tests/` — pytest (or shared with sea gym if merged later)
- `docs/gym/STRIP_UAS_V0.md` — spec

## Hard stops / next

1. Wire OpenVSP wing `.vsp3` parametric export (beyond POD smoke) → L2 panel path
2. JSBSim linear-aero / reference-UAS FDM as optional L1.5/L2 oracle on Strip vehicles
3. Optional BoTorch / bandit search (Yard-Sea already has BoTorch optional)
4. Zig L0 mirror under Strip `src/` or `tools/gym` (parity with Yard-Sea zig_gym)
5. Align evidence schema with Strip Zig evidence compiler (schemas/)

## Do not claim

FAA certification · ARP6983 conformance · flight clearance · learning-in-ops ·
ITAR programs · CREATE/VSPAERO as already-solved in this gym.
