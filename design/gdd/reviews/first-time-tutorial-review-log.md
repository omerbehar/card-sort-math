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
