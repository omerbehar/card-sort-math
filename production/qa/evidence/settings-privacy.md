# S6-003 — Settings → Privacy (view / withdraw / re-manage) · QA Evidence

**Story:** S6-003 (Sprint 6 — Compliance UI) · **Type:** UI/Integration
**Spec:** `design/ux/compliance-ui.md` §3.3 · ADR-0013 · AC-4
**Status:** integration suite green + screenshot captured.

## What shipped

A **Privacy & Data** row in the pause menu (`scenes/ui/pause_menu.gd`) that lets a player
review and change their consent after first launch:

- New full-width **"Privacy & Data ›"** row (the panel was enlarged to fit it; existing
  controls shifted, and tests find buttons by key, not position). Emits `privacy_pressed`.
- `main.gd._open_privacy_consent` opens the **consent sheet pre-filled** with the current
  choices — for an adult the `ComplianceService` verdict equals the stored consent field, so
  the verdicts seed the toggles (`ConsentSheet.set_initial`). Dismissable (opened from
  settings).
- Saving re-captures via `SaveService.capture_consent`; a toggle turned **off** is an
  **immediate withdrawal** — the matching `ComplianceService` verdict flips on its next call
  (live read, no restart; ADR-0013 §3).

## Automated evidence (BLOCKING — green)

`tests/integration/compliance/settings_privacy_test.gd` (real `main.tscn`):

| Test | Asserts |
|---|---|
| `test_pause_menu_exposes_a_privacy_row` | the pause menu has the `privacy` button |
| `test_privacy_opens_consent_sheet_prefilled_with_current_choices` | opening it seeds the toggles from current consent |
| `test_withdrawing_analytics_from_settings_flips_the_verdict` | **AC-4** — toggle Analytics off + Save → `can_collect_personal_data()` false; ads/IAP still granted |

Full suite: **820 test cases, 0 failures** (817 baseline + 3 new). The debug-reset flow
(which finds buttons by key) is unaffected by the layout shift.

## Screenshot evidence (ADVISORY)

Rendered at 390×844 via `tools/screenshot_pause_menu.gd` (opengl3 harness).

| File | Shows |
|---|---|
| `settings-privacy.png` | The pause menu with the new "Privacy & Data ›" row between the accessibility switches and the debug row. |

## Notes / follow-ups

- The declared age band is set at first launch; **re-declaring** the band is out of scope this
  sprint (a "set at first launch" note is the intended read-only treatment).
- Single-field `SaveService.withdraw_consent(field)` exists for an immediate per-field
  withdrawal; the sheet-based re-capture (toggle off + Save) achieves the same persisted
  result and is the chosen management UX.
