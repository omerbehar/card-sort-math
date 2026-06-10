# Milestone Review: M1 — Playable Core+ (Close-out)

> Close-out review (2026-06-10). The earlier mid-milestone review
> (`m1-review.md`, CONDITIONAL GO) is preserved for history. Review mode: lean
> (no producer gate spawned).

## Overview
- **Target Date**: TBD (M1 ≈ 3–4 wks per GAME_PLAN §4)
- **Current Date**: 2026-06-10
- **Sprints**: Sprint 1 — execution complete
- **Prior verdict**: CONDITIONAL GO — both conditions (S1-011, S1-010) now satisfied

## Feature Completeness

### Fully Complete (merged, automated-tested)
| Feature | Story | Test status |
|---------|-------|-------------|
| SaveService (versioned JSON, `age_band`) | S1-001 | ✓ green |
| Progression persistence | S1-002 | ✓ green |
| Settings model | S1-003 | ✓ green |
| Audio (SFX + music bed) | S1-004 | ✓ (device feel pending) |
| Juice pass | S1-005 | ✓ (feel / 60 FPS pending) |
| First-time tutorial | S1-010 | ✓ 34 tests |
| Settings / pause UI + colorblind | S1-011 | ✓ 11 tests |
| Win/lose result screen | S1-020 | ✓ 7 tests |

**Beyond M1 scope (bonus):** save-layer hardening (atomic write, `load_failed`),
`ComplianceService` chokepoint (ADR-0005), `PopupBase` shared modal chassis (ADR-0006).

### Not Started
| Feature | Priority | Cut? | Impact |
|---------|----------|------|--------|
| S1-021 efficiency score | Nice-to-have | Deferred to M2 | None — belongs with the star economy; no content to score yet |

## Quality Metrics
- **Open S1/S2/S3 bugs**: 0 known
- **Tests**: 165 green; CI green on every PR
- **Performance**: within budget in tests; on-device 60 FPS not yet hardware-verified (advisory)

## Code Health
- **TODO / FIXME / HACK**: 0 in product code (`core/`, `autoloads/`, `data/`, `scenes/`)
- `ResultScreen` reserved-placeholder comments are documented milestone deferrals (M2/M3/M4), not debt
- Risk register not maintained (`production/risk-register/` absent)

## Risk Assessment
| Risk | Status | Impact | Mitigation |
|------|--------|--------|------------|
| Device feel unverified (audio/juice/60 FPS) | Open | Polish-level | Manual QA sign-off (action item) |
| Tutorial visual ACs (reduced-motion/colorblind/font-scale) unverified | Open | Accessibility polish | Screenshot QA (action item) |
| Pop-up visual-language split (Kenney vs flat) | Open | Inconsistency as pop-ups grow | ADR-0006 flags it; one-place fix now |
| Last-level WIN replays final level | Open | Edge UX; pre-existing | M2 "all-complete" state |

## Velocity
- Must-Have critical path: 5/5. Should-Have: 2/2. Nice-to-have: 1 done, 1 deferred.
- All planned M1 features delivered; scope expanded (3 bonus systems) without slipping.

## Scope Recommendations
- **Protect:** none at risk — the "retainable build" goal (save + tutorial + settings + audio + juice) is fully implemented and automated-tested.
- **Deferred (done):** S1-021 → M2.

## Go/No-Go Assessment

**Recommendation: GO**

**Rationale:** Both prior CONDITIONAL-GO conditions (S1-011 Settings UI, S1-010
tutorial) are merged and tested. All BLOCKING gates are green — 165 automated
tests, CI green, 0 known bugs, model/view seam intact, autoloads injectable. The
only outstanding items are manual/device feel sign-offs, which are ADVISORY under
the project's test-evidence policy and do not block the foundation milestone; they
ride into early M2.

## Action Items
| # | Action | Owner | When |
|---|--------|-------|------|
| 1 | Flip S1-011 `In Review` → `Done` (merged + tested) | producer | now |
| 2 | Device sign-off: JuiceService full-motion + 60 FPS on mid-range | qa-lead | early M2 |
| 3 | Device sign-off: AudioService SFX correctness/feel | qa-lead | early M2 |
| 4 | Tutorial visual ACs (AC15–17) screenshot QA | qa-lead | early M2 |
| 5 | Pop-up visual-language decision (Kenney vs flat) | art/creative-director | before next pop-up |
| 6 | Backlog: "all levels complete" terminal state | game-designer | M2 |

## Next
- M1 is GO. Next: `/sprint-plan` for M2 (Content engine) — keystone is the
  procedural level generator (solvability invariant), then scoring/stars
  (lands S1-021) and the first operation world (subtraction).
