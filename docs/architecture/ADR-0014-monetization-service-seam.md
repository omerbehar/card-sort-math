# ADR-0014: Monetization service seam — thin autoloads behind interfaces with injectable mock backends

## Status
Accepted (2026-06-15 — governs Sprint 4 / M4 Monetize stories S4-002, S4-003, S4-004a/b, S4-007;
authored as part of the S4-000 kickoff paper trail per the PR-SPRINT producer gate). Acceptance
rests on ADR-0005 (audience), ADR-0013 (consent), GAME_PLAN §§8–12, and the author's go-ahead to
stand up the monetization service core mock-first this sprint.

## Date
2026-06-15

## Last Verified
2026-06-15

## Decision Makers
Product owner (omer.behar), technical-director, producer.

## Summary
Every monetization platform service — **`IAPService`**, **`AdService`**, the Remove-Ads
**`EntitlementService`**, and (M5-prep) **`Analytics`** — ships as a **thin autoload behind an
interface with an injectable mock backend** (DI via `configure()`), with **zero real SDK
dependency** in Sprint 4. The native Android/iOS SDK plugins (GDExtension) and the vendor CMP/UMP
SDK are a **separate, device-tested sprint** — justified because the gdUnit4 CI runs **headless**
and native SDKs cannot be exercised headlessly (risk M4-R3). This mirrors how `RemoteConfigSource`
already ships as a **no-op base designed for M4 subclassing**. The services wire into the existing
`WalletService` earn/spend call-ins (`initiate_iap()`, `_earn_rewarded_ad()`,
`convert_gems_to_coins()`) and are gated through `ComplianceService` + consent (ADR-0013) +
entitlement.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Platform / Monetization / Core |
| **Knowledge Risk** | MEDIUM — the *interfaces* are pure GDScript (LOW); the deferred native ad/IAP/UMP SDKs on Godot are fiddly (the reason they are a scoped device-tested sprint, GAME_PLAN §16) |
| **References Consulted** | `autoloads/wallet_service.gd` (call-ins `initiate_iap()`, `_earn_rewarded_ad()`, `is_ad_earn_available()`, `convert_gems_to_coins()`; `configure()` DI pattern; `economy_event` signal); `autoloads/compliance_service.gd`; `autoloads/remote_config_source.gd` (the no-op-base / M4-subclass precedent); ADR-0009 (`TimeProvider` seam); ADR-0008 (`EconomyEvent`); ADR-0013 (consent); ADR-0005 (audience); GAME_PLAN §§8–12; `production/sprints/sprint-04.md`; `production/risk-register/m4-risks.md` (M4-R3) |
| **Post-Cutoff APIs Used** | None (native SDKs deferred) |
| **Verification Required** | Per-service: state-transition unit tests against the mock backend; an integration test driving the real scene tree (`scenes/main/main.tscn` + autoloads) proving rewarded-ad → wallet earn and IAP → currency/entitlement grant; frequency-cap determinism via injected `TimeProvider`. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0013 (consent verdicts the services gate on), ADR-0005 (audience gate), ADR-0008 (`EconomyEvent` — services emit/trigger economy outcomes via `WalletService`), ADR-0009 (`TimeProvider` — deterministic frequency cap), ADR-0001 (model/view seam — services are node-level autoloads, no game state in UI), ADR-0004 (typed + gdUnit4) |
| **Enables** | The M4 monetization service core: `IAPService` (S4-002), `EntitlementService` (S4-003), `AdService` (S4-004a/b), `Analytics` seam (S4-007); the IAP catalog config (S4-006) |
| **Blocks** | S4-002 / S4-003 / S4-004a / S4-007 cannot start until this is Accepted; the native-SDK sprint and the monetization UI sprint bolt onto the interfaces defined here |
| **Ordering Note** | Second of the two S4-000 monetization ADRs; depends on ADR-0013's consent verdicts. Sprint sequence: S4-000 → S4-001 → S4-003 → S4-002 → S4-004a. |

## Context

### Problem Statement
M4 must stand up four platform services (IAP, ads, Remove-Ads entitlement, analytics) that move
real money and (eventually) real PII. GAME_PLAN §12 mandates each be "a thin platform wrapper …
each mockable for tests & editor," and §16 flags native ad/IAP SDKs on Godot as fiddly enough to
abstract behind interfaces and spike early. The open question S4-000 must settle: **what is the
uniform shape of these services, and what ships in Sprint 4 vs. the native sprint?** — given that
gdUnit4 CI is headless and a native SDK cannot run there.

### Current State
- `WalletService` is the economy chokepoint and already exposes the monetization **call-ins** the
  services will drive: `initiate_iap(sku)` (compliance-gated stub — "IAPService integration is
  deferred to M4"), `_earn_rewarded_ad(amount)` (compliance + daily-cap gated rewarded earn),
  `is_ad_earn_available()`, and `convert_gems_to_coins()`. It uses the project's `configure()` DI
  pattern and emits the single typed `economy_event` (ADR-0008).
- `ComplianceService` gates on `age_band` (ADR-0005); ADR-0013 extends it with consent × age_band.
- `RemoteConfigSource` is a **no-op base** whose docstring states "**M4 subclasses this**" — the
  exact pattern (testable seam now, native fetch later) we generalise here.
- `TimeProvider` (ADR-0009) is the injectable clock for deterministic time-based logic.
- No `IAPService`, `AdService`, `EntitlementService`, or `Analytics` exist yet.

### Constraints
- **Headless CI (risk M4-R3):** the gdUnit4 suite runs headless; native Android/iOS ad/IAP/UMP
  SDKs cannot be exercised there. Whatever ships in Sprint 4 must be **fully testable headlessly**.
- **Model/view seam (ADR-0001):** services are node-level autoloads that emit signals; **no game
  state may live in or be mutated by UI** — the monetization UI (deferred) will request via
  signals, exactly like the rest of the view layer.
- **No new economy mutation paths (ADR-0008):** services must route currency/entitlement outcomes
  through the existing `WalletService` call-ins, not invent a parallel wallet mutation.
- **Determinism (gameplay-code rule):** any time-based behaviour (interstitial frequency cap)
  must use the injected `TimeProvider`, never `Time.*` / global clocks.
- **No hardcoded tuning:** SKUs, prices, caps, and frequency windows drive from config
  (`EconomyConfig` / a catalog resource), never inline.

### Requirements
- A uniform service shape: **interface + injectable mock backend + `configure()` DI**, zero real
  SDK in Sprint 4.
- IAP purchase as a deterministic **state machine** (pending → success / failed / restored), with
  receipt-restore re-granting **non-consumables only**.
- Rewarded ads → `WalletService._earn_rewarded_ad`; interstitials frequency-capped via
  `TimeProvider`; never offered during active arithmetic (GAME_PLAN §9).
- Remove-Ads entitlement persisted, restorable, suppressing interstitials while keeping rewarded
  available; it gates `AdService`.
- Analytics seam (M5 prep) emitting monetization funnel events to a mock sink, consent-gated.

## Decision

### 1. Uniform seam: interface + injectable mock backend + `configure()` DI
Each service is a **thin autoload** that owns no SDK code directly. It talks to a **backend
interface** (a `RefCounted` base, e.g. `IAPBackend` / `AdBackend`); the **mock backend** is the
default and the test double. The real native backend is a *future* subclass injected later —
exactly the `RemoteConfigSource` pattern ("no-op base, M4 subclasses this, inject via
`configure()`, zero changes to the consumer"). DI is the existing project `configure()` idiom
(as on `WalletService` / `ComplianceService`): tests inject a mock + a `TimeProvider`; normal play
resolves to the mock backend in `_ready()` this sprint, and to the native backend once it ships.

```gdscript
# pattern (per service)
class_name AdBackend extends RefCounted        # interface base (mock is the default subclass)
# AdService (autoload):
func configure(backend: AdBackend, wallet: Object, compliance: Object, time: TimeProvider) -> void
```

### 2. `IAPService` (S4-002) — purchase state machine + receipt restore
A deterministic state machine: **pending → success / failed / restored**. On `success`, the
service grants via the existing **`WalletService.initiate_iap()`** call-in (currency packs →
currency; Remove-Ads SKU → `EntitlementService`). The catalog drives from config (S4-006), never
hardcoded SKUs. **Receipt-restore re-grants non-consumables only** (Remove-Ads and other
entitlements) — consumable currency packs are *not* re-granted on restore (they were already
spent/credited). The mock backend simulates each transition deterministically; no store SDK.

### 3. `EntitlementService` (S4-003) — Remove-Ads, on the shared v6 migration
A persisted Remove-Ads entitlement field added on the **same v6 migration as ADR-0013's consent
fields** (extend the single v6 step — never a second migration; risk M4-R4). It exposes whether
Remove-Ads is owned, suppresses **interstitials** when owned while **leaving rewarded available**
(GAME_PLAN §8: Remove-Ads keeps optional rewarded), restores across reinstall via the IAP receipt-
restore stub, and **gates `AdService`**.

### 4. `AdService` (S4-004a/b) — rewarded earn-in, interstitial frequency cap, triple gate
- **Rewarded** → routes the reward through **`WalletService._earn_rewarded_ad()`** (which already
  carries the compliance + daily-cap policy, ADR-0008); never offered during active arithmetic.
- **Interstitial frequency cap** (GAME_PLAN §9: e.g. every 3–4 levels, ≥60–90s apart) computed via
  the injected **`TimeProvider`** — fully deterministic, no `Time.*`.
- **Triple gate** (S4-004b): an ad's mode is the cross-product of `ComplianceService` (audience) ×
  **consent** (ADR-0013) × **Remove-Ads entitlement** (S4-003) — suppressed / contextual /
  personalized per the matrix. The audience+consent half is just the `ComplianceService.can_*`
  verdicts from ADR-0013; entitlement suppresses interstitials on top.

### 5. `Analytics` (S4-007, M5 prep) — funnel events to a mock sink, consent-gated
A vendor-agnostic interface emitting the IAP/ad monetization funnel to a **mock sink**, emitting
**only when consent allows** (`ComplianceService.can_collect_personal_data()`). The real vendor
backend is M5.

### 6. What Sprint 4 explicitly defers
- The **native Android/iOS ad/IAP SDK plugins** (GDExtension) — device-tested sprint (M4-R3).
- The **vendor CMP/UMP + iOS ATT SDK** (the consent *prompt*) — same native sprint (ADR-0013).
- **HMAC `age_band` signing** — native sprint (ADR-0013 / M4-R2).
- **All monetization UI** (shop, offer surface, ad-confirm, banner) — `/ux-design` sprint.
- The **Analytics vendor backend** — M5.

The mocks built this sprint **become the permanent test doubles**: when the native backends land,
the mock backends remain as the headless CI doubles behind the same interface.

### Architecture

```
                         ┌──────── ComplianceService (audience × consent, ADR-0005/0013) ────────┐
                         │                                                                        │
  IAPService ──grant──▶ WalletService.initiate_iap()          AdService ──reward──▶ WalletService._earn_rewarded_ad()
     │  state machine     (existing call-in)                     │  rewarded                       (existing call-in)
     │  pending→success/failed/restored                          │  interstitial freq-cap ◀── TimeProvider (ADR-0009)
     │  receipt restore → non-consumables only                   │  triple gate: compliance × consent × entitlement
     ▼                                                           ▼
  EntitlementService (Remove-Ads, persisted on shared v6) ──gates──┘
                         │
  Analytics (mock sink, consent-gated) ◀── funnel events (IAP / ad impression+reward)   [M5 vendor backend deferred]

  Each service = thin autoload ─▶ Backend interface (RefCounted)
                                    ├─ MockBackend  (ships now; permanent CI double)
                                    └─ NativeBackend (deferred; injected via configure())   ← mirrors RemoteConfigSource
```

### Implementation Guidelines
- **Interface + mock per service**, default to the mock in `_ready()`, swap via `configure()` —
  the `RemoteConfigSource` precedent; zero consumer changes when the native backend lands.
- **IAP state machine**: explicit transitions pending → success / failed / restored; each
  transition unit-tested against the mock; success wires to `WalletService.initiate_iap()`;
  **restore re-grants non-consumables only**.
- **Rewarded** → `WalletService._earn_rewarded_ad()` (do not re-implement the cap/compliance
  policy that already lives there); **never** offered during active arithmetic.
- **Interstitial frequency cap** via `TimeProvider` (deterministic, no `Time.*`); window values
  from config, not inline.
- **Triple gate** (S4-004b) is `ComplianceService` verdict (audience × consent, ADR-0013) ×
  `EntitlementService` (interstitial suppression) — no service reads `age_band` or a consent field
  directly.
- **Model/view seam preserved**: services are node-level autoloads emitting signals; no game state
  in UI; the (deferred) monetization UI requests via signals.
- **No hardcoded tuning**: SKUs/prices from the catalog resource (S4-006); caps/windows from
  `EconomyConfig`.
- **Validation (project mandate)**: each service needs unit tests (state machine / gating) **and**
  an integration test driving `scenes/main/main.tscn` + autoloads proving the end-to-end wiring;
  screenshots are not applicable to these headless service seams (no UI this sprint).

## Alternatives Considered

### Alternative 1: Integrate the real native SDKs now (no mock layer)
- **Description**: Ship `AdService`/`IAPService` directly on the Android/iOS ad/IAP SDKs.
- **Pros**: Real end-to-end monetization sooner.
- **Cons**: Native SDKs cannot be tested in the headless gdUnit4 CI (risk M4-R3); the whole M4
  slice would be unverifiable in CI; native plugin work is fiddly (GAME_PLAN §16) and belongs in
  a device-tested sprint; couples the core game to vendor SDKs the §9/§12 abstraction forbids.
- **Rejection Reason**: Breaks the CI merge gate and the vendor-abstraction mandate. Mock-first
  keeps the seam testable now; the SDK is a swap-in.

### Alternative 2: One monolithic `MonetizationService`
- **Description**: A single autoload owning IAP + ads + entitlement + analytics.
- **Pros**: Fewer files.
- **Cons**: Conflates four distinct lifecycles (purchase state machine, ad frequency cap,
  persisted entitlement, analytics sink) and four backends with different deferral timelines;
  a fat service is harder to mock per-concern and to gate independently; contradicts §12's "each
  behind a clean interface/autoload."
- **Rejection Reason**: Violates single-responsibility and the per-service mockability §12
  requires; the cross-gating (triple gate) is clearer as composition of small services.

### Alternative 3: Services bypass `WalletService` and mutate the wallet directly
- **Description**: `IAPService`/`AdService` write coins/gems/entitlement themselves.
- **Pros**: Fewer hops.
- **Cons**: Creates a second wallet-mutation path outside the ADR-0008 economy chokepoint
  (atomicity, caps, daily limits, `economy_event` telemetry all live in `WalletService`); the
  existing `initiate_iap()` / `_earn_rewarded_ad()` call-ins exist precisely so monetization flows
  through one policy layer.
- **Rejection Reason**: Bypasses the economy chokepoint and its policy/telemetry; the call-ins are
  the sanctioned seam.

## Consequences

### Positive
- Every monetization service is fully testable headlessly in CI this sprint (mock backends);
  native SDKs become a swap-in behind the same interface (the `RemoteConfigSource` guarantee).
- Currency/entitlement outcomes flow through the existing `WalletService` policy layer — no
  parallel wallet path; telemetry via the single `economy_event`.
- Composable gating: audience × consent × entitlement is a composition of small services, each
  independently testable.
- The mocks are not throwaway — they are the permanent CI doubles.

### Negative / accepted trade-offs
- **Real monetization is not wired this sprint** — only the mock-backed core. Accepted and
  explicit: native SDK, CMP/UMP, HMAC, and all monetization UI are deferred (not dropped). This is
  the same mock-first discipline M3 used to defer UI.
- **Four services + four mock backends + an interface each** to maintain. Accepted: the uniform
  pattern + the `configure()` idiom keep it mechanical; per-service mockability is required by §12.
- **The triple gate adds a cross-product of cases** to test (S4-004b). Accepted: covered by an
  integration test matrix; the audience×consent half is already centralised in `ComplianceService`.

### Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Native ad/IAP SDK cannot be headless-tested | High (planned) | Low | M4-R3: mock-first slice; native plugins to a device-tested sprint; mock is the permanent CI double behind the interface |
| A service mutates the wallet outside `WalletService` | Low | High | Services route only through `initiate_iap()` / `_earn_rewarded_ad()`; review + the ADR-0008 economy-chokepoint rule |
| Interstitial cap drifts non-deterministically | Low | Med | `TimeProvider`-driven (ADR-0009); no `Time.*`; deterministic unit test |
| Receipt-restore re-grants a consumable | Low | Med | Restore re-grants **non-consumables only**; explicit test asserts a currency pack is *not* re-granted |
| A service reads `age_band`/consent directly, bypassing the gate | Med | High | All gating via `ComplianceService.can_*` (ADR-0013) + `EntitlementService`; single-reader invariant |

## Validation Criteria
- [ ] Each service is a thin autoload with an interface + injectable mock backend via
      `configure()`; **no real SDK dependency** anywhere in Sprint 4.
- [ ] `IAPService` state machine: each transition (pending → success / failed / restored)
      unit-tested against the mock; success grants via `WalletService.initiate_iap()`; restore
      re-grants **non-consumables only**.
- [ ] `EntitlementService` persists Remove-Ads on the **shared v6 migration** (not a second
      step), restores across reinstall (stub), suppresses interstitials while leaving rewarded
      available, and gates `AdService`.
- [ ] `AdService`: rewarded reward reflected in the wallet via `_earn_rewarded_ad()`; interstitial
      frequency cap honoured deterministically via `TimeProvider` (no `Time.*`); never offered
      during active arithmetic; the triple gate (compliance × consent × entitlement) matrix tested.
- [ ] `Analytics` seam emits funnel events to a mock sink only when consent allows.
- [ ] An integration test drives `scenes/main/main.tscn` + autoloads proving rewarded-ad → wallet
      earn and IAP → currency/entitlement grant end-to-end.
- [ ] No hardcoded SKUs / prices / caps — all from config.

## GDD Requirements Addressed

| GDD / Plan | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| GAME_PLAN §8 | Remove-Ads anchor; IAP catalog; Remove-Ads disables non-rewarded ads, keeps rewarded, persists across reinstall | `EntitlementService` (suppress interstitials, keep rewarded, restore); `IAPService` catalog from config |
| GAME_PLAN §9 | Rewarded → boosters/currency; interstitial frequency-capped, never mid-puzzle; abstract behind `AdService`; CMP/limited-ads | `AdService` rewarded earn-in + `TimeProvider` cap + triple gate; vendor SDK + CMP deferred |
| GAME_PLAN §11 | Instrument behind an `Analytics` interface, vendor-agnostic | `Analytics` mock-sink seam (M5 vendor backend deferred) |
| GAME_PLAN §12 | Each platform service a thin wrapper, mockable for tests/editor, no vendor dependency in core | Interface + mock + `configure()` DI per service; native backend a swap-in |
| sprint-04.md S4-002/003/004/007 | Mock-first DI services wiring into `WalletService` call-ins + `ComplianceService` gating | Exactly this seam; native SDK/UI/Analytics-vendor deferred |

## Performance Implications
- **CPU**: mock backends are in-memory state machines invoked at purchase/ad-decision points
  (event-frequency, never per-frame). The frequency-cap check is a couple of `TimeProvider` reads.
  Negligible.
- **Memory**: four small autoloads + their mock backends; a handful of fields each. Trivial.
- **Load Time**: four extra autoloads at boot; thin (no SDK init). Negligible.
- **Network**: none this sprint (native SDKs that would add network are deferred).

## Migration Plan
1. Add the backend interface bases (`RefCounted`) + mock backends for IAP / Ad / (Analytics);
   default to the mock in each service's `_ready()`, swap via `configure()`.
2. `IAPService` autoload: purchase state machine + catalog (config) + receipt-restore (non-
   consumables only); wire success to `WalletService.initiate_iap()`.
3. `EntitlementService` autoload: Remove-Ads field on the **shared v6 migration** (ADR-0013);
   restore stub; interstitial suppression; gate `AdService`.
4. `AdService` autoload: rewarded → `WalletService._earn_rewarded_ad()`; interstitial cap via
   `TimeProvider`; triple gate (S4-004b).
5. `Analytics` seam (S4-007): mock sink, consent-gated.
6. Unit tests per service + an integration test on `scenes/main/main.tscn` + autoloads.
7. Defer to later sprints: native ad/IAP plugins, vendor CMP/UMP + ATT, HMAC `age_band`, all
   monetization UI, the Analytics vendor backend — each behind the interfaces defined here.

## Related Decisions
- ADR-0013 (consent / CMP model — the verdicts these services gate on), ADR-0005 (audience),
  ADR-0008 (`EconomyEvent` + the `WalletService` economy chokepoint), ADR-0009 (`TimeProvider`),
  ADR-0001 (model/view seam), ADR-0004 (typed + gdUnit4).
- `autoloads/wallet_service.gd` (`initiate_iap()`, `_earn_rewarded_ad()`, `is_ad_earn_available()`,
  `convert_gems_to_coins()`); `autoloads/remote_config_source.gd` (the no-op-base / M4-subclass
  precedent generalised here); `production/risk-register/m4-risks.md` (M4-R3); GAME_PLAN §§8–12;
  `production/sprints/sprint-04.md` (S4-002/003/004/007).
