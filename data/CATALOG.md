# Strip data catalog

Public / OSINT aero reference data for the Strip-UAS gym. Nothing classified, CUI or
ITAR-controlled. Machine-readable twin: [`catalog.yaml`](catalog.yaml).

| id | quantities | licence | status | used for |
|---|---|---|---|---|
| `ladson_naca0012_tm4074` | NACA 0012 C_l, C_d vs α, Re 6e6 tripped | US Gov / public domain | **vendored** | NeuralFoil, gym section, analytic fallback validation |
| `uiuc_lsat_vol1_3` | 360+ measured polars, 61 airfoils, Re 4e4–5e5 | GPL (polars) | **fetch-script** | NeuralFoil validation in the small-UAS Re range; Re envelope |
| `uiuc_lsat_vol4_6` | flapped / wind-turbine low-Re sets | GPL | catalogued | future flapped-section envelope |
| `uiuc_airfoil_coordinates` | ~1,600 coordinate files | free use (no licence file) | catalogued | airfoil geometry library |
| `uiuc_propeller_db` | small-prop C_T, C_P, η vs J | unspecified | catalogued | propulsion teacher validation |
| `nasa_tmr_naca0012_extra` | Gregory & O'Reilly, Abbott & von Doenhoff | public | catalogued | tripped vs free transition |
| `airfrans` | 1,000 RANS airfoil sims | ODbL | catalogued | CFD-vs-surrogate (simulation) |
| `aerozoo` | well-posed aero problems | CC BY 4.0 | catalogued | evidence schema / surrogate benchmark |
| `ground_wing` | 3-D WIG wings | CC BY 4.0 | catalogued | ground-effect envelope (simulation) |
| `nasa_crm_dpw` | transonic CRM | public | not-usable | transonic, outside L1 incompressible regime |
| `jsbsim_aircraft` | flight models | LGPL | catalogued | already used by JSBSim teacher |

Count: 11 entries — 1 vendored, 1 fetch-script (4,100+ measured points), 8 catalogued, 1 not-usable.

`python data/fetch/fetch_strip_data.py` pulls LSAT vols 1–3 into `data/cache/` (git-ignored,
sha256-checked). LSAT polars are GPL and Strip is Apache-2.0, so only derived statistics
(`tools/gym/reports/validation/neuralfoil_polar_validation.*`) are committed.

Not yet registered in `sources/primary-sources.json` (that manifest is digest-gated by the Zig
verifier; adding records needs the `strip.dataset-manifest.v1` extraction provenance).
