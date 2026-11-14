# Split-conformal calibration (`conformal_split_v0`) — Strip

`tools/gym/strip_uas_v0/conformal.py` is mirrored from SMC17/yard (keep in sync);
`conformal_strip.py` holds the Strip applications. Every record carries the assumptions
verbatim (exchangeability, marginal coverage, no shift guarantee, reference exact).

Run: `cd tools/gym && PYTHONPATH=. python -m strip_uas_v0.conformal_strip`

Local results (α = 0.1):

| Application | Surrogate → reference | n | q̂ | Coverage |
|---|---|---|---|---|
| Section cd | NeuralFoil NACA0012 (xtr 0.05) → Ladson TM-4074 tripped, Re 6e6, \|α\| ≤ 12° | 29 | 5.0% rel | leave-one-grit-out 0.90 |
| Section cl | same | 29 | 0.062 abs | leave-one-grit-out 0.93 |
| Wing CL | L1 (analytic) → planar VLM, i.i.d. wings | 60 cal / 60 test | 0.136 abs | test 0.95; random splits 0.90 |

Limits: one airfoil at one Re (grit zones are near-duplicates, so LOGO is optimistic);
the trip is approximated by `xtr = 0.05` and Mach is ignored; L1→VLM is model-vs-model
and calibrates a known structured gap (no finite-span lift-slope correction in L1).
