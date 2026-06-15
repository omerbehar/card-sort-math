# Milestone Definition: M4 — Monetize (Monetization Service Core)

> Authored 2026-06-15 at M4 kickoff (Sprint 4 story S4-000), closing M3 milestone
> review action item #1 (define M4 before sprint execution). Unlike M3 — whose
> definition was back-filled after the fact — M4 is defined up front, with the
> milestone gated on a definition before sprint planning. This document records
> M4's intended scope, success criteria, and boundaries as the acceptance baseline.

## Relationship to GAME_PLAN

GAME_PLAN §15 lists **M4 — Monetize** (IAP, ads + mediation, currency, remote
config, CMP), elaborated across §§8–12: IAP catalog + Remove-Ads anchor (§8);
rewarded/interstitial ads, mediation, and the `AdService` abstraction (§9); the
`ComplianceService` consent/age-band seam and CMP/UMP (§10); the vendor-agnostic
`Analytics` interface (§11); and the "each behind a clean interface/autoload,
each mockable" service architecture (§12). M4 is the **monetization foundation**
that bolts onto the M3 Deck Economy core: the `WalletService` earn/spend call-ins
already exist (`initiate_iap()`, `_earn_rewarded_ad()`, `is_ad_earn_available()`),
and `ComplianceService` is the sole `age_band` reader. This milestone deliberately
builds only the **service core** — the native SDK plugins and all monetization UI
surfaces are their own scoped work. So M4 is delivered in slices; the monetization
service core (Sprint 4) is the first and the load-bearing one, exactly as M3
delivered the economy core then deferred its UI.

## Goal

Stand up the **monetization service core** — consent/CMP model, `IAPService`,
Remove-Ads `EntitlementService`, and `AdService` — as **pure, DI-injected,
mockable** autoloads behind the mandatory model/view + `ComplianceService` seam,
wired into the existing `WalletService` earn/spend call-ins, so the native ad/IAP
SDKs (later, device-tested sprint) and the monetization UI (later, `/ux-design`
sprint) bolt on **without touching transaction or gating logic**. Mock-first by
design: every service ships behind an interface with a mock backend, carrying no
real ad revenue or PII surface until the native sprint.

## In Scope (monetization service-core slice — Sprint 4)

- Consent / CMP **model** (`core/` consent state) + SaveData **v5→v6** migration:
  personalized-ads / analytics / IAP-consent flags, routed **through
  `ComplianceService`** (never read directly). CMP *flow* modeled — not the vendor
  UMP SDK.
- `IAPService` interface + **mock backend** (autoload): purchase state machine
  (pending → success / failed / restored), catalog from config, receipt-restore
  stub; success → grants currency / Remove-Ads via existing
  `WalletService.initiate_iap()`; `configure()` DI, mock injectable.
- Remove-Ads `EntitlementService` (autoload): persisted entitlement on the **same
  v6 migration** (extend, not a second step); restore-across-reinstall stub;
  disables interstitials; gates `AdService`.
- `AdService` interface + **mock** (autoload): rewarded / interstitial mock;
  interstitial **frequency cap** (§9) via `TimeProvider` (deterministic); rewarded
  → existing `WalletService._earn_rewarded_ad()`; **triple-gate** cross-check
  (`ComplianceService` audience × consent × Remove-Ads entitlement); `configure()` DI.
- Real `RemoteConfigSource` subclass (M4 fetch+parse) with **injectable transport**
  (no hard network dependency): remote-wins-when-present / local-wins-when-absent /
  `{}`-on-failure robustness.
- IAP catalog / offer **config resource** (currency packs, value bundles,
  Remove-Ads SKU, starter bundle): data-driven + remote-config-loadable.
- `Analytics` interface **seam** + consent-gated monetization funnel events to a
  mock sink (M5 prep).

Delivered as a **mock-first slice**, exactly as M3 delivered the economy core then
deferred its UI. S4-000 + S4-001 + S4-002 alone is already a complete, tested
slice (consent model + IAP purchase/grant core); the ad path layers on.

## Out of Scope (deferred — explicitly, not dropped)

| Deferred | Home |
|----------|------|
| Native Android/iOS Ad & IAP SDK plugins (GDExtension wrappers) | Native, device-tested sprint (cannot be headless-tested in CI) |
| CMP / UMP vendor SDK (consent *flow* is modeled this sprint) | Native sprint, alongside iOS ATT |
| Shop / offer / ad-confirm / banner UI | Monetization UI sprint (needs `/ux-design`) |
| `Analytics` vendor backend (interface seam only this sprint) | M5 — Instrument |
| HMAC `age_band` tamper-resistance | Native sprint — formally deferred via ADR-0013 (mock services carry no real revenue/PII) |
| Stars-weighted earn (40/55/75) | Carryover S2-011; flat `COINS_WIN_FLAT_FALLBACK` used until it lands |

## Success Criteria (acceptance baseline)

1. `IAPService`, `AdService`, `EntitlementService` are **pure, DI-injected,
   mockable** behind interfaces — no native SDK dependency; mock backends
   injectable via `configure()`.
2. Consent × age_band gating routes through `ComplianceService` (`can_*` reflect
   the combination; UNKNOWN / no-consent → restricted); never read directly.
3. SaveData **v5→v6** migration tested (old save → consent + entitlement defaults;
   `from_dict` defaults missing keys) — one migration shared by S4-001/S4-003.
4. Rewarded-ad → `WalletService` earn and IAP → currency/entitlement grant proven
   via integration tests driving the real scene tree + autoloads.
5. No hardcoded tuning — costs / caps / catalog / SKUs drive from `EconomyConfig`
   and config resources; frequency cap is `TimeProvider`-driven (no `Time.*`).
6. Model/view split and the solvability invariant remain intact.
7. Full gdUnit4 suite green in CI.

## Dependencies

- **Upstream**: `WalletService` (IAP/ad earn-spend call-ins — present),
  `ComplianceService` (`age_band` + audience gate — sole reader, present),
  `RemoteConfigSource` no-op base (designed for M4 subclassing — present),
  `TimeProvider` (deterministic clock — present), `SaveService` migration ladder
  (at schema v5 — present). **No native SDK dependency this milestone** (mock-first).
- **Downstream (this milestone enables)**: native Ad/IAP SDK plugins (bolt onto
  the interfaces); monetization UI (shop/offers/ad-confirm — consumes the service
  seams); M5 analytics (the `Analytics` interface seam + consent gate).
- **Cross-milestone carryover**: S2-011 stars/efficiency score — until it lands,
  economy/IAP value remains tuned on the documented flat `COINS_WIN_FLAT_FALLBACK`
  (tracked in `production/risk-register/m4-risks.md`).

## Ratifying ADRs

- **ADR-0013** — consent / CMP model (incl. the HMAC `age_band` tamper-resistance
  deferral decision).
- **ADR-0014** — monetization service-seam (Ad/IAP/Entitlement interface + mock
  pattern, `configure()` DI).
- **ADR-0012** — Hint→Picker design change (M3 review carryover #2, recorded at M4
  kickoff in S4-000).
- Builds on **ADR-0005** — general-audience (13+) age-gated positioning, which
  drives the entire ad/IAP/consent posture (§§8–10).

## Sprints

- **Sprint 4** (`production/sprints/sprint-04.md`) — Monetization service core.
  Status: **in progress** (kicked off 2026-06-15).

## Status

**In progress** (Sprint 4 kicked off 2026-06-15). Remaining M4 slices — native
Ad/IAP SDK plugins (device-tested sprint), CMP/UMP vendor SDK, and monetization UI
(`/ux-design` sprint) — are not yet scheduled.
