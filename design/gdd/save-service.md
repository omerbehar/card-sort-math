# Save & Settings

> **Status**: Revised after design review (2026-06-09) — NEEDS REVISION items addressed.
> **Author**: reverse-documented from `core/save_data.gd`, `autoloads/save_service.gd`, `data/settings.gd`, `autoloads/settings_service.gd`
> **Last Updated**: 2026-06-09
> **Implements Pillar**: Foundation — enables all player-facing systems by making state trustworthy across sessions

> **P0 review follow-ups — IMPLEMENTED 2026-06-09:**
> 1. **Atomic write** ✓ — `save_game()` writes `user://save.json.tmp` then
>    `DirAccess.rename()` over the real path (atomic on Android/iOS/desktop).
>    Tests: SV-14, SV-09/10/11.
> 2. **`load_failed` signal** ✓ — `load_game()` emits `load_failed` (not `loaded`)
>    when a file existed but was unreadable/corrupt, distinguishing lost data from a
>    genuine first launch (Edge Case 14). Tests: SV-07/08.
> 3. **`ComplianceService` chokepoint** ✓ — new autoload `autoloads/compliance_service.gd`
>    is the sole reader of `age_band` (Core Rule 9, ADR-0005); exposes
>    `can_collect_personal_data()` etc. Tests: `tests/test_compliance_service.gd` (AG-08).
>
> Also fixed: `SaveData._parse_age_band` is now null-safe (a JSON `null` age_band
> no longer crashes the load — `int(null)` raises in GDScript). Test: AG-06.
> **Still pending:** HMAC/signature on `age_band` (required pre-AdService), and
> wiring `colorblind`/`reduced_motion` to view consumers.

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
without the scene tree). The `age_band` field is **not an ordinary game-state value** — it
is a *regulated compliance artifact* per ADR-0005, with its own integrity, access-control,
and (future) retention requirements. It must be read only through the `ComplianceService`
chokepoint (Core Rule 9), never directly by feature code. Nothing personal is collected
before it resolves to ADULT or CHILD, and `UNKNOWN` is always treated as `CHILD`
(restrictive).

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

5. **A bad save never crashes — but it must not be silent.** If the file is missing,
   `load_game()` uses `SaveData.defaults()` and emits `loaded` (genuine first launch). If
   the file **exists but is unreadable or contains invalid JSON**, `load_game()` uses
   `defaults()` and emits **`load_failed`** (not `loaded`) so consumers and telemetry can
   distinguish lost data from a new player — a returning level-47 player must not be
   silently treated as a first-timer (see Edge Case 14). The prior file is not clobbered on
   a load failure. *(`load_failed` is a scheduled code follow-up; see header.)*

6. **Schema versioning.** `SaveData.CURRENT_SCHEMA_VERSION` (currently `1`) is incremented
   whenever the persisted shape changes in a breaking way. `_migrate(dict, from_version)`
   upgrades a raw dict step-by-step. **A new field may be added without a version bump**
   when *its absence is semantically indistinguishable from "this save never had it"* —
   i.e. the missing-key default (`dict.get("field", default)`) is the correct value for
   every pre-existing save. This is a property of the field's *meaning*, not its *type*
   (a `bool tutorial_seen` defaulting to `false` qualifies; an `int high_score` defaulting
   to `0` qualifies equally; but a `bool opted_in` that should default `true` for legacy
   users does **not**). All other changes — including changing an existing default,
   renaming, removing, or retyping a field — require a bump and a migration step.
   **Migration invariant:** `schema_version` is stamped to CURRENT *only after* the
   relevant `_migrate` steps run, and every step must be idempotent (see Formulas →
   migration gate; this guards the downgrade/re-run hazard in Edge Case 9).
   **Protected fields:** consent/compliance fields (e.g. a future `consent_granted`) must
   **never** use the missing-key-default path — their absence must never silently default
   to a permissive value (see Edge Case 9).

7. **Settings is embedded, not separate.** `SaveData.settings` is a `Settings` instance
   serialized as a nested dictionary under `"settings"`. Not a separate file. All
   `Settings.from_dict()` keys use missing-key defaults — unknown keys are ignored.

8. **SettingsService is the UI seam.** UI never reads `SaveService.data.settings` directly
   — it uses `SettingsService.get_value(key)` / `set_value(key, value)` / `toggle(key)`.
   Every `set_value` call persists immediately via `_save.save_game()` and emits
   `SettingsService.changed(key, value)`.

9. **`age_band` is read only through `ComplianceService` (ADR-0005).** Set via
   `SaveService.set_age_band()` before any personal data collection; defaults to
   `AgeBand.UNKNOWN`. The "treat `UNKNOWN` as `CHILD`" rule is **enforced at a single
   chokepoint**, not left to each consumer: `ComplianceService` (per ADR-0005 Key
   Interfaces) exposes `can_collect_personal_data()` / `can_show_targeted_ads()` etc., and
   it is the *only* code permitted to read `SaveService.data.age_band` (besides
   `SaveService` itself). Future `AdService` / `Analytics` must call `ComplianceService`,
   never `age_band` directly — this makes the `== CHILD`-instead-of-`!= ADULT` mistake
   structurally impossible. The integer ordinals `UNKNOWN=0 / ADULT=1 / CHILD=2` are a
   stable persisted contract, not free-to-reorder enum values (see Formulas → AgeBand
   coercion). *(`ComplianceService` is a scheduled prerequisite for the first ad/analytics
   system; see header.)*

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
| `reduced_motion` | `bool` | `false` | *Intended:* suppresses pulse/animation in overlays and coach. **Persistence-only at M1 — not yet wired to any view consumer.** |
| `colorblind` | `bool` | `false` | *Intended:* activates Okabe-Ito stack palette. **Persistence-only at M1 — not yet wired to any view consumer.** |

> **Note (M1 reality):** `reduced_motion` and `colorblind` are persisted and toggleable but
> have **no visual effect yet** — no node consumes `SettingsService.changed` for them. The
> Player Fantasy promise ("set colorblind once, never again") describes the persistence
> guarantee, not a current visual outcome. Wiring these is tracked as a separate story.

---

### States and Transitions (SaveService lifecycle)

| State | Entered when | Behaviour |
|-------|-------------|-----------|
| `UNLOADED` | Script instantiated (`.new()`, or autoload before `_ready`) | `data` = fresh `SaveData.defaults()`; no file access yet. A bare `.new()` instance never auto-loads — `_ready()` (which calls `load_game()`) fires only on scene-tree entry. |
| `LOADING` | `load_game()` called | File opened; JSON parsed; `_migrate` run; `data` set. Re-entrant: calling `load_game()` again from READY is valid and re-enters LOADING (no guard; callers must not interleave). |
| `READY` (loaded) | `load_game()` finds a valid file, or no file (first launch) | `loaded` emitted; `data` is live; writes accepted |
| `READY` (load_failed) | `load_game()` finds a file that is unreadable or invalid JSON | **`load_failed`** emitted (data is `defaults()` but real data was lost); `data` is live; writes accepted |
| `WRITING` | `save_game()` called | Writes `to_dict()` to `…/save.json.tmp`, then atomically renames over `save.json`. **Synchronous and not externally observable** — `save_game()` completes before returning; there is no concurrency, queue, or mutex (do not add one based on this row). |
| `READY` | After `save_game()` completes | `saved` emitted on success; no-op on open/rename failure (error logged, prior `save.json` left intact — see Edge Case 4) |

The only signalled failure is `load_failed`; write failures are silent no-ops (the prior
file is preserved by the temp+rename pattern). `WRITING` is notional (a call-stack frame,
not an observable concurrent state).

---

### Interactions with Other Systems

| System | Direction | What flows |
|--------|-----------|-----------|
| `GameManager` (autoload) | Reads `SaveService.data.current_level` | Determines which level to start. **Must clamp to the available level count on use** — `SaveService` stores the raw value (floored ≥1) but cannot know the upper bound without an improper dependency (see Formulas → current level clamping). |
| `SettingsService` (autoload) | Reads/writes `SaveService.data.settings` | All settings *mutation* goes through `set_value`/`toggle`. **Caveat:** `settings()` returns the **live** `Settings` instance, not a copy — a caller could mutate it directly and bypass persistence + the `changed` signal. Treat `settings()` as read-only by convention; do not mutate through it. |
| `CoachOverlay` / `TutorialLogic` | Reads/writes `save.tutorial_seen` *(planned field — not yet in the schema; see first-time-tutorial.md §6 and Edge Case 12)* | First-time tutorial seen flag |
| ADR-0005 age gate (future) | Writes `age_band` via `SaveService.set_age_band()` | Compliance routing |
| **`ComplianceService` (future, ADR-0005)** | **Sole reader** of `SaveService.data.age_band` | Centralises the UNKNOWN=CHILD rule; exposes `can_collect_personal_data()` etc. |
| Future `AdService` / `Analytics` | Reads compliance verdicts **via `ComplianceService`** (never `age_band` directly) | Ad/analytics mode gating |
| `gdUnit4` tests | Injects temp path via `configure()`; uses `.new()` + manual `load_game()` (never `add_child` before `configure`, or `_ready` reads the real save) | Isolated I/O testing without touching real save |

> **Typing note (ADR-0004):** `SettingsService._save` is currently declared untyped
> (`var _save = null`) to accept a duck-typed test double. This is a known ADR-0004
> exception; the clean fix is a shared base/interface type for the real `SaveService` and
> the test stub. Tracked as code hygiene, not a blocker.

## Formulas

### Schema migration gate

```
should_migrate(from_version, to_version) =
    from_version < to_version

upgrade path: v0 → v1 → v2 → ... → CURRENT_SCHEMA_VERSION
(one `if version == N:` block per step in _migrate; each step sets version = N+1)

INVARIANT: every step must be idempotent, AND schema_version is written to disk
only after the steps that produced the current shape have run.
```

> **Downgrade hazard (see Edge Case 9):** `from_dict` always sets the in-memory
> `schema_version = CURRENT`. If an *older* binary loads a *newer* save, it runs no steps
> but still stamps its own (lower) CURRENT on the next write. A later upgrade then sees a
> lower version and **re-runs** migration steps. This is harmless only while every step is
> idempotent — hence the invariant above. The first non-idempotent step would silently
> corrupt downgraded saves.

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `from_version` | `int` | 0..CURRENT | Version found in the saved dict; 0 = pre-versioned save |
| `CURRENT_SCHEMA_VERSION` | `int` | 1 (today) | Constant in `SaveData`; bump for breaking changes |

**When to bump vs. when to use a missing-key default:**

```
requires_bump(change) =
    NOT (change is "add field" AND the field's missing-key default is the correct
         value for EVERY pre-existing save)

missing_key_default_safe(field) =
    absence is semantically indistinguishable from "this save never had the field"
    (a property of the field's MEANING, not its TYPE)
```

The criterion is semantic, not type-based. Examples:
- `tutorial_seen: bool` absent → `false` (correct; old saves haven't seen the tutorial) → **no bump**.
- `high_score: int` absent → `0` (correct for a brand-new stat) → **no bump** — type is irrelevant.
- `opted_in: bool` that should be `true` for legacy users → absent-default `false` is **wrong** → **bump + migrate step**, even though it is a bool.
- Changing an existing default (e.g. `sound` default `true`→`false`): stored values still win for old saves, so old and new users diverge silently. This is **not** a migration case — it is a deliberate policy split; document it where the default changes. A bump is only needed if old saves must be *rewritten* to the new default.
- Rename / remove / retype a field → always **bump + migrate step**.

---

### Current level clamping

```
stored_level = maxi(1, int(dict.get("current_level", 1)))
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `dict.get(...)` | `Variant` | int / float / missing | Parsed value from the save dict; missing → `1` via the `.get` default |
| `stored_level` | `int` | ≥ 1 (no upper bound here) | Written to `SaveData.current_level` |

Two independent protections, not one: the **`.get("current_level", 1)` default** handles a
*missing* key; the **`maxi(1, …)` floor** handles a zero/negative/garbage value. `int()`
coerces a JSON number (Godot 4.6 round-trips integers as `int`, not `float`; only
decimal/exponent tokens parse as `float`). `int(null)`→`0` and `int("garbage")`→`0`, both
caught by the floor — but note no warning is emitted on these coercions.

**Worked boundaries:** `int(7.0)=7`; `maxi(1,int(-5.0))=1`; `maxi(1,int(0))=1`;
`maxi(1,int(null))=1`.

**Upper bound is NOT applied here.** A corrupt `current_level: 999999` loads as `999999`.
`SaveService` deliberately does not clamp the ceiling because it cannot know the level count
without depending on `LevelData` (an improper dependency for `core/`-adjacent I/O). The
**consumer** (`GameManager`) must clamp to the available level count on use. Documented as a
GameManager responsibility, not a save-service one.

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
| `0`, null, missing, `-1`, `99` | `AgeBand.UNKNOWN` | Restrictive fallback — treated as `CHILD` via the `ComplianceService` chokepoint |

**Worked boundaries:** `int(null)=0`→UNKNOWN; `int(-1.0)=-1`→UNKNOWN (wildcard arm);
`int(99)=99`→UNKNOWN; `int(1.0)=1`→ADULT. The `match int(value)` wildcard (`_`) catches
everything outside {1,2}.

> **Ordinal stability is a persisted contract.** The integer values `0/1/2` are written to
> disk and must never change. The `AgeBand` enum **must not be reordered** and new bands
> must be appended (next free integer), never inserted — inserting would silently
> reclassify every existing save. A CI test pins this: `assert AgeBand.UNKNOWN==0 and
> AgeBand.ADULT==1 and AgeBand.CHILD==2` (AC SD-12).

## Edge Cases

| # | Situation | Explicit behaviour |
|---|-----------|--------------------|
| 1 | **File missing** (first install, cleared app data) | `load_game()` falls back to `SaveData.defaults()`; `loaded` emitted. Clean state, no error. |
| 2 | **File exists but unreadable** (bad permissions, partial write from a crash) | `FileAccess.open()` returns null; warning logged; `data = defaults()`; **`load_failed` emitted** (real data was lost — distinct from EC1). Broken file left on disk. *This branch is distinct from EC1/EC3 and needs its own test; triggering it requires a `FileAccess` DI seam or platform chmod — see AC notes.* |
| 3 | **Corrupt JSON** | `JSON.parse_string()` returns non-Dictionary; warning logged; `data = defaults()`; **`load_failed` emitted**. |
| 4 | **Save write fails** (disk full, read-only filesystem, or kill mid-write) | Writes go to `save.json.tmp` then atomic `DirAccess.rename()`. If `open(WRITE)` or `rename()` fails, error logged, method returns early, and the prior `save.json` is **genuinely intact** (it was never touched). A process kill mid-write damages only the `.tmp` file; the real save is untouched. *(This atomic pattern is the scheduled fix; the current in-place overwrite does NOT honour this — a mid-write kill on the live file yields a torn/zero-byte save that loads as EC3 → progress reset. Edge Case 4 describes the required behaviour, not the shipped one.)* |
| 5 | **Missing field in save dict** | Each `from_dict` field uses `.get(key, default)` — missing keys silently use safe defaults. No crash, no data loss. |
| 6 | **`current_level ≤ 0`** (corrupt or edited save) | Clamped to `1` via `maxi(1, int(value))`. |
| 7 | **`age_band` out of range** (e.g., `99` or `null`) | `_parse_age_band` returns `AgeBand.UNKNOWN`. All downstream consumers must treat `UNKNOWN` as `CHILD` (restrictive fallback). |
| 8 | **Unknown settings key** | `Settings.from_dict()` ignores unknown keys silently. `set_value()` on an unknown key warns and returns `false`. |
| 9 | **Save from a future schema version** (downgrade) | `_migrate` runs no steps; `from_dict` validates/clamps each known field. Unknown keys are ignored and **dropped on the next write** — so a field written by a newer client is silently lost if an older client saves over it. No crash, but: (a) migration steps must be idempotent (the older client stamps its lower CURRENT, so a later upgrade re-runs steps — see Formulas → downgrade hazard); (b) **consent/compliance fields must never round-trip through the missing-key-default path** (Core Rule 6) — losing a consent flag on downgrade is a compliance defect, so such fields require a migrate step and conservative (never-permissive) defaults. |
| 10 | **Rapid successive saves** | Each `save_game()` opens and overwrites synchronously. No queue. File is small (< 1 KB); acceptable at M1. Add debounce if write frequency becomes a concern. |
| 11 | **`configure(path)` called after `_ready()`** | New path stored; current `data` was loaded from the old path. Next explicit `load_game()` uses the new path. Test isolation only — do not call at runtime after boot. |
| 12 | **New optional bool field added post-v1** (e.g., `tutorial_seen`) | `from_dict` uses `.get("field", false)`. Old saves default correctly. `to_dict` writes the field on the next save. No migration step needed when the absent value is semantically correct. |
| 13 | **`AgeBand.UNKNOWN` at runtime** | Age gate not yet shown or stored. `ComplianceService` returns the restrictive (CHILD-equivalent) verdict for every consumer. No personal data collection permitted. |
| 14 | **Corrupt/unreadable save vs. genuine first launch** | Both yield `data = defaults()`, but they emit **different signals**: first launch (no file) → `loaded`; lost/corrupt data (EC2/EC3) → `load_failed`. Consumers and telemetry must treat them differently — a `load_failed` is a data-loss event worth logging, not a new player. *(Scheduled code follow-up: `load_failed` signal.)* |
| 15 | **Write failure loses an `age_band` declaration** | If `set_age_band()` is called and the write fails (EC4), the in-memory band is correct for the session but is not persisted. On next launch the gate's "already shown" state (a future flag) must also have failed to persist, so the gate re-presents — never silently runs at the stale band. Compliance-relevant write failures should flag the gate for re-presentation next launch. |

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
| First-Time Tutorial (`TutorialLogic`, `CoachOverlay`) | Depends on this | Reads/writes the **planned** `save.tutorial_seen`; injected via `configure()` in tests |
| Age gate / compliance (future) | Depends on this | Writes `age_band` via `set_age_band()`; ADR-0005 |
| **`ComplianceService` (future, ADR-0005)** | Depends on this | **Mandatory intermediary** — the only reader of `age_band`; `AdService`/`Analytics` depend on `ComplianceService`, not on this directly |
| `AdService` / `Analytics` (future) | Depends on `ComplianceService` | Gate ad/data-collection mode via compliance verdicts, never raw `age_band` |

**Test-seam dependency:** the EC2 (unreadable file) and EC4 (write failure) branches cannot
be triggered headlessly without injecting `FileAccess`. Spec'ing those ACs (below) implies a
small DI seam — a `FileAccessProvider` (or injected open-callable) on `SaveService` — or
those two branches must be marked manual-platform-verified. Tracked with the atomic-write
follow-up since both touch `save_game()`/`load_game()` I/O.

**Reverse references to maintain (bidirectional):**
- `design/gdd/first-time-tutorial.md` §6 — lists `SaveData` / `SaveService` as a dependency ✓ (already present)
- `design/systems-index.md` — **Save & Settings** row ✓ (added)
- `core/save_data.gd` doc comment — list all persisted fields including `tutorial_seen` when added
- ADR-0001 — `SaveData` in `core/` as a load-bearing example of the pure-model seam ✓ (already referenced)
- ADR-0005 — `age_band` + `ComplianceService` chokepoint as the compliance signal ✓ (already referenced)

## Tuning Knobs

All values live in `SaveService` or `SaveData` and can be adjusted without changing
migration or serialization logic.

| Knob | Location | Default | Safe Range | Effect |
|------|----------|---------|------------|--------|
| `SaveService.DEFAULT_PATH` | `autoloads/save_service.gd` | `"user://save.json"` | Any writable `user://` path | Changes the save file location. Override at runtime via `configure(path)` for test isolation. Do not change the default in production. |
| `SaveData.CURRENT_SCHEMA_VERSION` | `core/save_data.gd` | `1` | Integers ≥ 1, monotonically increasing | The version written to every save file. Increment when the persisted shape changes in a breaking way. **Never decrement.** Each increment requires a corresponding `_migrate()` step. |
| `Settings` default values | `data/settings.gd` | `sound=true`, `music=true`, `haptics=true`, `reduced_motion=false`, `colorblind=false` | Booleans — no range | Controls the first-run experience for each toggle. Change these only if the desired fresh-install default changes. Existing saves are unaffected (they carry stored values). |
| `AgeBand.UNKNOWN` fallback policy | **Enforced in `ComplianceService` (single chokepoint)** | Treat as `CHILD` | — | `UNKNOWN` maps to the restrictive verdict. **Enforced in one place, not per-consumer** — consumers call `ComplianceService`, never read `age_band`. The guard must be `age_band == ADULT` for the permissive path (so UNKNOWN and CHILD both fall through to restricted), never `== CHILD` for the restrictive path (which would leak UNKNOWN). |

**What is NOT tunable here:**

- The number of save slots (fixed at 1 — no multi-slot at M1).
- Save frequency (explicit call-site writes only; no auto-save timer).
- Write debounce threshold (no debounce at M1; add one in `SaveService` if write
  frequency becomes a concern at a later milestone — see Edge Case #10).

## Acceptance Criteria

**Legend:** COVERED = an existing test exercises this (function named in parens).
NEW = no test covers it yet; must be written before sign-off. All Logic/Integration
ACs are BLOCKING. Async waits use `simulate_frames(N, 16)` — `simulate_seconds()`
does not exist in gdUnit4 v6.1.3. (Most ACs here are synchronous and need no frames.)

### Group 1 — Unit: pure `SaveData` (no I/O) — `tests/test_save_data.gd`

| ID | Pass condition | Coverage |
|----|---------------|----------|
| SD-01 | `defaults()` → version=CURRENT, level=1, age=UNKNOWN, sound/music/haptics=true, reduced_motion/colorblind=false | PARTIAL (`test_defaults_are_safe` asserts only `sound`+`reduced_motion` of the 5 settings) → **extend the test to assert all 5 settings defaults**, or it under-covers the AC |
| SD-02 | Round-trip `to_dict`/`from_dict` preserves level, age_band, and **all 5 settings keys** | PARTIAL (`test_to_dict_from_dict_round_trips` spot-checks `music` only) → **extend to all 5 settings keys** so a dropped key (e.g. `haptics`) is caught |
| SD-03 | `from_dict({})` == `defaults()` | COVERED (`test_from_dict_missing_fields_use_defaults`) |
| SD-04 | `current_level` 0 and -5 both clamp to 1 | COVERED (`test_from_dict_clamps_current_level_to_minimum`) |
| SD-05 | `age_band:99` → UNKNOWN | COVERED (`test_from_dict_rejects_invalid_age_band`) |
| SD-06 | `age_band:2` → CHILD | COVERED (`test_from_dict_accepts_valid_age_band`) |
| SD-07 | Unknown settings key dropped from `to_dict` | COVERED (`test_from_dict_ignores_unknown_settings_keys`) |
| SD-08 | Pre-versioned save → version normalized to CURRENT | COVERED (`test_from_dict_normalizes_schema_version`) |
| SD-09 | JSON string round-trip preserves int fields | COVERED (`test_json_serialization_round_trips`) |
| SD-10 | `{schema_version:9999, current_level:3}` loads without crash; level=3, version=CURRENT (no infinite migrate loop) | **NEW** `test_save_data_future_schema_version_loads_known_fields` |
| SD-11 | `to_dict().keys()` ⊇ {schema_version, current_level, age_band, settings} (and no *unexpected* keys) | **NEW** `test_save_data_to_dict_contains_canonical_keys` — assert the canonical set is **present**, not an exact frozen set, so adding the planned `tutorial_seen` field does not turn this into a failing test. Update the expected-key set deliberately when a field is added. |
| SD-12 | `AgeBand.UNKNOWN==0 and AgeBand.ADULT==1 and AgeBand.CHILD==2` (persisted-ordinal contract) | **NEW** `test_save_data_age_band_ordinals_are_stable` — fails loudly if the enum is ever reordered |

### Group 2 — Unit: pure `Settings` (no I/O) — `tests/test_settings.gd`

| ID | Pass condition | Coverage |
|----|---------------|----------|
| ST-01 | Defaults: sound/music/haptics=true, reduced_motion/colorblind=false | COVERED (`test_defaults_are_sane`) |
| ST-02 | Every key in `Settings.KEYS` set/get round-trips | **NEW** `test_settings_all_canonical_keys_set_get_round_trip` — per-key sweep catches a missing `match` arm on future key additions. *(Supersedes the existing single-key `test_get_and_set_value_by_key`, which covers only `haptics`; the orphan test may be deleted once the sweep lands or kept as a focused case.)* |
| ST-03 | `set_value("bogus",true)` → false, no mutation | COVERED (`test_set_unknown_key_returns_false`) |
| ST-04 | `from_dict({"sound":false})` → only sound changes | COVERED (`test_from_dict_missing_keys_use_defaults`) |
| ST-05 | Unknown key ignored, absent from `to_dict` | COVERED (`test_from_dict_ignores_unknown_keys`) |
| ST-06 | `from_dict("not a dict")` → all defaults | COVERED (`test_from_dict_non_dictionary_yields_defaults`) |
| ST-07 | `KEYS` matches serialized shape exactly | COVERED (`test_keys_constant_matches_serialized_shape`) |
| ST-08 | `colorblind` round-trips | COVERED (`test_colorblind_round_trips_and_sets_by_key`) |
| ST-09 | Pre-colorblind save → colorblind=false | COVERED (`test_from_dict_missing_colorblind_defaults_false`) |

### Group 3 — Integration: `SaveService` file I/O — `tests/test_save_service.gd`
Inject temp path via `configure(TEST_PATH)`; clean up in `after_test`.

| ID | Pass condition | Coverage |
|----|---------------|----------|
| SV-01 | Round-trip persists level, age_band, settings across two instances | COVERED (`test_save_then_load_round_trips_to_disk`) |
| SV-02 | Missing file → defaults | COVERED (`test_load_missing_file_uses_defaults`) |
| SV-03 | Corrupt JSON → defaults, no crash | COVERED (`test_load_corrupt_file_uses_defaults`) |
| SV-04 | `set_current_level(9)` persists | COVERED (`test_set_current_level_persists`) |
| SV-05 | `set_age_band(CHILD)` persists | COVERED (`test_set_age_band_persists`) |
| SV-06 | `set_current_level(0)` → reloads as 1 | **NEW** `test_save_service_set_current_level_zero_clamps_to_one` |
| SV-07 | `loaded` fires **exactly once** on missing-file load AND on a valid-file load | **NEW** `test_save_service_loaded_signal_emitted_on_missing_file`, `..._on_success`. **Use a counter** (`count += 1`) and assert `count == 1` — "fires once" is not provable with a bool flag. |
| SV-08 | **`load_failed`** fires exactly once on corrupt-JSON load (NOT `loaded`) | **NEW** `test_save_service_load_failed_signal_on_corrupt_file` — depends on the `load_failed` follow-up |
| SV-09 | `saved` fires exactly once on successful save | **NEW** `test_save_service_saved_signal_emitted_on_success` (counter, `== 1`) |
| SV-10 | Three rapid `save_game()` → last write wins on reload | **NEW** `test_save_service_rapid_saves_last_write_wins` |
| SV-11 | `configure(B)` after writing A → save/reload uses B; A untouched | **NEW** `test_save_service_configure_redirects_io` |
| SV-12 | **EC2** — file exists but `open()` returns null → `defaults()` + `load_failed` | **NEW** `test_save_service_unreadable_file_emits_load_failed` — **requires a `FileAccess` DI seam** (or mark manual-platform-verified). Distinct branch from SV-02 (missing) and SV-08 (corrupt). |
| SV-13 | **EC4** — `save_game()` open/rename failure is a no-op; prior `save.json` intact | **NEW** `test_save_service_write_failure_is_noop_prior_save_intact` — also needs the DI seam |
| SV-14 | **Atomic write** — a successful `save_game()` leaves no `.tmp` and a single valid `save.json`; an interrupted write damages only `.tmp` | **NEW** `test_save_service_write_is_atomic_via_temp_rename` — depends on the atomic-write follow-up |

### Group 4 — Integration: `SettingsService` — `tests/test_settings_service.gd`
Inject via `configure(_make_save())` (temp-file-backed `SaveService`).

| ID | Pass condition | Coverage |
|----|---------------|----------|
| SS-01 | `get_value` returns defaults on fresh save | COVERED (`test_get_value_reads_defaults`) |
| SS-02 | `set_value("music",false)` persists to disk | COVERED (`test_set_value_persists_to_disk`) |
| SS-03 | `set_value` emits `changed(key,value)` | COVERED (`test_set_value_emits_changed_signal`) |
| SS-04 | `toggle("sound")` flips and persists | COVERED (`test_toggle_flips_and_persists`) |
| SS-05 | `set_value("bogus",...)` never emits `changed` | COVERED (`test_set_unknown_key_does_not_emit`) |
| SS-06 | `toggle` emits `changed` | **NEW** `test_settings_service_toggle_emits_changed_signal` |
| SS-07 | Unknown key does not mutate the save file | **NEW** `test_settings_service_unknown_key_does_not_mutate_save` |
| SS-08 | `settings()` returns the **same instance** as `SaveService.data.settings` (reference identity, not value equality) | **NEW** `test_settings_service_settings_accessor_returns_live_reference` — assert `svc.settings() == save.data.settings` by identity (`is`/same object), documenting the no-defensive-copy contract |
| SS-09 | All `KEYS` round-trip through `get_value`/`set_value` to disk | **NEW** `test_settings_service_all_canonical_keys_round_trip` |

### Group 5 — Compliance / Age Gate (ADR-0005, BLOCKING)
Protects the invariant: `UNKNOWN` must be treated as `CHILD` (restrictive) by every consumer.

| ID | Pass condition | Coverage |
|----|---------------|----------|
| AG-01 | Fresh `SaveData` age_band == UNKNOWN | COVERED (`test_defaults_are_safe`) |
| AG-02 | `age_band:0` explicitly → UNKNOWN | **NEW** `test_save_data_age_band_zero_coerces_to_unknown` |
| AG-03 | `from_dict({"age_band": 1})` → ADULT (direct coercion, not via round-trip) | **NEW** `test_save_data_age_band_one_coerces_to_adult` — the old citation (`test_to_dict_from_dict_round_trips`) tests serialization+coercion together and is **not** a direct coercion test; ADULT had no direct test |
| AG-03b | `set_age_band(ADULT)` survives a disk round-trip (parity with SV-05 for CHILD) | **NEW** `test_save_service_age_band_adult_persists` — the compliance-critical value was never disk-round-tripped |
| AG-04 | `age_band:2` → CHILD | COVERED (`test_from_dict_accepts_valid_age_band`) |
| AG-05 | `age_band:-1` → UNKNOWN | **NEW** `test_save_data_negative_age_band_coerces_to_unknown` |
| AG-06 | `age_band:null` → UNKNOWN | **NEW** `test_save_data_null_age_band_coerces_to_unknown` |
| AG-07 | Persisted UNKNOWN reloads as UNKNOWN (never silently upgraded) | **NEW** `test_save_service_age_band_unknown_persists_as_unknown` |
| AG-08 | **`ComplianceService.can_collect_personal_data()` (and peers) return the restrictive verdict for both UNKNOWN and CHILD, permissive only for ADULT** | **NEW** `test_compliance_service_unknown_treated_as_child` — tests the **real chokepoint**, not an abstract enum identity. *(Lives with `ComplianceService` when it ships; until then the assertion is the spec.)* A pure `age_band != ADULT` test proves a tautology and does not prevent a consumer from ignoring the gate — superseded by this real-consumer test. |

### New Tests Required Before Sign-Off (all BLOCKING)
SD-10, SD-11, SD-12, ST-02, SV-06, SV-07 (×2), SV-08, SV-09, SV-10, SV-11, SV-12, SV-13,
SV-14, SS-06, SS-07, SS-08, SS-09, AG-02, AG-03, AG-03b, AG-05, AG-06, AG-07, AG-08.
Plus **extend** the existing SD-01 and SD-02 tests to cover all 5 settings keys.

The **existing suite is 29 tests** (not 22), across `test_save_data.gd` (9),
`test_settings.gd` (10), `test_save_service.gd` (5), `test_settings_service.gd` (5); it
covers the ACs marked COVERED. Note that `test_get_and_set_value_by_key` is an orphan
(unreferenced) until ST-02 subsumes it.

**Coverage categories (be honest about all three):** (a) COVERED by an existing test;
(b) NEW test needed; (c) **documented Edge Cases with no test and no trivial test path** —
EC2/EC4 (SV-12/SV-13) need a `FileAccess` DI seam or manual-platform verification, and the
atomic-write / `load_failed` ACs depend on the scheduled code follow-ups.

**Implementation notes:**
- **Signal tests** (SV-07/08/09, SS-06): `load_game`/`save_game`/`emit` are synchronous —
  connect the lambda **before** the call and assert after; no `await`/frame-sim. This holds
  **only** with the DI pattern (`.new()` + manual `load_game()`); tests must never use the
  autoload singleton or the signal fires before they connect. Use a **counter** (`== 1`) for
  "fires once", not a bool.
- **AG-08**: test the real `ComplianceService` verdict, not a bare enum comparison. The
  chokepoint (Core Rule 9) is what makes this testable; a pure `age_band != ADULT` assertion
  is a tautology.
- **SD-10**: confirms `_migrate` has no unbounded loop and is idempotent on a
  future/downgrade version (level=3, version stamped to CURRENT, no crash).
- **SV-12/13/14**: gated on the `FileAccess` DI seam + atomic-write follow-ups; until then,
  mark manual-platform-verified with documented evidence.

## Open Questions & Recorded Decisions

### Decisions recorded at this review (2026-06-09)

- **`age_band` tamper-resistance — DECISION: accept plain-JSON tamperability at M1.**
  `user://save.json` is unsigned plain text, so a determined user (root/ADB/jailbreak) can
  edit `age_band` CHILD→ADULT to unlock adult ads/data collection. This is a COPPA/GDPR-K
  exposure, not merely anti-cheat. **At M1 we accept it**, with the compensating control that
  `UNKNOWN` is always restrictive and the gate is neutral (ADR-0005). **Full integrity
  protection (HMAC/signature over `age_band`, mismatch → coerce to CHILD/UNKNOWN; or
  server-authoritative resolve accepting only downward CHILD overrides) is a REQUIRED
  prerequisite before the first `AdService`/`Analytics` ships** — it must not be deferred
  past that point. Tracked as a pre-AdService ADR.

- **Retention / erasure — DECISION: save-file deletion = full erasure at M1; full design
  scheduled pre-AdService.** No personal data is collected before `age_band` resolves, and
  at M1 nothing is logged off-device, so deleting `user://save.json` constitutes complete
  erasure of all collected data. A full retention/consent/erasure design (right-to-erasure
  flow, privacy-policy enumeration of `age_band`, retention period) is **required before any
  off-device logging (`AdService`/`Analytics`) ships**. An AC must then assert no
  compliance-relevant data exists outside the save file.

### Still open

- **Cloud save / cross-device sync** — deferred past M1. When added, the migration seam and
  single-file model must be revisited (conflict resolution, last-write-wins vs. merge).
- **Save encryption (non-`age_band` fields)** — `current_level`/settings encryption is
  genuinely optional; revisit only if leaderboard/anti-cheat requirements emerge.
- **Settings expansion** — when non-boolean settings appear (e.g., volume sliders, language
  selection), `Settings` must move beyond the bool-only `match` model. That change requires
  a schema-version bump and a migration step (it is not a missing-key-default case).
- **Wiring `colorblind` / `reduced_motion`** — persisted but inert at M1; a separate story
  must connect view-layer consumers to `SettingsService.changed`.
