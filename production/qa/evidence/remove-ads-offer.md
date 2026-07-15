# S5-006 — Remove-Ads Offer Surface · QA Evidence

**Story:** S5-006 (Sprint 5 — Monetization UI) · **Type:** UI
**Spec:** `design/ux/monetization-ui.md` §3.4 (Remove-Ads offer) · §7 (per-session cap)
**Status:** integration suite green + screenshot captured.

## What shipped

`scenes/ui/remove_ads_offer.gd` (`RemoveAdsOffer extends PopupBase`) — a gentle,
dismissible bottom sheet that anchors the Remove-Ads SKU and deep-links the Shop:

- Shows "Tired of ads? / Remove interstitials — keep your rewarded ads." with a
  **Remove Ads · $X.XX** CTA (price read from the catalog's entitlement entry via
  `IAPCatalogEntryResource.price_display()`) and a quiet **Not now** dismiss.
- CTA → `shop_requested` → `main.gd._open_shop` (opens the Shop where Remove-Ads is the
  top anchor). Dismiss / backdrop tap → close.
- Suppresses itself entirely when Remove-Ads is already owned (reads the entitlement
  chokepoint `should_suppress_interstitials()`).

**Session cap wiring (main.gd):** surfaced **at most once per session** via a
`_remove_ads_offered` view flag, triggered after the first interstitial closes
(`_present_interstitial` → `_maybe_offer_remove_ads`). Never shown when owned.

## Automated evidence (BLOCKING — green)

`tests/integration/remove_ads/remove_ads_offer_test.gd`:

| Test | Asserts |
|---|---|
| `test_offer_renders_cta_that_requests_shop` | CTA built with the catalog price; tap emits `shop_requested` |
| `test_offer_suppressed_when_remove_ads_owned` | owned → the sheet never builds |
| `test_offer_shown_once_per_session` | **§7 cap** — shown once; a second opportunity does not re-show |
| `test_offer_not_shown_when_remove_ads_owned` | real-scene — owned → suppressed |

Full suite: **802 test cases, 0 failures** (798 baseline + 4 new). The suite resets the
shared save's `remove_ads_owned` after each test so no state leaks.

## Screenshot evidence (ADVISORY)

Rendered at 390×844 portrait via
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tools/screenshot_remove_ads_offer.gd`.

| File | Shows |
|---|---|
| `remove-ads-offer.png` | The dismissible bottom sheet over the dimmed board — "Tired of ads?", "Remove Ads · $2.99" CTA, "Not now". |

## Notes / follow-ups

- **Trigger cadence**: the offer fires after the first interstitial of the session (a
  natural, non-nagging moment). The spec's alternative "~session 2–3" trigger and the
  app-foreground counter reset are follow-ups (mock-first).
- **Deep-link target**: opens the full Shop (Remove-Ads is the top anchor); scrolling to
  the card is the same follow-up noted for S5-003's `currency_tapped` filter.
