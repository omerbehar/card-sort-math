# Project Stage Analysis

**Date**: 2026-06-08
**Stage**: Production (early)
**Stage Confidence**: PASS — clear signals (working code, vision, CI gate)

## Completeness Overview

- **Design**: ~70% — comprehensive `docs/GAME_PLAN.md` + 4 system GDDs +
  systems index for shipped systems. Gaps: GDDs for roadmap systems (save,
  audio, generator, economy, monetization) — expected, not yet built.
- **Code**: ~25% of full vision / 100% of MVP rules — 1,242 lines GDScript,
  21 scripts, 30 scenes. Core loop fully playable.
- **Architecture**: ~80% for current scope — 4 ADRs cover the load-bearing
  decisions. Will grow as services (save/ads/IAP) land.
- **Production**: ~40% — Sprint 1 plan exists; no milestone tracker yet.
- **Tests**: strong for `core/` — 22 gdUnit4 tests across 5 suites, green in CI;
  `test_solvable_play` simulates full clears. View/UI untested (expected).

## What Exists

| Area | Evidence |
|------|----------|
| Core gameplay | `core/board_model.gd` (routing, cascade, win/lose), `exposure.gd`, `layouts.gd`, `game_event.gd` |
| Data | `data/card_data.gd`, `data/level_config.gd`; 3 authored levels in `autoloads/level_data.gd` |
| View | `scenes/` (main, card, stack, discard, floor, ui) replays events |
| Tests + CI | `tests/` (22 cases) + `.github/workflows/tests.yml` (headless gdUnit4) |
| Vision | `docs/GAME_PLAN.md` (features, monetization, ads, roadmap, risks) |
| Design | `design/gdd/*` (4 systems), `design/systems-index.md` |
| Architecture | `docs/architecture/ADR-0001..0004` |
| Tooling/framework | `.claude/` Godot-focused agents/skills/rules |

## Gaps Identified

1. **Roadmap systems undocumented** — Save, Settings, Audio, Tutorial, Level
   Generator, Economy, Monetization have no GDDs. → Author via `/design-system`
   when each is picked up (Sprint 1 covers the first wave).
2. **Audience positioning undecided** — `GAME_PLAN.md` §10: general-audience (13+)
   vs. kids product. This gates the entire monetization design. → Product decision
   needed before Milestone M4.
3. **No milestone tracker** — Sprint 1 exists; M1–M7 not yet broken into a
   tracked roadmap. → `/milestone-review` at end of Sprint 1.
4. **View/UI untested** — acceptable (advisory per testing standards); add manual
   walkthrough docs as UI grows.
5. **No persistence** — progress is not saved between runs. → Sprint 1 S1-001.

## Recommended Next Steps (priority order)

1. **Decide audience positioning** (§10) — unblocks monetization design. *Product call.*
2. **Execute Sprint 1** — SaveService → progression persistence → Settings →
   Audio → Juice → Tutorial (`production/sprints/sprint-01.md`).
3. **Author GDDs** for the Sprint 1 systems via `/design-system` as they start.
4. **Build the level generator** (Phase 1) on the solvability invariant (ADR-0003).
5. **`/milestone-review`** at sprint end to formalize the M1→M2 transition.

## Role-Filtered Notes

- **Programmer**: Start at S1-001 (SaveService) — versioned, migration-tested,
  behind the model/view seam. Keep `core/` pure (ADR-0001).
- **Designer**: GDDs for the four shipped systems are done; next author Save/Audio/
  Tutorial specs and a scoring/stars design.
- **Producer**: Stand up milestone tracking; watch tutorial scope; force the
  audience-positioning decision before M4.
