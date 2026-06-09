# System Index — CardSortMath

> Reverse-engineered from the implemented MVP. Maps the shipped systems, their
> dependencies, and where each is specified. Source of truth for `core/` lives in
> code; these GDDs describe intent and rules so future work stays consistent.

## Layers

| Layer | Systems |
|-------|---------|
| **Foundation** | Floor Exposure, Level & Solvability |
| **Core** | Card Routing & Stacks (the game) |
| **Feature** | Math Exercises (card content) |
| **Presentation** | View replay (`scenes/`), HUD — not yet GDD'd |

## Systems

| System | GDD | Status | Code |
|--------|-----|--------|------|
| Card Routing & Stacks | [`card-routing-and-stacks.md`](gdd/card-routing-and-stacks.md) | Implemented | `core/board_model.gd`, `core/game_event.gd` |
| Floor Exposure | [`floor-exposure.md`](gdd/floor-exposure.md) | Implemented | `core/exposure.gd`, `core/layouts.gd` |
| Level & Solvability | [`level-and-solvability.md`](gdd/level-and-solvability.md) | Implemented | `autoloads/level_data.gd`, `data/level_config.gd` |
| Math Exercises | [`math-exercises.md`](gdd/math-exercises.md) | Implemented (addition only) | `data/card_data.gd` |
| First-Time Tutorial | [`first-time-tutorial.md`](gdd/first-time-tutorial.md) | Designed — Approved (re-review 2, 2026-06-09) | `core/` (`TutorialLogic`, `TutorialState`) + `scenes/ui/coach_overlay.gd` (planned, S1-010) |

## Dependency graph

```
Math Exercises ──provides result──▶ Card Routing & Stacks
Floor Exposure ──gates which cards are tappable──▶ Card Routing & Stacks
Level & Solvability ──builds board (cards + layout + queue)──▶ Card Routing & Stacks
Layouts ──placements──▶ Floor Exposure
Save + BoardModel + Settings + Level 1 content ──read by──▶ First-Time Tutorial
```

## Not yet designed (see `docs/GAME_PLAN.md`)

Save/profile, settings, audio, tutorial, level generator, economy/currencies,
boosters, monetization (IAP/ads), analytics, meta/progression. These are roadmap
items; GDDs should be authored (via `/design-system`) before implementation.

## Architecture decisions

See `docs/architecture/` — the model/view split (ADR-0001), event-sourced replay
(ADR-0002), solvability invariant (ADR-0003), and GDScript/gdUnit4 (ADR-0004)
are the load-bearing constraints all systems above respect.
