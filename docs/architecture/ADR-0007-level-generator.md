# ADR-0007: Level Generator — construction, determinism, dispatch & recoverability

## Status
Proposed (hardened 2026-06-11 after the independent `/design-review` of the GDD — added the
`level_id = -1` sentinel guard, typed `DifficultyScheduleData`, injected recovery predicate,
and the four determinism contracts: `rng.seed=`, global-RNG ban, canonical `card_pool` sort,
no-alias array assignment.)

## Date
2026-06-10 (rev. 2026-06-11)

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — pure deterministic logic; no post-cutoff APIs |
| **References Consulted** | `design/gdd/level-generator.md`; `core/board_model.gd`, `core/layouts.gd`, `autoloads/level_data.gd`, `data/level_config.gd`, `data/card_data.gd`; ADR-0001/0003/0004 |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | `hash()` is **not** used for seeding (unstable across platforms/versions); determinism rests on explicit integer seed math + a seeded `RandomNumberGenerator`. Verify AC-03/AC-30 (byte-identical re-generation) pass on CI. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (solvability invariant), ADR-0001 (model/view + core purity), ADR-0004 (typed GDScript + gdUnit4) |
| **Enables** | S2-003 (generator implementation); future operation worlds (M2) and daily challenge (M3) |
| **Blocks** | S2-003a/b, S2-004 cannot start until this is Accepted |
| **Ordering Note** | Implements `design/gdd/level-generator.md` (S2-001). Pins that GDD's Open Questions. |

## Context

### Problem Statement
The game ships three hand-authored levels. M2 needs an endless supply. The
GDD (S2-001) specifies *what* to generate; this ADR pins *how*: the construction
algorithm, the determinism mechanism, the warning surface, the `LevelData`
dispatch + seed derivation, the stagger semantics, and the recoverability
mechanism — the GDD's six Open Questions.

### Constraints
- Pure, node-free, deterministic `core/` (ADR-0001); statically typed + gdUnit4 (ADR-0004).
- Every output must satisfy `LevelData.is_solvable` (ADR-0003).
- Reproducible across runs/platforms (daily challenge, shareable seeds at M3).

### Requirements
- `generate(params, seed)` is a pure function: same inputs → byte-identical level.
- Solvability holds for **all** valid params/seeds (property-tested, ≥100 seeds).
- Generated levels are **fair to play**, not merely provably solvable (GDD Player Fantasy).

## Decision

### 1. By-construction generation (not rejection sampling)
`core/level_generator.gd` exposes a pure `static func generate(params: GeneratorParams, seed: int) -> GeneratorResult`. It builds the target queue first, then deals **exactly `3 × queue_count(R)`** cards per result, chooses operands, and deterministically shuffles slot assignment (Fisher–Yates). The solvability invariant (ADR-0003) is therefore **structural**; `LevelData.is_solvable` is demoted to a debug self-check that, by construction, cannot fail. This is the "generate-correct, not generate-then-reject" implementation guideline ADR-0003 asked for. The by-construction claim rests on three legs: supply/demand (3× per occurrence) **plus** exposure-independence (slot assignment never affects reachability — `core/exposure.gd` derives tappability from position/layer only) **plus** the recoverability backstop (§5).

### 2. Determinism — seeded RNG + explicit integer seed (NOT `hash()`)
A single `RandomNumberGenerator` with `rng.seed = seed` drives every draw in a fixed order. **The seed is an explicit integer expression, never `hash()`** (GDScript `hash()` is implementation-defined and unstable across platforms/versions — it would break reproducibility):

```
seed = world_id * WORLD_STRIDE + level_index        # WORLD_STRIDE = 1_000_000
```

`WORLD_STRIDE = 1_000_000` namespaces worlds with headroom (level indices stay well under 1M; `world_id` is a small enum). 64-bit ints never overflow at this scale.

### 3. Pure value types
`GeneratorParams` and `GeneratorResult` are `class_name … extends RefCounted` (not Dictionaries — keeps ADR-0004's typing). `GeneratorResult { config: LevelConfig, warnings: Array[String] }` is the **warning surface** — no global `push_warning` for clamp/promotion warnings (testable, no side-effects). Hard errors (empty candidate pool) still `push_error` + return a result whose `config` is `null`.

### 4. Dispatch — `LevelData` loads bytes; `core/` interprets them
- `LevelData.get_level(n)` returns the **authored** config for `n ≤ level_count()`, else calls the generator.
- The difficulty schedule lives in `assets/data/difficulty_schedule.tres`. **`LevelData` (the autoload) is the only layer that calls `load()`**; it hands the raw resource data to a **pure `core/difficulty_schedule.gd`** that computes `GeneratorParams` from the level index (the `R_max(N)` curve, clamps, stagger — all unit-testable headlessly per ADR-0004). The generator itself **never** calls `load()`/`ResourceLoader`.
- Generated configs are marked by a named constant **`LevelConfig.GENERATED_ID = 0`** with a `LevelConfig.is_generated()` accessor (no code compares the literal `0`). **Provenance is carried on `LevelConfig`** — `seed`, `world_id`, `level_index` fields — so M3 daily-challenge / "share this seed" is a data lookup, not a schema change. (`LevelConfig` is built at runtime and is **not** persisted in `SaveData`, so adding fields incurs no save migration.)
- **Sentinel-collision guard (design-review fix):** `LevelConfig.level_id`'s field default must be **`-1`** ("unset"), *not* `0` — otherwise a bare `LevelConfig.new()` or an editor-created `.tres` would default to `0` and read as generated. Authored levels set positive ids (`_build_level` uses `index + 1`); generated levels set `GENERATED_ID = 0`; `-1` means "neither / not initialised". A regression test asserts `is_generated() == false` for authored levels 1–3 (GDD AC-28). Provenance fields should be `@export_storage`/runtime-only so they are not baked into any future authored `.tres`.

### 5. Recoverability (fair-to-play backstop, GDD Core Rule 10)
"Forcedness" is bounded primarily by construction (exposure-independence; `D ≤ STACK_COUNT` in early bands; `max_repeats_per_result ≤ 2`). As a backstop, a constructed level is checked by a **pure `core/` simulation that reuses `BoardModel`** (a `RefCounted`: `from_config` → greedy `tap_card` route + one forced/suboptimal tap → `is_won`/`is_lost`) — no scene tree, no animation, events consumed only as data. A board leaving `< min_recovery_margin` free discard slots is **re-seeded deterministically** (`retry_seed = base_seed + attempt × 7919`, a small fixed attempt cap; on cap, keep the most-recoverable candidate + warn). The **mechanism** is Accepted; the **metric value** (`min_recovery_margin`, the exact sim) is **data-driven/TBD**, finalized with the game-designer at M2 playtest — so this ADR survives tuning without being superseded.

### Architecture Diagram
```
assets/data/difficulty_schedule.tres
        │  load() (autoload only)
        ▼
LevelData (Node autoload) ──get_level(n)──┐
   │ resolves world_id, level_index        │ authored?  → return authored LevelConfig
   ▼                                        │ else:
core/difficulty_schedule.gd (PURE) ── GeneratorParams ──▶ core/level_generator.gd (PURE)
   (N → params, R_max curve, stagger)        seed = world_id*STRIDE + level_index
                                                     │  by-construction build
                                                     │  + recoverability sim (reuses BoardModel)
                                                     ▼
                                            GeneratorResult { config, warnings }
                                                     ▼  config (level_id=GENERATED_ID, +provenance)
                                            BoardModel.from_config(config)  → play
```

### Key Interfaces
- `LevelGenerator.generate(params: GeneratorParams, seed: int) -> GeneratorResult` (pure, `core/`).
- `GeneratorParams` (RefCounted): `layout_id, D, R_min, R_max, max_operand, allow_queue_repeats`.
- `GeneratorResult` (RefCounted): `config: LevelConfig = null` (typed-nullable; `null` on hard error — callers must check before `BoardModel.from_config`), `warnings: Array[String]`.
- `DifficultySchedule.params_for(level_index: int, schedule_data: DifficultyScheduleData) -> GeneratorParams` (pure, `core/`). `DifficultyScheduleData extends Resource` (a `RefCounted`) — the parameter is **never** typed as `Node`/autoload, so `core/` stays node-free. Band/index fields are `int` (integer floor division in the `R_max(N)` curve).
- `LevelConfig`: `const GENERATED_ID := 0`, `var level_id := -1` (unset sentinel), `func is_generated() -> bool { return level_id == GENERATED_ID }`, `seed/world_id/level_index` provenance fields.
- `pick_operands(result, index, max_operand) -> Vector2i` (pure, `core/`): the **single** operand splitter shared by the generator and the authored `LevelData` path — retires `LevelData._split_operands` (whose unbounded formula could violate AC-11). Authored path passes `max_operand = result − 1`.
- Recoverability: `LevelGenerator.generate` takes an **injected** recovery predicate `is_recoverable: Callable` (default `RecoverabilitySimulator.run`) so the sim is deterministic in tests and the cap-exhaustion fallback (AC-34) is exercisable. The check is *necessary, not sufficient* — AC-27 human playtest is the real fairness gate.

**Determinism contracts (design-review):** (1) re-seed uses `rng.seed = …` (full reset), **never** `rng.state =` (which jumps mid-stream and breaks reproducibility); (2) only the caller's seeded `RandomNumberGenerator` is used — `Array.shuffle()`/`pick_random()` (global RNG) are **banned in `core/`**, enforced by a project rule; (3) `card_pool` is sorted by `layout_slot` before being stored on the `LevelConfig`, so array order is a pure function of slot assignment, not RNG draw order (load-bearing for `is_solvable` iteration and the greedy recoverability sim); (4) `LevelConfig.target_queue`/`card_pool` are assigned **fresh** arrays (not the generator's working buffers) to avoid aliasing.

## Alternatives Considered

### Alternative 1: Rejection sampling (generate random level, keep if solvable)
- **Description**: Randomly deal cards/queue, test `is_solvable`, retry until pass.
- **Pros**: Conceptually simple.
- **Cons**: Non-deterministic retry count; wasteful; provides **no** fairness/recoverability guarantee; determinism leaks through the retry loop.
- **Rejection Reason**: By-construction makes the invariant structural at zero retry cost.

### Alternative 2: Backtracking / constraint solver
- **Description**: Treat level generation as a CSP and solve.
- **Pros**: Maximally flexible for complex future constraints.
- **Cons**: Overkill — the invariant is a simple counting identity already satisfied by construction; adds determinism + performance complexity.
- **Rejection Reason**: Unjustified complexity for a counting constraint.

### Alternative 3: `seed = hash(world_id, level_index)`
- **Description**: Derive the seed from the GDScript `hash()` builtin.
- **Cons**: `hash()` is implementation-defined and **not stable** across platforms/Godot versions — breaks reproducibility (daily challenge, shareable seeds).
- **Rejection Reason**: Replaced with the explicit integer formula (§2).

## Consequences

### Positive
- Solvability is structural (ADR-0003 strengthened); determinism is trivial and testable.
- `core/` purity preserved — schedule math + seed derivation + recoverability sim all unit-testable headless.
- Provenance on `LevelConfig` makes M3 daily-challenge/shareable-seed a lookup, not a migration.

### Negative / accepted trade-offs
- **New coupling:** generator correctness is now tied to `BoardModel` behaviour (the recoverability sim reuses the real ruleset). A routing-rule change can change which levels pass recoverability. This is *desirable* (the sim tracks real rules) but must be named — a `BoardModel` change should re-run the generator's recoverability tests.
- The recoverability re-seed adds a bounded loop to an otherwise forward-only pipeline (capped, deterministic — acceptable).

### Risks
- **`hash()` misuse** → unstable seeds. *Mitigation:* the explicit formula is mandated here and in tests (AC-03/AC-30).
- **Dictionary iteration order** affecting determinism. *Mitigation:* populate result-count dicts by iterating a fixed/sorted order, never unordered key sets (Godot 4 dicts are insertion-ordered).
- **Array aliasing** — `LevelConfig` fields sharing the generator's working arrays. *Mitigation:* assign fresh/duplicated arrays to `config.target_queue`/`card_pool`.
- **Re-seed determinism leak.** *Mitigation:* each attempt sets `rng.seed = base_seed + attempt × 7919` at the top of the pipeline; never continue RNG state or use `hash()`.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| level-generator.md | by-construction solvability; determinism; `GeneratorResult` warnings; `level_id` dispatch; strict per-level stagger; recoverability | Pins all six Open Questions: §1 construction, §2 seed, §3 warnings, §4 dispatch + provenance, §5 recoverability mechanism; stagger = strict per-level (computed in `core/difficulty_schedule.gd`) |
| level-and-solvability.md | the invariant must hold for generated levels | `is_solvable` upheld structurally; demoted to debug self-check |
| card-routing-and-stacks.md | `BoardModel.from_config` consumes the output | Generated `LevelConfig` is consumed identically to authored; reused by the recoverability sim |

## Performance Implications
- **CPU**: generation is O(slot_count) construction + an O(slot_count) recoverability sim per level; negligible (≤18 cards). Re-seed loop is capped.
- **Memory**: one `LevelConfig` + a throwaway `BoardModel` per generation; freed immediately.
- **Load Time**: schedule `.tres` loaded once by `LevelData`; generation is on-demand per level.
- **Network**: none.

## Migration Plan
Additive. `LevelData.get_level` gains the generated branch (authored 1–3 unchanged — AC-28). `LevelConfig` gains `GENERATED_ID`, `is_generated()`, and provenance fields (no `SaveData` migration — `LevelConfig` isn't persisted). New files: `core/level_generator.gd`, `core/difficulty_schedule.gd`, `assets/data/difficulty_schedule.tres`, `GeneratorParams`/`GeneratorResult`.

## Validation Criteria
- AC-01/02: 300 generations across seeds×layouts all `is_solvable`.
- AC-03/AC-30: byte-identical re-generation (including any re-seeded levels).
- AC-21..26: `R_max(N)`/stagger math green in **headless CI with no autoload instantiated** (proves the pure-core seam held).
- AC-32: greedy + one-mistake recoverability sim never hits LOSE across the sweep.
- M3 check: daily-challenge level identity is a `provenance` lookup with zero `LevelConfig` schema change.

## Related Decisions
- ADR-0001 (model/view + core purity), ADR-0002 (event replay — untouched), ADR-0003 (solvability — strengthened), ADR-0004 (typed + gdUnit4).
- `design/gdd/level-generator.md` (S2-001), `production/sprints/sprint-02.md` (S2-002..004).
