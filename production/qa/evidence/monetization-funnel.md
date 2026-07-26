# S5-007 — Monetization Analytics Funnel · QA Evidence

**Story:** S5-007 (Sprint 5 — Monetization UI) · **Type:** Integration
**Spec:** `design/ux/monetization-ui.md` AC-7
**Status:** integration suite green (no UI surface — no screenshot required).

## What shipped

The three monetization funnel events are emitted from their UI flows through the
consent-gated `AnalyticsService` seam (the calls were wired as each surface landed;
S5-007 verifies the funnel end-to-end):

| Event | Emitted from | Flow |
|---|---|---|
| `iap_purchase` | `ShopScreen._on_purchase_completed` | `AnalyticsService.track_iap_purchase(sku, success)` on every resolution (S5-003) |
| `ad_reward` | `RewardedPrompt._on_watch` | `AnalyticsService.track_ad_reward(coins)` on a credited view (S5-004) |
| `ad_impression` | `main.gd._present_interstitial` | `AnalyticsService.track_ad_impression(ad_type)` on a shown interstitial (S5-005) |

`AnalyticsService` forwards to its sink **only** when
`ComplianceService.can_collect_personal_data()` (adult AND analytics consent), so every
funnel event is consent-gated at the chokepoint — the flows never gate it themselves.

## Automated evidence (BLOCKING — green)

- `tests/integration/analytics/monetization_funnel_ui_test.gd` (this story) — drives the
  real interstitial flow and asserts the `ad_impression` event reaches a recording sink
  through the real `AnalyticsService`; a second case revokes analytics consent and asserts
  **nothing** reaches the sink.
- `iap_purchase` flow emission → `tests/integration/shop/shop_screen_test.gd`
  (`test_successful_purchase…` / `test_failed_purchase…` assert `track_iap_purchase` fired).
- `ad_reward` flow emission → `tests/integration/rewarded/rewarded_prompt_test.gd`
  (`test_watch_credits_once_and_tracks_reward`).
- The consent × audience gate itself → `tests/integration/analytics/funnel_consent_test.gd`
  (S4-007).

Full suite: **798 test cases, 0 failures** (796 baseline + 2 new). The suite restores the
autoload `AnalyticsService` to a no-op sink after each test so no injected sink / consent
leaks into other suites.
