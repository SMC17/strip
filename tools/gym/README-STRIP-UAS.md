# Strip-UAS-v0

Evidence-coupled parametric **wing / UAS design-search gym** — aerospace twin of Yard-Sea-v0 for SMC17/strip.

- **L0** geometric monitors (AR, taper, sweep, t/c, …) — reject before aero rank
- **L1** NeuralFoil section + induced-drag ranking when installed; analytic polar fallback
- Evidence JSON every step (ODD + claims + GSN stub + **Strip assurance overlay**)
- Teachers: `neuralfoil_stub`, `jsbsim_stub`, `openvsp_stub`, `vspaero_l1` (skip cleanly if absent)
- Optional **VSPAERO reward**: `--vspaero` drives DesignSearchEnv L/D vs parent from VLM CL/CD
- Search: random + hill-climb gallery

```sh
pip install -r requirements.txt
pytest -q
python -m strip_uas_v0 detect-teachers
python -m strip_uas_v0 run-search --parents 5 --steps 40 --out out/gallery
python -m strip_uas_v0 run-search --vspaero --parents 2 --steps 5 --out out/gallery_vspaero
```

**Honesty:** not FAA certification, not ARP6983 conformance, not operational,
not flight clearance. FAA AI assurance / ARP6983 terms are vocabulary-only
(public OSINT). See `docs/gym/STRIP_UAS_V0.md`.

## Acceptance gate, measure-then-claim, evidence v2 (mirrors Yard-Sea-v0)

- `strip_uas_v0/acceptance.py` (`strip_uas_v0.acceptance.v1`): every aero number carries pass/fail
  checks: finite CL/CD/LD, CD plausible, analytic-polar CL not pinned at its stall clamp, effective
  alpha inside the attached-flow band, Re in range, and **same fidelity as the parent**. That last one
  catches a VSPAERO parent being compared against an analytic-fallback child. A failed gate earns −1,
  and the Strip overlay disposition becomes `reject_acceptance_gate`.
- `DesignSearchEnv.claim_done()`: "done/improved" is accepted only after the final wing is rebuilt and
  re-measured. `run_search` uses the verdict for `improved`.
- `strip_uas_v0.evidence.v2`: `harness` (version, git SHA), `optimizer` (implementation, version,
  settings, budget and spend), `seeds` (SeedSequence-derived, deterministic episode ids, so policies
  share randomness), `oracle`. `env.export_log()` writes a digest-chained JSONL log, and
  `provenance.verify_log` checks it.
- New CI workflow `.github/workflows/strip-uas-v0-gym.yml` runs the gym tests. Until now they had
  no CI.

Vocabulary only: not FAA AI assurance, not ARP6983/ED-324 conformance, not flight clearance.
