# QA Evidence — Operand variety floor (≥3 options per result)

> **Date**: 2026-06-14
> **Report**: In the multiply world a prime result (e.g. 7) has only one way to make
> it (`1 × 7`), so all three of its cards read identically. "Make sure each result
> has at least 3 options."
> **Implements**: design/gdd/math-exercises.md (variety AC), ADR-0011

## Fix

- `OperandPicker.option_count(result, max_operand, op)` — distinct displayed pairs
  the picker cycles. Multiply now cycles **both orientations** (e.g. 12 → 2×6, 6×2,
  3×4, 4×3) for more variety; `has_valid_pair` is unified as `option_count >= 1`.
- `OperandPicker.valid_operations(..., min_options)` — a result qualifies for an
  operation only if it offers `min_options` distinct pairs.
- `GeneratorParams.min_operand_options` (default 1; legacy callers unchanged) — the
  generator filters candidate results and per-card operations by this floor.
- `LevelData.OPERAND_OPTIONS_MIN = 3` set on every generated level, plus
  `LevelData._apply_world_number_range` widens each single-op world's number band so
  enough results clear the floor:
  - **×**: max_operand 12, results 8–24 → only composites with 3+ factor pairs
    (12, 16, 18, 20, 24…); primes excluded.
  - **÷**: max_operand 20, results 2–5 → small quotients with many dividends.
  - **−**: max_operand 12, result ≤ max−3.
  - **+ / mixed**: unchanged (addition already offers many options).

## Automated test evidence (full suite green — 519 cases, 0 failures)

- `tests/test_level_data_generation.gd`:
  - `test_generated_results_offer_at_least_three_distinct_exercises` — one level per
    world (4, 8, 13, 18, 25, 33): every result shows ≥3 distinct `exercise_text`.
  - `test_multiplication_world_excludes_prime_results` — LV13 uses no prime result.
- `tests/test_operand_picker.gd` — `option_count`, both-orientation multiply,
  non-trivial preference, determinism.

## Screenshot evidence (real renders)

Captured via `tools/screenshot_operations.gd`:

| World | Level | File | Sample (varied, no trivial) |
|-------|-------|------|------------------------------|
| Multiplication | 13 | `operations-multiply.png` | 16 = 2×8 / 8×2 / 4×4; 12 = 2×6 / 4×3; 18 = 3×6 / 2×9; 20 = 4×5 / 5×4 / 2×10 |
| Division | 18 | `operations-divide.png` | 5 = 15÷3 / 20÷4 / 10÷2; 4 = 16÷4 / 12÷3; 3 = 6÷2 / 12÷4 |

No `1 × n` and no `n ÷ 1` trivial cards; no prime multiply results.
