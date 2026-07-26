# S5-005 — Mock Interstitial · QA Evidence

**Story:** S5-005 (Sprint 5 — Monetization UI) · **Type:** Integration
**Spec:** `design/ux/monetization-ui.md` §3.4 · AC-6
**Status:** integration suite green + screenshot captured.

## What shipped

`scenes/ui/interstitial_mock.gd` (`InterstitialMock extends PopupBase`) — a full-screen
mock "ad" placeholder shown at the between-levels boundary, plus the `main.gd` wiring:

- **Boundary wiring:** `start_level` calls `AdService.notify_level_started()` (so an
  interstitial is never presented mid-arithmetic). On a **win** the claim ("TAP TO CLAIM")
  routes through `main.gd._on_win_advance`, which calls `AdService.notify_level_completed()`
  then `AdService.maybe_show_interstitial()`.
- **Present only on SHOWN:** if the outcome is `SHOWN`, `_present_interstitial` displays the
  mock full-screen ad and advances to the next level **only once it closes**; on any
  `SUPPRESSED_*` / `NO_FILL` the flow advances immediately with no UI. `AdService` owns the
  triple gate (compliance × consent × entitlement) + the frequency cap, so Remove-Ads
  suppression and the every-N-levels/min-seconds cadence are honored (S4-004).
- Emits `AnalyticsService.track_ad_impression(ad_type)` with the type `AdService` targeted.
- The close affordance appears after a short beat (models an un-skippable window); closing
  resumes the between-levels flow.

## Automated evidence (BLOCKING — green)

`tests/integration/interstitial/interstitial_mock_test.gd`:

| Test | Asserts |
|---|---|
| `test_close_affordance_hidden_until_beat_then_close_emits_closed` | close is hidden during the beat; revealing + closing emits `closed` |
| `test_win_advance_without_fill_advances_with_no_interstitial` | **AC-6** — a first win (frequency cap unmet + NO_FILL) advances with no UI (shown only on SHOWN) |
| `test_present_interstitial_shows_mock_and_advances_on_close` | **AC-6** — SHOWN → mock presented; closing it advances the level |

Full suite: **796 test cases, 0 failures** (793 baseline + 3 new). The suite resets the
process-global `AdService` frequency counters it mutates so no state leaks into other
suites.

## Screenshot evidence (ADVISORY)

Rendered at 390×844 portrait via
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tools/screenshot_interstitial.gd`.

| File | Shows |
|---|---|
| `interstitial-mock.png` | The full-screen mock interstitial — "Advertisement" tag, ▶ placeholder card ("Mock Interstitial" / "Your ad could be here"), and the close ✕ (revealed after the beat). |

## Notes / follow-ups

- The real ad backend reports `NO_FILL` (mock-first M4) until a native SDK lands (device
  sprint); the SHOWN presentation path is exercised via `_present_interstitial` in tests
  and the screenshot harness.
- **Per-session Remove-Ads offer** (spec §3.4, second half): the one-per-session Remove-Ads
  anchor banner is a separate should-have (S5-006/queue) and is not part of this story.
