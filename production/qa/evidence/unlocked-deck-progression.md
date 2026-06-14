# QA Evidence — Two-Deck Default + Multi-term Progression

**Date**: 2026-06-14
**Branch**: `claude/unlocked-deck-progression-yr7hst`
**Change**: Default unlocked decks raised to two; levels 21–40 reworked into a
three-term arithmetic progression (add/sub → parentheses → order of operations),
with level 41+ mixing all styles.

## What changed

- `main.PROTO_OPEN_COUNT` `1 → 2` — two decks (stacks) start unlocked.
- New world bands in `LevelData.world_for_level`:
  - **21–25** `WORLD_TRI_ADDSUB` — `a ± b ± c`, left-to-right (e.g. `3 + 7 − 4`),
    teaching that `+`/`−` order doesn't change the value.
  - **26–30** `WORLD_TRI_PARENS` — meaningful parentheses (e.g. `7 − (5 − 1)`).
  - **31–40** `WORLD_TRI_ORDER` — `×`/`÷` mixed with `+`/`−` under precedence,
    printed without parentheses (e.g. `2 + 3 × 4`).
  - **41+** `MIXED_WORLD_ID` — all three styles mixed.
- New pure helper `TernaryExpression` (evaluate/format/grouping), three-term
  `CardData.create_ternary`, and `OperandPicker.triple_options` / `triple_renderings`.
- All values stay non-negative and divisions exact (kid-friendly); routing stays
  result-only, so the 3×N solvability invariant is untouched.

## Automated tests (BLOCKING) — PASS

Full gdUnit4 suite: **548 test cases | 0 failures**.

- `tests/test_ternary_expression.gd` (new, 13 cases) — grouping evaluation/format,
  precedence (`×`/`÷` first), and rejection of negative/inexact triples.
- `tests/test_operand_picker.gd` — ternary `triple_options`/`triple_renderings`
  evaluate-back, in-bounds, deterministic, deduped.
- `tests/test_card_data.gd` — `create_ternary` result + `exercise_text`.
- `tests/test_level_data_generation.gd` — new band mapping; levels 21–25 / 26–30 /
  31–40 / 41+ assertions; solvability across indices.
- `tests/integration/operation_worlds_test.gd` (drives `scenes/main/main.tscn`):
  three-term/parentheses/order-of-ops cards render in the live scene; **two decks
  unlocked by default** (stacks 0 & 1 open, 2 & 3 locked).

## Screenshots (real Godot renders)

Captured via `tools/screenshot_progression.gd` with
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility`.
Harness logged `locked stacks: [2, 3]` for every level — confirming the 2-deck
default.

| File | Level | Shows |
|------|-------|-------|
| `progression-three-term-addsub.png` | 21 | `7 − 3 + 3`, `2 + 7 + 2`, … (no parens) + 2 decks open, 2 locked |
| `progression-parentheses.png` | 28 | `(6 + 4) + 2`, `7 − (5 − 1)`, `8 + (6 − 2)`, … |
| `progression-order-of-operations.png` | 33 | `6 + 5 × 4`, `9 + 2 ÷ 1`, `7 × 6 − 8`, … (no parens) |
| `progression-mixed.png` | 45 | plain, parenthesised and `×`/`÷` cards together |

Spot-checks against the live LV33 stack target `11`: `9 + 2 ÷ 1 = 11`,
`3 × 3 + 2 = 11`, `2 + 9 × 1 = 11` — precedence applied correctly.
