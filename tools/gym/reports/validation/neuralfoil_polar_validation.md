# Section-oracle validation vs measured polars

Schema `strip_uas_v0.validation.polars.v1`. 453 polars, 76 airfoils, 5847 points; sources: Ladson NASA TM-4074, UIUC LSAT vol 01, UIUC LSAT vol 02, UIUC LSAT vol 03, UIUC LSAT vol 04, UIUC LSAT vol 05, UIUC LSAT vol 06. LSAT cache present: True.

ΔC_L = pred − meas; E_CD% = (meas − pred)/meas·100 (positive = oracle under-predicts drag). Attached = α ≤ α(C_L,max) of the measured polar.

## Attached-flow summary

| oracle | n | median abs ΔCL | RMS ΔCL | mean ΔCL | median abs E_CD% | mean E_CD% | p90 abs E_CD% | conf↔error ρ |
|---|---|---|---|---|---|---|---|---|
| `neuralfoil_small` | 5774 | 0.054 | 0.090 | +0.028 | 8.3 | -3.3 | 32.2 | +0.13 |
| `neuralfoil_xlarge` | 5774 | 0.055 | 0.094 | +0.031 | 8.2 | -1.3 | 30.1 | -0.09 |
| `gym_section` | 5574 | 0.068 | 0.107 | +0.005 | 11.2 | -0.8 | 37.9 | +0.08 |
| `gym_section_camber_blind` | 5774 | 0.245 | 0.349 | -0.269 | 17.6 | -8.2 | 74.5 | +0.10 |
| `analytic` | 47 | 0.030 | 0.083 | -0.020 | 29.4 | +25.4 | 61.3 | – |

## By Reynolds band (attached)

| oracle | Re band | n | median abs ΔCL | median abs E_CD% | validated |
|---|---|---|---|---|---|
| `neuralfoil_small` | 0e+00-1e+05 | 1174 | 0.080 | 16.0 | no |
| `neuralfoil_small` | 1e+05-2e+05 | 1606 | 0.061 | 9.2 | no |
| `neuralfoil_small` | 2e+05-6e+05 | 2947 | 0.045 | 6.4 | yes |
| `neuralfoil_small` | 1e+06-2e+07 | 47 | 0.006 | 4.4 | yes |
| `neuralfoil_xlarge` | 0e+00-1e+05 | 1174 | 0.078 | 13.8 | no |
| `neuralfoil_xlarge` | 1e+05-2e+05 | 1606 | 0.062 | 8.5 | no |
| `neuralfoil_xlarge` | 2e+05-6e+05 | 2947 | 0.047 | 7.0 | yes |
| `neuralfoil_xlarge` | 1e+06-2e+07 | 47 | 0.011 | 4.1 | yes |
| `gym_section` | 0e+00-1e+05 | 1156 | 0.083 | 17.0 | no |
| `gym_section` | 1e+05-2e+05 | 1524 | 0.067 | 11.9 | no |
| `gym_section` | 2e+05-6e+05 | 2847 | 0.065 | 9.7 | no |
| `gym_section` | 1e+06-2e+07 | 47 | 0.051 | 2.6 | no |
| `gym_section_camber_blind` | 0e+00-1e+05 | 1174 | 0.224 | 28.7 | no |
| `gym_section_camber_blind` | 1e+05-2e+05 | 1606 | 0.258 | 21.1 | no |
| `gym_section_camber_blind` | 2e+05-6e+05 | 2947 | 0.255 | 13.7 | no |
| `gym_section_camber_blind` | 1e+06-2e+07 | 47 | 0.051 | 2.6 | no |
| `analytic` | 1e+06-2e+07 | 47 | 0.030 | 29.4 | no |

## Post-stall (not used for envelopes)

- `neuralfoil_small`: n=73, median |ΔCL| 0.087, median |E_CD| 28.0%
- `neuralfoil_xlarge`: n=73, median |ΔCL| 0.073, median |E_CD| 27.6%
- `gym_section`: n=69, median |ΔCL| 0.121, median |E_CD| 32.2%
- `gym_section_camber_blind`: n=73, median |ΔCL| 0.393, median |E_CD| 49.8%
- `analytic`: n=6, median |ΔCL| 0.299, median |E_CD| 96.9%

## Worst airfoils (attached, `neuralfoil_small`, by median abs E_CD)

- M06-13-128 (B): n=35, median |ΔCL| 0.085, median |E_CD| 62.0%
- E387 (C): n=76, median |ΔCL| 0.042, median |E_CD| 32.6%
- MA409: n=130, median |ΔCL| 0.076, median |E_CD| 23.1%
- GM15: n=41, median |ΔCL| 0.072, median |E_CD| 18.9%
- E387 (A): n=55, median |ΔCL| 0.033, median |E_CD| 18.8%
- LRN1007 (B): n=61, median |ΔCL| 0.081, median |E_CD| 18.0%
- S6063: n=60, median |ΔCL| 0.056, median |E_CD| 17.8%
- S9000: n=114, median |ΔCL| 0.063, median |E_CD| 16.2%

## Envelopes

- `neuralfoil_small`: validated Re bands [[200000.0, 550000.0], [1000000.0, 20000000.0]] (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).
- `neuralfoil_xlarge`: validated Re bands [[200000.0, 550000.0], [1000000.0, 20000000.0]] (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).
- `gym_section`: validated Re bands none (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).
- `gym_section_camber_blind`: validated Re bands none (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).
- `analytic`: validated Re bands none (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).

## Caveats

Measured 2-D section data vs section oracles. Wind-tunnel corrections as published; low-Re data carry tunnel-to-tunnel scatter of order 0.01-0.02 in C_d at Re<1e5. Not FAA/EASA, not ARP6983/ED-324.
- `gym_section` is the gym's section model: NACA 4-digit with max camber at 0.4 c, at the measured t/c and max camber (`w.tc`, `w.camber`). Checked on every measured section with camber <= 6% c; a non-NACA section is represented by the NACA 4-digit of the same thickness and camber, so camber-line shape (position, reflex, aft loading) is a model error here. `analytic` is checked on NACA 0012 only.
- `gym_section_camber_blind` is the pre-camber baseline (symmetric NACA 00xx at the measured t/c on every airfoil).
- On NACA 0012 the gym section (AeroSandbox NACA 0012, open trailing edge 0.25% c) is ~0.05 high on C_L against Ladson, while the closed-TE coordinates used by `neuralfoil_small` match to 0.006: NeuralFoil is sensitive to trailing-edge thickness, and that sensitivity (not the thickness scaling) explains the NACA 0012 ΔC_L.
- LSAT vols 4-6 ship no coordinates: their clean, flap-neutral polars use nominal UIUC ADS coordinates, not the measured model shape (vols 1-3 use measured coordinates). Skipped for lack of ADS coordinates: AG35-r, NACA 43012A, S822 (B), S834, SH3055. Flapped-section runs (vols 5-6) are excluded.
- Ladson is tripped at 5% chord; every NeuralFoil oracle (including `gym_section`) is run with xtr = 0.05 for those polars and free transition (n_crit 9) for LSAT. The gym itself always runs free transition; with free transition the gym section is ~27% low on C_d against the tripped Ladson data, which is a test-condition mismatch, not a model error.
- `analytic` (the no-NeuralFoil fallback) uses thin-airfoil C_l and a fully turbulent C_d0 = 2 C_f FF build-up (Raymer) with no lift-dependent profile drag, so it under-predicts C_d at high C_l; see analytic_fallback.md.
