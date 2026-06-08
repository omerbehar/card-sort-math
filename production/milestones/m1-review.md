# Milestone Review: M1 — Playable Core+

> **Review mode: Lean** — PR-MILESTONE producer gate skipped.

## Overview

| Field | Value |
|-------|-------|
| **Milestone** | M1 — Playable Core+ |
| **Scope** | Save, tutorial, audio, juice, settings |
| **Target effort** | 3–4 wks (GAME_PLAN §15) |
| **Current date** | 2026-06-08 |
| **Sprint in scope** | Sprint 1 |
| **Tests green** | 74 / 74 |

---

## Feature Completeness

### Fully Complete

| Feature | Acceptance Criteria | Test Status |
|---------|---------------------|-------------|
| **SaveService** (S1-001) | Round-trip save/load; corrupt → defaults; schema migration; `age_band` persists | ✅ 14 tests |
| **Progression persistence** (S1-002) | Win advances & persists across restart | ✅ 7 tests |
| **Settings model + service** (S1-003) | Toggles persist; sane defaults; unit tested | ✅ 13 tests |
| **AudioService** (S1-004) | Each `GameEvent.Kind` triggers correct SFX; mute respected; no audio in `core/` | ✅ 11 tests |
| **JuiceService** (S1-005) | Cascade animates in event order; reduced-motion disables particles/shake; haptics gated | ✅ 6 tests |

### Partially Complete

| Feature | % Done | Remaining Work | Risk to Milestone |
|---------|--------|----------------|-------------------|
| **Settings** | 70% | S1-011: Settings UI screen — binds the already-complete service to toggles | Medium — settings data exists but player cannot change it in-game |

### Not Started

| Feature | Priority | Can Cut? | Impact of Cutting |
|---------|----------|----------|-------------------|
| **First-time tutorial** (S1-010) | Should Have | No — central to M1 goal | M1's stated goal is a "retainable build"; without onboarding, new players have no coaching and churn immediately |
| **Win/lose result screen** (S1-020) | Nice to Have | Yes | Overlay currently shows "You Win!" text; no stars/retry UX — playable but sparse |
| **Efficiency score model** (S1-021) | Nice to Have | Yes | Pure-logic, no UI; negligible user impact if deferred to M2 |

---

## Quality Metrics

- **Open S1 Bugs**: 0 known
- **Open S2 Bugs**: 0 known
- **Open S3 Bugs**: 0 known
- **Test coverage**: 74 tests across 13 suites; all `core/` and `autoloads/` systems covered; 0 failing
- **Performance**: 60 FPS budget — JuiceService `reduced_motion` path exists; full-motion manual sign-off on device pending

---

## Code Health

- **TODO count in own code**: 0 (6 markers all inside vendored `addons/gdUnit4/`)
- **FIXME count**: 0
- **HACK count**: 0
- **ADRs**: 5 (ADR-0001 through ADR-0005) — all major decisions documented
- **GDDs**: 4 (card-routing-and-stacks, floor-exposure, level-and-solvability, math-exercises)
- **Technical debt items**:
  1. **Sprint doc statuses stale** — `production/sprints/sprint-01.md` still shows "In Review" for S1-002 through S1-005; all four are merged to main.
  2. **GAME_PLAN.md §2 "Current State"** is pre-Sprint-1 (shows 22 tests, missing all Sprint 1 systems).
  3. **No formal milestone file** — `production/milestones/` was empty; this review is the first entry.

---

## Risk Assessment

| Risk | Status | Impact if Realized | Mitigation Status |
|------|--------|--------------------|-------------------|
| Save schema churn | **Resolved** | Blocks future features | schema_version + migration test in place |
| Audio assets not ready | **Resolved** | SFX silent | Kenney CC0 SFX + ambient music in `assets/audio/` |
| Juice frame budget | **Partially Mitigated** | 60 FPS miss on low-end | `reduced_motion` path exists; device profiling pending |
| Tutorial scope creep | **Not Yet Active** | M1 slip | S1-010 limited to Level 1 coaching per sprint plan |
| Sprint doc drift | **New — Low impact** | Inaccurate status | Update docs before sprint close |

---

## Velocity Analysis

- **Must-Haves completed**: 5/5 (100%)
- **Should-Haves completed**: 0/2 (0%)
- **Nice-to-Haves completed**: 0/2 (0%)
- **Overall sprint tasks done**: 5/9 (56%)
- **Trend**: Critical path fully cleared; discretionary work not yet started
- **Remaining effort for M1**: ~3 days (S1-011 = 1 day, S1-010 = 2 days)

---

## Scope Recommendations

### Protect (Must ship with M1)
- **S1-010 Tutorial** — without onboarding, the game is not "retainable." This is the only remaining item that directly maps to M1's goal statement.
- **S1-011 Settings UI** — the settings data layer is complete; shipping without accessible toggles means players can't mute or enable reduced motion.

### At Risk (May need to simplify)
- **S1-010 Tutorial scope** — "guided Level 1 + coaching + skippable" is achievable in 2 days, but can easily creep. Keep to coach-on-tap + stack-explanation only; no interactive overlays on first attempt.

### Cut Candidates (Defer to M2 without compromising M1)
- **S1-020 Win/lose result screen** — current overlay is functional for testing; stars/retry/next UX is table stakes for M2 content engine, not M1 foundational goals.
- **S1-021 Efficiency score** — pure-logic model; no UI, low risk, but unnecessary before content exists to score.

---

## Go/No-Go Assessment

> *PR-MILESTONE skipped — Lean mode.*

**Recommendation: CONDITIONAL GO**

**Conditions (both required before M1 closes):**
1. S1-011 Settings UI merged and tested (~1 day)
2. S1-010 First-time tutorial merged and tested (~2 days)

**Rationale:** The Must-Have critical path is 100% complete with 74/74 tests green, CI green, and no known bugs. The architecture is sound — model/view seam maintained, all autoloads injectable and tested. However, M1's explicit goal is a *"retainable"* build that includes a first-time tutorial, and settings are only half-done (data layer ready, player-facing UI missing). The 3 remaining days of work are well-scoped and low-risk given the foundation is solid. M1 is close — ship those two items and it's done.

---

## Action Items

| # | Action | Owner | Deadline |
|---|--------|-------|----------|
| 1 | Implement Settings UI (S1-011) | ui-programmer | Before M1 close |
| 2 | Implement first-time tutorial (S1-010) | ux-designer + ui-programmer | Before M1 close |
| 3 | Update `sprint-01.md` statuses (S1-002–S1-005 → **Done**) | producer | This week |
| 4 | Update GAME_PLAN.md §2 "Current State" table to reflect Sprint 1 systems | producer | This week |
| 5 | Manual feel sign-off: JuiceService full-motion on device | qa-lead | Before M1 close |
| 6 | AudioService feel sign-off: all SFX correct on device | qa-lead | Before M1 close |

---

*Generated by `/milestone-review` (lean mode) on 2026-06-08.*
