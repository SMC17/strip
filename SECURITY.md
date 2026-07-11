# Security and Use Boundary

## Public build

The public Strip build permits education, research, preliminary design, and
simulation training. It does not provide operational flight control,
certification or accreditation decisions, weapon employment, targeting,
sensitive signatures, or controlled mission data.

Public defense-facing types are restricted to generic resilience, sensing
quality, communications degradation, readiness, logistics, and bounded
safe-state responses.

## Trust boundaries

- Inputs are untrusted until parsed, unit/frame checked, and envelope checked.
- External adapters are unavailable by default and run outside authoritative
  physics when linked.
- AI agents receive explicit capabilities; simulation permission does not imply
  publication or baseline-promotion permission.
- Learned models cannot promote their own evidence or validity.
- Result identity binds content via SHA-256 digests.
- Evidence and campaign bundles are Ed25519-attested under the committed CI
  development key (`fixtures/signing/`). That key is not a production HSM or
  organizational signing authority.
- No network dependency belongs in a safety-critical or authoritative loop.

## Reporting

Report vulnerabilities through GitHub private vulnerability reporting when
enabled. Do not include controlled, export-restricted, proprietary, or
operational mission data in public issues.
