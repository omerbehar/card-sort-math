# ADR-0006: Shared modal pop-up chassis (`PopupBase`)

## Status

Accepted

## Date

2026-06-10

## Last Verified

2026-06-10

## Decision Makers

Product owner (omer.behar), lead-programmer, ui-programmer

## Summary

The game will have **many modal pop-ups** (pause, win/lose result, settings,
confirm dialogs, level-select, store, daily reward, "all levels complete", etc.).
Today each pop-up (`PauseMenu`, `ResultScreen`) is an independent `Control` that
re-implements the same modal *chassis* from scratch: a full-screen backdrop, input
capture (`MOUSE_FILTER_STOP`), a show/dismiss lifecycle, and (ad-hoc) open/close
behaviour. Only the low-level `UiFactory` primitives (`label`, `nine_patch`,
`sprite`) are shared. This duplicates the load-bearing modal behaviour and lets the
pop-ups drift apart in lifecycle and feel.

**Decision:** introduce `PopupBase` (`scenes/ui/popup_base.gd`, `class_name
PopupBase extends Control`) that owns the common chassis. Each pop-up extends it
and supplies only its *content*. `PauseMenu` and `ResultScreen` are retrofitted
onto it; new pop-ups extend it.

## Context

- `PauseMenu` builds its own `_build_backdrop()`, pauses the tree, and is freed by
  `main.gd`. `ResultScreen` builds its own `Dim` in `_ready`, blocks input, and is
  freed by `main.gd`. Both hand-roll a panel + header + close-X.
- A **visual-language split** is already emerging: `PauseMenu` uses the Kenney
  nine-patch skin; `ResultScreen` uses flat `StyleBoxFlat` to match the bright
  reference mocks. (See Open Questions — this is an art-direction decision, NOT
  resolved by this ADR.)
- The model/view split (ADR-0001) is unaffected: pop-ups are pure view; they emit
  intent signals and own no game state.

## Decision

`PopupBase` owns **behaviour, not skin**:

1. **Backdrop + input capture** — a full-rect `Backdrop` `ColorRect`
   (`MOUSE_FILTER_STOP`) so taps never reach the board beneath; the root is also
   `MOUSE_FILTER_STOP`. `backdrop_color` is configurable.
2. **Content anchor** — a full-rect `Body` `Control`; subclasses build their panel
   and widgets into `body()` (positioned absolutely or centred, in their own skin).
3. **Lifecycle** — `play_open()` (pop-in) and `close()` (pop-out → free →
   `closed` signal). Both animations are **reduced-motion-gated** via the canonical
   `JuiceService.is_motion_enabled()` seam. `close()` is idempotent.
4. **Always-responsive** — `process_mode = PROCESS_MODE_ALWAYS` so pop-ups animate
   and accept input even when a pop-up pauses the tree.
5. **Optional tree-pause** — `pauses_tree` flag; `close()` unpauses if it was set.

Subclasses keep their own **domain signals** (`resumed`/`home_pressed`,
`retry_pressed`/`next_pressed`/`home_pressed`) and their own visual skin. They do
NOT re-implement the backdrop, input capture, or lifecycle.

## Engine Compatibility

| Field | Value |
|-------|-------|
| Engine | Godot 4.6 |
| Domain | UI |
| APIs used | `Control`, `ColorRect`, `CanvasLayer` host, `Tween` (node-scoped), `process_mode` |
| Post-cutoff risk | None — all stable Godot 4 UI APIs |

## Consequences

**Positive**
- New pop-ups supply only content; the modal behaviour is written once and tested
  once (`tests/test_popup_base.gd`).
- Consistent lifecycle/feel; the one-frame teardown seam and input-capture rules
  are solved in one place.
- A single seam to later add shared concerns (focus trapping, back-button handling,
  open/close SFX through the audio event system, gamepad nav).

**Negative / costs**
- Retrofitting `PauseMenu` (merged + tested) carries regression risk; mitigated by
  keeping its public surface (`setup`, `_round_bg`, `_switch_track`, signals) intact
  and re-running its tests.
- Does not resolve the visual-language split (see Open Questions).

## Alternatives considered

- **Composition over inheritance** (a `Modal` component node the pop-up adds as a
  child) — more flexible but more wiring per pop-up; inheritance is simpler for a
  uniform "full-screen modal" and matches the existing single-Control pop-ups.
- **Leave as-is** — rejected; duplication compounds with every new pop-up.

## Open Questions

- **Pop-up visual language** (Kenney nine-patch vs the bright flat mock style) is an
  art-direction decision for the creative-director/art-director. `PopupBase` is
  skin-agnostic so it does not pre-empt that choice; once decided, the panel/button
  styling should be standardised (likely a `UiFactory` extension or a theme).
- Open/close **SFX** should route through the audio event system when added.

## Requirements satisfied

- Coding standard "every system → ADR": this records the pop-up chassis decision.
- ui-code rules: input capture, motion-preference gating handled centrally.
