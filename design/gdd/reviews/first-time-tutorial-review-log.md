# Review Log — First-Time Tutorial GDD

## Review — 2026-06-08 — Verdict: NEEDS REVISION
Scope signal: M
Specialists: game-designer, systems-designer, ux-designer, qa-lead, creative-director
Blocking items: 7 | Recommended: 4
Summary: Design direction sound; blockers were spec-precision gaps. All four
specialists converged on completing the tutorial on the first ROUTE rather than
any committed tap (collapsing the misleading discard-first "success", the
`[LOSE]`-counts-as-completion bug, and the un-taught-exit churn risk). Other
blockers: capacity-aware `Topen` (a full stack must not make a card
"productive"), CoachOverlay observable hooks so integration ACs are CI-testable,
an input grace window, and concrete 390×844 placement. Creative-director
confirmed no locked decisions need overturning — "fire-and-forget" reinterpreted
as "shows once, completes on first route, never returns".
Prior verdict resolved: First review

## Revision — 2026-06-08 (same day)
All 7 blocking items addressed in commit `9730ae4`:
1. Completion = first ROUTE; discards keep the coach up; `TUTORIAL_MAX_TAPS`
   safety valve + terminal LOSE handling.
2. No-route-possible / `E=∅` paths defined (not shown / valve), so COACHING
   cannot hang.
3. Capacity-aware `Topen` (`stack_count(i) < STACK_CAPACITY`).
4. `CoachOverlay` observable hooks (`armed`/`completed` signals, `state`,
   `target_card_id`, `is_productive`, `confirm_shown`).
5. `INPUT_GRACE` window before completion is processed.
6. Concrete placement: safe insets, HUD/toolbar collision, adaptive arrow/banner
   bands.
7. §5 edge cases + §8 ACs rewritten to the ROUTE-completion model; flat test
   path (`tests/test_tutorial_logic.gd`); localization keys; font-scale AC;
   Level 1 content constraint; deferred replay-path a11y story.
Recommended items also folded in (route-scoped goal framing, softened fantasy
line, ACs for re-arm + save-fail).
Status: Awaiting re-review (clean session).

## Review — 2026-06-09 — Verdict: MAJOR REVISION NEEDED
Scope signal: L
Specialists: game-designer, systems-designer, ux-designer, qa-lead, godot-specialist, creative-director
Blocking items: 5 | Recommended: 16
Summary: Design direction confirmed sound; 5 blockers required design decisions and
architecture spec before code. (1) Arrow threshold (`card.top < 300`) confirmed as
global screen-space coordinates — with `FLOOR_ORIGIN=(0,300)` the flip branch is
dead code for all current layouts; explicitly documented as attention-pointer spec.
(2) `TutorialState` RefCounted intermediary specified for `n_nonroute` ownership;
grace timer in `CoachOverlay`; tap-observation wiring via `on_committed_tap()`.
(3) Safety-valve flag policy locked as explicit design decision (permanent flag,
post-M1 recovery path). (4) Copy revised to math-result framing. (5) Integration
test DI contract specified (configure() method + simulated-frame timing for CI).
Bidirectional ref added to level-and-solvability.md.
Prior verdict resolved: Yes — 5 MAJOR REVISION items addressed in same-day revision.

## Review — 2026-06-09 (re-review 3) — Verdict: NEEDS REVISION
Scope signal: M
Specialists: game-designer, systems-designer, ux-designer, qa-lead, godot-specialist, creative-director
Blocking items: 6 | Recommended: 10
Summary: Design identity confirmed sound; 6 blockers were all engine-API precision errors and
spec gaps — no design rethinking required. (1) `Tween.kill()` does not exist in Godot 4;
spec updated to mandate `node.create_tween()` (auto-freed with node, no manual kill).
(2) `simulate_seconds()` does not exist in gdUnit4 v6.1.3; all integration ACs updated to
`simulate_frames(N, 16)`. (3) State machine ARMED→no-overlay arc added for E=∅ case.
(4) AC8b rewritten to assert side-effect (event list non-empty) rather than unimplementable
call-interception. (5) AC10 step 5 and AC12 updated with `simulate_frames(2)` frame-advance
before `is_instance_valid` checks. (6) AC_E0 added for E=∅ integration coverage. Recommended
fixes also applied: caller contract for `results[c]`, ROUTE+LOSE priority note, `node.create_tween`
throughout, MOUSE_FILTER_IGNORE children note, pivot contract, arrow flip threshold derived from
constant, schema version decision documented, pre-M1 playtest gate added to arrow design decision,
AC14 "on disk" wording clarified. Advisory integration ACs added for LOSE-during-COACHING and
neutral-copy path.
Prior verdict resolved: Yes — all 6 NEEDS REVISION items addressed in same-day revision.
