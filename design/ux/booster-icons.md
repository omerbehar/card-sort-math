# Booster Icon Spec — CardSortMath

**Status:** Approved UX spec (ux-designer, 2026-06-13). Source mechanics:
`design/gdd/deck-economy.md` Core Rules 8/10/11. Replaces the placeholder
drill / hammer / potion tool icons. Implementation-ready.

The three boosters (Hint was replaced by **Picker**, 2026-06-13):

| Booster | Mechanic | Coin cost |
|---|---|---|
| **Picker** | Player selects any covered (lower-layer) card; it plays immediately (route or discard), bypassing coverage. | 120 |
| **Reshuffle** | Re-permutes floor coverage (same card set + queue); changes which cards are exposed. | 250 |
| **Extra Discard Slot** | Appends one temporary discard slot for the level (purchase-ahead, max 7). | 350 |

---

## 1. Shared visual system

- **Button frame:** square tile from the Kenney `slot_grey.png` nine-patch — echoes the
  discard-row slots, grounding boosters in the game's own vocabulary (no card/stack imagery).
- **Touch target:** 44×44 pt (non-negotiable, WCAG 2.5.5). Visual tile 40×40 pt with a 2 pt
  invisible padding ring (same invisible-padding-not-visual-growth pattern as `DiscardRow`).
- **Glyph area:** 24×24 pt centered (8 pt margin), shared 3 pt stroke weight, white-on-transparent.
- **Cost badge:** bottom-right, dark pill, a 12 pt coin glyph + digits. Numeral 10 sp, scales with
  system text size; tile does not grow. Pill stays dark in all states (tile + glyph change instead).
- **Tray:** three tiles in a centered horizontal row at the bottom of the play area
  (thumb-reachable), 12 pt gaps (matches `DiscardRow.SLOT_GAP`). Coin balance lives top-right.

## 2. Per-icon concepts

- **Picker** — a downward finger/pointer passing through 3 thin horizontal layer-bars: "reach
  past the coverage and pull a buried card." Bars are short (mid-floor cross-section), not the
  rounded discard slots.
- **Reshuffle** — a circular refresh arrow (≈270° arc + arrowhead) with 3 small dots inside:
  the universal "shuffle / re-deal"; dots = cards being repositioned (no values).
- **Extra Discard Slot** — a single discard-slot-shaped frame + bold "+": references the real
  discard row → reads as "+1 buffer space" (empty slot = buying space, not a card).

Collision check: none overlaps the card (rounded portrait), stack (tall colored column), or the
discard slot enough to confuse — Extra Discard *intentionally* echoes the slot, differentiated by "+".

## 3. Button states (all distinguishable WITHOUT color)

1. **Affordable** — tile warm-tinted, glyph full opacity, cost badge normal.
2. **Unaffordable** (balance < cost) — desaturated tile, glyph 40%, coin badge gains a diagonal
   **X** stroke; tap → shake (motion cue) + "not enough coins" toast. Button stays visible.
3. **Precondition-disabled** — desaturated + a **diagonal slash** over the glyph (shape cue that
   separates "can't use" from "can't afford"); tap → pulse + context toast.
4. **Picker-armed** — animated dashed border + glyph pulse (static thick border under
   `reduced_motion`); cost badge hidden; floor cards highlight via `FloorArea.set_pickable_all`.
   Tapping the button again cancels (no spend).
5. **Spend-confirm modal** — for ≥250 boosters (`SPEND_CONFIRM_THRESHOLD`): dim tray, show
   "[coin] Spend 250? [Confirm] [Cancel]" (both ≥44 pt) above the tapped button.

Every cue is shape/motion, never hue-only; all animations gate on `SettingsService.get_value("reduced_motion")` (same pattern as `DiscardRow._reduced_motion()`).

## 4. Accessibility

44 pt targets; colorblind-safe (luminance/saturation + shape, consistent with the `StackPalette`
Okabe-Ito pattern); cost label scales to 1.3×/1.5× text size without truncation ("350" fits);
no flashing; keyboard/gamepad N/A (touch-only project).

## 5. Asset list

**Reuse (no new art):** tile frame `kenney/slot_grey.png`; badge pill `kenney/round_grey.png`;
slash/dashed-border/dim drawn in code (`Line2D` / `_draw`).

**New art (5 SVGs, white-on-transparent, 3 pt stroke at 24 pt source):**
`icons/booster_picker.svg`, `icons/booster_reshuffle.svg`, `icons/booster_extra_discard.svg`,
`icons/coin_sm.svg` (gold circle+ring, distinct from the `dot_full` stack-fill dot),
`icons/coin_unavailable_sm.svg` (coin + diagonal X).

## 6. Handoffs

- **Art-director (owns final visual identity):** the exact warm "affordable" tint (avoid yellow
  = Kenney `slot_yellow`, avoid green = positive-feedback palette); confirm whether the Kenney
  Icons Pack already has a usable refresh/pointer glyph; align the cost-badge coin with the HUD
  balance coin. Match the Kenney flat/geometric register — no shadows/gradients/emboss.
- **UI-programmer (wiring):** buttons call the stable `Main.arm_picker()` / `Main.reshuffle_now()`
  / `Main.buy_extra_discard()`. State refresh subscribes to `WalletService.economy_event`
  (afford), board `GameEvent`s (precondition), and `Main._picker_armed` (armed). Spend-confirm is
  handled in the button before calling the booster.

## 7. Not decided here (owners)

Exact warm hue, Kenney-glyph availability, HUD coin style alignment, toast visual system, and the
spend-confirm strip visual treatment — all art-director / future toast-system decisions. This spec
fixes the interaction contract and metaphors only.
