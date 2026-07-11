# Reference UAS vertical slice

Date: 2026-07-11

## One vehicle / one envelope / one assurance case

| Layer | Artefact | Data class |
|-------|----------|------------|
| Atmosphere | `fixtures/validation/uas/us76-atmosphere-case.json` + `reports/validation/us76-atmosphere.json` | **Real** published US76 table points |
| Propulsion inputs | `fixtures/validation/uas/uiuc-propeller-case.json` + UIUC transcription | **Real** published static CT/CP points |
| Assurance | `fixtures/assurance/link-loss.json` | Programme claim graph (simulation-bounded) |
| Campaign SIL | `campaigns/reference-uas-contingency.toml` (10k) | Synthetic fault injections for Monte Carlo |
| HIL | synthetic `io_loopback` | Not a physical bench |
| Flight | — | `flight_test: missing` |

Programme entry: `programs/reference-uas.toml` now joins the **US76** case/report (not the synthetic perturbation fixture).

## Docs site path

```sh
cd /home/stax/sovereign-physics/strip/website
npm ci && npm start
```
