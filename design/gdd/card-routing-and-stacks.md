# Card Routing & Stacks

> **Status**: Implemented
> **Author**: Reverse-engineered from `core/board_model.gd`
> **Last Updated**: 2026-06-08
> **Last Verified**: 2026-06-08
> **Implements Pillar**: Calm-not-frantic · Math-is-the-mechanic

## Summary

The core game. The player taps an exposed floor card; the game computes the
card's arithmetic result and routes it onto one of four stacks that collect a
matching target value. Filling a stack of three clears it and cascades, pulling
matching cards back from the discard row. This is where the puzzle and the mental
math live.

> **Quick reference** — Layer: `Core` · Priority: `MVP` · Key deps: `Floor Exposure`, `Math Exercises`, `Level & Solvability`

## Overview

Cards are dealt onto a layered floor. Four stacks sit above the floor, each
showing a **target result**. The player reads a card's exercise (e.g. `3 + 4`),
computes the result (7), and taps it. If a stack currently wants that result and
has room, the card flies there; otherwise it lands in the discard row. When a
stack reaches capacity (3) it clears, draws the next target from the level's
queue, and pulls any matching discarded cards back in — which can chain into a
satisfying combo. Clear the whole floor to win; overflow the discard row to lose.

## Player Fantasy

"I'm calmly sorting a messy pile into neat, satisfying stacks — and I feel a
little sharper each time, because I did the math to do it." The pleasure is the
*clear-and-cascade* payoff and the quiet competence of fast mental arithmetic.
Never frantic: difficulty is planning and computation, not reflex.

## Detailed Design

### Core Rules

Constants (from `core/board_model.gd`): `STACK_COUNT = 4`,
`STACK_CAPACITY = 3`, `DISCARD_SLOTS = 5`, `NO_TARGET = -1`.

`tap_card(card_id)` resolves a tap and returns an ordered `Array[GameEvent]`:

1. **No-op guards** (return empty array, nothing happens) if: the game is over,
   the card is already removed, or the card is not currently exposed
   (see Floor Exposure).
2. Compute `result = result_of(card_id)`.
3. **Find an open matching stack**: the first stack whose `target == result` and
   whose `count < STACK_CAPACITY`.
   - **If found** → remove the card from the floor, increment that stack's count,
     emit `ROUTE(card_id, stack_index)`.
   - **If not found** → take the first empty discard slot.
     - If a slot exists → remove from floor, place in discard, emit
       `DISCARD(card_id, slot)`.
     - If the discard row is full → set `lost`, emit `LOSE`, return immediately.
4. **Resolve cascade** (loop until no full stack remains):
   - Find a stack at capacity. Reset its count to 0, draw the next target from
     the queue, set it as the stack's new target, emit
     `STACK_CLEARED(stack_index, new_target)`.
   - If the new target is not `NO_TARGET`, **pull matching** cards from discard
     into that stack (in slot order) until it is full or no more match; emit
     `PULL(card_id, stack_index, slot)` for each.
   - Pulling can refill a stack to capacity, so the loop repeats (cascade).
5. **Win check**: after the cascade, if the floor is empty (`floor_count() == 0`)
   and not already won, set `won`, emit `WIN`.

### States and Transitions

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| In play | level start | win or lose | taps resolve normally |
| Won | floor empty after a tap | — | `is_game_over()` true; taps are no-ops |
| Lost | discard full with no slot | — | `is_game_over()` true; taps are no-ops |

Per-stack: a stack holds a `target` (the result it collects) and a `count`
(0..3). On clear it adopts the next queue target or `NO_TARGET` (queue exhausted
→ stack goes inert).

### Interactions with Other Systems

- **Math Exercises**: supplies each card's `result` (the only card property the
  engine reads).
- **Floor Exposure**: gates which cards are tappable; the engine asks
  `is_exposed(card_id)` before routing.
- **Level & Solvability**: builds the board (`results`, `covered_by`,
  `target_queue`) via `BoardModel.from_config`.
- **View layer** (`scenes/`): consumes the returned `GameEvent` list and animates
  it; it never computes outcomes (see ADR-0002).

## Formulas

### Stack target matching

```
routable(card, stack) = (stack.target == card.result) AND (stack.count < STACK_CAPACITY)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| card.result | int | level-defined (e.g. 5–16) | `data/CardData` | Value printed by the exercise |
| stack.target | int | level queue values, or -1 | `target_queue` | Result this stack currently collects |
| stack.count | int | 0..3 | runtime | Cards currently on the stack |

### Clear & draw

```
on count == STACK_CAPACITY:
    count ← 0
    target ← queue[draw_index]; draw_index ← draw_index + 1   (or NO_TARGET if exhausted)
```

`draw_index` starts at `STACK_COUNT` (4), because the first 4 queue entries seed
the 4 starting stacks.

**Example cascade**: stack A (target 7) reaches 3 → clears → draws target 9 →
two `9`s sit in discard → both pulled into A → A now has 2/3, no clear → cascade
ends.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|-------------------|-----------|
| Tap a covered (unexposed) card | No-op, empty event list | Exposure gates input |
| Tap after win/lose | No-op | Game is over |
| No matching stack, discard has space | Card → discard | Deferred until a stack rotates to its value |
| No matching stack, discard full | Immediate `LOSE` | Fail state |
| Stack clears, queue exhausted | Stack target = `NO_TARGET` (inert) | Solvability guarantees remaining cards still route |
| Pull would exceed capacity | Stop at `STACK_CAPACITY` | Capacity is hard |
| Last card routes and floor empties | `WIN` emitted after cascade | Win evaluated post-cascade |
| Same target appears twice in queue | Stack re-collects it later | Enables same-value combos (Level 3) |

## Dependencies

| System | Direction | Nature |
|--------|-----------|--------|
| Math Exercises | This depends on it | Reads `card.result` |
| Floor Exposure | This depends on it | `is_exposed` gate, removal updates exposure |
| Level & Solvability | This depends on it | Board construction + winnability guarantee |
| View layer | Depends on this | Replays emitted `GameEvent`s |

## Tuning Knobs

| Parameter | Current | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|-----------|--------------------|--------------------|
| `STACK_COUNT` | 4 | 3–6 | More parallel targets → easier | Fewer → more discard pressure |
| `STACK_CAPACITY` | 3 | 2–4 | Longer to clear, bigger combos | Faster clears, fewer combos |
| `DISCARD_SLOTS` | 5 | 3–7 | More forgiving (more buffer) | Tighter, higher tension |

> ⚠️ Changing `STACK_CAPACITY` breaks the `3×N` solvability invariant baked into
> level data and `LevelData.is_solvable`. Treat it as a content-wide change, not a
> per-level tweak (see ADR-0003).

## Acceptance Criteria

- [x] Tapping an exposed card with a matching open stack routes it (test_board_model).
- [x] Tapping with no match and free discard discards it.
- [x] Discard full + no match → `LOSE`.
- [x] Full stack clears, draws next target, pulls matching discards (cascade).
- [x] Floor empty → `WIN`.
- [x] No-op on covered card, removed card, or after game over.
- [x] `tap_card` is pure: same state + same tap ⇒ same event list (deterministic).
- [ ] Performance: a tap (incl. cascade) resolves well under 1 ms on mid mobile.

## Open Questions

| Question | Owner | Resolution |
|----------|-------|-----------|
| Should an undo booster revert one tap? | game-designer | Roadmap (Phase 1); must not auto-solve math |
| Scoring formula (stars/efficiency)? | systems-designer | Open — fewer discards = higher; TBD |
