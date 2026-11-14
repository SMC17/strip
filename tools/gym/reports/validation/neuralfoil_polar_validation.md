# Section-oracle validation vs measured polars

Schema `strip_uas_v0.validation.polars.v1`. 365 polars, 61 airfoils, 4199 points; sources: Ladson NASA TM-4074, UIUC LSAT vol 01, UIUC LSAT vol 02, UIUC LSAT vol 03. LSAT cache present: True.

ΔC_L = pred − meas; E_CD% = (meas − pred)/meas·100 (positive = oracle under-predicts drag). Attached = α ≤ α(C_L,max) of the measured polar.

## Attached-flow summary

| oracle | n | median abs ΔCL | RMS ΔCL | mean ΔCL | median abs E_CD% | mean E_CD% | p90 abs E_CD% | conf↔error ρ |
|---|---|---|---|---|---|---|---|---|
| `neuralfoil_small` | 4168 | 0.054 | 0.091 | +0.028 | 8.2 | -2.9 | 32.3 | +0.18 |
| `neuralfoil_xlarge` | 4168 | 0.055 | 0.095 | +0.032 | 8.2 | -1.0 | 30.1 | -0.05 |
| `gym_section` | 47 | 0.051 | 0.063 | +0.050 | 2.6 | +3.4 | 11.4 | +0.11 |
| `analytic` | 47 | 0.030 | 0.083 | -0.020 | 272.7 | -231.0 | 467.1 | – |

## By Reynolds band (attached)

| oracle | Re band | n | median abs ΔCL | median abs E_CD% | validated |
|---|---|---|---|---|---|
| `neuralfoil_small` | 0e+00-1e+05 | 773 | 0.080 | 16.0 | no |
| `neuralfoil_small` | 1e+05-2e+05 | 1214 | 0.061 | 9.1 | no |
| `neuralfoil_small` | 2e+05-6e+05 | 2134 | 0.045 | 6.5 | yes |
| `neuralfoil_small` | 1e+06-2e+07 | 47 | 0.006 | 4.4 | yes |
| `neuralfoil_xlarge` | 0e+00-1e+05 | 773 | 0.075 | 14.4 | no |
| `neuralfoil_xlarge` | 1e+05-2e+05 | 1214 | 0.062 | 8.6 | no |
| `neuralfoil_xlarge` | 2e+05-6e+05 | 2134 | 0.048 | 7.0 | yes |
| `neuralfoil_xlarge` | 1e+06-2e+07 | 47 | 0.011 | 4.1 | yes |
| `gym_section` | 1e+06-2e+07 | 47 | 0.051 | 2.6 | no |
| `analytic` | 1e+06-2e+07 | 47 | 0.030 | 272.7 | no |

## Post-stall (not used for envelopes)

- `neuralfoil_small`: n=31, median |ΔCL| 0.142, median |E_CD| 46.6%
- `neuralfoil_xlarge`: n=31, median |ΔCL| 0.101, median |E_CD| 42.4%
- `gym_section`: n=6, median |ΔCL| 0.670, median |E_CD| 89.2%
- `analytic`: n=6, median |ΔCL| 0.299, median |E_CD| 68.2%

## Worst airfoils (attached, `neuralfoil_small`, by median abs E_CD)

- M06-13-128 (B): n=35, median |ΔCL| 0.085, median |E_CD| 62.0%
- E387 (C): n=76, median |ΔCL| 0.042, median |E_CD| 32.6%
- MA409: n=47, median |ΔCL| 0.060, median |E_CD| 19.4%
- GM15: n=41, median |ΔCL| 0.072, median |E_CD| 18.9%
- E387 (A): n=55, median |ΔCL| 0.033, median |E_CD| 18.8%
- LRN1007 (B): n=61, median |ΔCL| 0.081, median |E_CD| 18.0%
- S6063: n=60, median |ΔCL| 0.056, median |E_CD| 17.8%
- E387 (D): n=16, median |ΔCL| 0.100, median |E_CD| 14.9%

## Envelopes

- `neuralfoil_small`: validated Re bands [[200000.0, 550000.0], [1000000.0, 20000000.0]] (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).
- `neuralfoil_xlarge`: validated Re bands [[200000.0, 550000.0], [1000000.0, 20000000.0]] (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).
- `gym_section`: validated Re bands none (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).
- `analytic`: validated Re bands none (median |dCL| <= 0.05 and median |E_CD| <= 15.0% over attached points).

## Caveats

Measured 2-D section data vs section oracles. Wind-tunnel corrections as published; low-Re data carry tunnel-to-tunnel scatter of order 0.01-0.02 in C_d at Re<1e5. Not FAA/EASA, not ARP6983/ED-324.
- `gym_section` / `analytic` are only checked on NACA 0012 at Re 6e6 (the only measured NACA 0012 here); the gym evaluates that section at Re ≈ 1e5–1e6 for every design regardless of thickness (`w.tc`).
- Ladson is tripped at 5% chord; every NeuralFoil oracle (including `gym_section`) is run with xtr = 0.05 for those polars and free transition (n_crit 9) for LSAT. The gym itself always runs free transition; with free transition the gym section is ~27% low on C_d against the tripped Ladson data, which is a test-condition mismatch, not a model error.
- `analytic` (the no-NeuralFoil fallback, labelled exploratory in `aero_l1`) uses section k = 0.04 on C_l², several times the measured drag-due-to-lift; its C_d is not usable as a prediction and it has no validated envelope.
