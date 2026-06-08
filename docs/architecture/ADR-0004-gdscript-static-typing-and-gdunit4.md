# ADR-0004: GDScript (statically typed) + gdUnit4 in CI

## Status

Accepted

## Date

2026-06-08

## Last Verified

2026-06-08

## Decision Makers

technical-director, lead-programmer, devops-engineer

## Summary

We need a single implementation language and an automated, CI-enforced test gate.
We standardize on **statically typed GDScript** (no C#) and **gdUnit4** (vendored)
run headless on every push/PR, so the pure `core/` logic (ADR-0001) is verified
before merge.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Scripting / Tooling / CI |
| **Knowledge Risk** | LOW — typed GDScript and gdUnit4 6.1.3 are stable |
| **References Consulted** | gdUnit4 docs; `MikeSchulze/gdUnit4-action` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Confirm CI uses the vendored plugin (`version: installed`) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (pure core is what we test) |
| **Enables** | Regression-safe iteration on all systems |
| **Blocks** | Merge gate / Definition of Done |
| **Ordering Note** | Foundational tooling decision |

## Context

### Problem Statement

Mixing GDScript and C# fragments the codebase and tooling. Without enforced tests,
the deterministic core's correctness silently rots.

### Current State

100% GDScript. `addons/gdUnit4/` (v6.1.3) vendored. `.github/workflows/tests.yml`
runs the suite headless via `MikeSchulze/gdUnit4-action@v1` (pinned to the vendored
plugin) on push/PR to `main`; the run publishes results as a check. 22 tests pass.

### Constraints

- Small team; target low-end mobile; CI must run headless on Linux.
- Static typing is opt-in in GDScript but improves performance and tooling.

### Requirements

- One language; typed by default.
- Tests are a blocking merge gate; deterministic; no engine UI required.

## Decision

- **Language**: statically typed GDScript everywhere. The C# specialist is never
  routed (see `.claude/docs/technical-preferences.md`). Native code only via
  GDExtension for platform SDKs (ads/IAP) when needed.
- **Testing**: gdUnit4, vendored for version stability. CI runs it headless and
  blocks merge on failure. Pure `core/`/`data/` logic must be unit-tested.

### Architecture

```
push / PR ─▶ GitHub Actions ─▶ gdUnit4-action (Godot 4.6, version: installed)
                                   └─ runs res://tests ─▶ pass/fail gate + report check
```

### Key Interfaces

```gdscript
# Typed everywhere:
func tap_card(card_id: int) -> Array[GameEvent]:
var _stack_counts: Array[int] = []
```

### Implementation Guidelines

- Type all variables, params, returns; private members prefixed `_`.
- New gameplay systems ship with tests in the same PR (verification-driven).
- Keep gdUnit4 vendored; pin the action to the vendored version.

## Alternatives Considered

### Alternative 1: C# (.NET) or mixed GDScript+C#

- **Pros**: Static typing, familiar to some; faster for heavy compute.
- **Cons**: Heavier mobile export/runtime; two toolchains; team is GDScript.
- **Rejection Reason**: Complexity/runtime cost unjustified for a light puzzle.

### Alternative 2: GUT instead of gdUnit4

- **Pros**: Popular, mature.
- **Cons**: Team chose gdUnit4 (typed-friendly, good CI action, vendored).
- **Rejection Reason**: gdUnit4 already integrated and green.

### Alternative 3: No CI gate (local tests only)

- **Rejection Reason**: Lets regressions merge; defeats the determinism investment.

## Consequences

### Positive

- One coherent toolchain; better editor/runtime performance from typing.
- Every PR is regression-checked headlessly; correctness of the core is enforced.

### Negative

- gdUnit4 must be kept vendored/pinned to avoid version drift (already handled).
- Typed GDScript is slightly more verbose.

### Neutral

- Native SDK work will need GDExtension later (separate ADR when it lands).

## Validation Criteria

- [x] CI runs gdUnit4 headless on push/PR and blocks on failure.
- [x] Suite green (22 tests).
- [x] No C# in the project.
- [ ] New systems land with tests in the same PR (ongoing policy).

## GDD Requirements Addressed

Foundational — no direct GDD requirement. Enables verification of every system
GDD's acceptance criteria (Card Routing, Floor Exposure, Level & Solvability,
Math Exercises).

## Related

- Depends on ADR-0001. Code: `addons/gdUnit4/`, `.github/workflows/tests.yml`,
  `tests/*`. Prefs: `.claude/docs/technical-preferences.md`.
