# Open WeatherNext 2 replacement stack

Date: 2026-07-11  
Plane: **platform only**  
Proof: `scaffold` → `unit-tested` catalog; live HTTP bridges are interim, not OpsSpec weather.

## Bottom line

No credible public apples-to-apples benchmark currently proves a single open model
beats Google WeatherNext 2 overall. WN2 is proprietary (0.25°, 6 h, 15 d, ensemble).
Google open-sourced GraphCast and GenCast, **not** WeatherNext 2.

Strip therefore does **not** wait on Vertex EAP. The durable substitute is a
**multi-model stack**, not one model:

**AIFS ENS v2 + Atlas + FourCastNet 3** (+ FuXi 2.1 / Aurora detail, OneForecast /
StormScope regional, local calibration).

```sh
./zig-out/bin/strip-weathernext stack
./zig-out/bin/strip-weathernext stack-plan
./zig-out/bin/strip-weathernext fetch --live --interim aifs
./zig-out/bin/strip-weathernext fetch --live --interim ifs
./zig-out/bin/strip-weathernext fetch --live --interim nws
```

`zig build verify` runs offline `stack` only — never live network.

## Tier 1 ranking (doctrine)

| Rank | Model | Role |
|------|-------|------|
| 1 | NVIDIA Atlas / Earth-2 | Closest open-weight frontier ensemble |
| 2 | ECMWF AIFS ENS v2 | Best operational open anchor (live via Open-Meteo today) |
| 3 | FourCastNet 3 | Permissive large-ensemble / long-rollout engine |
| 4 | GenCast | Reference predecessor; NC weights |
| 5 | U-Cast / ArchesWeatherGen | Research efficiency / reproducibility |

## Trust boundary

| Plane | Open stack |
|-------|------------|
| Simulation | **Forbidden** as truth |
| Assurance | External candidate with digest + limitations |
| Platform | Catalog, plan, interim HTTP, future Earth2Studio runners |

`operational_qualification_claimed` remains **false**.

## What is wired vs deferred

| Surface | Status |
|---------|--------|
| Typed catalog + production plan JSON | **Wired** (`src/platform/weather_open_stack.zig`) |
| Open-Meteo AIFS / IFS interim fetch | **Wired** |
| NWS / Open-Meteo bridges | **Wired** |
| Local Atlas / FCN3 / Earth2Studio runners | **Deferred** |
| Vertex WeatherNext 2 | **Blocked** (EAP; no public REST) |

## Experience coupling

Forecast members must eventually travel as `ArtifactEnvelope` values (units,
authority, validity, provenance) — see `docs/EXPERIENCE.md`. Candidate ensemble
output must never render identically to accepted OpsSpec weather.
