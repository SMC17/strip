# External weather (platform plane)

Date: 2026-07-11  
Status: **non-authoritative** — never drives `zig build verify` or sim manifests.

## WeatherNext (DeepMind)

Locators:

- https://deepmind.google/science/weathernext/
- https://deepmind.google.com/science/weatherlab

| | WeatherNext Graph | WeatherNext Gen | WeatherNext 2 |
|--|-------------------|-----------------|---------------|
| Historical coverage | 2020–present | 2020–present | 2022–present |
| Architecture | GNN encoder–processor–decoder | Conditional diffusion + GNN/graph transformer | Functional Generative Network (FGN); graph transformer + noisy weights |
| Spatial resolution | 0.25° (~30 km equator) | 0.25° | 0.25° |
| Temporal resolution | 6 h | 12 h | 6 h (1 h experimental via Vertex AI) |
| Init times (UTC) | 00 / 06 / 12 / 18 | same | same |
| Lead time | 10 days | 15 days | 15 days |
| Forecast type | Deterministic | Ensemble (50) | Ensemble (64) + ensemble mean |
| Training / init | ERA5 / HRES-fc0 | ERA5 / HRES-fc0 | ERA5 / HRES-fc0 |

Shared atmospheric variables (pressure levels 50–1000 hPa): geopotential, specific
humidity, temperature, U/V wind, vertical velocity. Surface: 2 m T, 10 m winds,
MSLP, total precipitation; Gen/WN2 also 100 m winds and SST.

## Strip trust boundary

| Plane | WeatherNext / WeatherLab |
|-------|--------------------------|
| Simulation | **Forbidden** as truth source |
| Assurance | May cite as *external* forecast candidate with digest + limitations |
| Platform (`strip lab`) | Allowed client / briefing draft only |

Approved OpsSpec weather sources for Part 135/121 remain operator-specific.
Unapproved AI weather pulls are an explicit market-gap risk (see DISPATCH-OPS).

Strip’s native weather contracts (US76, Dryden/von Kármán, wind fields) stay
deterministic and local. External ML forecasts are candidates until human-signed
into an evidence package.
