# Sprint 4 — M4 Monetize: Monetization Service Core

> Indicative: 2026-06-15 → 2026-06-29 (~2 weeks). Goal-driven, not date-driven.
> Review mode: **full**. Producer gate **PR-SPRINT: CONCERNS → adjustments adopted**
> (migration corrected v2→v3 ⇒ **v5→v6**; S4-001 + S4-003 share **one** v6 migration;
> S4-004 split into 004a Must / 004b Should; HMAC `age_band` prerequisite **formally
> deferred via ADR** + risk line, not silently ridden onto the first AdService; the
> previously-invisible ADR/milestone/doc work made a **named** Must-Have line item S4-000).
> Confirmed against the codebase: `WalletService` already exposes `initiate_iap()`,
> `_earn_rewarded_ad()`, `is_ad_earn_available()`, `convert_gems_to_coins()`; `SaveData`
> is at schema **v5** with a clean per-step `_migrate` ladder; `RemoteConfigSource` is a
> no-op base designed for M4 subclassing; `ComplianceService` is the sole `age_band` reader.
> Implements GAME_PLAN §§8–12 (IAP / ads / compliance / service interfaces).

## Sprint Goal

Stand up the **monetization service core** — consent/CMP model, `IAPService`, Remove-Ads
`EntitlementService`, and `AdService` — as **pure, DI-injected, mockable** autoloads that
wire into the existing `WalletService` earn/spend call-ins and `ComplianceService` gating,
so the real native SDKs (later, device-tested sprint) and the monetization UI (later,
`/ux-design` sprint) bolt on **without touching transaction or gating logic**. This is the
M4 monetization foundation; the native SDK plugins and all monetization surfaces are their
own scoped work (mock-first, mirroring how M3 deferred UI).

## Capacity

- **Total days**: 10 (1 dev, 2 weeks) · **Buffer (20%)**: 2 · **Available**: 8
- Committed (Must-Have) ≈ **7.5 days** (incl. ~1.25d of ADR/milestone/doc work that the
  first-pass estimate omitted) → thin margin before the buffer, per the producer gate:
  protect the consent model + service seams; AdService cross-gating and the real
  RemoteConfig subclass are the pull-in queue.

## Tasks

### Must Have (Critical Path — consent model + the three monetization service seams)
| ID | Task | Owner | Days | Deps | Acceptance Criteria |
|----|------|-------|------|------|--------------------|
| S4-000 | **Kickoff docs** (M4 paper trail): Hint→Picker ADR (M3 carryover #2); `production/milestones/m4-definition.md`; `production/risk-register/m4-risks.md` (incl. **S2-011 stars carryover** as an owned open line — M3 carryover #3); **consent-model ADR** (incl. the HMAC `age_band` deferral decision); **service-seam ADR** (Ad/IAP/Entitlement interface + mock pattern) | producer + technical-director | 1.25 | — | All 5 files exist; both new ADRs Accepted; Hint→Picker ADR recorded; S2-011 logged as an owned, dated open risk; m4-definition states M4 scope/success criteria/boundaries |
| S4-001 | **Consent / CMP model** (`core/` consent state + SaveData **v5→v6** migration: new `if version == 5:` step + serialize/deserialize the consent fields through the existing dict round-trip): personalized-ads / analytics / IAP-consent flags routed **through `ComplianceService`** (never read directly); CMP *flow* modeled — **not** the vendor UMP SDK | gameplay-programmer | 2.0 | S4-000 (consent ADR) | v5→v6 migration unit test (old save → consent defaults); `from_dict` defaults missing keys; `ComplianceService.can_*` reflect **consent × age_band** (UNKNOWN/no-consent → restricted); integration test driving autoloads |
| S4-002 | **`IAPService` interface + mock backend** (autoload): purchase state machine (pending → success / failed / restored), catalog from config, receipt-restore stub; success → grants currency / Remove-Ads via existing **`WalletService.initiate_iap()`**; **`configure()` DI**, mock injectable | gameplay-programmer | 2.0 | S4-000 (service-seam ADR) | Each state transition unit-tested; mock backend injectable (no real SDK); grant call-in wired to `WalletService`; restore re-grants entitlement; integration test driving the real scene tree + autoloads |
| S4-003 | **Remove-Ads `EntitlementService`** (autoload): persisted entitlement field **on the same v6 migration as S4-001** (extend, do not add a second migration step); restore-across-reinstall stub; disables interstitials; gates `AdService` | gameplay-programmer | 1.0 | S4-001 (shared v6 migration) | Entitlement persists + restores via SaveService; interstitial suppressed when owned; rewarded still allowed when owned; own unit + integration test |
| S4-004a | **`AdService` interface + mock + frequency cap + rewarded earn-in** (autoload): rewarded / interstitial mock; interstitial frequency cap (§9, e.g. every 3–4 levels / ≥60–90s) via **`TimeProvider`** (deterministic); rewarded → existing **`WalletService._earn_rewarded_ad()`**; **`configure()` DI** | gameplay-programmer | 1.5 | S4-000 (service-seam ADR) | Freq-cap honoured (TimeProvider-driven, deterministic, no `Time.*`); rewarded reward reflected in wallet; never offered during active arithmetic; integration test |

> **Sequence (single chain, 1 dev):** S4-000 → S4-001 → S4-003 → S4-002 → S4-004a.
> **Shared-migration rule:** S4-001 establishes SaveData **v6** + consent fields; S4-003
> **extends** the same v6 step with the entitlement field — never a second independent
> migration (collision risk). S4-002 is otherwise independent of the consent chain (its
> `WalletService.initiate_iap()` call-in already exists).
> **Partial-landing safety:** S4-000 + S4-001 + S4-002 alone is already a complete, tested
> slice (consent model + IAP purchase/grant core); the ad path (S4-003/004a) layers on.

### Should Have (pull in with slack)
| ID | Task | Owner | Days | Deps | Acceptance Criteria |
|----|------|-------|------|------|--------------------|
| S4-004b | **`AdService` consent / entitlement cross-gating**: triple gate — `ComplianceService` (audience) + consent (S4-001) + Remove-Ads entitlement (S4-003); contextual-vs-personalized + suppression matrix | gameplay-programmer | 1.0 | S4-004a, S4-001, S4-003 | Ads suppressed / contextual / personalized per each gate combination; integration test matrix covers the gate cross-product |
| S4-005 | **Real `RemoteConfigSource` subclass** (M4 fetch+parse): **injectable transport** (no hard network dependency); remote-wins-when-present / local-wins-when-absent contract; `{}`-on-failure robustness | tools-programmer | 1.5 | RemoteConfigSource base, EconomyConfigLoader | Stub transport proves remote-over-local + fallback deterministically (no network); malformed payload → local defaults |

### Nice to Have (cut first / pull in only with slack)
| ID | Task | Owner | Days | Deps | Acceptance Criteria |
|----|------|-------|------|------|--------------------|
| S4-006 | **IAP catalog / offer config resource** (currency packs, value bundles, Remove-Ads SKU, starter bundle): data-driven + remote-config-loadable | systems-designer | 1.0 | S4-002 | Catalog drives entirely from config; no hardcoded SKUs / prices; remote-config-loadable via S4-005 path |
| S4-007 | **`Analytics` interface seam** + monetization funnel events (IAP funnel, ad impression/reward) to a **mock sink**, **consent-gated** (M5 prep) | gameplay-programmer | 1.0 | S4-001 | Events emitted only when consent allows; mock sink captures the IAP/ad funnel; vendor-agnostic interface |

## HMAC / tamper-resistance decision (producer-flagged, adopted)

`ComplianceService` documents HMAC-signed `age_band` as a prerequisite "before the first
AdService/Analytics ships." S4-004a is the first AdService. **Adopted resolution:** the
consent-model ADR (S4-000) **formally defers** HMAC to the native-SDK sprint with a
documented line in `m4-risks.md` — *not* scoped into Sprint 4, because the mock services
carry no real ad revenue or PII surface yet. Surfaced explicitly, not riding silently onto
the first shipped AdService.

## Carryover from Sprint 3 / M3 kickoff conditions
| Item | Reason | New home |
|------|--------|----------|
| S2-011 efficiency score / stars | Nice-to-Have since Sprint 2; economy/IAP value still tuned on `COINS_WIN_FLAT_FALLBACK` | Logged as an owned open risk in `m4-risks.md` (S4-000); sequence early in M4/M5 |
| Record Hint→Picker (2026-06-13) design change as an ADR | M3 review condition #2 | S4-000 |
| M4 milestone-definition + risk-register files do not exist | M3 review condition #1/#3 — gate the milestone on a definition | S4-000 |

## Risks (→ `production/risk-register/m4-risks.md`, authored in S4-000)
| Risk | Prob | Impact | Mitigation |
|------|------|--------|------------|
| S2-011 stars carryover (3 sprints) → economy / IAP value tuned on flat fallback | Med | Med | Logged as an owned M4 risk; sequence S2-011 early in M4/M5 |
| Native Ad / IAP SDK cannot be tested headlessly in gdUnit4 CI | High (planned) | Low | Mock-first slice; native plugins deferred to a device-tested sprint; everything mockable behind the interface |
| `age_band` tamper-resistance (HMAC) unshipped at first AdService | Med | Med | Formally deferred via the consent ADR + a risk line; mock-only this sprint (no real revenue/PII surface) |
| Shared v5→v6 migration collision if S4-001 / S4-003 sequenced as two independent steps | Med | High | One migration: S4-001 establishes v6, S4-003 extends it; explicit dependency in the sequence |
| Four new services × (mock + state machine + DI + integration test) overruns the 8-day window | Med | Med | S4-004 split (004a Must / 004b Should); cross-gating + real RemoteConfig are the pull-in queue, cut first |

## Dependencies on External Factors
- None blocking. All seams exist in-repo: `WalletService` IAP/ad earn call-ins,
  `ComplianceService` audience gate, `RemoteConfigSource` base, `TimeProvider`, `SaveService`
  migration ladder. **No native SDK dependency this sprint** (mock-first by design).

## Definition of Done for this Sprint
- [ ] All Must-Have tasks completed & passing ACs
- [ ] QA plan exists (`production/qa/qa-plan-sprint-4.md`) — run `/qa-plan sprint`
- [ ] Consent model: `ComplianceService.can_*` reflect consent × age_band; v5→v6 migration tested
- [ ] `IAPService` / `AdService` / `EntitlementService` are pure, DI-injected, mockable; no native SDK dependency
- [ ] Rewarded-ad → wallet earn and IAP → currency/entitlement grant proven via integration test (real scene tree + autoloads)
- [ ] No hardcoded tuning — costs/caps/catalog drive from `EconomyConfig` / config resources
- [ ] All 5 S4-000 docs exist; both new ADRs Accepted; S2-011 logged in `m4-risks.md`
- [ ] Full gdUnit4 suite green in CI; no S1 or S2 bugs in delivered features
- [ ] Design docs updated for any deviations
- [ ] Code reviewed & merged
- [ ] `/team-qa sprint` sign-off: APPROVED or APPROVED WITH CONDITIONS

## Notes
- **Scope check:** if stories are added beyond this list, run `/scope-check` against the M4 scope.
- **Mock-first discipline:** every service ships behind an interface with a mock backend.
  Native Android/iOS SDK plugins, the CMP/UMP vendor SDK, the shop/offer/ad-confirm/banner
  UI (needs `/ux-design`), and the Analytics vendor backend (M5) are explicitly deferred —
  not dropped.
