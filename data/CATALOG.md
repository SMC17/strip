# Strip data catalog

Public / OSINT aero reference data for the Strip-UAS gym. Nothing classified, CUI or
ITAR-controlled. Machine-readable twin: [`catalog.yaml`](catalog.yaml).

| id | quantities | licence | status | used for |
|---|---|---|---|---|
| `ladson_naca0012_tm4074` | NACA 0012 C_l, C_d vs α, Re 6e6 tripped | US Gov / public domain | **vendored** | NeuralFoil, gym section, analytic fallback validation |
| `uiuc_lsat_vol1_3` | 360+ measured polars, 61 airfoils, Re 4e4–5e5 | GPL (polars) | **fetch-script** | NeuralFoil validation in the small-UAS Re range; Re envelope |
| `uiuc_lsat_vol4_6` | 88 clean flap-neutral polars, 16 sections, Re 4e4–5e5 | GPL | **fetch-script** | NeuralFoil + gym-section validation (nominal ADS coordinates) |
| `uiuc_airfoil_coordinates` | ~1,600 coordinate files (15 fetched) | no licence stated | **fetch-script** | coordinates for LSAT vols 4–6 |
| `uiuc_propeller_db` | small-prop C_T, C_P, η vs J | unspecified | catalogued | propulsion teacher validation |
| `nasa_tmr_naca0012_extra` | Gregory & O'Reilly, Abbott & von Doenhoff | public | catalogued | tripped vs free transition |
| `airfrans` | 1,000 RANS airfoil sims | ODbL | catalogued | CFD-vs-surrogate (simulation) |
| `aerozoo` | well-posed aero problems | CC BY 4.0 | catalogued | evidence schema / surrogate benchmark |
| `ground_wing` | 3-D WIG wings | CC BY 4.0 | catalogued | ground-effect envelope (simulation) |
| `nasa_crm_dpw` | transonic CRM | public | not-usable | transonic, outside L1 incompressible regime |
| `tud_mh32_wing_all_aoa` | raw balance data, wing + winglet, all α | CC0 | catalogued | VLM check — geometry not in dataset |
| `cambridge_cued_wing_lab_data` | student AR 3–6 wing tests | none stated | not-usable | — |
| `naca_arc_finite_wing_reports` | C_L-α, C_D-C_L² per AR (scans) | public / Crown | catalogued | VLM reference if ever digitised by its publisher |
| `jsbsim_aircraft` | flight models | LGPL | catalogued | already used by JSBSim teacher |

Count: 14 entries — 1 vendored, 3 fetch-script (5,700+ measured attached points), 8 catalogued, 2 not-usable.

**VLM / VSPAERO measured validation: none possible yet.** No public, machine-readable,
licence-clear finite-wing C_L-α / C_Di data set with complete geometry was found (search
2026-11-14). The closest (TU Delft MH32, CC0) lacks the planform/winglet geometry and needs a
MATLAB tare chain; NACA/ARC reports are scans. The VLM path therefore stays flagged
`section_oracle_validated = False` in the applicability advisories.

`python data/fetch/fetch_strip_data.py` pulls LSAT vols 1–6 and 15 UIUC ADS coordinate files into `data/cache/` (git-ignored,
sha256-checked). LSAT polars are GPL and Strip is Apache-2.0, so only derived statistics
(`tools/gym/reports/validation/neuralfoil_polar_validation.*`) are committed.

Registered in `sources/primary-sources.json` (`strip.dataset-manifest.v1`, verified by
`src/validation/source.zig` / `strip-validation`): `ladson-naca0012-tm4074` (digest = the
vendored file, `source_content`), and `uiuc-lsat-vol1-3`, `uiuc-lsat-vol4-6`,
`uiuc-airfoil-coordinates` (digest = canonical bibliographic JSON in `sources/extracted/`, since
the GPL data themselves are not committed). Registration is provenance, not validation evidence.
