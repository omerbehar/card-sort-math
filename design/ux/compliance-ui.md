# Compliance UI — UX Spec

> **Status:** Draft · **Sprint:** 6 (Compliance UI) · **Consumes:** the `ComplianceService`
> / `SaveData` v6 consent model (S4-001, ADR-0013) and the audience decision (ADR-0005).
> **Scope:** the first-run **age gate**, the **consent capture** sheet, **settings privacy**
> (view/withdraw), and the **child-safe** UI treatment. Mock-first: no vendor CMP/UMP/ATT SDK
> yet (that's the native-SDK sprint) — these flows write the same `SaveData` fields the
> services already read.

## 1. Overview

Four surfaces that turn the (already tested, service-layer) compliance model into the
first-run flow players actually see, so the game can collect consent lawfully and adapt to
audience: (1) a **neutral age gate** on first launch; (2) a **consent capture** sheet for a
declared 13+ player (personalized ads / analytics / IAP); (3) **settings privacy** to review
and withdraw consent later; (4) a **child-safe** treatment so an under-13 player never sees
personalized-data surfaces. All are thin views (ADR-0001): they collect a choice and call a
`SaveService` setter; `ComplianceService` remains the sole reader and decision-maker.

## 2. Player Fantasy

"This game is upfront and respectful with me." The gate is quick and non-judgmental; consent
is a clear, honest choice (not a dark-pattern pre-checked trap); withdrawing is as easy as
granting. A younger player is quietly kept safe without being singled out or blocked from the
fun. Nothing feels like surveillance.

## 3. Detailed Rules — per surface

### 3.1 Age gate (S6-001, shipped)
- Shown once on first launch when `SaveData.age_band == UNKNOWN`, before any personal-data
  collection. Neutral, **non-leading** birth-year entry (not "are you 13+?"). Undismissable.
- On confirm: `ComplianceService.age_band_for_birth_year(year, now)` → `ADULT` (≥13) or
  `CHILD` (<13) → `SaveService.set_age_band(band)` (persists, flips verdicts live).

### 3.2 Consent capture (S6-002)
- New `scenes/ui/consent_sheet.tscn` (+ `consent_sheet.gd`) on `PopupBase`. Presented
  **immediately after the age gate for an ADULT** (a CHILD skips it — see §3.4).
- Three explicit, **default-off** toggles (never pre-granted — protected fields, ADR-0013):
  **Personalized ads**, **Analytics**, **Store purchases (IAP)**. Each with a one-line plain
  explanation. A short link-stub to the (future) privacy policy.
- Two actions: **Save choices** → `SaveService.capture_consent(personalized_ads, analytics,
  iap)` (writes all three + `consent_captured = true`, one save); **Not now / decline all** →
  `capture_consent(false, false, false)` (still marks captured, all denied).
- After capture, the shop/ads verdicts reflect the choices immediately (no restart).

### 3.3 Settings privacy (S6-003)
- A **Privacy** row/section in the pause menu (`pause_menu.gd`). Shows the current per-field
  state (Granted / Denied) read via `ComplianceService` — never the raw fields.
- **Manage** re-opens the consent sheet pre-populated with current choices; saving updates
  via `capture_consent`. Each field also supports one-tap **withdraw** →
  `SaveService.withdraw_consent(field)`, which flips that verdict to restricted immediately
  (ADR-0013 §3 withdrawal immediacy).
- Shows the declared age band (Adult / Child) read-only (re-declaration is out of scope this
  sprint; a "this was set at first launch" note).

### 3.4 Child-safe treatment (S6-004)
- When `age_band == CHILD` (`ComplianceService.is_restricted()` and not adult):
  - The **consent sheet is not shown** (no personal-data consent solicited from a child).
  - **Shop**: currency packs remain (IAP itself is gated by `can_process_iap()` → false for a
    child, so purchases resolve blocked with a calm "Ask a grown-up" affordance — a
    **parental-gate stub**, not a real gate this sprint). Remove-Ads still purchasable-blocked
    the same way. No personalized/targeted surfaces.
  - **Ads**: already contextual-only by construction (`can_show_targeted_ads()` false for a
    child); no ad-ID, no behavioral surfaces.
  - No analytics/personal-data prompts anywhere.

## 4. Formulas / bindings

- Age band = `ADULT if (current_year − birth_year) ≥ ADULT_MIN_AGE(13) else CHILD`
  (`ComplianceService.age_band_for_birth_year`; unit-tested S6-001).
- Every gated surface reads a **verdict**, never a raw field:
  `can_show_targeted_ads()` = `is_adult() AND consent_personalized_ads`;
  `can_collect_personal_data()` = `is_adult() AND consent_analytics`;
  `can_process_iap()` = `is_adult() AND consent_iap`.
- Consent defaults: all three **denied** until captured (protected-field default, ADR-0013).

## 5. Edge Cases

- **Age gate answered CHILD** → skip consent sheet entirely; enter child-safe mode; never
  collect personal data. (Explicit: no consent UI, not a hidden all-denied capture.)
- **Adult declines all consent** → `consent_captured = true`, all verdicts restricted; the
  game is fully playable, ads are contextual, no analytics, IAP blocked with a settings
  pointer. Re-grantable later in settings.
- **Consent withdrawn mid-session** → the corresponding verdict flips on the next
  `ComplianceService` call (live read, no cache); any open shop/offer re-reads on its next
  action. A purchase resolving after IAP consent is withdrawn is blocked by `can_process_iap`.
- **Returning player** (band already set, `consent_captured` true) → no gate, no sheet on
  launch; managed only from settings.
- **Child attempts IAP** → `can_process_iap()` false → purchase blocked → "Ask a grown-up"
  (parental-gate stub); wallet untouched.

## 6. Dependencies

- **Services (shipped):** `ComplianceService` (sole reader; `is_adult` / `can_*`),
  `SaveService` (`set_age_band`, `capture_consent`, `withdraw_consent`), `SaveData` v6.
- **Surfaces touched:** `main.gd` (present gate → sheet), `scenes/ui/pause_menu.gd` (privacy),
  `scenes/ui/shop_screen.gd` (child-safe / consent-unavailable state), `PopupBase`.
- **Blocks / enables:** unblocks store launch and — with the native-SDK sprint — personalized
  ads (`can_show_targeted_ads` can only become true once this captures consent).
- **Deferred:** vendor CMP/UMP + iOS ATT wiring (native-SDK sprint); real parental gate;
  `age_band` tamper-signing (M4-R2, ADR-0013 §4).

## 7. Tuning Knobs

| Knob | Source | Notes |
|---|---|---|
| Adult age threshold | `ComplianceService.ADULT_MIN_AGE` (13) | legal constant (COPPA), not balance |
| Consent field set | `SaveData` v6 + `capture_consent` | personalized_ads / analytics / iap |
| Default consent | denied (protected) | never pre-granted |
| Parental-gate copy / behavior | view (stub this sprint) | real gate is a follow-up |

## 8. Acceptance Criteria

- **AC-1** First launch shows the neutral age gate; it blocks play until answered; the result
  persists and flips `ComplianceService` verdicts. *(S6-001 — done.)*
- **AC-2** A declared **adult** is shown the consent sheet with three default-off toggles;
  saving writes all three + `consent_captured` via `capture_consent`; the matching verdicts
  reflect the choices immediately.
- **AC-3** A declared **child** is **not** shown the consent sheet and never has personal data
  collected; the shop reflects child-safe restrictions (IAP blocked with a parental-gate
  affordance).
- **AC-4** Settings shows current consent state (via `ComplianceService`) and can withdraw a
  field (`withdraw_consent`) with the verdict flipping immediately; re-managing re-captures.
- **AC-5** Every surface reads verdicts, never raw consent fields; consent defaults denied.
- **AC-6** All surfaces honor reduced-motion + are operable by touch at 390×844 (ADVISORY).

## 9. Out of scope (this sprint)

Vendor CMP/UMP consent form · iOS ATT prompt · real parental gate / age-appropriate account
linking · `age_band` HMAC signing · re-declaring age band · full privacy-policy content.
