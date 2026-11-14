# Reward impact of modelling wing thickness (w.tc) in the gym section

Schema `strip_uas_v0.section_tc_impact.v1`. Before: NACA 0012 for every design. After: symmetric NACA 00xx at w.tc (exact Kulfan scaling). NeuralFoil small, free transition, U = 25 m/s, sea level.

## t/c sweep on the default parent (only tc changed)

| t/c | CL before | CL after | CD before | CD after | L/D before | L/D after | reward before | reward after |
|---|---|---|---|---|---|---|---|---|
| 0.08 | 0.1064 | 0.1306 | 0.00756 | 0.00694 | 14.08 | 18.82 | +0.000 | +0.714 |
| 0.09 | 0.1064 | 0.1244 | 0.00756 | 0.00707 | 14.08 | 17.60 | +0.000 | +0.531 |
| 0.10 | 0.1064 | 0.1176 | 0.00756 | 0.00720 | 14.08 | 16.32 | +0.000 | +0.342 |
| 0.11 | 0.1064 | 0.1113 | 0.00756 | 0.00736 | 14.08 | 15.12 | +0.000 | +0.160 |
| 0.12 | 0.1064 | 0.1064 | 0.00756 | 0.00756 | 14.08 | 14.08 | +0.000 | +0.000 |
| 0.13 | 0.1064 | 0.1034 | 0.00756 | 0.00779 | 14.08 | 13.28 | +0.000 | -0.129 |
| 0.14 | 0.1064 | 0.1023 | 0.00756 | 0.00805 | 14.08 | 12.71 | +0.000 | -0.228 |
| 0.15 | 0.1064 | 0.1025 | 0.00756 | 0.00834 | 14.08 | 12.30 | +0.000 | -0.305 |
| 0.16 | 0.1064 | 0.1035 | 0.00756 | 0.00864 | 14.08 | 11.98 | +0.000 | -0.371 |
| 0.17 | 0.1064 | 0.1046 | 0.00756 | 0.00895 | 14.08 | 11.68 | +0.000 | -0.434 |
| 0.18 | 0.1064 | 0.1054 | 0.00756 | 0.00927 | 14.08 | 11.36 | +0.000 | -0.500 |

## 300 random designs (seed 0)

- Spearman L/D before vs after: 0.971; CD: 0.965
- Top-decile L/D overlap: 57%
- Median CD change: +0.3%
- Spearman(t/c, L/D): before +0.00, after -0.13
- Mean t/c of top-decile designs: before 0.132, after 0.112

## Camber sweep on the default parent (NACA 4-digit, camber at 0.4 c; t/c 0.12)

| camber | CL | CD | L/D | reward |
|---|---|---|---|---|
| 0.00 | 0.106 | 0.00756 | 14.1 | +0.000 |
| 0.01 | 0.227 | 0.00901 | 25.2 | +1.503 |
| 0.02 | 0.327 | 0.01097 | 29.8 | +2.037 |
| 0.03 | 0.444 | 0.01432 | 31.0 | +2.017 |
| 0.04 | 0.558 | 0.01859 | 30.0 | +1.594 |
| 0.05 | 0.669 | 0.02384 | 28.1 | +0.970 |
| 0.06 | 0.762 | 0.02932 | 26.0 | +0.313 |

Camber is a strong reward lever at fixed alpha (it adds lift at the same angle); the trimmed mission reward is the fair comparison. Measured sections back the section model to ~6% camber (neuralfoil_polar_validation.md, `gym_section`).

## With the spar-depth floor

Basis: structure.spar_check (14 CFR 23.337/23.303 loads by convention, elliptic loading, Wood Handbook spruce caps, cap-geometry conventions, 5 kg).

- Random designs violating the floor: 4%; mean t/c of the top decile among feasible designs: 0.115.
- L/D-optimal t/c per planform (100 planforms, t/c grid 0.08-0.18): without the floor median 0.08, 51% at the 0.08 bound; with the floor median 0.10, 37% at 0.08, floor binding in 19%, no feasible t/c in 0%.

## Reading this honestly

- Before, thickness was free in the reward (reward did not move with t/c), so the search could drift to any t/c at no cost. After, the reward has a thickness gradient from NeuralFoil.
- The section-only reward favours thin sections. The spar-depth floor (L0 violation `tc_below_spar_depth_floor`) now ties the minimum t/c to span, root chord and mass, so high-AR / small-chord planforms are pushed to their floor instead of 0.08; low-AR, large-chord planforms still go to 0.08 because a spruce-capped 5 kg wing genuinely does not need more depth there. Volume (fuel/battery) is not constrained.
- The L/D used here is at fixed alpha; the mission reward (trimmed C_L) is the better thickness trade.
- Most of the L/D change at fixed alpha comes from C_L, not C_D: at Re ~4e5 and alpha_eff ~1 deg NeuralFoil gives thin sections a higher lift slope (laminar-separation effects on thick sections). The reward's 2x L/D term amplifies this; an L/D gain at fixed alpha is not the same as lower drag at fixed lift.
- Section is symmetric (no camber), and at low Re NeuralFoil's thin-section advantage includes laminar-bubble effects that the measured symmetric sections only partly confirm (see neuralfoil_polar_validation.md, `gym_section`).
- Not FAA / ARP6983; exploratory L1.
