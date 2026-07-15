# S5-008 — Monetization UI Accessibility & Reduced-Motion Pass · QA Evidence

**Story:** S5-008 (Sprint 5 — Monetization UI) · **Type:** Visual/UI (ADVISORY gate)
**Spec:** `design/ux/monetization-ui.md` AC-8 · `.claude/rules/ui-code.md`
**Status:** pass complete — one reduced-motion gap fixed; findings + evidence consolidated.

Covers all five monetization surfaces shipped this sprint: HUD wallet display (S5-002),
Shop (S5-003), rewarded prompt (S5-004), interstitial (S5-005), Remove-Ads offer (S5-006).

## 1. Reduced-motion (MANDATORY — `ui-code`: "animations must respect motion prefs")

Every animation on a monetization surface is gated on `SettingsService.reduced_motion`:

| Surface | Animation | Gated? |
|---|---|---|
| Wallet pills | count-up + `+N/−N` float | ✅ snaps instantly (`Hud._is_reduced_motion`) — tested |
| Shop | success/error/restore toast fade | ✅ **fixed this pass** — holds then hides instantly, no fade |
| Rewarded prompt | open/close + outcome hold | ✅ open/close via `PopupBase._motion_ok`; hold is a delay, not motion |
| Interstitial | open/close + close-beat | ✅ open/close gated; the beat is a timed delay (models ad duration) |
| Remove-Ads offer | open/close | ✅ `PopupBase._motion_ok` |

`PopupBase.play_open`/`close` are the shared gate; the wallet count-up and the Shop toast
were the only bespoke animations, and both now honor the preference. The
`reduced_motion` path is exercised in the wallet, interstitial, and Remove-Ads suites.

## 2. Colorblind-safety (MANDATORY — `ui-code`: "colorblind modes are mandatory")

No surface relies on hue alone:

- **Wallet pills** — coins (warm gold) vs gems (cool violet) are **luminance-distinct**, and
  each carries a currency glyph (🪙 / 💎) + the number.
- **Shop** — the Remove-Ads anchor card is distinguished by warm tint **and** position (top)
  **and** its "Owned ✓" text/disabled state, not color alone.
- **Buttons** — every action reads by text + shape (Buy = price, Watch = "▶ Watch",
  Owned = "Owned ✓"); state changes carry a label, never a bare color swap.

## 3. Touch targets (ADVISORY findings)

Primary CTAs meet the ~44 px minimum (Shop Buy 96×46, Restore ×48, Watch 240×54,
interstitial close 46×46, Shop close 44×44, Remove-Ads CTA ×54). Sub-minimum secondary
controls, all with a larger alternative, are logged as follow-ups:

| Control | Size | Mitigation |
|---|---|---|
| HUD wallet pills | 84×**38** | deep-link convenience; balances are also read passively |
| Rewarded "No thanks" | 200×**42** | backdrop-tap also declines |
| Remove-Ads "Not now" | full-width×**30** | backdrop-tap also dismisses |

Recommendation: bump these to ≥44 px in a future polish pass (kept as-is here to avoid
disturbing the tested layouts + captured screenshots; ADVISORY gate).

## 4. Text legibility

All user-facing strings route through a `_tr()` stub (ready for a string table), render at
≥15 px with a dark outline for contrast on textured/colored backgrounds, and long strings
ellipsize (Shop grant summaries) rather than overflow.

## 5. Screenshot evidence (all surfaces, 390×844 portrait)

| Surface | Evidence |
|---|---|
| Wallet display | `wallet-display-before.png`, `wallet-display-after.png` |
| Shop | `shop-default.png`, `shop-remove-ads-owned.png` |
| Rewarded prompt | `rewarded-offer.png`, `rewarded-prompt.png` |
| Interstitial | `interstitial-mock.png` |
| Remove-Ads offer | `remove-ads-offer.png` |

## Verdict

**PASS (advisory).** Reduced-motion and colorblind-safety requirements are met across all
surfaces (one toast-fade gap fixed). Three secondary controls are below the 44 px touch
target and are logged for a polish pass; each has a larger alternative today. Full suite
**802 green**.
