# ADR-0003: Solvability invariant for all levels

## Status

Accepted

## Date

2026-06-08

## Last Verified

2026-06-08

## Decision Makers

game-designer, systems-designer, technical-director (reverse-documented from MVP)

## Summary

The game must never deal an unwinnable level. We adopt a structural invariant —
for every result, `card_count == 3 × occurrences in the target queue` — that
guarantees winnability by construction, and enforce it in code (`LevelData.is_solvable`)
and in tests for all authored (and future generated) content.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Content validation |
| **Knowledge Risk** | LOW — pure counting logic |
| **References Consulted** | N/A |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None (relies on `STACK_CAPACITY = 3`) |
| **Enables** | Procedural level generator (Phase 1) |
| **Blocks** | Any content-authoring or generation work |
| **Ordering Note** | Must hold for every shipped/served level |

## Context

### Problem Statement

A "calm, fair" puzzle is undermined if a level can be impossible. We need a cheap,
checkable guarantee that any level — hand-made or generated — can be cleared.

### Current State

`autoloads/level_data.gd::is_solvable(config)` validates a `LevelConfig`. The
three authored levels pass; `test_level_data` and `test_solvable_play` enforce it
(the latter actually simulates a full clear).

### Constraints

- A stack clears at exactly `STACK_CAPACITY = 3` and then draws the next queue
  target.
- Each queue occurrence of a value represents exactly one stack-load of it.

### Requirements

- O(n) checkable, no search.
- Necessary condition strong enough that, with reachable layouts, levels clear.

## Decision

A `LevelConfig` is **solvable** iff:

1. `set(card.result) == set(target_queue)` (every card has a destination; every
   target has cards), **and**
2. for every result `r`: `count(cards with result r) == 3 × count(r in target_queue)`.

This is enforced by `is_solvable` and is a hard gate for all content. Layout
reachability is guaranteed separately by the acyclic coverage DAG (see Floor
Exposure GDD / ADR-0001), so supply/demand balance is the remaining condition.

### Architecture

```
demand(r) = occurrences of r in target_queue
supply(r) = cards whose result == r
solvable  = (keys(demand) == keys(supply)) AND ∀r: supply(r) == 3 * demand(r)
```

### Key Interfaces

```gdscript
func is_solvable(config: LevelConfig) -> bool   # autoloads/level_data.gd
```

### Implementation Guidelines

- The generator (Phase 1) must construct pools by choosing a queue, then emitting
  exactly `3 × demand(r)` cards per `r` — generate-correct rather than
  generate-then-reject where possible.
- Changing `STACK_CAPACITY` invalidates this invariant project-wide — write a new
  ADR if ever revisited.

## Alternatives Considered

### Alternative 1: Brute-force solver per level

- **Pros**: Proves solvability exactly, including layout/order.
- **Cons**: Exponential in the worst case; overkill; slow for live generation.
- **Rejection Reason**: The structural invariant + acyclic layout is sufficient
  and O(n).

### Alternative 2: No guarantee (trust authoring)

- **Pros**: Zero code.
- **Cons**: One bad level erodes trust; impossible to safely auto-generate.
- **Rejection Reason**: Violates the "always solvable" pillar.

## Consequences

### Positive

- Winnability guaranteed cheaply for authored and generated content.
- Generator gets a ready-made correctness gate.
- Simple to reason about and teach.

### Negative

- It is a **necessary** structural condition assuming reachable layouts; a
  pathological layout could still strand cards. Mitigated by the acyclic-coverage
  guarantee and `test_solvable_play` (full-clear simulation).
- Couples content shape to `STACK_CAPACITY = 3`.

### Neutral

- Levels must be authored in multiples of 3 per value.

## Validation Criteria

- [x] All authored levels pass `is_solvable`.
- [x] `test_solvable_play` clears every authored level via simulation.
- [x] Mismatched supply/demand and set-mismatch configs fail the check.
- [ ] Generator output passes `is_solvable` for 100% of generated levels.

## GDD Requirements Addressed

| GDD | System | Requirement | How satisfied |
|-----|--------|-------------|---------------|
| `design/gdd/level-and-solvability.md` | Level | "every level winnable by construction" | The 3×N invariant + enforcement |
| `design/gdd/card-routing-and-stacks.md` | Card Routing | "queue exhaustion leaves no stranded cards" | Supply == demand guarantees homes |

## Related

- Code: `autoloads/level_data.gd`, `tests/test_level_data.gd`, `tests/test_solvable_play.gd`.
