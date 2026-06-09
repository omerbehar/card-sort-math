# Save & Settings

> **Status**: In Design
> **Author**: reverse-documented from `core/save_data.gd`, `autoloads/save_service.gd`, `data/settings.gd`, `autoloads/settings_service.gd`
> **Last Updated**: 2026-06-09
> **Implements Pillar**: Foundation — enables all player-facing systems by making state trustworthy across sessions

## Overview

`SaveData` (pure, node-free `RefCounted` in `core/`) is the single source of truth for
everything persisted between sessions: the current level index, the player's declared
audience band (`AgeBand`: UNKNOWN / ADULT / CHILD), and the boolean settings bundle
(`Settings`). `SaveService` (an autoload `Node` in `autoloads/`) is the thin I/O wrapper:
it loads `SaveData` from `user://save.json` on boot, writes it on demand, and falls back to
safe defaults when the file is missing or corrupt. `SettingsService` (also an autoload) is
the UI-facing adapter that reads and mutates individual settings keys, persisting on every
change. All schema evolution flows through a versioned `_migrate()` step in
`SaveData.from_dict`, so any save file from any prior release can be upgraded without loss.
`SaveData`'s placement in `core/` respects ADR-0001 (pure, node-free, fully unit-testable
without the scene tree); the `age_band` field is a first-class citizen per ADR-0005
(audience compliance seam — nothing personal is collected before it resolves to ADULT or
CHILD).

## Player Fantasy

*"My progress is mine."* The player never thinks about saving — they just close the app on
the bus and reopen it at home, and everything is exactly where they left it: the same level,
the same settings, the same accessibility preferences. The save system is invisible precisely
when it is working. Its player-facing promise is continuity without friction: no "are you
sure you want to quit?" warnings, no save-slot management, no re-entering preferences on
reinstall (to the degree the platform allows). A player who set colorblind mode on day one
never has to set it again. A player mid-level who gets a phone call resumes at the same
position. The system is successful when the player never notices it.

## Detailed Design

### Core Rules

1. **Single save file.** The entire player state lives in one file: `user://save.json`
   (configurable via `SaveService.configure(path)`). No save slots, no cloud sync at M1,
   no per-level snapshots.

2. **Two-layer architecture.** `SaveData` (pure `RefCounted`, `core/`) owns serialization,
   validation, and migration. `SaveService` (autoload `Node`, `autoloads/`) owns file I/O.
   Neither layer does the other's job (ADR-0001).

3. **Autoload owns the live instance.** At runtime, `SaveService.data` is the canonical
   `SaveData` instance. All reads (`GameManager`, `SettingsService`, `CoachOverlay`, etc.)
   go through `SaveService.data`. No consumer creates its own `SaveData`.

4. **Load on boot, write on demand.** `SaveService._ready()` calls `load_game()`
   automatically. Writes are explicit — callers invoke `save_game()`,
   `set_current_level()`, or `set_age_band()`. No auto-save on tick.

5. **A bad save never crashes.** If the file is missing, unreadable, or contains invalid
   JSON, `load_game()` silently replaces `data` with `SaveData.defaults()` and emits
   `loaded`. The prior file is not clobbered on a load failure.

6. **Schema versioning.** `SaveData.CURRENT_SCHEMA_VERSION` (currently `1`) is incremented
   whenever the persisted shape changes in a breaking way. `_migrate(dict, from_version)`
   upgrades a raw dict step-by-step. **New optional bool fields may be added without a
   version bump** using missing-key defaults (`dict.get("field", false)`) when the absent
   value is semantically correct; all other additions require a bump and a migration step.

7. **Settings is embedded, not separate.** `SaveData.settings` is a `Settings` instance
   serialized as a nested dictionary under `"settings"`. Not a separate file. All
   `Settings.from_dict()` keys use missing-key defaults — unknown keys are ignored.

8. **SettingsService is the UI seam.** UI never reads `SaveService.data.settings` directly
   — it uses `SettingsService.get_value(key)` / `set_value(key, value)` / `toggle(key)`.
   Every `set_value` call persists immediately via `_save.save_game()` and emits
   `SettingsService.changed(key, value)`.

9. **`age_band` is the compliance gate (ADR-0005).** Set via `SaveService.set_age_band()`
   before any personal data collection. Defaults to `AgeBand.UNKNOWN`. Systems reading
   `age_band` for ad / analytics decisions must treat `UNKNOWN` as `CHILD` (restrictive
   fallback).

10. **Injectable path for tests.** `SaveService.configure(path: String)` overrides the
    save path. Call before `load_game()`. Integration tests use a temp file under `user://`
    and clean up after themselves.

---

### SaveData Schema (v1)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `schema_version` | `int` | `CURRENT_SCHEMA_VERSION` | Written; read to drive migration |
| `current_level` | `int` | `1` | 1-indexed level; clamped ≥ 1 on load |
| `age_band` | `AgeBand` enum (`int`) | `UNKNOWN` | Compliance signal — see ADR-0005 |
| `settings` | nested dict | all defaults | Sound, music, haptics, reduced_motion, colorblind |

**Settings sub-schema (embedded in `SaveData`)**

| Key | Type | Default | Controls |
|-----|------|---------|---------|
| `sound` | `bool` | `true` | SFX on/off |
| `music` | `bool` | `true` | Music bed on/off |
| `haptics` | `bool` | `true` | Vibration on/off |
| `reduced_motion` | `bool` | `false` | Suppresses pulse/animation in overlays and coach |
| `colorblind` | `bool` | `false` | Activates Okabe-Ito stack palette |

---

### States and Transitions (SaveService lifecycle)

| State | Entered when | Behaviour |
|-------|-------------|-----------|
| `UNLOADED` | Script instantiated | `data` = fresh `SaveData.defaults()`; no file access yet |
| `LOADING` | `load_game()` called | File opened; JSON parsed; `_migrate` run; `data` set |
| `READY` | After `load_game()` completes (any outcome) | `loaded` emitted; `data` is live; writes accepted |
| `WRITING` | `save_game()` called | File opened for write; `data.to_dict()` serialized |
| `READY` | After `save_game()` completes | `saved` emitted on success; no-op on file-open failure (error logged, prior save left intact) |

There is no explicit error state — failures degrade gracefully (defaults on load, no-op on write failure).

---

### Interactions with Other Systems

| System | Direction | What flows |
|--------|-----------|-----------|
| `GameManager` (autoload) | Reads `SaveService.data.current_level` | Determines which level to start |
| `SettingsService` (autoload) | Reads/writes `SaveService.data.settings` | All settings access; persists on change |
| `CoachOverlay` / `TutorialLogic` | Reads/writes `save.tutorial_seen` (injected via `configure()`) | First-time tutorial seen flag |
| ADR-0005 age gate (future) | Writes `age_band` via `SaveService.set_age_band()` | Compliance routing |
| Future `AdService` / `Analytics` | Reads `age_band` | Ad/analytics mode gating |
| `gdUnit4` tests | Injects temp path via `configure()` | Isolated I/O testing without touching real save |

## Formulas

### Schema migration gate

```
should_migrate(from_version, to_version) =
    from_version < to_version

upgrade path: v0 → v1 → v2 → ... → CURRENT_SCHEMA_VERSION
(one `if version == N:` block per step in _migrate; each step sets version = N+1)
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `from_version` | `int` | 0..CURRENT | Version found in the saved dict; 0 = pre-versioned save |
| `CURRENT_SCHEMA_VERSION` | `int` | 1 (today) | Constant in `SaveData`; bump for breaking changes |

**When to bump vs. when to use a missing-key default:**

```
requires_bump(change) =
    NOT (new field whose absent value is semantically correct AND field type is bool)

missing_key_default_safe: type is bool AND absent → safe default AND old saves correct without it
```

Example: `tutorial_seen: bool` absent → `false` (correct; old saves haven't seen the tutorial) → **no bump**.
Example: new non-optional field (e.g., `high_score: int`) absent → `0` may be wrong or require explicit migration → **bump + migrate step**.

---

### Current level clamping

```
stored_level = maxi(1, int(raw_value))
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `raw_value` | `Variant` | any (JSON float/int/null) | Parsed value from the save dict |
| `stored_level` | `int` | ≥ 1 | Written to `SaveData.current_level` |

JSON parses integers as floats; `int()` coercion handles this. `maxi(1, …)` prevents corruption from a zero or negative.

---

### AgeBand coercion

```
parse_age_band(value) =
    ADULT    if int(value) == AgeBand.ADULT   (= 1)
    CHILD    if int(value) == AgeBand.CHILD   (= 2)
    UNKNOWN  otherwise  (0, null, missing, or out-of-range)
```

| Input | Output | Rationale |
|-------|--------|-----------|
| `1` | `AgeBand.ADULT` | Declared adult; full experience |
| `2` | `AgeBand.CHILD` | Declared under-13; restricted mode |
| `0`, null, missing, 99 | `AgeBand.UNKNOWN` | Restrictive fallback — treated as `CHILD` by all downstream consumers |

## Edge Cases

| # | Situation | Explicit behaviour |
|---|-----------|--------------------|
| 1 | **File missing** (first install, cleared app data) | `load_game()` falls back to `SaveData.defaults()`; `loaded` emitted. Clean state, no error. |
| 2 | **File unreadable** (bad permissions, partial write from a crash) | `FileAccess.open()` returns null; warning logged; `data = defaults()`; `loaded` emitted. Broken file left on disk. |
| 3 | **Corrupt JSON** | `JSON.parse_string()` returns non-Dictionary; warning logged; `data = defaults()`; `loaded` emitted. |
| 4 | **Save write fails** (disk full, read-only filesystem) | `FileAccess.open(WRITE)` returns null; error logged; method returns early. In-memory `data` valid for the session; prior save file left intact. |
| 5 | **Missing field in save dict** | Each `from_dict` field uses `.get(key, default)` — missing keys silently use safe defaults. No crash, no data loss. |
| 6 | **`current_level ≤ 0`** (corrupt or edited save) | Clamped to `1` via `maxi(1, int(value))`. |
| 7 | **`age_band` out of range** (e.g., `99` or `null`) | `_parse_age_band` returns `AgeBand.UNKNOWN`. All downstream consumers must treat `UNKNOWN` as `CHILD` (restrictive fallback). |
| 8 | **Unknown settings key** | `Settings.from_dict()` ignores unknown keys silently. `set_value()` on an unknown key warns and returns `false`. |
| 9 | **Save from a future schema version** (downgrade) | `_migrate` runs no steps (no matching `if version == N:` block); `from_dict` validates/clamps each known field. Unknown keys ignored; dropped on next write. No crash. |
| 10 | **Rapid successive saves** | Each `save_game()` opens and overwrites synchronously. No queue. File is small (< 1 KB); acceptable at M1. Add debounce if write frequency becomes a concern. |
| 11 | **`configure(path)` called after `_ready()`** | New path stored; current `data` was loaded from the old path. Next explicit `load_game()` uses the new path. Test isolation only — do not call at runtime after boot. |
| 12 | **New optional bool field added post-v1** (e.g., `tutorial_seen`) | `from_dict` uses `.get("field", false)`. Old saves default correctly. `to_dict` writes the field on the next save. No migration step needed when the absent value is semantically correct. |
| 13 | **`AgeBand.UNKNOWN` at runtime** | Age gate not yet shown or stored. All ad/analytics/IAP consumers must apply `CHILD`-equivalent restrictions. No personal data collection permitted. |

## Dependencies

**This system depends on:**

| System | Why | Notes |
|--------|-----|-------|
| `Settings` (`data/settings.gd`) | Embedded as a sub-object in `SaveData`; serializes/deserializes the settings bundle | `Settings` is pure data — no separate file, no autoload |
| Godot `FileAccess` | File I/O in `SaveService.load_game()` / `save_game()` | Engine API; `user://` path is platform-safe (Android, iOS, desktop) |
| Godot `JSON` | Serialize/deserialize save dict as JSON text | Engine API; all values must be JSON-compatible (bools, ints, strings) |

**Systems that depend on this:**

| System | Direction | Nature |
|--------|-----------|--------|
| `GameManager` (autoload) | Depends on this | Reads `SaveService.data.current_level` to determine start level |
| `SettingsService` (autoload) | Depends on this | Wraps `SaveService.data.settings`; calls `save_game()` on every change |
| First-Time Tutorial (`TutorialLogic`, `CoachOverlay`) | Depends on this | Reads/writes `save.tutorial_seen`; injected via `configure()` in tests |
| Age gate / compliance (future) | Depends on this | Writes `age_band` via `set_age_band()`; ADR-0005 |
| `AdService` / `Analytics` (future) | Depends on this | Reads `age_band` to gate ad/data collection mode |

**Reverse references to maintain (bidirectional):**
- `design/gdd/first-time-tutorial.md` §6 — lists `SaveData` / `SaveService` as a dependency ✓ (already present)
- `design/systems-index.md` — add a **Save & Settings** row (add with this GDD)
- `core/save_data.gd` doc comment — list all persisted fields including `tutorial_seen` when added
- ADR-0001 — `SaveData` in `core/` as a load-bearing example of the pure-model seam ✓ (already referenced)
- ADR-0005 — `age_band` in `SaveData` as the compliance signal ✓ (already referenced)

## Tuning Knobs

All values live in `SaveService` or `SaveData` and can be adjusted without changing
migration or serialization logic.

| Knob | Location | Default | Safe Range | Effect |
|------|----------|---------|------------|--------|
| `SaveService.DEFAULT_PATH` | `autoloads/save_service.gd` | `"user://save.json"` | Any writable `user://` path | Changes the save file location. Override at runtime via `configure(path)` for test isolation. Do not change the default in production. |
| `SaveData.CURRENT_SCHEMA_VERSION` | `core/save_data.gd` | `1` | Integers ≥ 1, monotonically increasing | The version written to every save file. Increment when the persisted shape changes in a breaking way. **Never decrement.** Each increment requires a corresponding `_migrate()` step. |
| `Settings` default values | `data/settings.gd` | `sound=true`, `music=true`, `haptics=true`, `reduced_motion=false`, `colorblind=false` | Booleans — no range | Controls the first-run experience for each toggle. Change these only if the desired fresh-install default changes. Existing saves are unaffected (they carry stored values). |
| `AgeBand.UNKNOWN` fallback policy | Convention (not a constant) | Treat as `CHILD` | — | All ad/analytics consumers must apply `CHILD`-equivalent restrictions when `age_band == UNKNOWN`. This is a policy, not a value — enforce it in each consumer. |

**What is NOT tunable here:**

- The number of save slots (fixed at 1 — no multi-slot at M1).
- Save frequency (explicit call-site writes only; no auto-save timer).
- Write debounce threshold (no debounce at M1; add one in `SaveService` if write
  frequency becomes a concern at a later milestone — see Edge Case #10).

## Acceptance Criteria

[To be designed]

## Open Questions

[To be designed]
