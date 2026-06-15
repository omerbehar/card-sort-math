# ADR-0013: Consent / CMP model — consent fields in `SaveData`, gated through `ComplianceService` (consent × age_band)

## Status
Accepted (2026-06-15 — governs Sprint 4 / M4 Monetize story S4-001; authored as part of the
S4-000 kickoff paper trail per the PR-SPRINT producer gate). Acceptance rests on ADR-0005
(audience positioning) + the GAME_PLAN §§9–10 compliance posture + the author's go-ahead to
implement the consent model this sprint.

## Date
2026-06-15

## Last Verified
2026-06-15

## Decision Makers
Product owner (omer.behar), technical-director, producer; builds on security-engineer +
creative-director inputs to ADR-0005.

## Summary
Model **consent state** (personalized-ads consent, analytics consent, IAP consent) as plain,
node-free fields persisted in [SaveData] via a **v5→v6 schema migration**, and route every
gating decision **exclusively through `ComplianceService`** — never by reading a consent field
directly. The verdict for each capability is the conjunction **consent × age_band**: permissive
only when the player is `ADULT` *and* the relevant consent is granted; `UNKNOWN` / `CHILD` or a
denied/absent consent yields the restrictive verdict. This ADR models the CMP **flow** (capture,
withdrawal, re-presentation) as pure state behind the existing compliance seam; the **vendor UMP
SDK** (GDPR consent UI, iOS ATT prompt) is deferred to the native-SDK sprint.

It also records, as a conscious owned decision, the **deferral of HMAC / `age_band`
tamper-resistance** to that same native-SDK sprint (risk M4-R2).

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Privacy / Compliance |
| **Knowledge Risk** | MEDIUM — relies on COPPA/GDPR-K + GDPR/UMP consent semantics; verify the vendor consent strings + ATT behaviour on device with legal before the native sprint |
| **References Consulted** | ADR-0005 (audience positioning, the `can_*` chokepoint); `autoloads/compliance_service.gd` (the sole `age_band` reader); `core/save_data.gd` (schema v5, per-step `_migrate` ladder, `_parse_*` guards); `design/gdd/save-service.md` (Core Rule 6, Edge Case 9, AgeBand ordinal contract); GAME_PLAN §§9–10; `production/sprints/sprint-04.md` (S4-001); `production/risk-register/m4-risks.md` (M4-R2, M4-R4) |
| **Post-Cutoff APIs Used** | None (the vendor UMP/ATT SDK is out of scope here) |
| **Verification Required** | v5→v6 migration unit test (old save → conservative consent defaults); a `ComplianceService` test proving `can_*` reflect consent × age_band across the full cross-product; an integration test driving the autoloads. Legal review of the consent taxonomy before the vendor UMP SDK ships. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0005 (audience positioning + the `ComplianceService` chokepoint this extends), ADR-0001 (consent state is pure, node-free `SaveData`), ADR-0004 (typed GDScript + gdUnit4) |
| **Enables** | The consent-aware `ComplianceService.can_*` verdicts that `AdService` (S4-004a/b), `IAPService` (S4-002), and `Analytics` (S4-007, M5 prep) query; the monetization service seam of ADR-0014 |
| **Blocks** | S4-001 cannot start until this is Accepted; S4-003 shares the same v6 migration; S4-004b's triple gate consumes the consent verdicts defined here |
| **Ordering Note** | First of the two S4-000 monetization ADRs. ADR-0014 (service seam) depends on the consent verdicts defined here. S4-001 establishes the v6 schema; S4-003 extends the *same* v6 step (M4-R4 collision rule). |

## Context

### Problem Statement
ADR-0005 settled the *audience* axis (`age_band`: UNKNOWN / ADULT / CHILD) and centralised it in
`ComplianceService` as the single `age_band` reader. Monetization adds a second, orthogonal axis:
**consent**. Even a declared adult may decline personalized ads, analytics, or (in some regimes)
IAP data processing. GAME_PLAN §9 requires a CMP for GDPR/UMP consent + iOS ATT, and "limited
ads" when consent is denied. The open questions S4-001 must settle: **where does consent state
live, how is it gated, and how does it combine with `age_band`?** — without leaking a second
"read the field directly" path that re-introduces the `== CHILD`-instead-of-`!= ADULT` class of
bug ADR-0005's chokepoint exists to prevent.

### Current State
- `ComplianceService` (`autoloads/compliance_service.gd`) is the **sole** reader of
  `SaveData.age_band`; its `can_collect_personal_data()` / `can_show_targeted_ads()` /
  `can_use_advertising_id()` are all keyed on `is_adult()` (`== ADULT`), so UNKNOWN and CHILD
  fall through to the restrictive verdict. Its docstring flags HMAC-signed `age_band` as a
  prerequisite "before the first AdService/Analytics ships."
- `SaveData` is at schema **v5** with a clean per-step `_migrate` ladder (v1→v2→…→v5) and
  conservative `_parse_*` guards (a JSON `null` never crashes; out-of-range coerces to the safe
  value). There are **no consent fields yet**.
- `WalletService.initiate_iap()` and `_earn_rewarded_ad()` already call `ComplianceService.is_restricted()`
  for the *age* gate — they have no consent gate.

### Constraints
- **`core/` purity (ADR-0001):** consent state must be pure, node-free, deterministic, serialized
  through the existing `SaveData` dict round-trip and unit-testable without the scene tree.
- **Single chokepoint (ADR-0005, save-service Core Rule 9):** the "treat the absence of
  permission as restrictive" rule must live in exactly one place. Adding consent must *not* create
  a second class of direct readers — `AdService`/`IAPService`/`Analytics` must ask
  `ComplianceService`, never read a consent field.
- **Consent fields are protected fields (save-service Core Rule 6 / Edge Case 9):** they must
  **never** round-trip through the missing-key-default path on a downgrade, and their absence must
  **never** silently default to a permissive value. This is precisely the `opted_in`-that-should-
  default-permissive counter-example Core Rule 6 forbids — so it forces a real migration step with
  conservative defaults, not a free missing-key add.
- **Persisted-ordinal stability** (save-service AgeBand contract) applies equally to any consent
  enum/representation written to disk.

### Requirements
- Persist three independent consent flags — personalized-ads, analytics, IAP — survivable across
  restart and reinstall-from-save, defaulting conservatively (denied) for every pre-existing save.
- Gate every monetization capability on **consent × age_band** through `ComplianceService`.
- Model the CMP *flow*: first-run capture, later withdrawal, and re-presentation triggers — as
  pure state, with the vendor SDK deferred.
- Withdrawal of consent must **immediately** flip the relevant `ComplianceService` verdict (no
  cache, no restart needed).

## Decision

### 1. Consent state = pure fields in `SaveData`, behind a v5→v6 migration
Add consent fields to `SaveData` (e.g. `consent_personalized_ads`, `consent_analytics`,
`consent_iap`, plus the flow bookkeeping needed for re-presentation — e.g. a `consent_captured`
marker and/or a consent-version stamp). They are plain serialized fields in `to_dict()` /
`from_dict()`, with conservative parsing exactly like the existing fields.

Because consent fields are **protected** (Core Rule 6 / Edge Case 9), they require a **schema
bump and an explicit migration step**, not a missing-key-default add:

- `SaveData.CURRENT_SCHEMA_VERSION` → **6**.
- A new `if version == 5:` step in `_migrate` seeds every consent field to its **denied / not-
  captured** default. This is the single S4-001/S4-003 v6 step — S4-003 **extends** it with the
  Remove-Ads entitlement field; it must **never** be a second independent `_migrate` step (risk
  M4-R4).
- The migration step is **idempotent** (re-running it on an already-v6 dict is a no-op on the
  consent fields), preserving the downgrade/re-run invariant (save-service Formulas → migration
  gate).

### 2. All gating goes through `ComplianceService` — extend it, never read consent directly
`ComplianceService` becomes the sole reader of the consent fields as well as `age_band`. Its
`can_*` verdicts gain consent-awareness; the permissive branch is the **conjunction** of the
adult check and the relevant consent:

```gdscript
# autoloads/compliance_service.gd (extended)
func can_show_targeted_ads() -> bool:
    return is_adult() and _consent_personalized_ads()     # consent × age_band
func can_collect_personal_data() -> bool:
    return is_adult() and _consent_analytics()
func can_process_iap() -> bool:                            # new verdict (S4-002 chokepoint)
    return is_adult() and _consent_iap()
```

The structure mirrors ADR-0005 exactly: permissive only on `is_adult() AND <consent granted>`;
`UNKNOWN`/`CHILD` *or* a denied/absent consent falls through to restricted. The same reason the
guard is `== ADULT` and never `== CHILD` (so UNKNOWN can't leak) applies to consent: the guard is
`AND consent_granted`, never `AND NOT consent_denied` (so an absent/unknown consent can't leak).
`AdService` / `IAPService` / `Analytics` call these verdicts — they never read a consent field.

### 3. Model the CMP *flow*, not the vendor SDK
This ADR models consent **capture → withdrawal → re-presentation** as pure transitions over the
`SaveData` consent fields:

- **Capture:** the (future, UI/UMP) flow writes the player's choices into the consent fields via
  a `SaveService` setter; `consent_captured` flips true; the save persists.
- **Withdrawal:** flipping any consent field to denied persists immediately and, because every
  consumer reads the live verdict, **immediately** flips the corresponding `ComplianceService`
  verdict — the next `can_*` call returns restrictive with no restart and no cache to invalidate.
- **Re-presentation:** triggered by `consent_captured == false`, an age-band change, or a consent-
  version bump (policy change). The flow is modelled here; *when/how* the prompt renders is the
  vendor UMP SDK's job, deferred.

The **vendor UMP/ATT SDK** (the actual GDPR consent UI and iOS ATT prompt) is **out of scope** —
it is part of the native-SDK sprint, consistent with ADR-0014's mock-first seam and with how
`RemoteConfigSource` ships as a no-op base for M4 subclassing.

### 4. HMAC / `age_band` tamper-resistance — formally DEFERRED (conscious decision)
`ComplianceService`'s docstring and `design/gdd/save-service.md` (Open Questions, 2026-06-09)
name an HMAC/signature over `age_band` as a **required prerequisite before the first
`AdService`/`Analytics` ships**, because `user://save.json` is unsigned plain text and a rooted/
jailbroken user could edit `age_band` CHILD→ADULT. Sprint 4's `AdService` (S4-004a) is technically
"the first AdService" — but it is a **mock** with **no real ad revenue and no PII leaving the
device**. We therefore **formally defer** HMAC to the **native-SDK sprint** (the sprint that ships
the real `AdService`/`Analytics` + the vendor UMP SDK), where it lands *before* any off-device
data flow.

This is recorded as a conscious, owned decision — **not an oversight** — and is logged as risk
**M4-R2 (OPEN-DEFERRED)** in `production/risk-register/m4-risks.md`, which must close before the
native AdService sprint. The compensating control until then is unchanged from M1: `UNKNOWN` is
always restrictive, the gate is neutral (ADR-0005), and the mock services move no PII off-device.

### Architecture

```
First launch ─▶ Neutral Age Gate (ADR-0005) ─▶ age_band in SaveData (v6)
                              │
        CMP flow (modelled here; vendor UMP SDK deferred):
        capture / withdraw / re-present ─▶ consent_* fields in SaveData (v6)
                              │
                ┌────────────┴─────────────┐
                ▼                           ▼
        age_band axis               consent axis (per capability)
                └──────────── ComplianceService (SOLE reader of BOTH) ───────────┘
                   can_show_targeted_ads()  = is_adult() AND consent_personalized_ads
                   can_collect_personal_data() = is_adult() AND consent_analytics
                   can_process_iap()        = is_adult() AND consent_iap
                              │ (verdicts only — never raw fields)
        ┌─────────────────────┼──────────────────────┐
   AdService (S4-004)   IAPService (S4-002)    Analytics (S4-007)
```

### Implementation Guidelines
- **Conservative (never-permissive) defaults** for every consent field: a fresh `SaveData` and
  every migrated pre-v6 save start with all consent **denied** and `consent_captured == false`.
- **Idempotent migration step:** the `if version == 5:` block seeds the consent (and S4-003
  entitlement) fields; re-running it on a v6 dict must not change a granted consent back to
  denied. One step, shared with S4-003 — never two (M4-R4).
- **Protected-field rule (Edge Case 9):** consent fields must **never** be served by the missing-
  key-default path on downgrade. A field absent because an older client dropped it must be treated
  as **denied** and re-captured, never silently granted. The migration step + conservative
  `from_dict` defaults enforce this.
- **Withdrawal immediacy:** verdicts are computed from the live `SaveData` on each `can_*` call —
  no cached boolean. A withdrawal write therefore flips the verdict on the next query.
- **No second reader:** a grep must show consent fields are read only by `ComplianceService`
  (besides `SaveService` itself), mirroring the `age_band` chokepoint invariant.
- **Persisted representation stability:** if consent is stored as anything ordinal/enumerated,
  the persisted values are a stable contract (save-service AgeBand precedent) — append, never
  reorder.

## Alternatives Considered

### Alternative 1: A standalone `ConsentService` autoload separate from `ComplianceService`
- **Description**: A new autoload owning consent, queried alongside `ComplianceService`.
- **Pros**: Separation of the consent flow from the age gate.
- **Cons**: Two gating services means every consumer must remember to AND two verdicts together —
  precisely the "consumer forgets the gate" failure ADR-0005's single chokepoint was built to
  make impossible. The consent × age_band conjunction would live in N call sites, not one.
- **Rejection Reason**: Re-introduces the multi-reader hazard. The conjunction belongs in the one
  chokepoint; `ComplianceService` already owns the audience half of it.

### Alternative 2: Consent as missing-key-default booleans (no schema bump)
- **Description**: Add `consent_*` bools read via `dict.get("consent_x", false)` with no v6 bump.
- **Pros**: Smallest change; no migration step.
- **Cons**: Directly violates save-service Core Rule 6 / Edge Case 9 — consent/compliance fields
  must **never** round-trip through the missing-key-default path, because a downgrade-then-save by
  an older client would drop them and a later load could not distinguish "never captured" from
  "was granted." Conservative defaults via `.get(..., false)` *look* safe but the **drop-on-
  downgrade** path is the documented compliance defect.
- **Rejection Reason**: Explicitly forbidden for compliance fields; the protection is the whole
  point of the rule.

### Alternative 3: Ship the vendor UMP/ATT SDK now (model the SDK, not the flow)
- **Description**: Integrate the GDPR UMP consent UI + iOS ATT prompt this sprint.
- **Pros**: End-to-end consent including the real prompt.
- **Cons**: A native SDK cannot be tested headlessly in the gdUnit4 CI (risk M4-R3); it pulls the
  whole mock-first M4 slice off its testable seam; the monetization UI it needs is a separate
  `/ux-design` sprint. The *model* (consent state + gating) is what unblocks every other M4
  service; the *prompt* is a swap-in.
- **Rejection Reason**: Same rationale as ADR-0014's mock-first seam — model the flow now behind
  the testable seam; defer the native SDK to the device-tested sprint.

## Consequences

### Positive
- One chokepoint enforces both axes; the consent × age_band conjunction can't be forgotten by a
  consumer (the ADR-0005 guarantee now covers consent too).
- Consent is pure, node-free `SaveData` — fully unit-testable; the migration is a single tested
  v6 step shared with the entitlement (no collision).
- Withdrawal is immediate and cache-free by construction.
- The HMAC deferral is a named, owned, time-bounded risk rather than a silent gap.

### Negative / accepted trade-offs
- **New schema v6** + a migration step to maintain. Accepted: consent fields are protected and
  *must* migrate (Core Rule 6); the ladder already has this shape. Shared with S4-003 to avoid a
  second step.
- **`age_band` remains tamperable through Sprint 4.** Accepted, scoped, and risk-logged (M4-R2):
  the mock services surface no real revenue/PII; HMAC lands before the native AdService.
- The vendor consent **prompt** does not exist yet — only the flow/state. Accepted: it is the
  native-SDK + UI sprint's work; the model is sufficient to gate every M4 service.

### Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| A consumer reads a consent field directly, bypassing the conjunction | Med | High | Single-reader invariant (grep gate); consent fields private to `ComplianceService`; review checklist mirrors the `age_band` rule |
| Consent dropped on downgrade silently re-grants a capability | Low | High | Protected-field rule (Edge Case 9): migrate step + conservative defaults; absent ⇒ denied + re-capture, never granted |
| `age_band` tamper (CHILD→ADULT) before HMAC ships | Med | Med | M4-R2 OPEN-DEFERRED; mock-only this sprint (no off-device PII); UNKNOWN always restrictive; HMAC required before native AdService |
| Two independent v5→v6 migrations (S4-001 + S4-003) collide | Med | High | One shared v6 step; explicit S4-001→S4-003 sequence (M4-R4) |
| Consent-version policy change leaves stale grants | Low | Med | Re-presentation triggered by a consent-version stamp; bump forces re-capture |

## Validation Criteria
- [ ] `SaveData.CURRENT_SCHEMA_VERSION == 6`; a v5 (and older) save migrates to v6 with all
      consent fields at their **denied / not-captured** defaults (unit test).
- [ ] The v6 `_migrate` step is idempotent and is the **single** step shared with S4-003's
      entitlement field (no second migration).
- [ ] `from_dict` defaults missing consent keys conservatively; a downgrade-dropped consent field
      loads as denied + re-capture, never granted (Edge Case 9 test).
- [ ] `ComplianceService.can_*` return permissive **only** for `ADULT × granted` and restrictive
      for every other cell of the consent × age_band cross-product (unit test over the full
      cross-product).
- [ ] Withdrawing a consent flips the corresponding `can_*` verdict on the next call with no
      restart (integration test driving the autoloads).
- [ ] Consent fields are read only by `ComplianceService` (besides `SaveService`) — single-reader
      grep gate.

## GDD Requirements Addressed

| GDD / Plan | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| GAME_PLAN §9 | CMP for GDPR/UMP consent + ATT; "limited ads" when consent denied | Consent modelled as state; verdicts gate ads on consent × age_band; vendor UMP/ATT deferred to native sprint |
| GAME_PLAN §10 | `ComplianceService` owns `age_band` **+ consent state**; Ad/IAP/Analytics query it, never assume | Consent fields added behind the same chokepoint; consumers call `can_*` only |
| save-service.md Core Rule 6 / EC9 | Consent/compliance fields never use the missing-key-default path; conservative defaults; idempotent migration | v6 migration step + denied defaults + idempotency; protected from downgrade-drop |
| sprint-04.md S4-001 | Consent fields + v5→v6 migration routed through `ComplianceService` (consent × age_band); CMP flow not vendor SDK | Exactly this design; HMAC deferral recorded |

## Performance Implications
- **CPU**: each `can_*` call is a couple of field reads + boolean ANDs; called at ad/IAP/analytics
  decision points (event-frequency, never per-frame). Negligible.
- **Memory**: a handful of fields per `SaveData`. Trivial.
- **Load Time / Network**: none (the vendor SDK that would add network is deferred).

## Migration Plan
1. Add consent fields to `SaveData` (`to_dict`/`from_dict` round-trip + conservative parsing).
2. Bump `CURRENT_SCHEMA_VERSION` to **6**; add one idempotent `if version == 5:` step seeding the
   consent fields (and, per S4-003, the entitlement field) to conservative defaults — the single
   v6 step.
3. Extend `ComplianceService` with consent-aware `can_*` verdicts (permissive = `is_adult() AND
   consent_granted`) + a `can_process_iap()` verdict; add `SaveService` consent setters for the
   capture/withdrawal flow.
4. Add unit tests: v5→v6 migration defaults, idempotency, downgrade-drop protection, the consent ×
   age_band cross-product, and an integration test proving withdrawal flips the live verdict.
5. Leave the vendor UMP/ATT SDK and the consent prompt UI to the native-SDK + `/ux-design`
   sprints; leave HMAC `age_band` signing to the native-SDK sprint (M4-R2).

## Related Decisions
- ADR-0005 (audience positioning + the `ComplianceService` chokepoint this extends), ADR-0001
  (core purity), ADR-0004 (typed + gdUnit4).
- ADR-0014 (monetization service seam) — consumes the consent verdicts defined here.
- `design/gdd/save-service.md` (Core Rule 6, Edge Case 9, AgeBand ordinal contract, Open
  Questions HMAC decision); `autoloads/compliance_service.gd`; `core/save_data.gd`;
  `production/risk-register/m4-risks.md` (M4-R2, M4-R4); `production/sprints/sprint-04.md` (S4-001).
