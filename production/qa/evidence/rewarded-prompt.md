# S5-004 — Rewarded-Ad Prompt · QA Evidence

**Story:** S5-004 (Sprint 5 — Monetization UI) · **Type:** UI/Integration
**Spec:** `design/ux/monetization-ui.md` §3.3 · AC-5
**Status:** integration suite green + screenshots captured.

## What shipped

`scenes/ui/rewarded_prompt.gd` (`RewardedPrompt extends PopupBase`) — the opt-in
"watch a rewarded ad" component, a thin view over `AdService`:

- Presents the offer ("Watch a short ad for **+N coins**"); the amount is read from the
  service (`AdService.rewarded_reward_amount()` → `EconomyConfig.coins_rewarded_ad`),
  never hardcoded.
- **Watch** → `AdService.show_rewarded()`; the service owns presentation + the daily/
  compliance gate + the `WalletService` credit and returns the coins actually credited:
  - `> 0` → emits `AnalyticsService.track_ad_reward(coins)`, fires `reward_earned(coins)`,
    shows "+N coins!" and auto-closes (HUD pills animate via `economy_event`).
  - `0` (abandoned / no-fill / capped) → shows "No reward this time" and closes; nothing
    credited.
- **No thanks** / backdrop → close, no ad shown (always opt-in, never auto-shown).
- Double-tap guarded (`_resolved`) so a completed view is never spent twice.

**Attach point (this sprint):** the **win** result screen. `main.gd._show_result` reveals
a "🎬 Watch for +N coins" button (`ResultScreen.reveal_rewarded_offer`) **only** when
`AdService.is_rewarded_available()`; tapping it opens the prompt over the result screen.
(The booster/near-loss attach points in §3.3 need a rewarded→booster grant path in
`AdService` that doesn't exist yet — tracked as a follow-up.)

## Automated evidence (BLOCKING — green)

`tests/integration/rewarded/rewarded_prompt_test.gd` — two integration layers:

**Real scene (`main.tscn` + autoloads):**

| Test | Asserts |
|---|---|
| `test_win_reveals_rewarded_offer_when_available_and_opens_prompt` | adult under cap → offer revealed; tap opens the prompt |
| `test_win_hides_offer_when_rewarded_unavailable` | **AC-5** — CHILD age → restricted → no offer button (no dead button) |

**Injected fakes (deterministic credit/abandon):**

| Test | Asserts |
|---|---|
| `test_watch_credits_once_and_tracks_reward` | **AC-5** — one ad shown, `reward_earned(60)`, analytics `[60]` |
| `test_double_confirm_only_watches_once` | **AC-5** — fast double-tap → exactly one view |
| `test_abandoned_view_credits_nothing` | **AC-5** — 0 credit → no analytics, "No reward this time" |
| `test_declining_never_shows_an_ad` | **AC-5** — decline never presents an ad (opt-in) |

Full suite: **793 test cases, 0 failures** (787 baseline + 6 new).

## Screenshot evidence (ADVISORY)

Rendered at 390×844 portrait via
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tools/screenshot_rewarded.gd`.

| File | Shows |
|---|---|
| `rewarded-offer.png` | The win result screen ("WELL DONE!") with the opt-in "🎬 Watch for +60 coins" offer above "TAP TO CLAIM". |
| `rewarded-prompt.png` | The `RewardedPrompt` open — "FREE COINS" / "+60 coins" / Watch / No thanks. |

## Notes / follow-ups

- **Booster/near-loss attach points** (spec §3.3): deferred — they need a rewarded→booster
  grant path in `AdService`; the component is already reusable via a caller-supplied offer
  text (`configure(..., offer_text)`).
- Reward amount (`+60`) is data-driven from `EconomyConfig.coins_rewarded_ad`.
