# Strip-UAS-v0 static stability gate (`static_margin_v0`, `vlm_planar_v0`)

Modules: `tools/gym/strip_uas_v0/vlm.py`, `tools/gym/strip_uas_v0/stability.py`.

* **VLM** — numpy horseshoe vortex lattice on the trapezoidal `WingState`
  (cosine spanwise spacing, 1/4–3/4 rule, linear washout). Planar, flat-plate,
  inviscid, linear. Gives CL, CM, CL_α and the wing-alone neutral point.
* **Static margin** — `SM = (x_np − x_cg)/MAC`. CG is a convention: `fixed`
  (default in the env: placed where the parent has `sm_target = 0.10`, then held,
  so planform changes move the margin) or `frac_mac`.
* **Gate** — `DesignSearchEnv(stability_gate=True)`: `static_margin_in_band`
  (0.05–0.30, convention) is folded into the acceptance block as
  `stability:*` checks; failing children earn no credit; `claim_done` re-measures SM.
  Trim (Cm about CG at a cruise CL) is reported, not gated.
* **Cross-check** — `static_margin(..., cross_check_vspaero=True)` runs VSPAERO at two
  alphas and records the VLM-vs-VSPAERO neutral-point disagreement
  (`np_vlm_vs_vspaero_agree`, ≤ 0.08 MAC).

Sanity limits in tests (not validation): rectangular CL_α within 7% of Helmbold,
unswept NP 0.23–0.26 MAC, sweep-back moves NP aft and lowers CL_α. VSPAERO vs VLM
(local run): CL_α within 2.3%, NP within 0.01 m (≤ 3% MAC) on three planforms.

**Bug found by the cross-check (fixed here):** `teachers/vspaero_l1.py` passed the
*total* wing area to OpenVSP's per-panel `XSec_1 Area`, so every VSPAERO wing had
**twice the intended span** (AR 16 instead of 8 for the default-ish rectangle), and its
sweep was applied at the leading edge, not the quarter chord used by `WingState`.
Earlier VSPAERO CL/CD numbers in evidence were for the doubled wing.

Scope: wing alone — no tail, fuselage, propeller, controls. Not FAA / EASA, not
ARP6983 / ED-324, not a handling-qualities requirement, not flight-test validated.
