# S5-003 — Shop Screen · QA Evidence

**Story:** S5-003 (Sprint 5 — Monetization UI) · **Type:** UI/Integration
**Spec:** `design/ux/monetization-ui.md` §3.2 · AC-2/3/4/7
**Status:** integration suite green + screenshots captured.

## What shipped

`scenes/ui/shop_screen.gd` (`ShopScreen extends PopupBase`) — the in-game store, a thin
view over the M4 service seams:

- Renders the authored `IAPCatalog` (`assets/data/iap_catalog.tres`) as a scrollable list
  of offer cards: **Remove-Ads anchor** (top, warm-tinted) · currency packs · starter
  bundle. Each card shows `display_name`, `grant_summary` (ellipsized against the real
  font so it never runs under the price), and `price_display()`.
- Card **Buy** → `IAPService.purchase(sku)`; on `purchase_completed`:
  - SUCCESS → "Purchase complete!" toast; a Remove-Ads card flips to **"Owned ✓"**
    (disabled). Wallet animates via the S5-002 HUD pills (`economy_event`).
  - FAILED → "Purchase didn't go through" toast; wallet untouched; card re-enabled.
- **Restore Purchases** → `IAPService.restore()`; on `restore_completed(n)` shows
  "Restored N purchase(s)" or "Nothing to restore".
- Remove-Ads "Owned" is read through `EntitlementService.should_suppress_interstitials()`
  — never the `remove_ads_owned` field (single-reader chokepoint, ADR-0014 §3) — and
  live-updates on `remove_ads_changed`.
- Each resolution emits `AnalyticsService.track_iap_purchase(sku, success)` (AC-7).
- Entry point: tapping a HUD wallet pill (S5-002 `currency_tapped`) opens the Shop
  (`main.gd._open_shop`), one at a time, dismissable via the ✕ or a backdrop tap.

## Automated evidence (BLOCKING — green)

`tests/integration/shop/shop_screen_test.gd` — two integration layers:

**Real scene (`main.tscn` + autoloads):**

| Test | Asserts |
|---|---|
| `test_currency_tap_opens_shop_and_renders_full_catalog` | pill tap opens the Shop; one buy button per authored SKU incl. Remove-Ads |
| `test_real_backend_purchase_fails_and_leaves_wallet_untouched` | **AC-2 failure** — the mock-first (always-FAILED) backend surfaces the error toast; wallet unchanged |

**Injected fakes (deterministic success/owned/restore/analytics — the autoload backend can't succeed until a real SDK is wired):**

| Test | Asserts |
|---|---|
| `test_successful_purchase_marks_remove_ads_owned_and_tracks_analytics` | **AC-3/AC-7** — SUCCESS → "Owned ✓" + disabled + analytics `[sku, true]` |
| `test_failed_purchase_toasts_and_tracks_without_owning` | **AC-2/AC-7** — FAILED → error toast, card re-enabled, analytics `[sku, false]` |
| `test_restore_reports_restored_count` | **AC-4** — "Restored 1 purchase(s)" |
| `test_restore_with_nothing_reports_none` | **AC-4** — "Nothing to restore" |
| `test_opens_with_remove_ads_already_owned` | **AC-3** — a held entitlement opens the card in the Owned state |

Full suite: **787 test cases, 0 failures** (780 baseline + 7 new).

## Screenshot evidence (ADVISORY)

Rendered at 390×844 portrait via
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tools/screenshot_shop.gd`.

| File | Shows |
|---|---|
| `shop-default.png` | Full catalog — Remove-Ads anchor (`$2.99`, summary ellipsized), Handful/Sack of Coins, Pouch of Gems, Starter Bundle, Restore Purchases. |
| `shop-remove-ads-owned.png` | After `EntitlementService.grant_remove_ads()`: the Remove-Ads card reads **"Owned ✓"** (grey, disabled) — proving the chokepoint gating end-to-end. |

## Notes / follow-ups

- **Consent-unavailable state** (AC edge case): when `ComplianceService.can_process_iap()`
  is false a purchase fails (Gate 1) and surfaces the error toast. The proactive
  "purchases unavailable / Enable in Settings" affordance belongs with the deferred
  consent-UI sprint and is a follow-up (the mock-consent path is exercised here).
- **Deep-link filter**: `currency_tapped(currency)` opens the full catalog; scrolling/
  filtering to the tapped currency is a follow-up (spec §3.1 nicety).
- **PENDING spinner**: the mock backend resolves synchronously, so the disabled/spinner
  window isn't visible; the code disables the card during the call for a future async SDK.
- The real IAP backend always FAILS by design (mock-first M4) until a native SDK lands
  (device sprint) — that's why the success paths are proven via injected fakes.
