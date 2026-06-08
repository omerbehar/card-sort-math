# ADR-0001: Model/View separation (pure `core/`)

## Status

Accepted

## Date

2026-06-08

## Last Verified

2026-06-08

## Decision Makers

technical-director, godot-specialist (reverse-documented from the shipped MVP)

## Summary

Gameplay rules need to be deterministic and unit-testable, but Godot node/scene
code is hard to test headlessly. We split the game into a pure, node-free model
(`core/`) that owns all rules and state, and a view layer (`scenes/`) that only
renders — keeping the entire ruleset testable without the engine runtime.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | LOW — uses `RefCounted`, plain GDScript, no post-cutoff APIs |
| **References Consulted** | Godot `RefCounted`, autoload docs |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0002 (event replay), ADR-0004 (gdUnit4 testing of core) |
| **Blocks** | All gameplay systems |
| **Ordering Note** | Foundational — establish before any new system |

## Context

### Problem Statement

Puzzle logic (routing, cascades, win/lose) must be provably correct and
regression-safe. If rules live inside `Node`/scene scripts, tests need the scene
tree, animations, and timing — slow, flaky, and hard to run in CI.

### Current State

`core/board_model.gd` (a `RefCounted`) holds all per-level state and rules.
`autoloads/` holds only meta state (`GameManager`, `LevelData`). `scenes/` reads
state and animates. No scene node ever computes a gameplay outcome.

### Constraints

- GDScript-only project; CI runs Godot headless.
- Must run at 60 FPS on low-end mobile (rules cheap; animation separate).

### Requirements

- All rules unit-testable without the scene tree.
- Deterministic outcomes for a given state + input.
- New systems (generator, economy, save) fit behind the same seam.

## Decision

`core/` is **pure**: no `Node`, no scene-tree access, no I/O, no `await`. It is
deterministic and emits results as data. The **view** (`scenes/`) owns all
`Node`s, input, and animation, and calls into the model. Dependency direction is
strict: **view → core**, never the reverse.

### Architecture

```
[ Input / scenes/* (View) ]
        │ tap_card(id)
        ▼
[ core/BoardModel (pure rules + state) ]  ──reads── [ data/*, LevelData ]
        │ returns Array[GameEvent]
        ▼
[ scenes/main replays events as animation ]
```

### Key Interfaces

```gdscript
# core/ — pure
class BoardModel extends RefCounted:
    func tap_card(card_id: int) -> Array[GameEvent]   # mutates state, returns steps
    func is_exposed(card_id: int) -> bool
    static func from_config(config: LevelConfig) -> BoardModel
# view/ — no rules, only replay (see ADR-0002)
```

### Implementation Guidelines

- Never `import`/reference scene nodes from `core/`.
- Keep tuning values out of `core/` literals — drive from `data/`/config.
- Meta/persistent state goes in autoloads, not in `BoardModel`.

## Alternatives Considered

### Alternative 1: Logic inside Node scripts (MVC-on-nodes)

- **Pros**: Less boilerplate; "the Godot way" for small games.
- **Cons**: Requires scene tree to test; slow/flaky CI; rules entangled with
  animation timing.
- **Rejection Reason**: Loses headless testability — the project's core value.

### Alternative 2: ECS

- **Pros**: Scales to many entities.
- **Cons**: Overkill for a board of ≤18 cards; heavier mental model.
- **Rejection Reason**: Unjustified complexity for this scope.

## Consequences

### Positive

- Entire ruleset is unit-tested headlessly (22 tests today).
- Deterministic → reproducible bugs, safe refactors, generator validation.
- Clean place to add generator/economy/save behind the seam.

### Negative

- Some boilerplate translating events into animations in the view.
- Two representations of the board (model state + scene nodes) to keep in sync.

### Neutral

- View becomes a "dumb" replayer (see ADR-0002).

## Validation Criteria

- [x] `core/` contains no `extends Node` and no scene-tree calls.
- [x] All core rules covered by gdUnit4 tests that run without a scene.
- [x] View scripts compute no outcomes (only replay events).

## GDD Requirements Addressed

| GDD | System | Requirement | How satisfied |
|-----|--------|-------------|---------------|
| `design/gdd/card-routing-and-stacks.md` | Card Routing | "`tap_card` is pure/deterministic" | Rules live in node-free `BoardModel` |
| `design/gdd/level-and-solvability.md` | Level | "validate winnability automatically" | Pure model is testable/simulatable |

## Related

- Enables ADR-0002, ADR-0004. Code: `core/board_model.gd`, `autoloads/*`.
