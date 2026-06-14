# ADR-0010: Extra Discard Slot — mutable `_active_discard_slots` + `expand_discard()` on `BoardModel`

## Status
Accepted (2026-06-12 — ratifies the "Extra Discard Slot requires BoardModel change" Open Question
of the approved `design/gdd/deck-economy.md`; unblocks the Deck Economy sprint). Acceptance rests
on the GDD's approval + the author's go-ahead to implement.

**Amendment (2026-06-14):** the **"purchase-ahead-only" precondition was dropped**. Originally the
Extra Discard booster was blocked when the discard row was full (`occupied >= active_slots` →
`DISCARD_FULL`), to forbid a one-tap-from-LOSE rescue. In play this made the button silently
unresponsive exactly when a player reaches for it (row 5/5) — it read as broken. Per the author's
call, the booster may now be used when the row is full, adding a slot as a rescue; only the absolute
slot cap (`active_slots >= MAX_DISCARD_SLOTS` → `AT_MAX`) still gates it. `WalletService._extra_discard_allowed`
now checks the cap only. `BoardModel` is unchanged (`expand_discard` was already uncapped). The
`DISCARD_FULL` reason code is retained in `EconomyEnums.FailReason` but is no longer emitted by this path.

## Date
2026-06-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — pure GDScript state change to an existing `RefCounted`; no engine APIs |
| **References Consulted** | `design/gdd/deck-economy.md` (Core Rule 11, EC-06/07, AC-E01..E06, Open Questions); `core/board_model.gd` (the three `DISCARD_SLOTS` loops); `tests/test_board_model.gd`; `design/registry/entities.yaml` (`MAX_DISCARD_SLOTS`); ADR-0001/0003/0004/0007 |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Re-run the full board suite after the refactor: the existing discard/`_pull_matching` behaviour must be byte-identical at the default 5 slots (the change is inert until `expand_discard()` is called). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (core purity), ADR-0004 (typed + gdUnit4), ADR-0003 (solvability invariant — must still hold after expansion) |
| **Enables** | The Extra Discard Slot booster (AC-E01..E06); `WalletService` cap enforcement (`MAX_DISCARD_SLOTS`). |
| **Blocks** | The Extra Discard Slot story cannot start until this is Accepted (it mutates an already-tested core system). |
| **Ordering Note** | Sibling of ADR-0008 (`EconomyEvent`) and ADR-0009 (TimeProvider). Independent; touches `BoardModel`, so it should be sequenced where the board suite can be re-run in isolation. |

## Context

### Problem Statement
The Extra Discard Slot booster adds one discard buffer slot to the *current* level (default cap
`MAX_DISCARD_SLOTS = 7`, i.e. up to two purchases over the base 5). Today `core/board_model.gd`
hard-codes the discard size as `const DISCARD_SLOTS = 5`, read in **three** places:
- `_init()` — seeds `_discard` with `DISCARD_SLOTS` empty (`-1`) entries (board_model.gd:60–62).
- `_first_empty_discard()` — iterates `for slot in DISCARD_SLOTS` (board_model.gd:225–229).
- `_pull_matching()` — iterates `for slot in DISCARD_SLOTS` (board_model.gd:197–208).

There is no way to grow the buffer at runtime. The open question: **how does the buffer become
mutable, and who enforces the maximum?**

### Constraints
- `BoardModel` is pure, node-free, deterministic, and **already covered by a large board suite**
  (`tests/test_board_model.gd`). The change must be inert at 5 slots (no behavioural diff).
- `BoardModel` must stay **free of economy-config knowledge** — it does not know coins, costs, or
  `MAX_DISCARD_SLOTS` (that is economy policy, not board rules). ADR-0001 keeps tuning out of `core/`.
- Solvability (ADR-0003) and the discard/pull/cascade semantics must be preserved.
- The booster is **purchase-ahead-only** (GDD Core Rule 11 / EC-06): the *precondition* (room
  remains, below max) is checked before spend — but that precondition is an **economy** decision,
  not a board rule.

### Requirements
- A runtime-growable discard buffer on `BoardModel`, appending one empty slot per expansion.
- The base size resets to 5 at each level (win/lose/quit) — i.e. expansions are per-level.
- The cap (`MAX_DISCARD_SLOTS`) is enforced by the economy layer, not `BoardModel`.
- All existing board tests pass unchanged.

## Decision

Replace the `const DISCARD_SLOTS = 5` *usage* with a mutable per-instance field
**`_active_discard_slots: int`** (initialised to the `DISCARD_SLOTS` constant, which is retained as
the **base/default** and the level-reset value). All three loops iterate `_active_discard_slots`
instead of the constant. `BoardModel` gains **`expand_discard()`** — an **uncapped** append of one
empty slot. The **`MAX_DISCARD_SLOTS` cap is enforced by `WalletService`** before it calls
`expand_discard()`, so `BoardModel` never learns about economy config.

`BoardModel` knows *how* to grow the buffer; `WalletService` decides *whether* it may.

### Architecture Diagram
```
WalletService (autoload)  ── use_booster(EXTRA_DISCARD_SLOT) ──┐
   precondition (ECONOMY policy):                              │
     _active_discard_slots < MAX_DISCARD_SLOTS  (cap)          │  if precondition + affordability hold:
     AND occupied < _active_discard_slots       (purchase-ahead)│     spend(coins) → board.expand_discard()
     else → BOOSTER_PRECONDITION_FAILED (no spend)             │
                                                               ▼
BoardModel (core/ — NO economy knowledge):
   var _active_discard_slots: int = DISCARD_SLOTS    # base 5, the level-reset value
   func expand_discard():                         # UNCAPPED append of one empty slot
       _active_discard_slots += 1
       _discard.append(-1)
   # init / _first_empty_discard / _pull_matching now iterate _active_discard_slots
```

### Key Interfaces
```gdscript
# core/board_model.gd
const DISCARD_SLOTS: int = 5          # retained: BASE size + the level-reset value

var _active_discard_slots: int = DISCARD_SLOTS   # NEW mutable field

## Appends one empty discard slot. UNCAPPED by design — the MAX_DISCARD_SLOTS policy is
## enforced by the caller (WalletService), keeping BoardModel free of economy config.
func expand_discard() -> void:
    _active_discard_slots += 1
    _discard.append(-1)

## Current discard capacity (for the economy precondition + view layout).
func active_discard_slots() -> int:
    return _active_discard_slots

## Count of occupied discard slots (for the purchase-ahead precondition / EC-06).
func occupied_discard_count() -> int:
    var n: int = 0
    for slot in _active_discard_slots:
        if _discard[slot] != -1:
            n += 1
    return n
```
Refactor sites — the **three instance-capacity reads in `core/board_model.gd`** that govern this
`BoardModel`'s live discard array (all three replace `DISCARD_SLOTS` with `_active_discard_slots`):
- `_init()` discard seeding loop (`for _i in _active_discard_slots`) — board_model.gd:61.
- `_first_empty_discard()` (`for slot in _active_discard_slots`) — board_model.gd:226.
- `_pull_matching()` (`for slot in _active_discard_slots`) — board_model.gd:198.

**Other `DISCARD_SLOTS` readers — deliberately NOT refactored (correction to the earlier
"exactly three loops" claim).** `core/recoverability_simulator.gd` also reads
`BoardModel.DISCARD_SLOTS` at lines 23, 47, and 103 (`min_headroom` seed; `DISCARD_SLOTS −
occupancy` headroom; the occupancy scan loop). These **must stay on the base `DISCARD_SLOTS`
constant** — the recoverability simulator runs at *generation time* on a fresh board and must
prove the level is recoverable at **base capacity** (5), independent of whether a player later
buys runtime slots. Routing them through `active_discard_slots()` would be a bug (it would let the
generator assume the player will purchase buffer). So the full picture is **3 instance reads to
change + 3 simulator reads to leave (with a clarifying comment)**. A grep for `DISCARD_SLOTS`
across `core/` must return exactly these six sites and no others before the story is considered
complete.

Economy side (enforced in `WalletService`, **not** `BoardModel`):
```
precondition(EXTRA_DISCARD):
    board.active_discard_slots() < EconomyConfig.MAX_DISCARD_SLOTS        # cap (EC-07)
    AND board.occupied_discard_count() < board.active_discard_slots()     # purchase-ahead (EC-06)
# on pass + affordability: spend(coins) → board.expand_discard()
# on fail: BOOSTER_PRECONDITION_FAILED(EXTRA_DISCARD, reason=AT_MAX | DISCARD_FULL), no spend
```
**Level reset:** at level end (win/lose/quit) a fresh `BoardModel` is built (`from_config`), so
`_active_discard_slots` naturally returns to `DISCARD_SLOTS` (5) — AC-E03. No explicit teardown
needed beyond the existing per-level construction.

## Alternatives Considered

### Alternative 1: One-shot `discard_capacity = 6` flag
- **Description**: A boolean/`int` "expanded?" flag that bumps capacity to 6 once.
- **Pros**: Smallest change.
- **Cons**: Doesn't model the default `MAX_DISCARD_SLOTS = 7` (two purchases); contradicts the GDD's
  "single mechanism" mandate; special-cases "6" in the loops. Doesn't generalise to the tuning range
  (6–8).
- **Rejection Reason**: GDD Core Rule 11 explicitly rejects the one-shot `discard_capacity = 6` in
  favour of a mutable count + append.

### Alternative 2: `BoardModel.expand_discard(max_slots)` — cap passed in
- **Description**: `BoardModel` takes the cap and self-enforces.
- **Pros**: One call site; cap can't be forgotten.
- **Cons**: Pushes economy config (`MAX_DISCARD_SLOTS`) into `core/`, violating ADR-0001's "no
  tuning in core" rule; `BoardModel` would need to know it's being driven by a paid booster.
- **Rejection Reason**: Keeps the cap with its owner (economy) instead; `BoardModel` stays policy-free.

### Alternative 3: Keep `const DISCARD_SLOTS`; track extra slots in a parallel structure
- **Description**: Leave the constant; maintain "extra slots" outside `_discard`.
- **Pros**: `_discard` core array untouched.
- **Cons**: Two sources of truth for discard capacity; `_first_empty_discard`/`_pull_matching` must
  consult both; high bug surface in the most-tested board paths.
- **Rejection Reason**: One contiguous `_discard` array iterated by one length field is simpler and
  preserves the existing loop shape exactly.

## Consequences

### Positive
- Single mechanism (mutable count + append) covers the full `MAX_DISCARD_SLOTS` range (6–8 tuning).
- `BoardModel` stays free of economy config; the cap lives with the economy that owns it.
- Inert at 5 slots — the existing board suite is the regression guard.
- Per-level reset is free (new `BoardModel` per level).

### Negative / accepted trade-offs
- **Touches an already-tested core system** (the three discard loops). Accepted: the change is
  mechanical (constant → field), behaviour-preserving at 5, and re-run against the full board suite
  (Validation Criteria). This coupling is named, per ADR-0007's "a `BoardModel` change re-runs its
  suite" discipline.
- `occupied_discard_count()` is an O(slots) scan. Negligible (≤8 slots), called only on the
  precondition check.

### Risks
- **A read site mis-classified** (an instance-capacity loop left on the constant → capacity desync,
  OR a simulator read wrongly switched to `active_discard_slots()` → the generator assumes bought
  buffer). *Mitigation:* a `DISCARD_SLOTS` grep across `core/` must return exactly the **six** sites
  named in the Decision (3 in `board_model.gd` → change; 3 in `recoverability_simulator.gd` → keep
  base, comment); a new test expands to 6/7 and asserts `_first_empty_discard` and `_pull_matching`
  see the new slot, AND a generator/recoverability test confirms the simulator still reasons at base
  capacity after the refactor.
- **Solvability questioned after expansion.** *Mitigation:* expansion only *adds* buffer capacity;
  it cannot reduce reachability or change the card set / queue, so ADR-0003's invariant is untouched
  (a test asserts `is_solvable` holds after `expand_discard()`).

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| deck-economy.md | Core Rule 11: increment a mutable `_active_discard_slots` + append one `-1` slot; refactor the three `DISCARD_SLOTS` loops; `expand_discard()` uncapped; `WalletService` enforces `MAX_DISCARD_SLOTS`; reset to 5 at level end | Exactly this design |
| deck-economy.md | AC-E01/E06 (expand 5→6, `_discard.size()==6`); AC-E04/EC-07 (at-max blocked); AC-E05/EC-06 (discard-full blocked, purchase-ahead); AC-E03 (reset to 5 next level) | `expand_discard()` + economy-side precondition + per-level reconstruction satisfy each |
| deck-economy.md / ADR-0003 | solvability preserved | Expansion only adds buffer; card set/queue unchanged |

## Performance Implications
- **CPU**: `expand_discard()` is O(1) append; `occupied_discard_count()` O(≤8). Loops unchanged in
  shape, now bounded by `_active_discard_slots` (≤8) instead of a constant 5. Negligible.
- **Memory**: one extra int per `BoardModel` + up to 3 extra `_discard` entries. Trivial.
- **Load Time / Network**: none.

## Migration Plan
1. Add `var _active_discard_slots: int = DISCARD_SLOTS` to `BoardModel`; keep the constant as
   base/reset. (Explicit `: int` annotation per the project's typing standard.)
2. Replace the constant with the field in the three loops (`_init`, `_first_empty_discard`,
   `_pull_matching`). Preserve the `_i` unused-loop-variable prefix in the `_init` seeding loop
   (`for _i in _active_discard_slots`) to keep the linter quiet.
3. Add `expand_discard()`, `active_discard_slots()`, `occupied_discard_count()`.
4. Add a clarifying comment at the three `recoverability_simulator.gd` reads (lines 23/47/103)
   stating they intentionally use the base `DISCARD_SLOTS` (generation-time recoverability is
   evaluated at base capacity, not the runtime-expanded board) — do NOT route them through
   `active_discard_slots()`.
5. Run the full board suite **and** the generator/recoverability suite — both must be green (inert
   at 5).
6. Economy sprint wires the precondition + cap in `WalletService` (this ADR does not modify economy
   files; it only defines the `BoardModel` surface they call).

## Validation Criteria
- Board suite green after the refactor (no diff at 5 slots).
- AC-E01: `expand_discard()` once → `active_discard_slots()==6`, `_discard.size()==6`, last slot `-1`.
- AC-E06: with room (3 of 5 occupied) the economy precondition passes; AC-E05: discard full → blocked;
  AC-E04: at `MAX_DISCARD_SLOTS` → blocked.
- A pull/cascade test with 6–7 slots confirms `_first_empty_discard` and `_pull_matching` honour the
  expanded length.
- `is_solvable` holds after expansion.

## Related Decisions
- ADR-0001 (core purity — cap stays out of `core/`), ADR-0003 (solvability preserved), ADR-0004
  (typed + gdUnit4), ADR-0007 (the "`BoardModel` change re-runs its suite" coupling discipline).
- ADR-0008 (`EconomyEvent`), ADR-0009 (TimeProvider) — sibling Deck Economy ADRs.
- `design/gdd/deck-economy.md` (Core Rule 11, EC-06/07, AC-E01..E06); `core/board_model.gd`.
