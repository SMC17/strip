# Navigation systems (domain map)

Date: 2026-07-11  
Proof level: bibliographic / doctrine map — **not** Strip sensor truth.

Primary locator: [FAA AIM Basic w/ Chg 1–2 (3-21-24)](https://www.faa.gov/air_traffic/publications/media/AIM-Basic-w-Chg1-and-Chg2-dtd-3-21-24.pdf)  
Related: FAA Satellite Navigation / PBN materials; Strip GNSS model is a
simulation sensor contract (`src/sensor/gnss.zig`), not WAAS/RAIM certification.

## GNSS and augmented positioning

| Term | Role |
|------|------|
| **GPS / GNSS** | Three-dimensional position (lat, lon, altitude) across phases of flight |
| **PBN** | Performance Based Navigation — flexible point-to-point / parallel tracks |
| **ABAS / RAIM** | Aircraft-based integrity monitoring without ground SBAS |
| **SBAS / WAAS** | Space-based augmentation (FAA Wide Area Augmentation System) |
| **GBAS** | Ground-based augmentation for precision approach at equipped airports |
| **RNAV** | Area navigation via waypoints; not sequential ground-beacon tracking alone |
| **RNP** | RNAV with onboard performance monitoring and alerting; curved paths allowed |
| **ADS-B** | Aircraft broadcast GPS position/altitude/velocity to ATC and nearby traffic |
| **IRS** | Inertial reference — dead reckoning via gyros/accelerometers if GNSS lost |

FAA Satellite Navigation Team framing: GPS + WAAS + ABAS are collectively GNSS
for RNAV/RNP in the NAS. GBAS landing systems are a non-Federal precision-approach
path alongside ILS/LOC/VOR baselines.

## Traditional ground NAVAIDs (baseline / backup)

- **VOR** — VHF omnidirectional range; radial tracking to/from station
- **ILS** — instrument landing system; lateral + vertical guidance in low visibility
- Still relevant as backup when GNSS is degraded or for procedure design heritage

## Flight management

Modern FMS uses RNAV waypoints independent of sequential ground beacons. RNP adds
self-monitored accuracy bounds for complex terminal paths.

## Strip mapping

| Domain concept | Strip surface today | Honest limit |
|----------------|---------------------|--------------|
| GNSS sample | `src/sensor/gnss.zig` + `NumericalResult` | Simulated timing/noise; not SBAS/RAIM |
| IMU / IRS-like | `src/sensor/imu.zig` | Sensor model, not certified IRS |
| Navigation capability claim | `schemas/navigation-capability.schema.json` (scaffold) | `operational_qualification_claimed: false` |
| AIM / CNS doctrine | this doc + primary-sources | Citation only; no AIM body vendored |

## Air-to-air coordination (AIM-aligned SOP summary)

Frequencies (operational coordination only — not ATC/emergency bands):

| Use | Frequency |
|-----|-----------|
| Fixed-wing GA air-to-air | 122.75 MHz |
| Helicopters | 123.025 MHz |
| Gliders / balloons / instruction | 123.3 / 123.5 MHz |
| Oceanic inter-plane | 123.45 MHz |

Message shape: **Who** called, **Who** you are, **Where**, **What** intentions.
Near non-towered airports: monitor/self-announce on CTAF within ~10 NM (VFR).
Lost-nav mnemonic (training doctrine): Climb, Conserve, Confess, Comply, Call.
Collision avoidance: TCAS/ADS-B + see-and-avoid; right-of-way per 14 CFR §91.113.
Sterile cockpit: no non-essential air-to-air / nav programming in critical phases.

Sources for SOP detail are listed under AIM / AC 120-71A / §91.113 in
`sources/primary-sources.json`. Community forum posts are **not** primary Strip
evidence.
