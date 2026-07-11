# Dispatch and charter ops (domain map)

Date: 2026-07-11  
Status: market-gap map + pipeline sketch — **not** a dispatch product claim.

Asset: [assets/AI_Dispatch_Market_Gaps.pdf](assets/AI_Dispatch_Market_Gaps.pdf)

## Carrier entry points

| Part | Segment | Strip posture |
|------|---------|---------------|
| **91** | GA | Lowest barrier; first learning use case |
| **135** | Charter | Primary pain-point density (duty, weather, FRAT, pressure) |
| **121** | Airline | Airline-specific ops; SWA as research access example only |

## End-to-end charter pipeline (platform candidates)

1. **Sales / lead gen** — intake, CRM
2. **Booking** — end-to-end charter booking side
3. **Crew feasibility** — FAA duty limits + prior-week schedule
4. **Aircraft airworthiness** — certificates, AFM/RFM, W&B, MEL/logs, OSINT part risk
5. **Flight planning / weather** — cost routes (standard) + predictive edge (platform only)
6. **Flight release / go–no-go** — packed briefing; human authority retained
7. **Ground coordination** — FBO, fuel, catering, day-of PAX
8. **Logistics** — crew hotels, ground transport, PAX amenities

Airworthiness checklist reminders (Part 135 context): Form 8100-2 airworthiness,
registration match, current AFM/RFM, weight & balance / equipment list. Predictive
MEL/OSINT patterns are **candidates**, not approved maintenance control.

## AI intervention market gaps (from research PDF)

1. Fragmented information systems  
2. Duty time & legality tracking  
3. Weather decision windows (react 2–6 h when data existed 24–48 h earlier)  
4. Escalation routing & authority  
5. Static risk scoring (FRAT replacement needed: dynamic, multi-factor)  
6. External pressure detection (owner/broker/crew short-circuits)  
7. Aircraft & maintenance pattern recognition  
8. Dispatcher knowledge / institutional memory  
9. Automated customer & broker communication  
10. Regulatory & SMS compliance gaps (unapproved weather/AI sources; no decision audit trail)

## Edge ideas (explicitly non-authoritative)

- ATC-frequency niche signals / NOTAM deltas beyond standard reports  
- 3D crew briefing with pilot remarks + continuous schedule-vs-forecast monitoring  

These belong on the platform plane with OpsSpec-approved sources only when an
operator adopts them. Schema scaffold:
`schemas/dispatch-decision-evidence.schema.json` (`operational_qualification_claimed: false`).

## UAS / drone dispatch

Separate lane from manned Part 91/135/121. See [REFERENCE-UAS.md](../REFERENCE-UAS.md)
for Strip’s reference UAS vertical slice — not drone charter dispatch automation.
