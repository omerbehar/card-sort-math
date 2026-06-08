# S1-011 — Settings UI: Visual Evidence

- **Story**: S1-011 (Settings UI screen wired to S1-003 model)
- **Date**: 2026-06-08
- **Evidence**: `s1-011-settings-panel.png`
- **Gate level**: Advisory (UI story — coding-standards.md)

## How it was produced

Real Godot render (not a mockup) via the dev harness `tools/screenshot_settings.gd`:

```sh
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --rendering-method gl_compatibility -s res://tools/screenshot_settings.gd
```

The harness boots `scenes/main/main.tscn`, opens the panel via the HUD gear
path, and flips **Music** off and **Reduced Motion** on so the capture shows
both dot states. Headless can't render (dummy renderer), so this uses the
OpenGL3 compatibility backend under a virtual framebuffer (Mesa llvmpipe).

## What it shows

- Dimmed, input-blocking backdrop over the board (tap-outside dismisses).
- "Settings" title + round close (X) button.
- One toggle row per `Settings` key — Sound / Music / Haptics / Reduced Motion —
  each a full-width touch target with a dot indicator: `dot_full` + green when
  on, `dot_empty` + grey when off.
- Captured state: Sound on, Music **off**, Haptics on, Reduced Motion **on**.

## Notes / follow-ups (non-blocking)

- Dot indicators read clearly as on/off but are a weak *control* affordance;
  consider a switch treatment or explicit ON/OFF label in a later polish pass.
- Panel bottom edge sits near the toolbar; fine at four rows, watch if more are
  added.

## Automated coverage

Binding logic is covered by `tests/test_settings_panel.gd` (5 interaction
tests): row reflects setting, tap mutates+persists, tap refreshes dot, external
change refreshes, dismiss emits `closed`.
