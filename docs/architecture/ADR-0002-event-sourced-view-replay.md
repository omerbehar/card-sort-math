# ADR-0002: Event-sourced view replay (`GameEvent`)

## Status

Accepted

## Date

2026-06-08

## Last Verified

2026-06-08

## Decision Makers

technical-director, godot-specialist (reverse-documented from the shipped MVP)

## Summary

Given the pure model (ADR-0001), the view needs to know *what happened* to animate
it without re-deriving rules. `BoardModel.tap_card` returns an ordered list of
`GameEvent`s describing each step; the view replays them sequentially. This makes
a multi-step cascade read as one satisfying animated combo.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Scripting / Animation boundary |
| **Knowledge Risk** | LOW — plain data objects + `await` tweens in view |
| **References Consulted** | Godot `Tween`, `await` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 |
| **Enables** | Deterministic playthrough harness; future replay/undo |
| **Blocks** | View animation work |
| **Ordering Note** | Implement alongside the model |

## Context

### Problem Statement

A single tap can trigger a cascade: route → stack clears → draws target → pulls
several discards → possibly clears again → win. The view must animate this exact
sequence, in order, without containing the rules that produced it.

### Current State

`core/game_event.gd` defines `GameEvent` with `Kind` ∈ {ROUTE, DISCARD,
STACK_CLEARED, PULL, WIN, LOSE} and payload fields (`card_id`, `stack_index`,
`discard_slot`, `new_target`). `tap_card` returns `Array[GameEvent]`;
`scenes/main` plays them one after another.

### Constraints

- The model is pure (no animation, no `await`).
- Order matters — events must be replayed exactly as produced.

### Requirements

- View animates outcomes without recomputing them.
- Sequence is serializable/inspectable (enables the playthrough harness & tests).

## Decision

Adopt a lightweight **event-sourcing** boundary: the model is the single source of
truth and outputs an ordered, immutable list of `GameEvent` value objects per
input. The view is a **replayer** — it walks the list and maps each `Kind` to an
animation, then yields to the next.

### Architecture

```
tap_card(id) ─▶ [ROUTE, STACK_CLEARED, PULL, PULL, WIN]   (ordered events)
                          │
              for each e: match e.kind -> play_animation(e); await
```

### Key Interfaces

```gdscript
enum Kind { ROUTE, DISCARD, STACK_CLEARED, PULL, WIN, LOSE }
class GameEvent extends RefCounted:
    var kind: Kind
    var card_id: int; var stack_index: int
    var discard_slot: int; var new_target: int
    # static factories: route(), discard(), stack_cleared(), pull(), win(), lose()
```

### Implementation Guidelines

- Add new mechanics by adding a `Kind` + factory, never by putting logic in the view.
- The view must handle events in array order; long cascades may stagger timing.
- Keep `GameEvent` a plain data object (no behavior, no node refs).

## Alternatives Considered

### Alternative 1: View polls model state and diffs each frame

- **Pros**: No event objects.
- **Cons**: Reconstructing "what changed and in what order" is error-prone; loses
  cascade ordering; harder to test.
- **Rejection Reason**: Re-derives sequencing the model already knows.

### Alternative 2: Model emits Godot `signal`s directly

- **Pros**: Idiomatic Godot.
- **Cons**: Couples pure model to engine signal system; ordering/awaiting across
  signals is awkward; breaks ADR-0001 purity.
- **Rejection Reason**: Pollutes the pure core; harder to unit-test.

## Consequences

### Positive

- Cascades animate in exact model order → satisfying combos.
- Event lists are directly assertable in tests and drive `tools/playthrough.gd`.
- Opens the door to replays, undo, and net-safe action logs later.

### Negative

- Must keep the `Kind` set and view's replay switch in sync.
- Per-tap allocation of small event objects (negligible at this scale).

### Neutral

- View is intentionally "thin".

## Validation Criteria

- [x] `tap_card` returns an ordered `Array[GameEvent]` covering the full cascade.
- [x] Tests assert event sequences (test_board_model).
- [x] View contains no rule logic — only `kind`→animation mapping.

## GDD Requirements Addressed

| GDD | System | Requirement | How satisfied |
|-----|--------|-------------|---------------|
| `design/gdd/card-routing-and-stacks.md` | Card Routing | "cascade reads as a combo" | Ordered event replay |
| `design/gdd/card-routing-and-stacks.md` | Card Routing | "deterministic outcomes" | Events are a pure function of state+tap |

## Related

- Depends on ADR-0001. Code: `core/game_event.gd`, `core/board_model.gd`, `scenes/main/main.gd`.
