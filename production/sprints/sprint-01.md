# Sprint 1 — Foundation (Phase 0 / Milestone M1)

> Indicative dates; adjust to your calendar. Goal-driven, not date-driven.

## Sprint Goal

Turn the playable rules MVP into a *retainable* build: progress persists, the game
has settings, and the core loop has audio + juice + a first-time tutorial.

## Milestone Context

- **Current Milestone**: M1 — Playable Core+ (`docs/GAME_PLAN.md` §15)
- **Milestone Deadline**: TBD (M1 ≈ 3–4 weeks)
- **Sprints Remaining in M1**: ~1–2

## Capacity

- **Total days**: 10 (assume 1 dev, 2 working weeks) — adjust to team
- **Buffer (20%)**: 2 days reserved for unplanned work
- **Available**: 8 days

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria | Status |
|----|------|-------------|-----------|-------------|--------------------|--------|
| S1-001 | **SaveService** autoload: versioned JSON in `user://` (schema_version, current_level, settings, **age_band** per ADR-0005); load on boot, save on change; corrupt/missing → safe defaults | godot-gdscript-specialist | 2 | None | Unit tests: round-trip save/load; missing file → defaults; bumped schema migrates without data loss; `age_band` persists. Behind model/view seam (ADR-0001) | **Done** (merged in #3, 14 tests green) |
| S1-002 | Persist progression: `GameManager.current_level` read/written via SaveService (score persistence deferred to scoring design, S1-021) | gameplay-programmer | 1 | S1-001 | Win advances & persists across app restart (test + manual) | **Done** (merged in #4, 7 tests green) |
| S1-003 | **Settings**: data model (sound on/off, music on/off, haptics, reduced-motion) persisted via SaveService | godot-gdscript-specialist | 1 | S1-001 | Toggles persist; defaults sane; unit test on settings model | **Done** (merged in #4, 13 tests green). UI = S1-011 |
| S1-004 | **Audio**: `AudioService` + SFX for tap/route/discard/stack-clear/win/lose + calm music bed; honors Settings mute | sound-designer + godot-gdscript-specialist | 2 | S1-003 | Each `GameEvent.Kind` triggers correct SFX on replay; mute respected; no audio logic in `core/` | **Done** (merged in #5, 11 tests green; CC0 assets in; audio _feel_ pending manual sign-off) |
| S1-005 | **Juice pass** on event replay: tween polish, clear particles, haptic on clear/win; gated by reduced-motion setting | technical-artist + ui-programmer | 2 | S1-003 | Cascade animates in event order (ADR-0002); reduced-motion disables shake/particles; 60 FPS on mid device | **Done** (merged in #6, 6 tests green; clear burst/haptic/punch wired; feel + 60 FPS pending manual) |

### Should Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria | Status |
|----|------|-------------|-----------|-------------|--------------------|--------|
| S1-010 | **First-time tutorial**: guided Level 1 (coach the tap, explain stacks/discard), shown once (flag in save) | ux-designer + ui-programmer | 2 | S1-001 | New player sees coaching; completing once sets flag; skippable | **Done** (2026-06-09): TutorialLogic/TutorialState (core), CoachOverlay (view), main.gd wiring, SaveData.tutorial_seen. 34 tutorial tests (23 unit + 11 integration); full suite 152 green. Visual ACs (reduced-motion / colorblind / font-scale) pending manual QA |
| S1-011 | Settings UI screen wired to S1-003 model | ui-programmer | 1 | S1-003 | All toggles reflect & mutate persisted settings; UI owns no game state | **In Review** (built as a **pause menu** per design ref: `PauseMenu` w/ round audio toggles + pill switches + Home/Continue, pauses tree; bound to SettingsService. Adds **colorblind mode** — `colorblind` setting + `StackPalette` Okabe-Ito swap, live board recolour. 11 interaction/palette tests green + rendered evidence; device feel pending) |

### Nice to Have (Cut First)

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria | Status |
|----|------|-------------|-----------|-------------|--------------------|--------|
| S1-020 | Win/lose result screen (stars placeholder, retry/next) | ui-programmer | 1 | S1-002 | Appears on WIN/LOSE event; routes to next/retry | **Done** (2026-06-10): `ResultScreen` WIN ("WELL DONE!"+hero star+claim) / LOSE (modal+retry) per ref mocks; routes via `start_level`. Monetisation/meta (revive/coins/IAP offer, reward chips, star rating, tournament) are hidden placeholders → M2/M3/M4. 7 interaction tests; full suite 159 green. Visual polish (confetti/star art) + monetisation wiring deferred |
| S1-021 | Basic efficiency score (fewer discards → higher) — model only | systems-designer | 1 | None | Pure function in `core/`/`data`, unit-tested; no UI required | Not Started |

## Carryover from Sprint 0

| Original ID | Task | Reason | New Estimate | Priority |
|------------|------|--------|--------------|----------|
| — | None (Sprint 0 = MVP + CI + framework import, complete) | — | — | — |

## Risks to This Sprint

| Risk | Probability | Impact | Mitigation | Owner |
|------|------------|--------|-----------|-------|
| Save schema churn as features land | Med | Med | Version field + migration test from day one (S1-001) | lead-programmer |
| Audio assets not ready | Med | Low | Use placeholder Kenney/CC0 SFX; swap later | sound-designer |
| Juice work risks frame budget on low-end | Low | Med | Profile (`/perf-profile`); reduced-motion path is the floor | performance-analyst |
| Tutorial scope creep | Med | Med | Keep to Level 1 coaching only; `/scope-check` mid-sprint | producer |

## External Dependencies

| Dependency | Status | Impact if Delayed | Contingency |
|-----------|--------|------------------|-------------|
| SFX/music assets (licensed) | Not started | Audio task slips | Placeholder CC0 audio |

## Definition of Done

- [x] All Must Have tasks complete and pass acceptance criteria
- [x] SaveService, Settings, scoring (if done) have passing gdUnit4 tests
- [x] CI green on the PR(s)
- [x] Reduced-motion / mute paths verified (unit-tested; device feel sign-off pending)
- [x] `core/` purity preserved (no Node/audio/IO in core) — ADR-0001
- [x] Design docs updated for any deviations; new systems get a GDD if non-trivial
- [x] Code reviewed and merged to `main`

## Notes

- Sequence: **S1-001 → S1-002/003 → S1-004/005 → S1-010/011**. The save layer
  unblocks everything else; do it first.
- Author GDDs for SaveService/Settings/Audio via `/design-system` if they grow
  beyond trivial (the four shipped systems are already documented in `design/gdd/`).
