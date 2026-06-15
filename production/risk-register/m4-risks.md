# Risk Register — M4 Monetize (Monetization Service Core)

> Stood up at M4 kickoff 2026-06-15 (Sprint 4 story S4-000) per the PR-SPRINT
> producer gate, closing M3 milestone review action item #3 (carry the S2-011
> stars dependency into the M4 risk register as an open, owned line). M4's central
> risk shape is that the four new services ship **mock-first** behind interfaces —
> so the gating, migration, and SDK-deferral risks are tracked here, not buried in
> the sprint plan. Mirrors the M3 review Risk Assessment carryover.

| # | Risk | Prob | Impact | Owner | Mitigation | Status |
|---|------|------|--------|-------|-----------|--------|
| M4-R1 | **S2-011 stars carryover (3 sprints)** — economy / IAP value still tuned on the flat `COINS_WIN_FLAT_FALLBACK` placeholder rather than stars-weighted earn (40/55/75); monetization balancing built on a known-temporary number. | Med | Med | producer | Flat fallback documented + flagged in code (`data/economy_config.gd`, `autoloads/wallet_service.gd`); sequence S2-011 **early in M4/M5** before IAP pricing/value tuning hardens. (M3 review action item #3.) | **OPEN** |
| M4-R2 | **HMAC `age_band` tamper-resistance deferred** — `ComplianceService` names HMAC-signed `age_band` as a prerequisite "before the first AdService/Analytics ships"; S4-004a is the first AdService and ships unsigned (mock). | Med | Med | technical-director | **Formally deferred via ADR-0013** — mock-only this sprint (no real ad revenue or PII surface yet), surfaced explicitly rather than riding silently onto the first shipped AdService. **Must ship before the native AdService.** | **OPEN-DEFERRED** |
| M4-R3 | **Native Ad / IAP SDK cannot be headless-tested** in the gdUnit4 CI suite — real network/device SDKs are not exercisable headlessly. | High (planned) | Low | technical-director | **Mock-first slice**: every service ships behind an interface with an injectable mock backend; native plugins deferred to a **device-tested sprint**. The mock seam is the thing CI proves; the native SDK is a swap-in. | **ACCEPTED** |
| M4-R4 | **Shared v5→v6 migration collision** — if S4-001 (consent fields) and S4-003 (Remove-Ads entitlement) are sequenced as two independent migration steps, the second clobbers / re-versions the first. | Med | High | gameplay-programmer | **One migration**: S4-001 establishes SaveData **v6** + the consent fields; S4-003 **extends** the same v6 step with the entitlement field — never a second independent `_migrate` step. Enforced by the explicit S4-001 → S4-003 dependency in the Sprint 4 sequence. | **MITIGATED-BY-SEQUENCE** |
| M4-R5 | **Four new services × (mock + state machine + DI + integration test) overruns the 8-day window** — committed Must-Have ≈ 7.5d leaves a thin margin before the 20% buffer. | Med | Med | producer | S4-004 split (004a Must / 004b Should); `AdService` cross-gating (S4-004b) + the real RemoteConfig subclass (S4-005) are the **pull-in queue, cut first**. Re-plan at sprint mid-point (`/sprint-status`). | **OPEN** |

## Review cadence

Re-check at **sprint mid-point** (`/sprint-status`) and at the M4 milestone
review. Close risks as their mitigating stories land:

- **M4-R1** closes when S2-011 ships and earn moves off `COINS_WIN_FLAT_FALLBACK`
  (spans into M5 — carries forward if unclosed).
- **M4-R2** stays OPEN-DEFERRED through Sprint 4; **must** close before the native
  AdService sprint (HMAC `age_band` signing shipped).
- **M4-R3** remains ACCEPTED for the life of the mock-first slice; revisited at the
  native-SDK sprint.
- **M4-R4** verified closed once the single v6 migration round-trip test (consent +
  entitlement) is green.
- **M4-R5** closes at sprint end once the Must-Have chain lands within the buffer.
