# Math Exercises (Card Content)

> **Status**: Implemented (+, −, ×, ÷ as operation worlds; ADR-0011)
> **Author**: Reverse-engineered from `data/card_data.gd`
> **Last Updated**: 2026-06-14
> **Last Verified**: 2026-06-14
> **Implements Pillar**: Math-is-the-mechanic

## Summary

Defines what is printed on a card and the one value the sort engine cares about:
its `result`. A card is an arithmetic exercise (`a + b`, `a − b`, `a × b`, `a ÷ b`);
the player must compute the result to know where the card belongs. This is the
system that turns a sort puzzle into a math game. Operations are organised as
**worlds** (ADR-0011): every 5 levels advances one operation (1–5 `+`, 6–10 `−`,
11–15 `×`, 16–20 `÷`), and level 21 onward mixes all four on the same board.

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

- `CardData` fields: `operand_a`, `operand_b`, `result`, `operation`,
  `layout_layer`, `layout_slot`.
- `operation` is an `Operation.Type` enum (`ADD`, `SUBTRACT`, `MULTIPLY`,
  `DIVIDE`); ordinals are stable and default to `ADD` (0).
- Invariant: `result == Operation.apply(operand_a, operand_b, operation)` — i.e.
  `a + b`, `a − b`, `a × b`, or `a ÷ b` (exact integer division by construction).
- `CardData.create(a, b, layer, slot, operation := ADD)` computes the result via
  `Operation.apply`; the trailing default keeps addition callers unchanged.
- `exercise_text()` returns `"%d %s %d"` with the operator glyph from
  `Operation.glyph` (`+`, `−`, `×`, `÷`).
- Operand selection is done by `OperandPicker.pick(result, index, max_operand, operation)`,
  not the card. Each operation has a legal-operand window so the printed pair
  evaluates back to `result` within `[1, max_operand]`, and `index` cycles the
  window so equal-result cards show different pairs:
  - `+`: `a ∈ [max(1, r−max), min(max, r−1)]`, `b = r − a`. `result ≤ 1` → `(0, max(r,0))`.
  - `−`: `a = b + r`, divisor `b ∈ [1, max − r]`.
  - `×`: factor pairs within `[1, max]`, preferring non-trivial (both `≥ 2`).
  - `÷`: `a = r × b`, divisor `b ∈ [1, max / r]`, preferring `b ≥ 2`.
- A result is a candidate for a world only if at least one of the world's allowed
  operations has a valid pair (`OperandPicker.valid_operations`). In the mixed
  world each card's operation is chosen (seeded) from the operations valid for its
  result, so the board stays solvable.

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

- [x] `result == Operation.apply(operand_a, operand_b, operation)` for every created card (test_card_data, test_operation).
- [x] `exercise_text()` renders `"a + b"` / `"a − b"` / `"a × b"` / `"a ÷ b"`.
- [x] Cards with the same result can display different operand pairs (test_operand_picker).
- [x] `OperandPicker` handles `result ≤ 1` / no-pair misuse without error.
- [x] An `operation` enum drives display + result for non-addition worlds (ADR-0011).
- [x] Single-operation worlds and the mixed world stay solvable across seeds (test_level_generator, test_level_data_generation).

## Open Questions

| Question | Owner | Resolution |
|----------|-------|-----------|
| Add an `operation` field to `CardData`? | systems-designer | ✅ Resolved (ADR-0011): `Operation.Type` enum on `CardData`; engine still routes by `result` only |
| Subtraction framing (which operand larger) | game-designer | ✅ Resolved: `−` picker sets `a = b + result`, guaranteeing `a > b ≥ 1` (no negatives) |
| Per-world difficulty schedule | systems-designer | Open — single-op worlds currently share the addition-tuned schedule, so `÷`/`×` worlds skew easy/trivial; a per-world schedule is a future tuning task |
