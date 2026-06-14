# ADR-0011: Arithmetic operations as a content concern — `Operation` enum on `CardData`, operation worlds in `LevelData`

## Status
Accepted (2026-06-14 — implements the "Add an `operation` field to `CardData`" Open
Question and the "Operation type → world" Tuning Knob of `design/gdd/math-exercises.md`).

## Date
2026-06-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Data |
| **Knowledge Risk** | LOW — pure GDScript; new `RefCounted`/`Resource` field + helpers, no engine APIs |
| **References Consulted** | `design/gdd/math-exercises.md`; `data/card_data.gd`; `core/operand_picker.gd`; `core/level_generator.gd`; `autoloads/level_data.gd`; ADR-0001 (core purity), ADR-0003 (solvability), ADR-0007 (level generator / world seeding) |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Full gdUnit4 suite green (addition output byte-identical); integration test on `main.tscn` proving the glyphs render; screenshots per world. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (model/view + core purity), ADR-0003 (result-only solvability invariant), ADR-0007 (generator determinism + `world_id * WORLD_STRIDE + n` seeding) |
| **Enables** | Subtraction / multiplication / division content; a mixed-operation world; future per-world difficulty tuning |
| **Blocks** | Nothing — additive change, inert for addition |

## Context

Every card was an addition exercise: `CardData.create` hard-coded `result = a + b`
and `exercise_text()` hard-coded `"%d + %d"`. The GDD's math-exercises doc already
anticipated this and recommended an `operation` field so non-addition "worlds" can
exist without touching the sort engine.

The load-bearing fact (ADR-0003): **the engine routes solely by `result`**. The
operation only affects (a) how `result` is computed from the operands and (b) what
glyph is displayed — both pure content concerns. So operations can be layered on
top of the existing solvability invariant with no change to `BoardModel`,
`Solvability`, or the view's replay logic.

### Constraints
- Addition output must stay **byte-identical** (regression-guarded by AC-28 and the
  generator determinism tests).
- `core/` stays pure/deterministic — operand selection per operation must use the
  caller-supplied seeded RNG only.
- Solvability (ADR-0003) must hold unchanged for every operation and the mix.

## Decision

1. **`core/operation.gd`** — a pure `Operation` helper: `enum Type { ADD,
   SUBTRACT, MULTIPLY, DIVIDE }` plus `glyph()`, `apply(a, b, op)` and
   `format(a, b, op)`. Ordinals are stable (ADD == 0), so a bare card / authored
   card defaults to addition.

2. **`CardData.operation`** — a new `@export var operation := Operation.Type.ADD`.
   `create(a, b, layer, slot, operation := ADD)` computes
   `result = Operation.apply(...)`; `exercise_text()` delegates to
   `Operation.format(...)`. The trailing default keeps every existing call valid.

3. **`OperandPicker` is operation-aware** — `pick()`/`has_valid_pair()` take an
   `operation` (default ADD; the ADD branch is the original code verbatim). Each
   operation has its own legal-operand window so the printed pair evaluates back to
   the requested result within `[1, max_operand]`:
   - `−`: `a = b + result`, divisor window `b ∈ [1, max_operand − result]`.
   - `×`: factor pairs within `[1, max_operand]`, preferring non-trivial (`≥ 2`).
   - `÷`: `a = result × b`, window `b ∈ [1, max_operand / result]`, preferring `b ≥ 2`.
   `valid_operations(result, max_operand, allowed)` returns the allowed operations
   that can produce a result — the generator's candidate filter and per-card chooser.

4. **`GeneratorParams.allowed_operations: Array[int]`** (default `[ADD]`) — the
   generator filters candidate results to those with at least one valid operation,
   and for each card picks an operation from the valid set. A single-operation world
   has one entry and **skips the RNG draw entirely**, so addition levels consume the
   RNG in the exact same order as before (determinism preserved).

5. **Operation worlds in `LevelData`** — `world_for_level(n) = min((n−1)/WORLD_SIZE,
   MIXED_WORLD_ID)` with `WORLD_SIZE = 5`: levels 1–5 `+`, 6–10 `−`, 11–15 `×`,
   16–20 `÷`, 21+ mixed (all four). The generated-level seed becomes
   `world_for_level(n) * WORLD_STRIDE + n`, keeping each world's seed space disjoint
   (extends ADR-0007). `DifficultySchedule` stays operation-agnostic (difficulty
   knobs only); the operation is set by `LevelData` as a world concern.

`BoardModel`, `Solvability`, and the view's event replay are **untouched** — they
read only `result`.

## Alternatives Considered

### Alternative 1: Mix operations within every level from level 1
- **Cons**: Contradicts the GDD's "operations are worlds" framing; no gentle
  per-operation onboarding. **Rejected** — boss chose 5-level worlds then mix.

### Alternative 2: Store the glyph/string on `CardData` instead of an enum
- **Cons**: Not type-safe; can't compute `result`; bloats the resource.
  **Rejected** — an int enum + pure helpers is the established pattern (cf.
  `EconomyEnums`).

### Alternative 3: Put operation selection in `DifficultySchedule`
- **Cons**: The schedule is difficulty-only by design; world identity is provenance
  owned by `LevelData` (ADR-0007). **Rejected** — keeps the schedule operation-free.

## Consequences

### Positive
- Subtraction/multiplication/division/mixed content with zero change to the sort
  engine or solvability check.
- Addition is provably unchanged (single-op worlds skip the RNG draw; tests green).
- Per-world or per-operation difficulty tuning is now a natural next step.

### Negative / accepted trade-offs
- Single-operation worlds inherit the shared (addition-tuned) difficulty schedule,
  so e.g. the division world's small `max_operand` yields some trivial `n ÷ 1`
  cards. Accepted for now; a per-world schedule is a future tuning task noted in the
  GDD.

### Risks
- A result with no valid pair for the world's operation could empty the candidate
  pool → null level. *Mitigation:* `valid_operations()` filters candidates up front,
  the generator already degrades gracefully, and per-world solvability is tested
  across 20 seeds per operation plus a spread of real level indices.

## GDD Requirements Addressed

| GDD System | Requirement | How addressed |
|------------|-------------|---------------|
| math-exercises.md | "(Future) An `operation` enum drives display + result for non-addition worlds" | `Operation` + `CardData.operation` |
| math-exercises.md | Tuning Knob "Operation type → world" | `LevelData.world_for_level()` / `operations_for_level()` |
| math-exercises.md | "split policy must guarantee non-negative for `−`" | subtraction window keeps `a = b + result`, both `≥ 1` |
| ADR-0003 | solvability preserved | engine routes by `result`; counts unchanged |

## Validation Criteria
- Full gdUnit4 suite green; addition determinism/round-robin tests unchanged (508 cases, 0 failures).
- `Operation.apply` round-trips for every picked pair, operands within `[1, max_operand]`.
- Single-operation worlds print exactly their operation; mixed world shows > 1 operation; all solvable across seeds.
- Integration: live `main.tscn` card labels render `−` / `×` / `÷`; operation-world board is playable.
- Screenshots in `production/qa/evidence/operations-*.png`.

## Related Decisions
- ADR-0001 (core purity), ADR-0003 (solvability invariant), ADR-0007 (generator + world seeding).
- `design/gdd/math-exercises.md`.
