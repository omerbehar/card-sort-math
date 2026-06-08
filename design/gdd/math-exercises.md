# Math Exercises (Card Content)

> **Status**: Implemented (addition only)
> **Author**: Reverse-engineered from `data/card_data.gd`
> **Last Updated**: 2026-06-08
> **Last Verified**: 2026-06-08
> **Implements Pillar**: Math-is-the-mechanic

## Summary

Defines what is printed on a card and the one value the sort engine cares about:
its `result`. Today every card is an addition exercise (`a + b`); the player must
compute the sum to know where the card belongs. This is the system that turns a
sort puzzle into a math game.

> **Quick reference** — Layer: `Feature` · Priority: `MVP` (addition); generalize in `Full Vision` · Key deps: `Level & Solvability`

## Overview

A `CardData` resource carries two operands and their sum, plus layout fields
(`layout_layer`, `layout_slot`) describing where the card sits. The displayed
exercise (`exercise_text` → e.g. `"3 + 4"`) forces the player to do the
arithmetic; the engine then routes by the computed `result`. Because the engine
only reads `result`, the *operation* is a content concern — future worlds can add
subtraction, multiplication, etc. without touching the sort logic.

## Player Fantasy

"I'm doing quick sums in my head and it feels effortless and satisfying — I'm
getting faster." Practice is implicit: the math is the means to play, not a quiz
interrupting play.

## Detailed Design

### Core Rules

- `CardData` fields: `operand_a`, `operand_b`, `result`, `layout_layer`,
  `layout_slot`.
- Invariant (today): `result == operand_a + operand_b` (addition).
- `CardData.create(a, b, layer, slot)` computes `result = a + b`.
- `exercise_text()` returns `"%d + %d"` (operator hard-coded to `+`).
- Operand selection is done by the level builder, not the card: `_split_operands(result, slot)`
  picks `a = 1 + (slot % (result-1))`, `b = result - a`, so cards sharing a result
  show different operand pairs (e.g. `3+4` and `5+2` both = 7). For `result ≤ 1`
  it returns `(0, max(result,0))`.

### Interactions with Other Systems

- **Level & Solvability** constructs all `CardData` (it owns operand choice via
  `_split_operands`).
- **Card Routing & Stacks** reads only `result`.
- **View layer** renders `exercise_text()` on the card face.

## Formulas

### Result & operand split

```
result      = operand_a + operand_b
a (split)   = 1 + (slot mod (result - 1))     # for result ≥ 2
b (split)   = result - a
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| result | int | ≥ 0 (currently 5–16) | level data | Sort key; what stacks match on |
| operand_a/b | int | 0..result | `_split_operands` | Displayed addends |
| slot | int | 0..pool size | layout | Varies operand pairs across equal-result cards |

**Example**: `result = 7`, slots 0,1,2 → `(1+0)→1+6`, `(1+1)→2+5`, `(1+2)→3+4`.
All read differently, all equal 7.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|-------------------|-----------|
| `result ≤ 1` | Split returns `(0, result)` | Avoids modulo by zero/negative |
| Two cards, same result | Different operand pairs shown | Variety; avoids visual repetition |
| `a == b` (e.g. 4+4) | Allowed | Valid sum |
| result equal to a stack target with 0 supply | Prevented upstream | Solvability invariant (see Level GDD) |

## Dependencies

| System | Direction | Nature |
|--------|-----------|--------|
| Level & Solvability | This depends on it | It builds cards & chooses operands |
| Card Routing & Stacks | Depends on this | Consumes `result` |
| View layer | Depends on this | Renders `exercise_text()` |

## Tuning Knobs

| Parameter | Current | Safe Range | Effect |
|-----------|---------|-----------|--------|
| Operation type | Addition only | +, −, ×, ÷, mixed | Defines difficulty band / "world" |
| Operand magnitude | 1..15-ish | content-driven | Larger operands → harder mental math |
| Operand-split policy | `1 + slot%(r-1)` | any sum = result | Controls visual variety & subtraction framing |
| Allow zero / negatives | no | per world | Negatives raise difficulty (future) |

## Acceptance Criteria

- [x] `result == operand_a + operand_b` for every created card (test_card_data).
- [x] `exercise_text()` renders `"a + b"`.
- [x] Cards with the same result can display different operand pairs.
- [x] `_split_operands` handles `result ≤ 1` without error.
- [ ] (Future) An `operation` enum drives display + result for non-addition worlds.

## Open Questions

| Question | Owner | Resolution |
|----------|-------|-----------|
| Add an `operation` field to `CardData`? | systems-designer | Recommended before Phase 1 worlds; keeps engine result-only |
| Subtraction framing (which operand larger) | game-designer | Open — split policy must guarantee non-negative for `−` world |
