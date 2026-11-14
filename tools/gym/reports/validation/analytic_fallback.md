# No-NeuralFoil fallback: section drag and Oswald factor

Schema `strip_uas_v0.analytic_fallback.v1`. Bases: thin-airfoil C_l; C_d0 = 2 C_f FF (Raymer eqs. 12.27, 12.30; fully turbulent, (x/c)_m = 0.3 convention); wing e from Nita & Scholz (2012). Attached measured points; E_CD% = (meas - pred)/meas.

| data | version | n | median abs E_CD% | mean E_CD% | median abs ΔCL |
|---|---|---|---|---|---|
| Ladson NACA 0012, Re 6e6 tripped | before | 47 | 272.8 | -231.0 | 0.030 |
| Ladson NACA 0012, Re 6e6 tripped | after | 47 | 29.4 | +25.4 | 0.030 |
| LSAT symmetric sections, Re 4e4-5e5 | before | 509 | 40.8 | -59.6 | 0.055 |
| LSAT symmetric sections, Re 4e4-5e5 | after | 509 | 28.9 | -9.1 | 0.055 |

## Span efficiency vs Glauert lifting line (unswept, no twist)

Mean |Δe|: Nita & Scholz 0.005, old convention 0.126; max |Δe|: 0.011 vs 0.174.

| AR | taper | e lifting line | e Nita & Scholz | e old |
|---|---|---|---|---|
| 6 | 0.35 | 0.991 | 0.986 | 0.818 |
| 6 | 0.50 | 0.988 | 0.988 | 0.825 |
| 6 | 0.70 | 0.977 | 0.978 | 0.835 |
| 6 | 1.00 | 0.954 | 0.955 | 0.850 |
| 8 | 0.35 | 0.987 | 0.981 | 0.818 |
| 8 | 0.50 | 0.983 | 0.984 | 0.825 |
| 8 | 0.70 | 0.967 | 0.971 | 0.835 |
| 8 | 1.00 | 0.937 | 0.941 | 0.850 |
| 12 | 0.35 | 0.980 | 0.972 | 0.818 |
| 12 | 0.50 | 0.973 | 0.977 | 0.825 |
| 12 | 0.70 | 0.949 | 0.957 | 0.835 |
| 12 | 1.00 | 0.907 | 0.914 | 0.850 |
| 18 | 0.35 | 0.970 | 0.959 | 0.818 |
| 18 | 0.50 | 0.959 | 0.966 | 0.825 |
| 18 | 0.70 | 0.926 | 0.937 | 0.835 |
| 18 | 1.00 | 0.871 | 0.876 | 0.850 |

## Limits

- Fully turbulent C_f over-predicts drag for laminar low-Re sections (LSAT): the fallback is conservative there.
- No lift-dependent profile drag and no stall model in the fallback section; thin-airfoil C_l ignores thickness and Re.
- The NeuralFoil path still uses the historical e = 0.85 - 0.05(1 - taper) convention; switching it is a reward change and is not done here.
- Not FAA / ARP6983; exploratory L1.
