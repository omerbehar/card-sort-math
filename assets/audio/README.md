# Audio Assets

## Kenney — Interface Sounds (CC0)

`kenney_interface_sounds/` — Kenney's *Interface Sounds* pack (v1.0), 100 UI/SFX
`.wav` files. **License: CC0 1.0** (public domain) — see
`LICENSE_kenney_interface_sounds.txt`. Crediting Kenney (www.kenney.nl) is
appreciated but not required.

- Source: https://kenney.nl/assets/interface-sounds
- Packaged for Godot by: https://github.com/Calinou/kenney-interface-sounds

These are **placeholder/shippable SFX** for Sprint 1 audio (S1-004). The bespoke
audio pass can swap individual cues later without touching the mapping.

## Music — `music/calm_ambience.ogg` (CC0)

A gentle ambient bed used as the looping background track. **License: CC0 1.0**
(see `music/LICENSE_calm_ambience.txt`). Source: Kenney *Starter Kit: City
Builder* (`sounds/ambience.ogg`) — https://github.com/KenneyNL/Starter-Kit-City-Builder.
Placeholder; a dedicated calm music loop can replace it by editing
`AudioCues.MUSIC_PATH`.

## Implementation

- Cue selection: `data/audio_cues.gd` (`AudioCues`) — pure, unit-tested mapping.
- Playback: `autoloads/audio_service.gd` (`AudioService`) — plays event SFX and
  the music bed, gated by `SettingsService` (`sound` / `music`). The view
  (`scenes/main/main.gd`) calls `AudioService.play_event(event)` during replay.

## Suggested cue → game-event mapping (for `AudioService`, S1-004)

The `AudioService` should map each `GameEvent.Kind` (see `core/game_event.gd`) to
a cue, and respect the `sound` / `music` flags in `Settings`.

| Event / action | Suggested cue | Feel |
|----------------|---------------|------|
| Card tap (input) | `select_001.wav` / `click_001.wav` | light, immediate |
| `ROUTE` (card → matching stack) | `confirmation_001.wav` / `pluck_001.wav` | satisfying placement |
| `DISCARD` (no match → discard) | `drop_003.wav` / `minimize_006.wav` | soft "set aside" |
| `STACK_CLEARED` (stack clears) | `maximize_006.wav` / `confirmation_003.wav` | rewarding pop |
| `PULL` (cascade pull-back) | `pluck_002.wav` | quick combo tick |
| `WIN` (floor cleared) | `confirmation_004.wav` (or a music sting) | bright, conclusive |
| `LOSE` (discard overflow) | `error_004.wav` | gentle fail, not harsh |
| UI button / back | `click_002.wav` / `back_001.wav` | neutral UI |

> No music bed is included here — the calm background track is a separate asset
> to source (a single looping CC0/licensed track), tracked under S1-004.
