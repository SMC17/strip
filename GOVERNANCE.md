# Governance

## Evidence before promotion

Every capability starts as `sketch` or `scaffold`. Promotion requires the named
gate and evidence:

- implemented: executable code exists
- unit-tested: isolated invariant/reference tests pass
- integration-tested: a composed workflow passes
- cross-implementation or benchmark: pinned independent evidence passes
- experimental or hardware evidence: the relevant physical setup is identified
- accreditation or certification evidence: an external authority and context
  are referenced; Strip cannot self-issue these labels

A composition inherits the weakest demonstrated evidence of every required
dependency. Missing evidence is never inferred.

## Roles

- implementation proposes code and models
- verification tries to falsify claims and fixtures
- assurance owns claim-to-evidence consistency
- maintainers accept baseline changes
- external authorities own accreditation and certification decisions

The same automated agent must not both propose a change and silently promote
its proof level.

## Change control

Schema meaning, units, coordinate frames, RNG algorithms, event ordering, and
model envelopes are compatibility-sensitive. Breaking changes require a new
schema or model major version and retained migration evidence.
