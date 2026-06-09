# GDD: First-Time Tutorial

> **Status:** Drafting (skeleton). Sections filled one at a time with sign-off.
> **Story:** S1-010 (`production/sprints/sprint-01.md`) · **Milestone:** M1

## Design decisions (locked)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Intrusiveness | **Coached, free play** | Non-blocking hint; never gates input. Fits the "calm, not frantic" pillar. |
| Depth | **Core route only** | Teach the one load-bearing action (compute → tap → routes to matching stack). Clear/discard discovered naturally. |
| Trigger | **Once, fire-and-forget** | Shows once on first Level 1, sets a save flag, never offered again. No replay path (yet). |

---

## 1. Overview

A non-blocking, first-run **coach** on Level 1. Once the board spawns for a
brand-new player, the tutorial highlights a single *productive* card (one whose
result matches an open stack target) and shows a one-line prompt to solve it and
tap. The player may tap **anything** — the hint never gates input. On the
player's first committed tap the coach briefly confirms (when that tap routed a
card) and fades out, sets a persistent `tutorial_seen` flag, and is never shown
again. The decision logic (should-show, pick-highlight-target) is pure and
node-free per ADR-0001; a thin `CoachOverlay` view renders the hint.

## 2. Player Fantasy

*"I get it in one tap."* The player feels gently oriented, never lectured. One
clear nudge points the way, the first card flies satisfyingly onto its matching
stack, and then they're trusted to play. No modal walls, no forced sequence, no
quiz — the game's calm tone holds from the very first second. A returning player
never sees the tutorial again and is never nagged.

## 3. Detailed Rules
_TBD_

## 4. Formulas
_TBD_

## 5. Edge Cases
_TBD_

## 6. Dependencies
_TBD_

## 7. Tuning Knobs
_TBD_

## 8. Acceptance Criteria
_TBD_
