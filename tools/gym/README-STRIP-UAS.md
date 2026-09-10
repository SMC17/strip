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
