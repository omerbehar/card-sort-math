# S6-002 — Consent Capture Sheet · QA Evidence

**Story:** S6-002 (Sprint 6 — Compliance UI) · **Type:** UI/Integration
**Spec:** `design/ux/compliance-ui.md` §3.2 · ADR-0013 · AC-2
**Status:** integration suite green + screenshot captured.

## What shipped

`scenes/ui/consent_sheet.gd` (`ConsentSheet extends PopupBase`) — the consent capture sheet,
shown after the age gate for a declared 13+ player (a child skips it):

- Three explicit **default-OFF** toggles — **Personalized ads**, **Analytics**, **Store
  purchases (IAP)** — each with a plain one-line explanation. Protected fields are never
  pre-granted (ADR-0013).
- **Save choices** → `SaveService.capture_consent(personalized_ads, analytics, iap)` (writes
  all three + `consent_captured`, one save); **Not now** → declines all (still captured).
  Emits `consent_saved(...)`. A thin view: `ComplianceService` verdicts reflect the choices
  live on the next query.
- `main.gd._on_age_submitted` presents it only when the declared band is **ADULT** and consent
  isn't already captured — a **CHILD never sees it** (child-safe by construction).
- Injectable save (`configure`) for tests; `set_initial(...)` pre-populates for the Settings
  "Manage" re-open (S6-003).

## Automated evidence (BLOCKING — green)

`tests/integration/compliance/consent_sheet_test.gd`:

| Test | Asserts |
|---|---|
| `test_defaults_off_save_captures_all_denied` | untouched Save → `capture_consent(false,false,false)` |
| `test_toggling_personalized_then_save_captures_it` | toggle personalized → Save → `[true,false,false]` + `consent_saved` |
| `test_decline_captures_all_denied` | "Not now" declines all even after a toggle |
| `test_adult_is_offered_consent_sheet_after_age_gate` | **AC-2** — adult clears the gate → sheet presented |
| `test_child_skips_the_consent_sheet` | **AC-3** — child → no sheet |

Full suite: **817 test cases, 0 failures** (812 baseline + 5 new).

## Screenshot evidence (ADVISORY)

Rendered at 390×844 via
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tools/screenshot_consent_sheet.gd`.

| File | Shows |
|---|---|
| `consent-sheet.png` | "Your privacy choices" — the three toggles (Analytics ON / others OFF), "Save choices" + "Not now". |

## Notes / follow-ups

- The vendor CMP/UMP form + iOS ATT prompt are deferred to the native-SDK sprint; this sheet
  writes the same `SaveData` fields those will. Privacy-policy link is a stub.
- S6-003 (Settings → Privacy) reuses this sheet via `set_initial(...)` for re-management.
