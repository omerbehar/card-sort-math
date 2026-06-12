# ADR-0009: Injectable `TimeProvider` seam for deterministic, headless-safe time

## Status
Accepted (2026-06-12 — ratifies the "Injectable clock" Open Question of the approved
`design/gdd/deck-economy.md`; unblocks the Deck Economy sprint). Acceptance rests on the GDD's
approval + the author's go-ahead to implement.

> **Scope note:** an earlier framing bundled this seam with an Undo replay coordinator. **The Undo
> booster was removed on 2026-06-12** (see `design/gdd/reviews/deck-economy-review-log.md`). The
> `TimeProvider` seam **survives independently**: it is still required for Reshuffle determinism
> (Formula 6 `level_start_timestamp`, AC-R04/R08) and for daily caps / login streaks (calendar-day
> reasoning). This ADR is therefore scoped to the clock seam **only** — there is no session
> coordinator, no `tap_history`, and no replay logic anywhere in the economy.

## Date
2026-06-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — wraps the stable `Time` singleton behind a `RefCounted`; no post-cutoff APIs |
| **References Consulted** | `design/gdd/deck-economy.md` (Formula 6, Formula 8, Rules 14–16, AC-R04/R08, AC-C0x, AC-EF03/04, Open Questions); `autoloads/save_service.gd`, `core/save_data.gd`; ADR-0007 (determinism contracts — `rng.seed`, no global RNG); ADR-0001/0004 |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Confirm the default provider's `Time.get_unix_time_from_system()` returns Unix epoch **seconds** (it does in 4.x) so Formula 6's `level_start_timestamp` matches the GDD examples. The default is the only code path that touches the engine clock; everything testable injects a stub. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (core purity), ADR-0004 (typed + gdUnit4), ADR-0007 (determinism discipline this seam extends to time) |
| **Enables** | Deterministic Reshuffle seeding (Formula 6) and deterministic daily-cap/streak tests; AC-R04, AC-R08, AC-C01..03, AC-EF03, AC-EF04. |
| **Blocks** | Reshuffle and daily-cap/streak stories cannot have deterministic blocking tests until this seam exists. |
| **Ordering Note** | Sibling of ADR-0008 (`EconomyEvent`) and ADR-0010 (Extra Discard). Should land before Reshuffle and daily-cap stories. |

## Context

### Problem Statement
Two economy mechanisms read wall-clock time:
1. **Reshuffle seeding** — Formula 6 derives `reshuffle_seed` from `level_start_timestamp` (Unix
   seconds) so two sessions reshuffling the "same" level diverge (AC-R08 anti-replay).
2. **Daily caps & login streaks** — the rewarded-ad coin cap (Formula 8), the daily-challenge
   reset, and the streak day all key on the **calendar day** (midnight UTC).

If this code calls `Time.get_unix_time_from_system()` directly, the blocking tests (AC-R04/R08
require *exact* seeds from a *fixed* timestamp; AC-EF04 requires "missed day" vs "rollover"
transitions) become non-deterministic and headless-fragile. ADR-0007 already banned global RNG in
`core/` for the same reason; time is the remaining hidden non-determinism source.

### Constraints
- `core/` is pure and node-free (ADR-0001); it must not call engine singletons directly.
- Determinism is a project rule (ADR-0007): seeds and time-derived state must be reproducible.
- Tests run headless in CI; they must not depend on the real clock or timezone.
- `SaveData`/`SaveService` already persist player state; daily-cap/streak counters and the
  "last-active day" they compare against will live in `SaveData` (schema bump, owned by the economy
  sprint) — but the *current* day must come through the seam, not a direct engine read.

### Requirements
- A single injectable clock all time-dependent economy/level code reads through.
- A production default that wraps the engine clock; a test stub that returns a fixed value.
- Helpers for both needs: Unix seconds (Reshuffle) and a UTC calendar-day key (caps/streaks).
- No `Time.get_unix_time_from_system()` call anywhere outside the default provider.

## Decision

Introduce **`core/time_provider.gd`** — `class_name TimeProvider extends RefCounted` — a tiny seam
with a real default and an injectable override. Anything that needs "now" (the `WalletService`
autoload, the Reshuffle seed derivation, the daily-cap/streak tracker) takes a `TimeProvider` by
dependency injection (constructor/`configure()`), exactly like `SaveService`/`ComplianceService`/
`GameManager` already accept injected dependencies via `configure()`. Production wires the default;
tests inject a fixed-clock stub.

`TimeProvider` exposes the two shapes the GDD needs and **nothing reads the engine clock except its
default implementation**.

### Architecture Diagram
```
core/time_provider.gd  (PURE RefCounted)
   ├─ default: unix_seconds() -> Time.get_unix_time_from_system()   ← ONLY engine-clock call site
   └─ test stub: returns injected fixed value(s)
        ▲ injected via configure()/ctor (same pattern as SaveService injection)
        │
WalletService (autoload) ──┬─ reshuffle seed: uses time.unix_seconds() as level_start_timestamp
                           ├─ daily cap:      uses time.utc_day_key() to detect day rollover
                           └─ streak:         uses time.utc_day_key() for missed-day vs rollover
LevelData / Reshuffle path ─ uses the SAME injected TimeProvider for Formula 6 determinism
```

### Key Interfaces
```gdscript
class_name TimeProvider
extends RefCounted
## Injectable clock. The DEFAULT is the only code in the project permitted to call
## Time.get_unix_time_from_system(); everything else reads time through an instance of this.

## Unix epoch SECONDS. Used as Formula 6 `level_start_timestamp`.
func unix_seconds() -> int:
    return int(Time.get_unix_time_from_system())

## Integer key for the current UTC calendar day (days since epoch), for daily-cap reset,
## daily-challenge reset, and streak missed-day/rollover logic. Derived from unix_seconds()
## so a single injected stub controls both shapes consistently.
func utc_day_key() -> int:
    return unix_seconds() / 86_400   # integer floor division; UTC midnight boundaries
```
```gdscript
# Test stub (tests/ only) — deterministic:
class FixedTimeProvider extends TimeProvider:
    var now_seconds: int = 0
    func unix_seconds() -> int: return now_seconds
```
Injection contract (mirrors existing autoloads):
- `WalletService.configure(save: Object, compliance: Object, time: TimeProvider) -> void`
  (production passes `TimeProvider.new()`; tests pass a `FixedTimeProvider`).
- The Reshuffle path receives the **same** `TimeProvider` instance so `level_start_timestamp` is
  captured once at level entry and reused for every reshuffle of that level (Formula 6 stability
  within a level; AC-R04 reproducibility).

**Determinism contract (extends ADR-0007):** no `core/` or economy code calls
`Time.get_unix_time_from_system()`, `Time.get_datetime_dict_from_system()`, `OS`-clock APIs, or
`Time.get_ticks_*()` directly. The single permitted call site is `TimeProvider`'s default body. A
project rule / code-review gate enforces this (analogous to the global-RNG ban).

**Every calendar-day-keyed economy decision routes through `utc_day_key()`** — not only the
rewarded-ad cap and login streak, but also the daily-challenge reset (Rule 14), `first_win_today`
(Formula 1, "first level cleared each calendar day"), the gem→coin daily cap
(`DAILY_GEM_CONVERT_CAP`, EC-13), and any once-per-day milestone gating. They are all the *same*
`utc_day_key()` consumer, so a single injected clock makes the entire "what day is it" surface
deterministic and prevents a contributor from reading `Time` directly for `first_win_today`.

### Reshuffle seed derivation — explicit integer mix, NEVER `hash()` (resolves the ADR-0007 conflict)

`TimeProvider.unix_seconds()` supplies Formula 6's `level_start_timestamp`, but the seed **derived**
from it must obey ADR-0007 §2: **GDScript `hash()` is banned for any value fed to `rng.seed`** (it is
implementation-defined and unstable across platforms/Godot versions — it would break cross-device
reshuffle reproducibility, the daily-challenge identity, and any future "share this seed"). The
original GDD Formula 6 wrote `abs(hash(str(level_id)+":"+...))`; that is **superseded**. The reshuffle
seed is derived by an **explicit integer mix** of the three integer inputs, in the same spirit as
ADR-0007 §2's `world_id * WORLD_STRIDE + level_index`:

```gdscript
# core/ (LevelGenerator.reshuffle path). NO hash(). Reference form — the exact
# constants are pinned and property-tested at the Reshuffle dev-story.
const MIX_A: int = 0x9E3779B1   # 2654435761 (Knuth/Fibonacci multiplicative)
const MIX_B: int = 0x85EBCA77   # 2246822519
const MIX_C: int = 0xC2B2AE3D   # 3266489917

static func reshuffle_seed(level_id: int, level_start_timestamp: int, reshuffle_count: int) -> int:
    var s: int = level_id * MIX_A
    s = (s ^ level_start_timestamp) * MIX_B
    s = (s ^ reshuffle_count) * MIX_C
    s ^= (s >> 16)
    return s & 0x7FFFFFFFFFFFFFFF   # non-negative 63-bit; passed straight to rng.seed
```

This is pure 64-bit integer arithmetic (Godot int overflow wraps deterministically), is stable across
platforms and engine versions, and changes for **any** difference in `level_start_timestamp`
(cross-session anti-replay, AC-R08) or `reshuffle_count` (consecutive reshuffles, AC-R04). It feeds
`rng.seed` exactly where ADR-0007 §2 requires an explicit integer — so this ADR now genuinely
*extends* ADR-0007's discipline rather than contradicting it. **Cascade:** GDD Formula 6 and
AC-R04/R08 were updated alongside this ADR to assert the determinism + difference *properties* of
`reshuffle_seed(...)` rather than a literal `hash()` value.

## Alternatives Considered

### Alternative 1: Call `Time.get_unix_time_from_system()` directly where needed
- **Description**: Read the engine clock inline in the Reshuffle seed math and the cap/streak code.
- **Pros**: No new type.
- **Cons**: AC-R04/R08 (exact seeds from a fixed timestamp) and AC-EF04 (missed-day vs rollover)
  become non-deterministic; CI depends on the runner's wall clock and timezone; impossible to test
  "yesterday vs today" without sleeping or mocking the engine globally.
- **Rejection Reason**: Defeats the GDD's explicitly required determinism (Open Questions) and the
  project's headless-test mandate.

### Alternative 2: A global `TimeService` autoload
- **Description**: A singleton autoload exposing `now()`, set globally for tests.
- **Pros**: Reachable everywhere without threading a parameter.
- **Cons**: Singleton global state is exactly what ADR-0001/coding-standards push against
  ("dependency injection over singletons"); per-test isolation requires mutating global state and
  resetting it; harder to run parallel tests with different fixed clocks; pulls a Node dependency
  toward `core/`-adjacent logic.
- **Rejection Reason**: Violates the DI-over-singleton standard; injection is already the
  established pattern (`SaveService`, `ComplianceService`, `GameManager` all use `configure()`).

### Alternative 3: Pass a raw `int` timestamp into each function
- **Description**: No type — callers pass `now_seconds: int` everywhere.
- **Pros**: Maximally simple; trivially deterministic in tests.
- **Cons**: Every call site must source the int (re-introducing direct engine reads upstream); no
  home for the `utc_day_key()` derivation; the "no direct clock read" rule has no single seam to
  enforce. Spreads the engine-clock call to many sites.
- **Rejection Reason**: A thin `TimeProvider` gives one enforceable seam + shared day-key logic for
  near-zero cost; raw ints just relocate the problem.

## Consequences

### Positive
- Reshuffle seeds and daily-cap/streak transitions are fully deterministic and headless-safe.
- One enforceable call site for the engine clock (mirrors ADR-0007's single-RNG discipline).
- Reuses the project's existing `configure()` injection idiom — no new architectural concept.
- `utc_day_key()` centralizes "what day is it" so cap-reset and streak logic can't disagree.

### Negative / accepted trade-offs
- One more dependency to thread through `WalletService.configure()`. Accepted: it is one parameter,
  and the autoload already takes injected `save`/`compliance`.
- `utc_day_key()` uses UTC only (matches the GDD's "midnight UTC" resets); local-time players see
  resets at their UTC offset. Accepted per GDD; revisit only if playtest shows confusion.

### Risks
- **A contributor calls the engine clock directly**, silently breaking a determinism test.
  *Mitigation:* code-review gate + the determinism rule; the fixed-clock tests (AC-R04/R08, AC-EF04)
  fail loudly if real time leaks in.
- **Epoch-unit mismatch** (ms vs s). *Mitigation:* `unix_seconds()` casts to int seconds; a unit
  test pins `reshuffle_seed(42, 1_718_000_000, 1)` (the explicit integer mix — no `hash()`) against
  an injected `1_718_000_000` and asserts it differs from `reshuffle_seed(42, 1_718_000_000, 2)`.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| deck-economy.md | Formula 6 uses `level_start_timestamp`; AC-R04/R08 require exact seeds from an **injected** timestamp ("via a `TimeProvider` seam, not `Time.get_unix_time_from_system()`") | `unix_seconds()` is the injected source; tests pass a fixed value; default wraps the engine clock |
| deck-economy.md | Formula 8 daily ad cap; Rule 15 cap reset at midnight UTC; Rule 14 daily-challenge reset | `utc_day_key()` gives a deterministic UTC day boundary for reset detection |
| deck-economy.md | Rule 16 streak: "missed day" → day-3 floor vs natural day-8 rollover; AC-EF04 | `utc_day_key()` lets tests drive consecutive/missed days deterministically |
| deck-economy.md | Open Questions: "`WalletService`/`LevelData` must read time through an injectable `TimeProvider` seam" | Exactly this seam, injected via `configure()` |

## Performance Implications
- **CPU**: one integer division for `utc_day_key()`; one engine-clock read per timestamp need. Negligible.
- **Memory**: a single `RefCounted` instance shared by injection.
- **Load Time / Network**: none.

## Migration Plan
Additive. New file `core/time_provider.gd` (+ a `FixedTimeProvider` test helper under `tests/`).
The economy sprint's `WalletService.configure()` gains a `time: TimeProvider` parameter (production
passes `TimeProvider.new()`). No existing file reads the clock today, so there is nothing to retrofit
beyond wiring the new economy code through the seam. The daily-cap/streak counters + "last-active
day" they compare against are added to `SaveData` by the economy sprint (its own schema bump);
this ADR only mandates that the *current* day be sourced from `TimeProvider`.

## Validation Criteria
- AC-R04: injected `level_start_timestamp = 1_718_000_000` → `reshuffle_seed(42, 1_718_000_000, 1)`
  is reproducible run-to-run and differs from `reshuffle_seed(42, 1_718_000_000, 2)` (no `hash()`).
- AC-R08: injected `T1`, `T2` one second apart → different seeds, different layouts.
- AC-EF04: a `FixedTimeProvider` advanced by 1 day → streak continues; skipped a day → resets to
  `STREAK_RESET_FLOOR`.
- AC-C01..03: cap counters reset when `utc_day_key()` increments; uncapped sources unaffected.
- Code-review gate: no economy/`core/` source calls `Time.get_unix_time_from_system()` outside
  `TimeProvider`'s default.

## Related Decisions
- ADR-0007 (determinism: seeded RNG, `rng.seed`, global-RNG ban) — this ADR extends the same
  discipline to time.
- ADR-0001 (core purity), ADR-0004 (typed + gdUnit4).
- ADR-0008 (`EconomyEvent`), ADR-0010 (Extra Discard Slot) — sibling Deck Economy ADRs.
- `design/gdd/deck-economy.md` (Formula 6/8, Rules 14–16, AC-R04/R08); `design/gdd/reviews/deck-economy-review-log.md` (Undo removal that left this seam standalone).
