# ADR-0005: Audience positioning — 13+ with a neutral age gate (mixed-audience)

## Status

Accepted

## Date

2026-06-08

## Last Verified

2026-06-08

## Decision Makers

Product owner (omer.behar), creative-director, live-ops-designer, security-engineer

## Summary

CardSortMath is math-flavored and therefore at risk of being classified as
child-directed, which would force the restrictive kids regime (no targeted ads,
no ad IDs, minimal analytics). We position the game as a **general-audience (13+)**
product with a **neutral age gate** and **COPPA "mixed-audience" handling**: users
who declare 13+ get the full monetizable experience; any user who declares under
13 receives child-safe restrictions.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Privacy / Monetization / Platform |
| **Knowledge Risk** | MEDIUM — relies on COPPA/GDPR-K/UK Children's Code + platform kids programs; verify current rules with legal before launch |
| **References Consulted** | COPPA mixed-audience guidance; Google Play Families policy; Apple App Review (age rating); GDPR-K / UK AADC |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Legal review of "child-directed" determination; CMP/UMP + ATT integration behavior on device |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | Ad-led + IAP monetization (`GAME_PLAN.md` §§8–9), standard analytics (§11) |
| **Blocks** | Ad SDK integration, analytics SDK, store submission (M4), privacy policy |
| **Ordering Note** | Must be settled before any ad/analytics SDK or store listing work |

## Context

### Problem Statement

The 13+ vs. <13 choice determines the entire monetization and data model. A math
game can be deemed "directed to children" regardless of label, so we must choose
a posture and back it up in substance.

### Current State

No age gate, no ads, no analytics yet. `GAME_PLAN.md` §10 framed the two paths and
flagged the decision as the single most consequential product call.

### Constraints

- COPPA/platform kids classification is **app-level**: enrolling as a kids product
  restricts the experience for *all* users, including adults.
- "Directed to children" is judged on totality of circumstances (content,
  visuals, marketing), not solely on a self-declared label.
- Self-declared age gates are accepted **only** if the app is not primarily
  child-directed in substance.

### Requirements

- Adult players get the full experience (targeted ads, ad ID, full analytics, IAP).
- Compliant handling for any under-13 users who appear.
- Business viable even if ad ARPU is later constrained.

## Decision

Adopt **general-audience (13+)** positioning with **mixed-audience** handling:

1. **Neutral age gate** on first launch (a non-leading date/age entry, not "are
   you 13?"). Persist the result; gate before any personal-data collection.
2. **13+ users** → full experience: consent-gated targeted ads, advertising ID,
   full analytics, IAP.
3. **Under-13 users** → child-safe mode: contextual-only ads (or no ads), **no**
   advertising ID, no behavioral profiling, data minimization; IAP behind parental
   gating. No personal data collected before/without this branch.
4. **Substance backs the label**: neutral (not toddler-coded) art direction, store
   rating 13+, **no marketing to children**, and ad/analytics SDKs configured to
   honor the age signal and consent.
5. **Consent**: integrate a CMP (GDPR/UMP) + iOS ATT; respect "limited ads" when
   consent is denied.
6. **Economy resilience**: design so the business survives on **Remove-Ads + IAP
   alone** — ad revenue is upside, not load-bearing — to de-risk any future
   tightening or reclassification.

### Architecture

```
First launch ─▶ Neutral Age Gate ─▶ persist age_band in SaveService
                       │
        ┌──────────────┴───────────────┐
   age_band = ADULT (13+)         age_band = CHILD (<13)
        │                               │
   AdService: targeted            AdService: contextual-only / off
   Analytics: full + ad ID        Analytics: minimal, no ad ID
   IAP: standard                  IAP: parental-gated
        └──────────── ConsentService (CMP/UMP/ATT) ───────────┘
```

### Key Interfaces

```gdscript
enum AgeBand { UNKNOWN, ADULT, CHILD }
# ComplianceService (autoload, behind ADR-0001 seam):
func age_band() -> AgeBand
func can_use_advertising_id() -> bool      # false for CHILD or no consent
func can_show_targeted_ads() -> bool       # ADULT AND consent granted
func can_collect_personal_data() -> bool   # gated by age + consent
```

### Implementation Guidelines

- The age gate, consent, and age_band are a **compliance seam**: `AdService`,
  `Analytics`, and `IAPService` must query it, never assume.
- Persist `age_band` via SaveService (Sprint 1, S1-001); collect nothing personal
  before the gate resolves.
- Keep the gate neutral (date-of-birth style), not a yes/no "are you old enough".

## Alternatives Considered

### Alternative 1: Kids product (<13) — Designed for Families / Kids Category

- **Pros**: Brand/parent trust; safer classification; curated edu channels.
- **Cons**: App-wide restrictions (no targeted ads/ad ID **even for adults**),
  attribution lost, analytics dulled, monetization limited to paid/subscription/
  remove-ads, VPC burden, SDK vetting.
- **Rejection Reason**: Caps the business hard; our audience skews adult casual.

### Alternative 2: 13+ with no age gate

- **Pros**: Zero friction.
- **Cons**: No mechanism to handle under-13 users; if deemed child-directed we're
  liable app-wide with no mitigation.
- **Rejection Reason**: Leaves us exposed; the gate is cheap insurance.

### Alternative 3: Defer the decision

- **Rejection Reason**: It gates ad/analytics SDK choice and store listing; cost of
  not deciding compounds.

## Consequences

### Positive

- Full ad + IAP + analytics + UA attribution for the (adult-majority) audience.
- A defined, compliant path for under-13 users; reduced regulatory exposure.
- SDK choices are unblocked (M4).

### Negative

- Age gate adds a small first-launch friction (minor install/retention cost).
- Must enforce neutral art/marketing discipline or the gate won't hold.
- Mixed-audience branching adds engineering complexity across ad/analytics/IAP.
- Self-declared age is imperfect; a child can mis-declare (mitigated by substance + parental purchase gates).

### Neutral

- Store rating set to 13+; data-safety/privacy labels filled accordingly.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Regulator deems app child-directed despite 13+ | Med | High | Neutral art/marketing; no kid targeting; legal review; economy not ad-dependent |
| Children mis-declare age | High | Med | Substance test holds; parental-gated IAP; contextual fallback |
| Ad SDK ignores age/consent signal | Low | High | Abstract behind `AdService`; verify SDK config; CMP integration tests |
| Future tightening of kids rules | Med | Med | Remove-Ads + IAP keep business viable without ad ARPU |

## Validation Criteria

- [ ] Neutral age gate shown on first launch; result persisted; nothing personal
      collected beforehand.
- [ ] ADULT branch: targeted ads + ad ID + full analytics only with consent.
- [ ] CHILD branch: no ad ID, no behavioral ads, minimized data, parental-gated IAP.
- [ ] CMP/UMP + ATT integrated; "limited ads" path works when consent denied.
- [ ] Store listing rated 13+; privacy policy + data-safety forms consistent.
- [ ] Legal sign-off on the child-directed determination before launch.

## GDD Requirements Addressed

Foundational/product — no direct gameplay GDD. Enables `GAME_PLAN.md` §§8–9
(monetization/ads) and §11 (analytics). Constrains future GDDs for AdService,
Analytics, IAPService, and the onboarding/age-gate flow.

## Related

- `docs/GAME_PLAN.md` §10 (compliance), §§8–9 (monetization/ads), §11 (analytics).
- Depends on SaveService (Sprint 1 S1-001) to persist `age_band`.
- Future ADRs: Ad SDK/GDExtension integration; Analytics SDK selection.
