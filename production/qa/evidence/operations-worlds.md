# QA Evidence — Arithmetic Operation Worlds (+, −, ×, ÷)

> **Feature**: Subtraction, multiplication and division exercises added alongside
> addition, organised as operation "worlds" (every 5 levels advances one
> operation; level 21+ mixes all four).
> **Date**: 2026-06-14
> **Implements**: `design/gdd/math-exercises.md`, ADR-0011

## What changed

- New pure `core/operation.gd` (`Operation` enum + glyph/apply/format helpers).
- `CardData` carries an `operation` field; `result` and `exercise_text()` are now
  operation-aware (defaults to addition, so authored cards are unchanged).
- `OperandPicker` picks a valid operand pair per operation and exposes
  `valid_operations()`; `has_valid_pair()` is operation-aware.
- `GeneratorParams.allowed_operations` + the generator pick each card's operation
  from those valid for its result (single-op worlds skip the RNG draw, so addition
  levels stay byte-identical).
- `LevelData.world_for_level()` / `operations_for_level()` map level → world:
  1–5 `+`, 6–10 `−`, 11–15 `×`, 16–20 `÷`, 21+ mixed.

## Automated test evidence (all green)

- Full suite: **508 test cases, 0 failures**.
- Unit: `tests/test_operation.gd`, `tests/test_operand_picker.gd`,
  `tests/test_card_data.gd` (operation cases), `tests/test_level_generator.gd`
  (operation-world + mixed solvability/determinism across seeds),
  `tests/test_level_data_generation.gd` (world mapping, per-world operation,
  mixed level).
- Integration (drives `scenes/main/main.tscn` via gdUnit4 `scene_runner`):
  `tests/integration/operation_worlds_test.gd` — asserts the live card view
  labels render `−` / `×` / `÷` for the subtraction/multiplication/division
  worlds, that a mixed-world board shows multiple operators, and that an
  operation-world board is still playable (a tap routes/discards end to end).

## Screenshot evidence (real Godot renders)

Captured with `tools/screenshot_operations.gd` via
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility`.

| World | Level | File | Sample cards |
|-------|-------|------|--------------|
| Addition | 3 | `operations-add.png` | `1 + 4`, `2 + 5`, … |
| Subtraction | 8 | `operations-subtract.png` | `5 − 3`, `4 − 2`, `6 − 1` |
| Multiplication | 13 | `operations-multiply.png` | `1 × 3`, `2 × 4`, `3 × 3` |
| Division | 18 | `operations-divide.png` | `8 ÷ 2`, `5 ÷ 1`, `7 ÷ 1` |
| Mixed | 25 | `operations-mixed.png` | `6 + 7`, `8 − 2`, `1 × 5`, `8 ÷ 2` |

All four math glyphs render correctly (no missing-glyph boxes), and the mixed
level shows `+`, `−`, `×`, `÷` together on one solvable board.
