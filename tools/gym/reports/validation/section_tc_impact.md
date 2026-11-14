# Reward impact of modelling wing thickness (w.tc) in the gym section

Schema `strip_uas_v0.section_tc_impact.v1`. Before: NACA 0012 for every design. After: symmetric NACA 00xx at w.tc (exact Kulfan scaling). NeuralFoil small, free transition, U = 25 m/s, sea level.

## t/c sweep on the default parent (only tc changed)

| t/c | CL before | CL after | CD before | CD after | L/D before | L/D after | reward before | reward after |
|---|---|---|---|---|---|---|---|---|
| 0.08 | 0.1064 | 0.1306 | 0.00761 | 0.00703 | 13.97 | 18.59 | +0.000 | +0.699 |
| 0.09 | 0.1064 | 0.1244 | 0.00761 | 0.00715 | 13.97 | 17.40 | +0.000 | +0.521 |
| 0.10 | 0.1064 | 0.1176 | 0.00761 | 0.00728 | 13.97 | 16.16 | +0.000 | +0.336 |
| 0.11 | 0.1064 | 0.1113 | 0.00761 | 0.00743 | 13.97 | 14.99 | +0.000 | +0.157 |
| 0.12 | 0.1064 | 0.1064 | 0.00761 | 0.00761 | 13.97 | 13.97 | +0.000 | +0.000 |
| 0.13 | 0.1064 | 0.1034 | 0.00761 | 0.00784 | 13.97 | 13.19 | +0.000 | -0.127 |
| 0.14 | 0.1064 | 0.1023 | 0.00761 | 0.00810 | 13.97 | 12.62 | +0.000 | -0.225 |
| 0.15 | 0.1064 | 0.1025 | 0.00761 | 0.00839 | 13.97 | 12.22 | +0.000 | -0.302 |
| 0.16 | 0.1064 | 0.1035 | 0.00761 | 0.00870 | 13.97 | 11.90 | +0.000 | -0.368 |
| 0.17 | 0.1064 | 0.1046 | 0.00761 | 0.00901 | 13.97 | 11.60 | +0.000 | -0.431 |
| 0.18 | 0.1064 | 0.1054 | 0.00761 | 0.00933 | 13.97 | 11.29 | +0.000 | -0.497 |

## 300 random designs (seed 0)

- Spearman L/D before vs after: 0.972; CD: 0.969
- Top-decile L/D overlap: 63%
- Median CD change: +0.2%
- Spearman(t/c, L/D): before +0.00, after -0.13
- Mean t/c of top-decile designs: before 0.131, after 0.115

## With the spar-depth floor

Basis: structure.spar_check (14 CFR 23.337/23.303 loads by convention, elliptic loading, Wood Handbook spruce caps, cap-geometry conventions, 5 kg).

- Random designs violating the floor: 4%; mean t/c of the top decile among feasible designs: 0.121.
- L/D-optimal t/c per planform (100 planforms, t/c grid 0.08-0.18): without the floor median 0.08, 51% at the 0.08 bound; with the floor median 0.10, 37% at 0.08, floor binding in 19%, no feasible t/c in 0%.

## Reading this honestly

- Before, thickness was free in the reward (reward did not move with t/c), so the search could drift to any t/c at no cost. After, the reward has a thickness gradient from NeuralFoil.
- The section-only reward favours thin sections. The spar-depth floor (L0 violation `tc_below_spar_depth_floor`) now ties the minimum t/c to span, root chord and mass, so high-AR / small-chord planforms are pushed to their floor instead of 0.08; low-AR, large-chord planforms still go to 0.08 because a spruce-capped 5 kg wing genuinely does not need more depth there. Volume (fuel/battery) is not constrained.
- The L/D used here is at fixed alpha; the mission reward (trimmed C_L) is the better thickness trade.
- Most of the L/D change at fixed alpha comes from C_L, not C_D: at Re ~4e5 and alpha_eff ~1 deg NeuralFoil gives thin sections a higher lift slope (laminar-separation effects on thick sections). The reward's 2x L/D term amplifies this; an L/D gain at fixed alpha is not the same as lower drag at fixed lift.
- Section is symmetric (no camber), and at low Re NeuralFoil's thin-section advantage includes laminar-bubble effects that the measured symmetric sections only partly confirm (see neuralfoil_polar_validation.md, `gym_section`).
- Not FAA / ARP6983; exploratory L1.
