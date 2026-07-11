# Strip Category

Strip is not primarily a simulator, assurance tool, or research platform.

Strip is the **trust and evidence operating system** for computational aerospace engineering.

## The asset

The asset is not an `f64`, a mesh, or a requirements diagram. It is the machine-verifiable relationship between:

- a **decision** someone is about to make;
- the **models** used to support it;
- their **valid domains** and **uncertainties**;
- the **dependencies** between artifacts;
- the **evidence** justifying confidence;
- and the **minimal evidence that must be regenerated** when anything changes.

NASA-STD-7009B already separates capability credibility, result credibility, intended use, pedigree, verification, validation, uncertainty, review, and defects. Strip makes that separation **executable** — not another PDF stack.

## Three planes

| Plane | Trust model | Examples |
|-------|-------------|----------|
| **Simulation** | Deterministic, no network, no LLM | RK4 executive, atmosphere, rigid body, sensors |
| **Assurance** | Cannot mutate simulation results | Requirements, hazards, claims, reviews, waivers |
| **Platform (Strip Lab)** | Non-authoritative orchestration | Campaigns, Python SDK, OpenRouter drafting, reports |

External tools (JSBSim, OpenVSP, FMI, PX4, OpenMDAO) are **evidence producers** integrated at boundaries — not replaced.

## Product ladder

1. **strip-core** — typed quantities, frames, evidence references (embeddable library)
2. **Strip Verify** — CI credibility on every PR ← **current wedge**
3. **Strip Lab** — campaigns, calibration, flight analytics
4. **Strip Assurance** — programme-level claim/evidence graph
5. **Strip Exchange** — supplier attestations and review portals

## World-moving levers (ranked)

| Lever | Why it matters |
|-------|----------------|
| Evidence compiler | Process → compiler; scales like LLVM |
| Aerospace CI | Engineering argument stays valid on every PR |
| Certification-delta engine | Aerospace lives on *change*, not first-time cert |
| Model credibility passports | Machine-readable SBOM for models |
| Validation campaign compiler | Research and qualification share one substrate |
| Flight-test foundry | Closes physical–computational loop |
| Open protocol (AeroEvidence) | Hard to compete against shared exchange format |

## Decisive benchmark

```sh
strip campaign run campaigns/reference-uas-contingency.toml
```

Until that command produces an immutable evidence bundle (runs, UQ, counterexamples, claim graph, reproducible report), Strip remains a disciplined prototype — not a validated platform.

See [ROADMAP-1.0.md](../ROADMAP-1.0.md) for the frozen programme.
