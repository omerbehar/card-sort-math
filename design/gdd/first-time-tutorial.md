# GDD: First-Time Tutorial

> **Status:** Revised after design review (2026-06-08) — NEEDS REVISION items
> addressed. Ready for re-review / implementation.
> **Story:** S1-010 (`production/sprints/sprint-01.md`) · **Milestone:** M1

## Design decisions (locked)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Intrusiveness | **Coached, free play** | Non-blocking hint; never gates input. Fits the "calm, not frantic" pillar. |
| Depth | **Core route only** | Teach the one load-bearing action (compute → tap → route to the matching stack). Clear/discard discovered naturally. *Goal framing is scoped to the route itself (see §3 R3) — it does not explain clear/win/discard.* |
| Trigger | **Once, fire-and-forget** | Shows once on first Level 1, sets a save flag, never offered again. No replay path (tracked as a future a11y story — see §6). |
| Completion | **First ROUTE, not any tap** | The tutorial completes when the player actually *routes* a card to its match (with a safety valve). A pre-route discard keeps the coach up. Resolves the "exit un-taught" risk while keeping "shows once, never returns". |

---

## 1. Overview

A non-blocking, first-run **coach** on Level 1. Once the board spawns for a
brand-new player, the tutorial highlights a single *productive* card (one whose
result matches an **open, non-full** stack) and shows a one-line prompt to solve
it and route it. The player may tap **anything** — the hint never gates input.
The coach persists (silently) through any early discards and **completes on the
player's first ROUTE**: it shows a brief confirm toast, sets a persistent
`tutorial_seen` flag, and never appears again. A safety valve completes it after
a few non-routing taps so it can never trap a confused player. The decision logic
(`should_show`, `pick_target`, `should_complete`, `is_route`) is pure and
node-free per ADR-0001; a thin `CoachOverlay` view renders the hint and exposes
inspectable hooks for testing.

## 2. Player Fantasy

*"I know what to do immediately."* The player feels gently oriented, never
lectured. One clear nudge points the way; when they send their first card onto
its matching stack it lands satisfyingly, the coach gives a small "yes, that",
and then they're trusted to play. No modal walls, no forced sequence, no quiz —
the game's calm tone holds from the very first second. A returning player never
sees the tutorial again and is never nagged.

## 3. Detailed Rules

**Lifecycle (three states):**

| State | Entered when | Behaviour |
|-------|-------------|-----------|
| `ARMED` | A level starts and `should_show` is true | Pick the highlight target **once** (at board spawn, before any tap); spawn the `CoachOverlay`. |
| `COACHING` | Overlay shown | Hint visible, non-blocking. Waiting for the first **ROUTE** (or the safety valve / a terminal LOSE). |
| `DONE` | First ROUTE, safety valve, terminal LOSE, or already-seen | Flag persisted (except the defensive no-cards case, R9); overlay faded out; never re-armed this session. |

**Rules:**

1. **Trigger.** The coach arms **only** on level `TUTORIAL_LEVEL` (= 1) and
   **only** when `save.tutorial_seen == false`. Any other level, or a returning
   player, skips straight to `DONE` (no overlay created).
2. **Target selection (once, at spawn).** Immediately after the board spawns and
   exposure is computed — and **only** then — pick one **productive** card: an
   exposed card whose result matches an **open, non-full** stack (see §4). If
   several qualify, pick the lowest `card_id` (deterministic). If none qualify,
   fall back to the lowest exposed `card_id` with neutral copy. `pick_target` is
   never re-run mid-play (it is re-run only on a fresh `start_level`, R-EC8).
3. **Render + goal framing.** The overlay draws a **shape-based** highlight on the
   target card (outline ring + an arrow — never colour alone) and a one-line
   banner. Copy names the immediate *route* objective (it does **not** explain
   clear/win/discard):
   - Productive target: *"Add it up — send the card to its matching stack."*
   - Fallback (no productive tap available): *"Tap a card to place it."*
   - Confirm (after a route): *"Nice — matched the stack!"*

   All strings are resolved through localization keys (`tutorial_route`,
   `tutorial_neutral`, `tutorial_confirm`), not literals (see §6, §7).
4. **Placement (390×844 portrait).** Tutorial chrome respects safe insets (top
   ≥ 24 px, bottom ≥ 34 px, sides ≥ 16 px) and must not overlap the HUD (gear at
   `(12,12,60×60)`, top badges) or the tool bar (`y ≥ 724`):
   - **Highlight ring** hugs the target card's rect, stroke `HIGHLIGHT_RING_WIDTH`.
   - **Arrow** sits just outside the card pointing at it; it points **down** from
     above the card by default, and flips to point **up** from below when the card
     sits in the top band (`card.top < 300`, i.e. near the stacks) so it never
     overlaps the stack row.
   - **Message banner** occupies a fixed safe band: centred, `BANNER_W` wide, in
     the **bottom** band (`y ≈ 652`, clear of the tool bar). If the highlighted
     card overlaps that band, the banner moves to the **top** band (`y ≈ 84`,
     just under the HUD header). The banner never overlaps the highlighted card.
5. **Non-blocking + grace.** The overlay never intercepts touches
   (`MOUSE_FILTER_IGNORE`); the player can tap **any** exposed card, never gated.
   Completion processing is suppressed until the hint has been visible for at
   least `MESSAGE_FADE_IN + INPUT_GRACE` — an instant first tap still routes the
   card in-game, but the confirm/flag wait out the grace so the banner was seen.
6. **Completion = first ROUTE.** While `COACHING`, each *committed* tap (one the
   model accepts — a non-empty event list) is classified (`should_complete`, §4):
   - Events contain a **ROUTE** → complete with `routed = true`: show the confirm
     toast for `CONFIRM_DWELL`, set `save.tutorial_seen = true`, persist, fade to
     `DONE`.
   - Events are non-routing (discard-only) and the running non-route tap count is
     **below** `TUTORIAL_MAX_TAPS` → **stay** `COACHING` (coach persists; flag
     **not** set; no confirm).
   - Non-routing tap that reaches `TUTORIAL_MAX_TAPS` (safety valve) → complete
     with `routed = false`: no confirm, set flag, persist, fade.
   - Events contain a terminal **LOSE** → complete with `routed = false`: no
     confirm, set flag, persist, fade (the board is over; release the coach).
7. **One nudge only.** The coach never re-points or chases. A tap on a
   *different* card is fine — it completes on the first ROUTE just the same.
8. **Accessibility.** `reduced_motion` → highlight is static (no pulse/bob, arrow
   bob `= 0`), confirm toast fades only. `colorblind` → unaffected (shape-based,
   not colour). No audio cue for the prompt at this stage (touch-first;
   deferred — see §6).
9. **Abandon / defensive.** If the player closes the app before completion,
   `tutorial_seen` stays false and the coach shows again next launch. If `E = ∅`
   at spawn (no exposed cards — should not occur on a valid Level 1), the coach
   is **not** shown and the flag is **not** set (leave it for a valid board),
   rather than transitioning to a `COACHING` state that can never complete.

## 4. Formulas

**Variables**

| Symbol | Meaning | Type / Range |
|--------|---------|--------------|
| `TUTORIAL_LEVEL` | Level index that triggers the coach (1-indexed; `1` = first level) | `int`, `1` |
| `seen` | `save.tutorial_seen` | `bool` |
| `E` | Exposed (tappable) card ids this turn | `Array[int]` |
| `R(c)` | Result of card `c` (`CardData.result`) | `int` |
| `Topen` | Targets of stacks that are **open AND have room** | `Array[int]` (see below) |
| `n_nonroute` | Running count of committed non-routing taps while `COACHING` | `int ≥ 0` |

**Open-target set** (the fix: capacity-aware)
```
Topen = { stack_target(i) : i ∈ stacks,
          stack_target(i) ≥ 0 AND stack_count(i) < STACK_CAPACITY }
```
A full stack (`count == CAPACITY`) is **not** open — a card matching it would
discard, so it must not make a card "productive".

**Should-show predicate**
```
should_show(seen, level) = (not seen) AND (level == TUTORIAL_LEVEL)
```

**Highlight-target selection** — pure signature:
`pick_target(exposed: Array[int], results: Dictionary, open_targets: Array[int]) -> int`
```
productive = { c ∈ exposed : results[c] ∈ open_targets }
pick_target = min(productive)        if productive ≠ ∅
            = min(exposed)           else if exposed ≠ ∅   (fallback, neutral copy)
            = -1                     else                  (no card → not shown, R9)
```
Inputs are plain `Array`/`Dictionary` (no `BoardModel` reference). `min` over
`card_id` is deterministic; the returned id is always a member of `exposed`
(hence guaranteed tappable).

**Route test** — `is_route(events: Array[GameEvent]) -> bool`
```
is_route(events) = ∃ e ∈ events : e.kind == ROUTE      (regardless of other kinds)
```

**Completion classifier** — pure:
`should_complete(events, n_nonroute, max_taps) -> { complete: bool, routed: bool }`
```
if is_route(events):                 → { true,  true  }   # routed
elif events contains LOSE:           → { true,  false }   # terminal
elif (n_nonroute + 1) ≥ max_taps:    → { true,  false }   # safety valve
else:                                → { false, false }   # keep coaching
```
(`events` is assumed non-empty — i.e. a *committed* tap. Empty event lists, from
tapping a covered/removed card, are ignored and do not advance `n_nonroute`.)

**Constants** (defaults; tunable — see §7)

| Constant | Default | Unit |
|----------|---------|------|
| `MESSAGE_FADE_IN` | 0.25 | s |
| `INPUT_GRACE` | 0.30 | s |
| `CONFIRM_DWELL` | 1.2 | s |
| `FADE_OUT` | 0.30 | s |
| `HIGHLIGHT_PULSE_PERIOD` | 0.90 | s (ignored if `reduced_motion`) |
| `TUTORIAL_MAX_TAPS` | 3 | committed non-route taps |

**Worked examples**
> **Productive path.** Fresh save, Level 1 → `should_show(false, 1) = true`.
> `exposed = [0,2,5]`, `results = {0:7, 2:4, 5:7}`. Stacks: targets `[7,9,3,5]`,
> counts `[0,0,0,0]` → `open_targets = [7,9,3,5]`. `productive = {0,5}` →
> `pick_target = 0`. Player taps 0 → `[ROUTE(0→stack@7)]` → `is_route = true` →
> confirm 1.2 s → `tutorial_seen = true` → `DONE`.
>
> **Capacity fix.** Same board, but stack `@7` already has `count = 3`. Now
> `open_targets = [9,3,5]`, so `R(0)=7 ∉ open_targets` → card 0 is **not**
> productive; `pick_target` looks elsewhere. (Old formula would have highlighted
> card 0 and it would have discarded — broken promise.)
>
> **Discard-then-route.** `pick_target = 0` (productive). Player ignores it and
> taps a non-matching card → `[DISCARD(..)]` → `should_complete(.., 0, 3)` →
> `{false,false}` (`n_nonroute → 1`): coach stays. Player then taps card 0 →
> `[ROUTE]` → `{true,true}` → confirm → `DONE`. Flag set only now.

## 5. Edge Cases

| # | Situation | Explicit behaviour |
|---|-----------|--------------------|
| 1 | **No productive tap at spawn** (no exposed result matches an open, non-full stack) | Highlight `min(exposed)` with **neutral** copy. Coach persists through discards; the safety valve (`TUTORIAL_MAX_TAPS`) completes it (`routed = false`, no toast) if no route ever happens. *Level 1 is authored to avoid this — see §6 constraint.* |
| 2 | **No exposed cards at all** (`E = ∅`, defensive — shouldn't occur on Level 1) | `pick_target = -1`: overlay is **not** shown and the flag is **not** set (R9). No `COACHING` state that can't complete. |
| 3 | **Player taps a non-highlighted card** | Allowed (free play). If it routes → completes; if it discards → coach stays (until a route or the safety valve). Coach never re-points. |
| 4 | **First tap is a discard (no match)** | Coach **stays** `COACHING`; `tutorial_seen` is **not** set; `n_nonroute += 1`; no confirm. The player still gets a chance to route. (Changed from the pre-review "any tap completes".) |
| 5 | **Player can't/won't route** (repeated discards) | After `TUTORIAL_MAX_TAPS` committed non-route taps, the safety valve completes it (`routed = false`, no toast, flag set). The coach never traps the player. |
| 6 | **Player taps a covered/removed card** (empty event list) | Not a committed tap: ignored, `n_nonroute` unchanged, coach stays. |
| 7 | **Player opens the pause menu during coaching** | Pause menu (S1-011) overlays and pauses the tree; the coach sits underneath untouched and resumes when unpaused. Tapping **Resume/Home/Continue is not a card tap** — the completion listener (wired through `_on_card_tapped`) never fires for menu buttons, so it cannot complete the tutorial. No flag change. |
| 8 | **Returning player** (`tutorial_seen == true`) | `should_show = false`: overlay never created; zero runtime cost. |
| 9 | **`reduced_motion` on** | Highlight static (no pulse/bob); confirm toast fades only. Fully functional. |
| 10 | **Level 1 restarts before completion** (Home, or lose→retry while still unseen) | `start_level(1)` re-evaluates `should_show`; since `seen` is still false, the coach **re-arms**: `pick_target` runs again on the fresh board, `n_nonroute` resets to 0, state → `COACHING`. The prior session's transient state does not persist. |
| 11 | **Player loses during the tutorial** | A committed tap returning `[..,LOSE]` completes the tutorial (`routed = false`, no toast, flag set); the normal Game-Over overlay then shows. Rare on an authored Level 1. |
| 12 | **Save write fails on completion** | In-memory `tutorial_seen` stays `true` and suppresses the coach for the rest of the session (`should_show → false`); a failed disk write only risks re-showing next launch. Non-fatal, consistent with SaveService's "bad save never crashes" stance. |

## 6. Dependencies

**This system depends on:**

| System | Why | Change required |
|--------|-----|-----------------|
| `SaveData` / `SaveService` (`core/save_data.gd`) | Persist `tutorial_seen` | **Add** `tutorial_seen: bool` (default `false`) to `to_dict`/`from_dict`, missing-key-defaulted (no schema bump — same pattern as `colorblind`). |
| `BoardModel` (`core/board_model.gd`, read-only) | Exposed card ids, card results, and **stack target + count** per stack (for capacity-aware `Topen`) | **Read** `stack_count(i)` (already exposed) alongside `stack_target(i)`. No model change. |
| `GameEvent` (`core/game_event.gd`) | `ROUTE`/`LOSE` kinds drive completion + confirm | None. |
| `main.gd` (view controller) | Arms the coach once on `start_level`; feeds each committed tap's events to the coach in `_on_card_tapped` | Wire-up only. |
| `Settings` (`data/settings.gd`) | `reduced_motion` gates highlight animation | None — no new setting. |
| `FloorArea` / `Card` (`scenes/`) | Resolve the highlighted card's global rect to anchor ring/arrow | None. |
| **Level 1 content** (`autoloads/level_data.gd`, `data/level_config.gd`; `level-and-solvability.md`) | Tutorial effectiveness | **Constraint:** Level 1 must expose ≥1 productive card at spawn (a card whose result matches an open, non-full stack) and present **no discard-pressure loss on a first clear**, so the route lesson always lands and first play isn't punishing. Co-authored with this GDD. |

**New components introduced:**

- `TutorialLogic` (pure, node-free — `core/`): `should_show`, `pick_target`,
  `is_route`, `should_complete`. Unit-tested.
- `CoachOverlay` (view — `scenes/ui/coach_overlay.gd`): renders ring + arrow +
  banner + confirm toast; owns no game state. **Observable test hooks:**
  `signal armed(card_id: int, productive: bool)`, `signal completed(routed: bool)`,
  `var state: int` (enum `ARMED`/`COACHING`/`DONE`), `var target_card_id: int`,
  `var is_productive: bool`, `var confirm_shown: bool`, and
  `mouse_filter == MOUSE_FILTER_IGNORE` at spawn.

**Reverse references to update when implementing (bidirectional):**

- `design/systems-index.md` — add a **First-Time Tutorial** node (depends on
  Save, BoardModel, Settings, Level 1 content).
- `core/save_data.gd` doc comment — list `tutorial_seen` among persisted fields.
- `design/gdd/level-and-solvability.md` — note the Level 1 tutorial constraint.
- A **future story** (post-M1) covers a "replay tutorial / how-to-play" entry
  point from the pause menu (closes the no-replay accessibility gap). Tracked in
  `docs/GAME_PLAN.md` onboarding scope.
- Follows ADR-0001 (model/view) and ADR-0002 (event replay); **no new ADR**
  required (small feature reusing existing seams) — a deliberate exception to the
  coding-standards "every system → ADR" guideline.

## 7. Tuning Knobs

| Knob | Default | Safe range | Affects |
|------|---------|-----------|---------|
| `TUTORIAL_LEVEL` | `1` | **`1` in shipped builds** (other values QA-only) | Which level triggers the coach. Non-1 values point the coach at boards the copy/constraint weren't authored for. |
| `TUTORIAL_MAX_TAPS` | `3` | `2–6` | Safety-valve: committed non-route taps before the coach completes itself. Lower = releases sooner; higher = more chances to route. |
| `INPUT_GRACE` | `0.30` s | `0.20–0.60` | Min time the hint is visible before completion is processed (protects "non-blocking but readable"). |
| Route copy (`tutorial_route`) | *"Add it up — send the card to its matching stack."* | ≤ ~44 chars @ base scale | First-tap instruction + immediate goal framing. |
| Neutral copy (`tutorial_neutral`) | *"Tap a card to place it."* | ≤ ~40 chars | Instruction when no productive tap exists (accurate for a discard). |
| Confirm copy (`tutorial_confirm`) | *"Nice — matched the stack!"* | ≤ ~30 chars | Positive reinforcement after a route. |
| `MESSAGE_FADE_IN` | `0.25` s | `0.10–0.60` | How quickly the hint appears. |
| `CONFIRM_DWELL` | `1.2` s | `0.6–2.5` | How long the success toast lingers; the toast is `MOUSE_FILTER_IGNORE` so it never blocks the next tap. |
| `FADE_OUT` | `0.30` s | `0.10–0.60` | Hint dismissal smoothness. |
| `HIGHLIGHT_PULSE_PERIOD` | `0.90` s | `0.5–1.5` (or off) | Attention-pulse cadence; **ignored** under `reduced_motion`. |
| `HIGHLIGHT_ARROW_BOB` | `6` px | `0–8` px | Arrow bob amplitude; forced to `0` under `reduced_motion`. |
| `HIGHLIGHT_RING_WIDTH` | `5` px | `3–8` px | Ring stroke; the low-vision floor — too thin disappears at arm's length. |
| `HIGHLIGHT_ARROW_SIZE` | `28` px | `20–40` px | Arrow size; legibility of the directional cue. |
| `BANNER_W` | `358` px | `≤ 358` (16 px side margins) | Banner width at 390 px; must not clip at base or max OS font scale. |
| Target pick rule | `min(card_id)` | must stay deterministic | Which productive card is highlighted; determinism keeps it unit-testable. |

> Constants live colocated with `TutorialLogic` / `CoachOverlay`; if they
> proliferate, promote to a config resource (per the data-driven rule). All
> user-facing strings resolve through localization keys (stub today, real system
> later) — never raw literals in `CoachOverlay`. Banner text must wrap/shrink (not
> clip) when the OS font scale enlarges it; verify at base and max scale (§8).

## 8. Acceptance Criteria

**Logic — automated unit tests, BLOCKING** (`tests/test_tutorial_logic.gd`,
matching the repo's flat layout; `SaveData` cases may live beside
`tests/test_save_data.gd`):

| AC | Pass condition |
|----|----------------|
| AC1 | `should_show(false, 1) == true`; `should_show(true, 1) == false`; `should_show(false, 0) == false`; `should_show(false, 2) == false`. (Level is 1-indexed.) |
| AC2 | `pick_target([0,2,5], {0:7,2:4,5:7}, [7,9]) == 0` — lowest productive id. Returned id ∈ `exposed`. |
| AC3 | `pick_target([2,5], {2:4,5:8}, [7,9]) == 2` (no productive → lowest exposed); `pick_target([], {}, [7]) == -1`. |
| AC4 | `is_route([]) == false`; `is_route([discard]) == false`; `is_route([route]) == true`; `is_route([discard,route]) == true`; `is_route([route,win]) == true`. (`events: Array[GameEvent]`.) |
| AC5 | `should_complete([route], 0, 3) == {true,true}`; `should_complete([discard], 0, 3) == {false,false}`; `should_complete([discard], 2, 3) == {true,false}` (valve); `should_complete([lose], 0, 3) == {true,false}`. |
| AC6 | `SaveData.to_dict()` contains key `"tutorial_seen"`; `from_dict({"tutorial_seen":true}).tutorial_seen == true`; `from_dict({}).tutorial_seen == false`; `from_dict({"tutorial_seen":false}).tutorial_seen == false`; schema version unchanged (no bump). |

**Integration — BLOCKING** (gdUnit4 integration test using the `CoachOverlay`
hooks, or documented playtest where noted):

| AC | Pass condition |
|----|----------------|
| AC7 | Fresh save → `start_level(1)` adds a `CoachOverlay` whose `state == COACHING`, `target_card_id == pick_target(...)`, and `is_productive == true` (Level 1 constraint). |
| AC8a | At spawn, `coach.mouse_filter == Control.MOUSE_FILTER_IGNORE`. **AC8b (playtest):** tapping a card visually under the overlay during `COACHING` is processed by the model. |
| AC9 | A committed **discard** tap while `COACHING` (below the valve): `tutorial_seen` stays `false`, `coach.state == COACHING`, `coach.confirm_shown == false`. |
| AC10 | A committed **ROUTE** tap: `coach.completed(true)` fires, `coach.confirm_shown == true`, injected `SaveData.tutorial_seen == true`, injected spy `SaveService.save()` called once, and the overlay is freed (`is_instance_valid(coach) == false`) after `CONFIRM_DWELL + FADE_OUT`. |
| AC11 | Safety valve: `TUTORIAL_MAX_TAPS` committed non-route taps → `coach.completed(false)` fires, no confirm, `tutorial_seen == true`. |
| AC12 | Re-arm (EC10): calling `start_level(1)` again with `seen == false` yields a fresh `COACHING` overlay with a (re)picked `target_card_id` and `n_nonroute == 0`. |
| AC13 | With `tutorial_seen == true`, `start_level(1)` creates **no** `CoachOverlay` child of the main scene. |
| AC14 | Save-fail (EC12): with a `SaveService` stub that fails to write, after completion the in-session `should_show(...)` returns `false` (in-memory suppression holds). |

**Visual — ADVISORY** (screenshot + lead sign-off, `production/qa/evidence/`):

| AC | Pass condition |
|----|----------------|
| AC15 | With `reduced_motion == true`, two captures ≥1 s apart show no pixel delta in the highlight region (no pulse/bob). |
| AC16 | Under a deuteranopia simulation, the ring + arrow are distinguishable from the card/background (shape-based, not colour). |
| AC17 | Banner text does **not** clip or overflow `BANNER_W` at base **and** maximum supported OS font scale (wraps or shrinks instead). |
