# Level & Solvability

> **Status**: Implemented
> **Author**: Reverse-engineered from `autoloads/level_data.gd`, `data/level_config.gd`
> **Last Updated**: 2026-06-08
> **Last Verified**: 2026-06-08
> **Implements Pillar**: Always solvable, never unfair

## Summary

Defines what a level is — a floor layout, a queue of stack targets, and a pool of
cards — and guarantees by construction that every level is winnable. The
solvability invariant is the rule that lets us trust both hand-authored and
future generated content.

> **Quick reference** — Layer: `Foundation` · Priority: `MVP` · Key deps: `Floor Exposure (Layouts)`, `Math Exercises`

## Overview

A `LevelConfig` bundles a `layout_id`, an ordered `target_queue`, and a
`card_pool` (`Array[CardData]`). The four stacks start showing `target_queue[0..3]`;
each stack clear draws the next unused queue entry. `LevelData` is an autoload
that builds the three authored levels on demand (cached) and exposes
`is_solvable()` to validate any config. A level is solvable when the supply of
cards for every result exactly matches demand created by the queue.

## Player Fantasy

"Every level can be beaten — if I lose, it's because of my choices, not a rigged
deal." Trust in fairness is what makes the puzzle relaxing rather than stressful.

## Detailed Design

### Core Rules

- `LevelConfig` fields: `level_id`, `layout_id`, `target_queue: Array[int]`,
  `card_pool: Array[CardData]`.
- Stacks seed from the first `STACK_COUNT` (4) queue entries; clears draw forward
  from `draw_index = 4`.
- Authored data (`level_data.gd`): `_LEVEL_RESULTS` (result printed per slot),
  `_LEVEL_QUEUES` (ordered targets), `_LEVEL_LAYOUTS` (which layout per level).
- `get_level(n)` clamps `n` to the authored range and caches built configs.
- `_build_level` asserts `results.size() == layout slot count`, then creates a
  `CardData` per slot via `_split_operands` (varies operands so equal-result cards
  don't all read identically).
- `next_target(queue, draw_index)` returns the queue entry or `-1` when exhausted.

### The three authored levels

| Level | Layout | Cards | Results (×3 each) | Queue | Teaches |
|-------|--------|-------|-------------------|-------|---------|
| 1 | 0 | 12 | 5, 7, 9, 11 | `[5,7,9,11]` | Basics; all targets visible at once |
| 2 | 1 | 18 | 6, 8, 10, 12, 14, 16 | `[6,8,10,12,14,16]` | Discard + pull-back (14,16 not in starting stacks) |
| 3 | 2 | 15 | 7×6, 9, 11, 13 | `[7,9,11,13,7]` | Repeated target (7) → same-value combos |

### Interactions with Other Systems

- **Card Routing & Stacks** consumes a built `BoardModel` (`BoardModel.from_config`
  derives results, coverage graph, and queue).
- **Floor Exposure / Layouts** provides placements; card-pool size must match.
- **Math Exercises** turns each slot's result into a concrete exercise.

## Formulas

### Solvability invariant

```
solvable(config) =
    set(card.result for card in pool) == set(target_queue)
  AND  for every result r:  count(cards with result r) == STACK_CAPACITY × count(r in target_queue)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| STACK_CAPACITY | int | 3 | const | Cards needed to clear a stack |
| count(r in queue) | int | ≥1 | target_queue | How many times a stack will collect r |
| count(cards r) | int | =3×queue | card_pool | Cards printed with result r |

**Why it works**: each queue occurrence of `r` is exactly one stack-load (3
cards) of `r`. If supply = `3 × demand` for every value and the value sets match,
every card has a home and every stack that opens can be filled — the board can be
fully cleared.

**Example (Level 3)**: queue has `7` twice → demand `2`, so `2×3 = 6` cards of
result 7 (matches `7×6`). `9,11,13` each once → 3 cards each. ✓

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|-------------------|-----------|
| Card result not in queue | `is_solvable` = false | That card could never be collected |
| Queue target with no cards | `is_solvable` = false (set mismatch) | Stack would idle forever |
| `count ≠ 3 × occurrences` | `is_solvable` = false | Supply/demand mismatch leaves stranded cards or unfillable stacks |
| `get_level(n)` out of range | Clamped to nearest authored level | Safe fallback |
| `results.size() ≠ layout slots` | Assert fails at build | Authoring error caught early |

## Dependencies

| System | Direction | Nature |
|--------|-----------|--------|
| Floor Exposure (Layouts) | This depends on it | Slot count + placements |
| Math Exercises | This depends on it | Builds a `CardData` per result |
| Card Routing & Stacks | Depends on this | Receives a validated, winnable board |

## Tuning Knobs

| Parameter | Current | Safe Range | Effect |
|-----------|---------|-----------|--------|
| Distinct results per level | 4–6 | 3–8 | More distinct values → harder to track |
| Queue length / rotations | 4–6 | ≥ STACK_COUNT | Longer queue → more clears, longer level |
| Repeated targets in queue | 0–1 | 0–N | Repeats enable same-value combos |
| Result magnitudes | 5–16 | content-driven | Bigger sums → harder mental math |

## Acceptance Criteria

- [x] All three authored levels pass `is_solvable` (test_level_data, test_solvable_play).
- [x] A config with mismatched supply/demand fails `is_solvable`.
- [x] A config whose result set ≠ queue set fails `is_solvable`.
- [x] `get_level` caches and clamps correctly.
- [x] An automated playthrough clears each authored level (tools/playthrough + test_solvable_play).

## Open Questions

| Question | Owner | Resolution |
|----------|-------|-----------|
| Generator must emit only solvable configs | systems-designer | Phase 1 — reuse `is_solvable` as the gate |
| Difficulty rating per level | game-designer | Open — derive from depth, distinct results, discard pressure |
