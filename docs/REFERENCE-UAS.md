# Reference UAS vertical slice

Date: 2026-07-11

## One vehicle / one envelope / one assurance case

| Layer | Artefact | Data class |
|-------|----------|------------|
| Atmosphere | `fixtures/validation/uas/us76-atmosphere-case.json` + `reports/validation/us76-atmosphere.json` | **Real** published US76 table points |
| Propulsion inputs | `fixtures/validation/uas/uiuc-propeller-case.json` + UIUC transcription | **Real** published static CT/CP points |
| Assurance | `fixtures/assurance/link-loss.json` | Programme claim graph (simulation-bounded) |
| Campaign SIL | `campaigns/reference-uas-contingency.toml` (10k) | Synthetic fault injections for Monte Carlo |
| HIL | `physical_bench_protocol` (+ unix daemon selftest) | Protocol-path HIL; not aircraft clearance |
| Flight | `fixtures/validation/flight-test/heldout-telemetry.csv` + `strip-flight-seal` → `STRIP_FLIGHT_PACKAGE` | Held-out sensor-model CSV (not aircraft log); `flight_test: passed` when sealed package loaded |
| MAVLink | `strip-mavlink-sitl selftest` | In-process HEARTBEAT loopback + fault inject; not live PX4 SITL |

Programme entry: `programs/reference-uas.toml` now joins the **US76** case/report (not the synthetic perturbation fixture).

## Docs site path

```sh
cd /home/stax/sovereign-physics/strip/website
npm ci && npm start
```
