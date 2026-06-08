# S1-011 — Pause Menu + Colorblind Mode: Visual Evidence

- **Story**: S1-011 (settings UI) — reworked into a pause menu per design reference
- **Date**: 2026-06-08
- **Evidence**: `s1-011-pause-menu.png`
- **Gate level**: Advisory (UI story — coding-standards.md)

## How it was produced

Real Godot render (not a mockup) via the dev harness
`tools/screenshot_pause_menu.gd`:

```sh
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --rendering-method gl_compatibility -s res://tools/screenshot_pause_menu.gd
```

Headless can't render (dummy renderer), so this uses the OpenGL3 compatibility
backend under a virtual framebuffer (Mesa llvmpipe). The harness boots
`scenes/main/main.tscn`, sets explicit settings for a deterministic capture, and
opens the pause menu. **Note:** it writes to the real `user://` save.

## What it shows

Matches the design reference (pause-menu mock):

- **Header strip** "PAUSE" with a red close (X) button.
- **Three round audio toggles** — SFX / BGM / VIB — green when on, grey + dimmed
  when off. Captured: SFX on, **BGM muted**, VIB on.
- **Two pill-switch rows** — Colorblind Mode (**ON**) and Reduced Motion (off) —
  code-drawn track + sliding knob.
- **Home (red) + Continue (green)** actions.
- **Colorblind palette applied live**: the stacks behind the menu are recoloured
  from the default red/yellow/green/blue to the Okabe-Ito colour-blind-safe
  palette (blue / orange / bluish-green / vermillion). See `data/stack_palette.gd`.

## Behaviour wired in `main.gd`

- HUD gear opens the menu and **pauses the SceneTree**; the menu runs with
  `PROCESS_MODE_ALWAYS` so its controls stay live.
- Continue / X / backdrop tap resume (unpause). Home restarts the current level
  (placeholder until a main-menu/world-map screen exists — M3).
- Toggling Colorblind Mode recolours the live board via
  `SettingsService.changed`.

## Approximations (Kenney-only art)

- No cat mascot (bespoke art) — omitted.
- Pill switch, round toggles, and Home/Continue buttons are code-drawn from
  neutral Kenney slots/buttons + tints, not bespoke assets.
- Audio toggles use short text glyphs (SFX/BGM/VIB) since the Kenney set has no
  speaker/note/vibrate icons. Swap for icons in a later art pass.

## Automated coverage

- `tests/test_pause_menu.gd` (7 interaction tests): round toggle + pill switch
  both mutate+persist, controls reflect setting, knob slides on, external change
  refreshes, Continue/Home emit signals.
- `tests/test_stack_palette.gd` (4 tests): default vs colorblind mapping, tints
  mutually distinct, index wrap.
- `tests/test_settings.gd`: colorblind round-trip + missing-key default.
