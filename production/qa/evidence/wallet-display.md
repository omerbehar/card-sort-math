# S5-002 — HUD Wallet Display (coins + gems) · QA Evidence

**Story:** S5-002 (Sprint 5 — Monetization UI) · **Type:** UI/Integration
**Spec:** `design/ux/monetization-ui.md` §3.1 · AC-1
**Status:** integration suite green + screenshots captured.

## What shipped

- Coins **and** gems pills in the HUD top bar (`scenes/ui/hud.gd`), each a thin view
  over `WalletService`:
  - Seeded from `WalletService.balance(currency)` at build.
  - Refreshed on every `WalletService.economy_event` (never polled in `_process`).
  - Brief count-up on earn/spend with a `+N` / `−N` float; snaps instantly under
    `SettingsService.reduced_motion` (accessibility).
  - Tapping a pill emits `Hud.currency_tapped(currency)` — the Shop deep-link hook
    wired by S5-003.
- Removed the stopgap coins `Label` that `main.gd` drew on `_hud_layer`; it overlapped
  the percent badge (see "before/after the reflow" note below). The top bar is now a
  single clean row: `[gear] [LV] [%] [🪙 coins] [💎 gems]`.

## Automated evidence (BLOCKING — green)

`tests/integration/hud/wallet_display_test.gd` (drives the real `main.tscn` + autoloads):

| Test | Asserts |
|---|---|
| `test_wallet_pills_present_and_seeded_from_service` | both pills exist and read the live balances |
| `test_gems_pill_updates_on_economy_event` | **AC-1** — gems pill reflects the new balance after an IAP grant |
| `test_coins_pill_updates_on_earn` | coins pill reflects the new balance after an earn |
| `test_tapping_coins_pill_emits_currency_tapped` | pill tap fires the Shop deep-link intent |

Full suite: **780 test cases, 0 failures** (776 baseline + 4 new). The migrated
`main_booster_flow_test` debug-reset assertion now checks the HUD pill.

## Screenshot evidence (ADVISORY)

Rendered at 390×844 portrait via
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tools/screenshot_wallet_display.gd`.

| File | Shows |
|---|---|
| `wallet-display-before.png` | Top bar with `🪙 1250` (gold pill) + `💎 58` (violet pill); the `+8` gems count-up float visible. No overlap with the LV / % chrome. |
| `wallet-display-after.png` | After `earn(coins,+250)` + `grant(gems,+40)`: pills live-updated to `🪙 1500` / `💎 98`, with the fading `+250` / `+40` floats — proving the `economy_event` binding + count-up end-to-end. |

Pill tints are luminance-distinct (warm gold vs. cool violet), not hue-only —
colorblind-safe per `ui-code` rules.

## Notes / follow-ups

- The `currency_tapped` deep-link is emitted but not yet consumed — the Shop screen
  (S5-003) connects it. Until then, tapping a pill is a no-op by design.
- Accessibility sign-off (AC-8, touch reachability + reduced-motion) remains ADVISORY
  for the `accessibility-specialist` pass.
