# Monetization UI — UX Spec

> **Status:** Draft (planning) · **Sprint:** 5 (Monetization UI — the view half of
> Milestone M4 Monetize) · **Consumes:** the M4 service seams (PR #39).
> **Scope note:** this sprint builds the **commerce + ad presentation** surfaces.
> The first-run **age-gate / CMP consent UI is a separate dedicated sprint**
> (compliance-critical); until it ships, these surfaces are exercised in tests with
> mock consent **granted**, and gated live by `ComplianceService` in production.

## 1. Overview

Four player-facing surfaces that turn the (already tested, mock-backed) monetization
service core into a calm, non-nagging storefront and ad layer:

1. **Wallet display** — coins **and gems** in the HUD, live-bound to `WalletService`.
2. **Shop screen** — the `IAPCatalog` rendered as purchasable offers (currency packs,
   Remove-Ads anchor, starter bundle), driving `IAPService.purchase` / `restore`.
3. **Rewarded-ad prompt** — opt-in "watch for reward" attach points →
   `AdService.show_rewarded`.
4. **Interstitial + Remove-Ads offer** — the between-levels interstitial presentation
   (mock) at `AdService` boundaries, plus one tasteful per-session Remove-Ads anchor.

All four are **thin views** over the services (ADR-0001 model/view seam): the UI reads
state and emits intent; the services own all economy/entitlement/consent decisions.

## 2. Player Fantasy

"The game respects me." Purchases feel optional and generous, never coerced. The
calm/edu tone is protected: no countdown-timer pressure, no interstitial mid-puzzle,
one gentle offer per session at most, rewarded ads framed as *free help I chose*.
Remove-Ads reads as a fair one-time thank-you that visibly quiets the experience.

## 3. Detailed Rules — per surface

### 3.1 Wallet display (HUD)
- Extend `scenes/ui/hud.gd` top bar with a **gems** pill beside the existing coins pill.
- Both live-bind to `WalletService.balance(currency)` and refresh on the
  `WalletService.economy_event` signal (never poll in `_process`).
- Tapping a currency pill opens the **Shop** filtered to that currency (deep-link).
- Earn/spend deltas animate with a brief count-up + a `+N` / `−N` float (respects
  `SettingsService` reduced-motion → instant snap, no float).

### 3.2 Shop screen
- New `scenes/ui/shop_screen.tscn` (+ `shop_screen.gd`), built on `popup_base`.
- Renders `IAPCatalog` (`assets/data/iap_catalog.tres`) as a scrollable list of
  **offer cards**, grouped: Remove-Ads (anchor, top) · currency packs · starter bundle.
- Each card shows: display name, grant summary (icon + amount, or "Removes ads"),
  and the localized price string. **Requires a catalog display-metadata extension**
  (see §6 Dependencies — the resource currently has no title/description).
- Card tap → `IAPService.purchase(sku)`; card disabled + spinner while
  `current_state() == PENDING`.
- Subscribes to `IAPService.purchase_completed(sku, outcome)`:
  - SUCCESS → success toast, wallet animates, card returns to idle (Remove-Ads card
    flips to "Owned ✓" and disables).
  - FAILED / blocked → non-blocking error toast ("Purchase didn't go through"),
    wallet unchanged.
- **Restore purchases** button → `IAPService.restore()`; on `restore_completed(n)`
  show "Restored N purchase(s)" (or "Nothing to restore").
- Remove-Ads card hidden/"Owned" when `EntitlementService.should_suppress_interstitials()`
  is true (read via a service query, **never** the `remove_ads_owned` field — chokepoint).
- Emits `AnalyticsService.track_iap_purchase(sku, success)` on each resolution.

### 3.3 Rewarded-ad prompt
- New `scenes/ui/rewarded_prompt.tscn` reusable across attach points:
  - **Result screen**: "Watch an ad for +N coins" (double/bonus).
  - **Booster tray / near-loss**: "Watch for a free hint / extra discard / continue".
- Visible only when `AdService.is_rewarded_available()` (else the attach point hides
  the offer, no dead button).
- Confirm → `AdService.show_rewarded()`; on the returned credit (`> 0`) or the
  `rewarded_earned(coins)` signal, animate the reward and close; on `0`
  (abandoned/capped) close quietly with a soft "No reward this time".
- Always opt-in; never auto-shown; never during active arithmetic.
- Emits `AnalyticsService.track_ad_reward(coins)`.

### 3.4 Interstitial + Remove-Ads offer
- **Interstitial**: the `Main` controller calls `AdService.notify_level_completed()` then
  `AdService.maybe_show_interstitial()` at the level-complete boundary. On `SHOWN`, a
  mock full-screen "Ad" placeholder (`scenes/ui/interstitial_mock.tscn`) displays with a
  close affordance after a short beat; on any `SUPPRESSED_*` / `NO_FILL` the flow proceeds
  with no UI. Emits `AnalyticsService.track_ad_impression(ad_type)`.
- **Remove-Ads offer**: at most **one per session**, surfaced after ~session 2–3 or after
  the first interstitial, as a dismissible banner/sheet anchoring the Remove-Ads SKU →
  opens the Shop to that card. Suppressed entirely when Remove-Ads is owned.

## 4. Formulas / bindings

- Displayed price = format(`IAPCatalogEntryResource.price_cents`) → `"$%d.%02d"` (mock;
  real builds substitute the store's localized price string). **Tuning:** price_cents live
  in the catalog `.tres` / remote config (S4-005/006) — never hardcoded in the view.
- Rewarded reward amount, interstitial cadence, ad availability = **read from the
  services** (`EconomyConfig.coins_rewarded_ad`, `interstitial_every_n_levels`,
  `interstitial_min_seconds`); the UI shows what the service reports, computes nothing.
- Offer-per-session cap = 1 (view-side counter reset on app foreground; tunable).

## 5. Edge Cases

- Purchase resolves while the Shop is closing / player navigates away → guard against a
  toast on a freed node (connect with `CONNECT_ONE_SHOT` or check `is_inside_tree`).
- `is_rewarded_available()` flips to false between prompt-show and confirm (daily cap hit
  mid-flow) → `show_rewarded()` returns 0, prompt closes with the soft no-reward message.
- Remove-Ads bought elsewhere (restore) while Shop open → card live-updates to "Owned".
- Consent not yet granted (pre consent-UI sprint): `ComplianceService.can_process_iap()`
  false → Shop shows purchases as unavailable with a "Enable in Settings" affordance
  (stub → the future consent flow); `can_show_targeted_ads()` only affects ad *type*, not
  the UI.
- Wallet at cap during a currency-pack purchase → IAP is uncapped (`grant_iap_currency`),
  so the full pack always lands; the wallet display shows the true (possibly cap-exceeding)
  balance.

## 6. Dependencies

- **Services (M4, shipped):** `WalletService`, `IAPService`, `AdService`,
  `EntitlementService`, `ComplianceService`, `AnalyticsService`.
- **New data need:** extend `IAPCatalogEntryResource` with **display metadata**
  (`display_name`, `grant_summary`/`icon`, and a localization key) — the resource today
  carries only mechanical fields. Small `data/` + `.tres` change; unit-tested with S4-006.
- **UI toolkit (reuse):** `scenes/ui/popup_base.gd`, `hud.gd`, `result_screen.gd`,
  Kenney skin (`assets/ui/`), booster icon set. New scenes scoped by `ui-code` rules.
- **Blocked-by (soft):** the **consent/age-gate UI sprint** — until it ships, the Shop's
  "purchases available" state and personalized-ad type are gated by mock consent in tests.
- **Localization:** price + copy strings should route through a string table (i18n lead) —
  flagged, not blocking for the mock sprint.

## 7. Tuning Knobs

| Knob | Source | Notes |
|---|---|---|
| Offer-per-session cap | view constant (default 1) | protect the calm tone |
| Reward amounts / ad cadence | `EconomyConfig` (S3/S4) | UI reads, never sets |
| Catalog SKUs / prices / grants | `iap_catalog.tres` + remote (S4-005/006) | data-driven |
| Reduced-motion / haptics | `SettingsService` | disables floats/count-up + taps |
| Remove-Ads offer trigger (session N) | view constant | merchandising |

## 8. Acceptance Criteria

- **AC-1** Gems balance appears in the HUD and updates on `economy_event` (integration
  test on `main.tscn`).
- **AC-2** Shop renders every `IAPCatalog` SKU with name/grant/price; a card tap drives
  `IAPService.purchase` and reflects SUCCESS/FAILED without touching the wallet on failure.
- **AC-3** Remove-Ads card shows "Owned" and interstitials stop once the entitlement is held
  (end-to-end through `EntitlementService`).
- **AC-4** Restore purchases surfaces the correct restored count.
- **AC-5** Rewarded prompt only appears when `is_rewarded_available()`; confirm credits the
  wallet exactly once; abandon credits nothing.
- **AC-6** Interstitial shows only on `AdService` `SHOWN`, never mid-puzzle, and respects the
  frequency cap + Remove-Ads suppression.
- **AC-7** Each purchase/impression/reward emits the matching `AnalyticsService` funnel event
  (consent permitting).
- **AC-8** Every surface honors reduced-motion + is reachable/operable by touch at 390×844
  (accessibility-specialist sign-off; ADVISORY).

## 9. Out of scope (this sprint)

Age-gate / CMP consent UI (own sprint) · cosmetic/season-pass store · banner ads ·
native ad/IAP SDK (device sprint) · real localized pricing (mock `$X.XX`).
