# QA Evidence — New Layout Presets + Target Spacing

Date: 2026-06-14
Branch: `claude/unlocked-deck-progression-yr7hst`

## Scope

1. **Distinct starting decks / no two-of-a-kind in a row** — generated target
   queues now spread equal targets apart, so the two starting decks never share a
   number and no two identical targets sit back-to-back in the draw order.
2. **Three new floor layout presets** (ids 3, 4, 5) added to `core/layouts.gd` and
   rotated into the late-game layout cycle.

## Automated tests

Full gdUnit4 suite: **555 cases, 0 failures** (`godot --headless … -a res://tests`).

New / updated coverage:
- `tests/test_level_generator.gd`
  - `test_extra_layouts_generate_solvable_levels_across_seeds` — layouts 3/4/5 build
    solvable, correctly-sized boards across 30 seeds each.
  - `test_spaced_queue_has_no_two_targets_in_a_row` — no back-to-back duplicate
    targets across all layouts/seeds whenever the multiset allows it.
  - `test_spaced_queue_starting_decks_are_distinct` — `queue[0] != queue[1]`.
  - `test_spacing_is_deterministic_for_a_seed`, `test_spacing_disabled_uses_plain_shuffle`,
    `test_spacing_allows_forced_repeat_for_single_result`.
  - `test_invalid_params_return_null_config` updated (out-of-range id is now
    `SLOT_COUNTS.size()`, since id 3 is a valid preset).
- `tests/test_difficulty_schedule.gd`
  - `test_layout_cycle_covers_all_presets` — the late cycle reaches all six layouts.
  - `test_scheduled_params_generate_solvable_levels` extended with 57/65/73 (the
    first levels that hit layouts 3/4/5).
- `tests/test_layouts.gd` (unchanged) iterates `SLOT_COUNTS`, so the same-layer
  no-overlap and slot-count property checks now cover the three new presets.

The per-level stagger invariant (AC-26) still holds: the cycle is held 4 levels and
every adjacent entry (incl. wrap) differs, so layout changes land only on levels
≡ 1 mod 4 (53, 57, 61, …), which carry no other knob change.

## Screenshots (real GL renders, xvfb)

Captured via `tools/screenshot_new_layouts.gd`:

| File | Level | Layout | Logged starting decks | Logged queue |
|------|-------|--------|-----------------------|--------------|
| `layout3-lv57.png` | 57 | 3 (21 cards, 3-layer block) | `[22, 20]` | `[22, 20, 22, 14, 32, 20, 13]` |
| `layout4-lv65.png` | 65 | 4 (24 cards, 4-layer pyramid) | `[15, 23]` | `[15, 23, 4, 23, 4, 19, 15, 18]` |
| `layout5-lv73.png` | 73 | 5 (18 cards, wide overhang) | `[23, 27]` | `[23, 27, 22, 23, 28, 13]` |

Each screenshot shows two distinct starting decks (red + yellow) with the two
locked decks beside them, and each logged queue has no adjacent duplicates —
confirming both changes in the real scene.
