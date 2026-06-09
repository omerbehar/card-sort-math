# GDD: First-Time Tutorial

> **Status:** Revised after design review (2026-06-09) — MAJOR REVISION items
> addressed (re-review 2). Ready for implementation.
> **Story:** S1-010 (`production/sprints/sprint-01.md`) · **Milestone:** M1

## Design decisions (locked)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Intrusiveness | **Coached, free play** | Non-blocking hint; never gates input. Fits the "calm, not frantic" pillar. |
| Depth | **Core route only** | Teach the one load-bearing action (compute → tap → route to the matching stack). Clear/discard discovered naturally. *Goal framing is scoped to the route itself (see §3 R3) — it does not explain clear/win/discard.* |
| Trigger | **Once, fire-and-forget** | Shows once on first Level 1, sets a save flag, never offered again. No replay path (tracked as a future a11y story — see §6). |
| Completion | **First ROUTE, not any tap** | The tutorial completes when the player actually *routes* a card to its match (with a safety valve). A pre-route discard keeps the coach up. Resolves the "exit un-taught" risk while keeping "shows once, never returns". |
| Safety valve flag | **Sets `tutorial_seen` permanently** | Confused player's recovery path (replay tutorial / how-to-play) is the post-M1 a11y story (see §6). M1 ships without it — **deliberate scoped deferral**. The valve's silent exit is intentional: the coach never traps the player, and future in-context help is planned. |
| Arrow gesture | **Attention pointer only** | The highlight ring + arrow point *at* the highlighted card; they are not a directional cue for card travel and do not indicate the destination stack. Teaching which card to act on is sufficient for the first-time frame. No secondary stack highlight at M1. |

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
| `COACHING` | Overlay shown | Hint visible, non-blocking. Waiting for the first **ROUTE** (or the safety valve / a terminal LOSE). A call to `start_level(1)` while in `COACHING` exits to a fresh `ARMED → COACHING` cycle (EC10); this is the only mid-session re-arm path. |
| `DONE` | First ROUTE, safety valve, terminal LOSE, or already-seen | `tutorial_seen = true` set and persisted (except the defensive E=∅ case, R9); overlay faded out. **DONE is terminal** — once entered, the coach is never re-armed this session (the flag suppresses it). |

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
   banner. The arrow is an **attention pointer**: its arrowhead always faces the
   highlighted card; it does **not** indicate the direction of card travel or the
   location of the destination stack. Copy connects the arithmetic result to the
   routing action (it does **not** explain clear/win/discard):
   - Productive target: *"Solve it — your answer picks the stack."*
   - Fallback (no productive tap available): *"Tap any card to start."*
   - Confirm (after a route): *"Matched — nice work!"*

   All strings are resolved through localization keys (`tutorial_route`,
   `tutorial_neutral`, `tutorial_confirm`), not literals (see §6, §7).
4. **Placement (390×844 portrait).** Tutorial chrome respects safe insets (top
   ≥ 24 px, bottom ≥ 34 px, sides ≥ 16 px) and must not overlap the HUD (gear at
   `(12,12,60×60)`, top badges) or the tool bar (`y ≥ 724`):
   - **Highlight ring** hugs the target card's rect, stroke `HIGHLIGHT_RING_WIDTH`.
     `card.rect` is computed as `Rect2(card.global_position, Vector2(Layouts.CARD_W, Layouts.CARD_H))`
     (`Card` is an `Area2D` — use `global_position`, not a `global_rect` property).
     Read this once at overlay spawn (after `ARMED` picks the target); the card
     does not move while `COACHING` (it is on the static floor).
   - **Arrow** sits just outside the card pointing **at** it (attention pointer —
     arrowhead faces the card). It points **down** from above the card by default.
     When the card sits in the top band (`card.global_position.y < 300` in screen
     space, near the stack row at `y = 112`), the arrow flips to point **up** from
     below, keeping it clear of the stack row. **Note:** with `FLOOR_ORIGIN =
     Vector2(0, 300)`, all floor cards in the current authored layouts (0–2) have
     `global_position.y ≥ 350`, so the flip branch is currently inactive. The
     threshold remains in the spec as a guard for future layouts that place cards
     higher on screen. Validate this threshold against any new layout added.
   - **Message banner** occupies a fixed safe band: centred, `BANNER_W` wide, in
     the **bottom** band (`y ≈ 652`, clear of the tool bar). If the highlighted
     card's rect overlaps that band, the banner moves to the **top** band
     (`y ≈ 84`, just under the HUD header). The banner never overlaps the
     highlighted card. **Note:** with current layouts, the deepest card bottom
     edge reaches y ≈ 636, so the banner will always remain in the bottom band.
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

**Open-target set** (capacity-aware) — deduplicated set of unique targets:
```
Topen = { stack_target(i) : i ∈ stacks,
          stack_target(i) ≥ 0 AND stack_count(i) < STACK_CAPACITY }
```
`Topen` is a **set** (duplicate values collapsed). When two stacks share the same
target (as possible in Level 3), that target appears at most once. In GDScript
implementation use a deduplicated `Array[int]` or check membership with `has()` —
either is correct since `results[c] ∈ Topen` is a membership test, not a count.
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

**Lose test** — `is_lose(events: Array[GameEvent]) -> bool`
```
is_lose(events) = ∃ e ∈ events : e.kind == LOSE        (regardless of other kinds)
```

**Completion classifier** — pure:
`should_complete(events: Array[GameEvent], n_nonroute: int, max_taps: int) -> Dictionary`

Returns `{ "complete": bool, "routed": bool }`.
```
if is_route(events):                   → { "complete": true,  "routed": true  }   # routed
elif is_lose(events):                  → { "complete": true,  "routed": false }   # terminal
elif (n_nonroute + 1) >= max_taps:     → { "complete": true,  "routed": false }   # safety valve
else:                                  → { "complete": false, "routed": false }   # keep coaching
```
(`events` is assumed non-empty — i.e. a *committed* tap. Empty event lists, from
tapping a covered/removed card, are ignored and do not advance `n_nonroute`.)

`n_nonroute` is the caller's responsibility to track (see §6 `TutorialState`) and
is passed by value to `should_complete`. The caller increments it **after** calling
`should_complete` when `complete == false` — i.e. the count passed in is the tally
*before* this tap. Example: second non-route tap → caller passes `n_nonroute = 1`;
`(1 + 1) >= 3` is false → keep coaching, then increment to 2. Third non-route tap →
caller passes `n_nonroute = 2`; `(2 + 1) >= 3` is true → safety valve fires.

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
| `main.gd` (view controller) | Arms the coach once on `start_level`; feeds each committed tap's events to the coach in `_on_card_tapped` | Wire-up only. After `BoardModel.tap_card(card_id)` returns a non-empty event list, call `_coach.on_committed_tap(events)` if `_coach != null` (coach is null when `tutorial_seen == true` or after `DONE`). On `start_level`, free any existing `_coach` before creating a new one: call `_coach.tween_kill(); _coach.free(); _coach = null` before instantiation to prevent double-overlay during rapid restarts. |
| `Settings` (`data/settings.gd`) | `reduced_motion` gates highlight animation | None — no new setting. |
| `FloorArea` / `Card` (`scenes/`) | Resolve the highlighted card's global rect to anchor ring/arrow | None. |
| **Level 1 content** (`autoloads/level_data.gd`, `data/level_config.gd`; `level-and-solvability.md`) | Tutorial effectiveness | **Constraint:** Level 1 must expose ≥1 productive card at spawn (a card whose result matches an open, non-full stack) and present **no discard-pressure loss on a first clear**, so the route lesson always lands and first play isn't punishing. Co-authored with this GDD. |

**New components introduced:**

- `TutorialLogic` (pure, node-free — `core/`): `should_show`, `pick_target`,
  `is_route`, `is_lose`, `should_complete`. Unit-tested. Stateless — all functions
  take their inputs as parameters and return values only.

- `TutorialState` (plain `RefCounted`, node-free — `core/`): holds the one mutable
  session counter `n_nonroute: int`. Created by `main.gd` when arming the coach and
  reset on each `start_level(1)`. Passed to `CoachOverlay.configure(...)` at init.
  Lives in `core/` because it is pure data; `main.gd` owns its lifetime.
  **This is the only valid home for `n_nonroute`** — not `TutorialLogic` (stateless)
  and not `CoachOverlay` (view must not own game-logic counters).

- `CoachOverlay` (view — `scenes/ui/coach_overlay.gd`): renders ring + arrow +
  banner + confirm toast; owns no game-logic state. The grace timer (`MESSAGE_FADE_IN
  + INPUT_GRACE`) lives here as a **presentation-timing concern** — it delays when
  completion feedback is shown, not when the model processes the tap.
  `CoachOverlay` exposes a `configure(state: TutorialState, save_data: SaveData,
  save_service: Object) -> void` method for test dependency injection (enables
  instantiation without a full scene). The overlay must call `_tween.kill()` before
  `queue_free()` to prevent use-after-free on active tweens.
  **Observable test hooks:**
  `signal armed(card_id: int, productive: bool)`,
  `signal completed(routed: bool)`,
  `var state: State` (typed enum — `enum State { ARMED, COACHING, DONE }`, **not**
  `var state: int` — static typing is mandatory per project standards),
  `var target_card_id: int`,
  `var is_productive: bool`,
  `var confirm_shown: bool`,
  `func on_committed_tap(events: Array[GameEvent]) -> void` (called by `main.gd`),
  and `mouse_filter == MOUSE_FILTER_IGNORE` at spawn.
  Parented to the **HUD `CanvasLayer`** (`layer 1`, same layer as the HUD) so it
  renders above all 2D floor/stack nodes without interfering with `Overlay` (layer 10).

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
| Route copy (`tutorial_route`) | *"Solve it — your answer picks the stack."* | ≤ ~44 chars @ base scale | Connects the arithmetic result to the routing action. |
| Neutral copy (`tutorial_neutral`) | *"Tap any card to start."* | ≤ ~40 chars | Instruction when no productive tap exists; does not imply player agency over destination. |
| Confirm copy (`tutorial_confirm`) | *"Matched — nice work!"* | ≤ ~30 chars | Positive reinforcement after a route. |
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
| AC5 | Returns `Dictionary` with keys `"complete"` and `"routed"` (both `bool`). `should_complete([route], 0, 3)` → `{complete:true, routed:true}`; `should_complete([discard], 0, 3)` → `{complete:false, routed:false}`; `should_complete([discard], 2, 3)` → `{complete:true, routed:false}` (valve, `n_nonroute` passed as pre-tap value); `should_complete([lose], 0, 3)` → `{complete:true, routed:false}`. Also: `should_complete([route, win], 0, 3)` → `{complete:true, routed:true}` (ROUTE+WIN path). |
| AC5b | `is_lose([]) == false`; `is_lose([route]) == false`; `is_lose([lose]) == true`; `is_lose([route, lose]) == true`. |
| AC6 | `SaveData.to_dict()` contains key `"tutorial_seen"`; `from_dict({"tutorial_seen":true}).tutorial_seen == true`; `from_dict({}).tutorial_seen == false`; `from_dict({"tutorial_seen":false}).tutorial_seen == false`; schema version unchanged (no bump). |

**Integration — BLOCKING** (gdUnit4 integration tests using `CoachOverlay` hooks)

**Test setup contract (must be decided and documented before writing tests):**
Use `GdUnitSceneRunner` loading `res://scenes/main/main.tscn` with `SaveService`
replaced by an injected double (`double(SaveService).new()`), OR instantiate
`CoachOverlay` directly and call `configure(state, save_data, save_service)` before
adding it to the scene tree. The chosen pattern must be documented in
`tests/test_tutorial_integration.gd` before implementation begins. All timing
assertions must use `await runner.simulate_seconds(N)` (simulated frame time), never
wall-clock `await get_tree().create_timer(N).timeout`, to remain deterministic in
headless CI.

| AC | Pass condition |
|----|----------------|
| AC7 | Fresh save → `start_level(1)` adds a `CoachOverlay` whose `coach.state == CoachOverlay.State.COACHING`, `coach.target_card_id == TutorialLogic.pick_target(...)`, and `coach.is_productive == true` (Level 1 constraint). |
| AC8a | At spawn, `coach.mouse_filter == Control.MOUSE_FILTER_IGNORE`. |
| AC8b | **BLOCKING (automated):** While `COACHING`, simulate a touch at the position of the highlighted card; assert that `BoardModel.tap_card` is called (board model registers the event, e.g. event list is non-empty). Use `GdUnitSceneRunner.simulate_mouse_button_pressed(card_global_pos)`. This verifies that `MOUSE_FILTER_IGNORE` passes input through the overlay to the card beneath. |
| AC8c | **Grace period:** Simulate a tap at `t = 0` (immediately after overlay spawns); assert `coach.completed` signal has **not** fired and `coach.state == COACHING` after the tap. Then `await runner.simulate_seconds(MESSAGE_FADE_IN + INPUT_GRACE + 0.05)`; if the tap was a ROUTE, assert `coach.completed(true)` fired (deferred completion). |
| AC9 | A committed **discard** tap while `COACHING` (below the valve): `injected_save_data.tutorial_seen` stays `false`, `coach.state == COACHING`, `coach.confirm_shown == false`, and `coach._state_obj.n_nonroute == 1` (counter incremented). |
| AC10 | A committed **ROUTE** tap (after grace window — use `await runner.simulate_seconds(MESSAGE_FADE_IN + INPUT_GRACE + 0.05)` before checking): (1) `coach.completed` signal emitted with `routed == true`; (2) `coach.confirm_shown == true`; (3) `injected_save_data.tutorial_seen == true`; (4) injected spy `SaveService.save()` called exactly once; (5) `await runner.simulate_seconds(CONFIRM_DWELL + FADE_OUT + 0.1)` → `is_instance_valid(coach) == false`. Assert each step in order. |
| AC10b | **ROUTE+WIN path:** Tap the last card on the board during `COACHING`; event list contains both `ROUTE` and `WIN`. Assert `coach.completed(true)` fires (not suppressed by WIN), `tutorial_seen == true`, and the normal WIN overlay still shows. |
| AC11 | Safety valve: issue exactly `CoachOverlay.TUTORIAL_MAX_TAPS` committed non-route taps (read the constant — do not hardcode the literal). Assert `coach.completed(false)` fires, `coach.confirm_shown == false`, `injected_save_data.tutorial_seen == true`. |
| AC12 | Re-arm (EC10): call `start_level(1)` while `COACHING` with `seen == false`; assert the old overlay is freed (`is_instance_valid(old_coach) == false`) and a fresh `COACHING` overlay has `coach.state == COACHING`, a (re)picked `target_card_id`, `coach.confirm_shown == false`, and `coach._state_obj.n_nonroute == 0`. |
| AC13 | With `tutorial_seen == true`, `start_level(1)` creates **no** `CoachOverlay` in the scene tree (assert `main.find_child("CoachOverlay", true, false) == null`). |
| AC14 | Save-fail (EC12): with a `SaveService` stub that always fails to write, after completion the in-session `should_show(false, 1)` call returns `false` (in-memory `tutorial_seen` flag suppresses re-show). Separately assert `injected_save_data.tutorial_seen` on disk remains `false` (write failure did not corrupt the in-memory data object — the disk state is separate from the session guard). |

**Visual — ADVISORY** (screenshot + lead sign-off, `production/qa/evidence/`):

| AC | Pass condition |
|----|----------------|
| AC15 | With `reduced_motion == true`, two captures ≥1 s apart show no pixel delta in the highlight region (no pulse/bob). |
| AC16 | Under a deuteranopia simulation, the ring + arrow are distinguishable from the card/background (shape-based, not colour). |
| AC17 | Banner text does **not** clip or overflow `BANNER_W` at base **and** maximum supported OS font scale (wraps or shrinks instead). |
