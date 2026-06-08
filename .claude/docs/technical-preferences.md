# Technical Preferences

<!-- Project-specific standards and conventions for CardSortMath. -->
<!-- All agents reference this file. Update as architectural decisions are made. -->

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript (statically typed)
- **Rendering**: Mobile rendering method
- **Physics**: Jolt Physics (3D) — not used by core gameplay (2D/UI puzzle)

## Input & Platform

- **Target Platforms**: Mobile (Android first, iOS fast-follow)
- **Input Methods**: Touch (mouse emulates touch in editor)
- **Primary Input**: Touch
- **Gamepad Support**: None
- **Touch Support**: Full
- **Platform Notes**: Portrait orientation, 390×844 base viewport, `canvas_items`
  stretch with `expand` aspect. Design for one-handed play and small-screen
  numeral legibility.

## Naming Conventions

- **Classes**: `PascalCase` via `class_name` (e.g. `BoardModel`, `CardData`)
- **Variables / functions**: `snake_case`; private members prefixed `_`
- **Signals/Events**: `snake_case`, past-tense where they report facts
- **Files**: `snake_case.gd` / `snake_case.tscn`
- **Scenes**: `snake_case.tscn` colocated with their script
- **Constants / enums**: `CONSTANT_CASE`

## Performance Budgets

- **Target Framerate**: 60 FPS on mid-range mobile (graceful on low-end)
- **Frame Budget**: ~16 ms; no per-frame allocations in `_process`/`_physics_process`
- **Draw Calls**: keep UI batched; minimize unique materials
- **Memory Ceiling**: lean — target low-end Android devices

## Testing

- **Framework**: gdUnit4 (v6.1.3, vendored in `addons/gdUnit4/`)
- **Minimum Coverage**: all pure logic in `core/` and `data/` must be unit-tested
- **Required Tests**: board rules, exposure graph, level solvability, future
  level generator + economy math + save migrations
- **CI**: `.github/workflows/tests.yml` runs the suite headless on push/PR to `main`

## Architecture Notes (load-bearing)

- **Model/View split is mandatory.** `core/` is pure, deterministic, node-free
  and emits `GameEvent`s; the view layer (`scenes/`) replays them. Keep all new
  systems behind this seam.
- **Solvability invariant** (`LevelData.is_solvable`): every result's card count
  equals `3 × occurrences in the target queue`. All generated content must pass it.

## Forbidden Patterns

- No Godot 3.x APIs; use `await`, not `yield`.
- No hardcoded gameplay/tuning values in `core/` — drive from `data/` resources/config.
- No game state owned or mutated by UI scripts — UI requests changes via signals.
- No booster/power-up that auto-solves the arithmetic (guts the core value prop).

## Allowed Libraries / Addons

- gdUnit4 (testing). Add others here as approved.

## Architecture Decisions Log

- [No ADRs yet — use `/architecture-decision` to create one in `docs/architecture/`]

## Engine Specialists

- **Primary**: `godot-specialist`
- **Language/Code Specialist**: `godot-gdscript-specialist`
- **Shader Specialist**: `godot-shader-specialist`
- **UI Specialist**: `ui-programmer` (+ `godot-gdscript-specialist` for code)
- **Native/Plugin Specialist**: `godot-gdextension-specialist` (for ad/IAP SDKs)
- **Routing Notes**: GDScript-only project — never route to the C# specialist.

### File Extension Routing

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| `.gd` game code | `godot-gdscript-specialist` |
| `.gdshader` / material | `godot-shader-specialist` |
| `.tscn` UI screens (`scenes/ui/`) | `ui-programmer` |
| `.tscn` scenes / levels | `godot-specialist` |
| Native extension / plugin | `godot-gdextension-specialist` |
| General architecture review | `godot-specialist` |
