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

**Lifecycle (three states):**

| State | Entered when | Behaviour |
|-------|-------------|-----------|
| `ARMED` | A level starts and `should_show` is true | Decide the highlight target; spawn the `CoachOverlay`. |
| `COACHING` | Overlay shown | Hint visible, non-blocking; waiting for the first committed tap. |
| `DONE` | First committed tap (or already-seen) | Flag persisted; overlay faded out; never re-armed this session. |

**Rules:**

1. **Trigger.** The coach arms **only** on level `TUTORIAL_LEVEL` (= 1) and
   **only** when `save.tutorial_seen == false`. Any other level, or a returning
   player, skips straight to `DONE` (no overlay created).
2. **Target selection.** After the board spawns and exposure is computed, pick
   one **productive** card to highlight — an exposed card whose result matches an
   open stack target (see §4). If several qualify, pick deterministically (lowest
   `card_id`). If none qualify, fall back to the first exposed card with neutral
   copy.
3. **Render.** The overlay draws a **shape-based** highlight on the target card
   (outline ring + a downward arrow — never colour alone) and a one-line message
   banner:
   - Productive target: *"Add it up, then tap the card to sort it."*
   - Fallback (no productive tap available): *"Tap a card to sort it onto a
     stack."*
4. **Non-blocking.** The overlay never intercepts touches
   (`MOUSE_FILTER_IGNORE`); the player can tap **any** exposed card. Input is
   never gated. Ignoring the hint and just playing *is* the skip path — there's
   no modal to dismiss.
5. **Completion.** The **first committed tap** (the first `_on_card_tapped` the
   model accepts, i.e. returns a non-empty event list) ends the tutorial:
   - If those events include a **ROUTE**, show a brief confirm toast (*"Nice —
     matched the stack!"*) for `CONFIRM_DWELL`.
   - If the tap only **discarded** (no route), skip the confirm — don't celebrate
     a non-match.
   - Set `save.tutorial_seen = true` and persist immediately.
   - Fade out the overlay; transition to `DONE`.
6. **One nudge only.** If the player taps a *different* card than highlighted,
   the tutorial still completes on that tap — the coach does not re-point or
   chase.
7. **Accessibility.** `reduced_motion` → highlight is static (no pulse/bob),
   confirm toast appears without motion. `colorblind` → unaffected, because the
   highlight is shape-based, not colour-based.
8. **Abandon.** If the player closes the app before any committed tap,
   `tutorial_seen` stays false and the coach shows again next launch (they never
   engaged it).

## 4. Formulas

**Variables**

| Symbol | Meaning | Range |
|--------|---------|-------|
| `TUTORIAL_LEVEL` | Level index that triggers the coach | `1` (fixed) |
| `seen` | `save.tutorial_seen` | bool |
| `E` | Exposed (tappable) card ids this turn | subset of card ids |
| `R(c)` | Result of card `c` (`CardData.result`) | int |
| `Topen` | Open stack targets (`stack_target(i) ≥ 0`) | multiset of ints |

**Should-show predicate**
```
should_show(seen, level) = (not seen) AND (level == TUTORIAL_LEVEL)
```

**Highlight-target selection** (pure; operates on plain data, not nodes)
```
productive = { c ∈ E : R(c) ∈ Topen }
pick_target = min(productive)        if productive ≠ ∅
            = min(E)                 else if E ≠ ∅   (fallback, neutral copy)
            = -1                     else            (no highlight; copy only)
```
`min` over `card_id` makes the choice deterministic (testable).

**Confirmation rule**
```
show_confirm = first_committed_events contains a ROUTE event
```

**Timing constants** (defaults; tunable — see §7)

| Constant | Default | Unit |
|----------|---------|------|
| `MESSAGE_FADE_IN` | 0.25 | s |
| `CONFIRM_DWELL` | 1.2 | s |
| `FADE_OUT` | 0.30 | s |
| `HIGHLIGHT_PULSE_PERIOD` | 0.90 | s (ignored if `reduced_motion`) |

**Worked example**
> Fresh save, Level 1 → `should_show(false, 1) = true`.
> Exposed `E = {0, 2, 5}` with results `R = {0:7, 2:4, 5:7}`; open targets
> `Topen = {7, 9}`. `productive = {0, 5}` (both result 7 ∈ Topen) →
> `pick_target = min{0,5} = 0`. Highlight card 0, productive copy. Player taps
> card 0 → model returns `[ROUTE(0 → stack@7)]` → committed, contains ROUTE →
> confirm toast 1.2 s → `tutorial_seen = true` → fade to `DONE`.

## 5. Edge Cases

| # | Situation | Explicit behaviour |
|---|-----------|--------------------|
| 1 | **No productive tap at start** (no exposed card's result matches an open target) | Highlight `min(E)` (first exposed card) with the **neutral** copy. Tutorial still completes on the first committed tap; if that tap discards, no confirm toast. |
| 2 | **No exposed cards at all** (`E = ∅`, defensive — shouldn't occur on a valid Level 1) | `pick_target = -1`: show the message banner only, no highlight. Completes on first committed tap. |
| 3 | **Player taps a non-highlighted card** | Allowed (free play). Tutorial completes on that tap; coach does **not** re-point. Confirm shown iff it routed. |
| 4 | **First tap is a discard (no match)** | Completion fires and the flag is set, but **no** confirm toast (don't celebrate a non-match). |
| 5 | **Player opens the pause menu during coaching** | Pause menu (S1-011) overlays and pauses the tree; the coach overlay sits underneath untouched. On resume it's still shown, still waiting. Pausing changes no flag. |
| 6 | **Returning player** (`tutorial_seen == true`) | `should_show = false`: overlay is never created; zero runtime cost. |
| 7 | **`reduced_motion` on** | Highlight is static (no pulse/bob); confirm toast fades only. Fully functional. |
| 8 | **Level 1 restarts before first tap** (Home button, or lose→retry while still unseen) | `start_level(1)` re-evaluates `should_show`; since `seen` is still false, the coach **re-arms** on the fresh board with a freshly-picked target. Consistent. |
| 9 | **Highlighted card "disappears" before the tap** | Cannot happen: nothing on the board moves until the player taps, and the first tap completes the tutorial. No stale-highlight path exists. |
| 10 | **Save write fails on completion** | The in-memory `tutorial_seen` still suppresses the coach for the rest of the session; a failed disk write only risks re-showing next launch. Non-fatal, consistent with SaveService's "bad save never crashes" stance. |

## 6. Dependencies

**This system depends on:**

| System | Why | Change required |
|--------|-----|-----------------|
| `SaveData` / `SaveService` (`core/save_data.gd`) | Persist `tutorial_seen` | **Add** `tutorial_seen: bool` (default `false`) to `to_dict`/`from_dict`, missing-key-defaulted (no schema bump — same pattern as `colorblind`). |
| `BoardModel` (`core/board_model.gd`, read-only) | Source of exposed card ids, card results, open stack targets | None — the pure selector consumes plain data extracted from the model. |
| `GameEvent` (`core/game_event.gd`) | `ROUTE` kind is the confirm trigger | None. |
| `main.gd` (view controller) | Arms the coach on `start_level`; completes it on the first committed tap in `_on_card_tapped` | Wire-up only. |
| `Settings` (`data/settings.gd`) | `reduced_motion` gates highlight animation | None — no new setting (`colorblind` irrelevant, highlight is shape-based). |
| `FloorArea` / `Card` (`scenes/`) | Resolve the highlighted card's global position to anchor the marker | None. |

**New components introduced:**

- `TutorialLogic` (pure, node-free — `core/`): `should_show`, `pick_target`,
  `is_route(events)`. Unit-tested.
- `CoachOverlay` (view — `scenes/ui/coach_overlay.gd`): renders highlight ring +
  arrow + message + confirm toast; owns no game state.

**Reverse references to update when implementing (bidirectional):**

- `design/systems-index.md` — add a **First-Time Tutorial** node (depends on
  Save, BoardModel, Settings).
- `core/save_data.gd` doc comment — list `tutorial_seen` among persisted fields.
- Follows ADR-0001 (model/view) and ADR-0002 (event replay); **no new ADR**
  required (small feature reusing existing seams) — noted here per the
  coding-standards "every system → ADR" guideline as a deliberate exception.

## 7. Tuning Knobs
_TBD_

## 8. Acceptance Criteria
_TBD_
