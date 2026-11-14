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

## Horizontal tail + fuselage (`airframe.py`, `airframe_np_v0`)

`static_margin(w, cg, airframe=Airframe(...))`, `cg_for_margin(..., airframe=...)`,
`DesignSearchEnv(stability_gate=True, airframe="wing_tail_fuselage")` (or `"wing_tail"`, an
`Airframe`, or `None` / `"wing_only"` for the original wing-alone mode). The Simplex stability
monitor uses the same airframe.

* Tail: `x_np = (a_w·x_np,w + a_te·x_ac,t − c̄·Cmα_f)/(a_w + a_te)`, `a_te = η(S_t/S)a_t(1 − dε/dα)`.
  `a_t` comes from the DATCOM/Helmbold formula, `dε/dα = 2a_w/(πA_w)` (elliptic), and η = 0.9.
* Fuselage: Gilruth & White, NACA Report 711 (1941), `dCm_f/dα = K_f·w_f²·L_f/(S·c̄)` per rad.
  `K_f` was hand-digitised from fig. 8: 10 % → 0.07, 20 → 0.30, 30 → 0.59, 40 → 1.00, 50 → 1.63,
  60 → 2.70 (wing-root ¼-chord position, % body length). It is uncertain to about ±0.05, and positions
  outside 10–60 % are clamped and flagged (`tr711_kf_in_digitised_range`). TR 711 notes that the
  rearward values rest on few data.
* `Airframe.default_for(wing)` sizes the airframe by convention: tail volume 0.5 at a 3·MAC arm, tail
  AR 4, fuselage 0.6·span long and 0.45·MAC wide, nose 30 % of body length ahead of the root LE.
  These are not a design.

Default wing (span 2.4 m, root chord 0.30 m, taper 0.7, 5° sweep, AR 9.4), CG at 25 % MAC:

| mode | static margin | NP shift vs wing alone |
|---|---|---|
| wing_only | −0.015 (fails band) | – |
| wing_tail | 0.207 | +0.222 MAC (tail) |
| wing_tail_fuselage | 0.188 | +0.222 tail, −0.019 fuselage (K_f 0.80 at 35 %) |

The fuselage term grows as the wing sits further aft on the body: −0.007 MAC at 20 %, −0.038 at
50 %. Not modelled: fuselage lift, propeller / power, elevator, trim drag, ground effect. Not FAA / EASA, and not a handling-qualities requirement.

### VSPAERO wing+tail cross-check (`teachers/vspaero_config.py`, `vspaero_wing_tail_v0`)

`neutral_point(w, af)` adds a rectangular horizontal tail (a second OpenVSP WING geom with the
`Airframe` tail area, AR and ¼-chord position, 0.1·span_t above the wing plane) to the `vspaero_l1`
wing. It runs VSPAERO at α = 0° and 4° and takes `x_np = −CMα/CLα·c̄`. The fuselage is **not**
in the VSPAERO model (thin-surface VLM gives no TR 711-comparable body moment), so this checks only
the analytic tail term (η, a_t, dε/dα). It returns `None` when VSPAERO is unavailable.

Sweep: 4 wings (default; 20° sweep; low AR 1.8 m × 0.36 m; high AR 3.2 m × 0.26 m, taper 0.5) ×
tail volume 0.3 / 0.5 / 0.7 at a 3·MAC arm and 0.5 at 2.2 / 4·MAC (20 cases):

| quantity | analytic − VSPAERO |
|---|---|
| total wing+tail NP | max 2.6 % MAC (median ≈ 0.6 %) |
| tail NP shift (vs each method's own wing alone) | −3.6 … +2.2 % MAC; VSPAERO's shift is larger for swept / long-arm cases |
| wing-alone NP (VLM vs VSPAERO) | −0.8 … +1.4 % MAC |
| CLα with tail | analytic 1–3.5 % lower |

Default airframe: VSPAERO NP 0.1768 m vs analytic 0.1777 m (MAC 0.2576 m, 0.3 % MAC); tail height
0 → 0.3·span_t moves the VSPAERO NP by 0.9 % MAC. The test asserts < 3 % MAC on the default
airframe and on a 20° swept wing (`tests/test_vspaero_tail.py`, skipped without VSPAERO).
Two VLMs agreeing is not validation against wind-tunnel or flight data.
