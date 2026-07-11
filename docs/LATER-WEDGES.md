# Later product wedges

Date: 2026-07-11  
Status: **scaffolded schemas only** — not product claims.

| Wedge | Schema | Honest status |
|-------|--------|---------------|
| Certification-delta | `schemas/certification-delta.schema.json` (`strip.certification-delta.v0`) | Declares what must be revalidated on change; no engine yet |
| Model credibility passport | `schemas/model-passport.schema.json` (`strip.model-passport.v0`) | Machine-readable applicability + C=(P,V,E,R,G); atmosphere example fixture only |
| Physical HIL bench | — | Current HIL tier uses synthetic `io_loopback`; physical bench not present |
| Flight evidence | — | `flight_test` tier remains **`missing`** until a sealed flight package exists |

`operational_qualification_claimed` is forced `false` on all scaffold artifacts.
