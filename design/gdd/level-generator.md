# Level Generator

> **Status**: In Design
> **Author**: omer.behar + agents (S2-001)
> **Last Updated**: 2026-06-10
> **Implements Pillar**: Content engine — endless, difficulty-scaled, always-solvable levels

## Overview

The Level Generator is the content engine that replaces CardSortMath's three
hand-authored levels with an **endless supply of procedurally generated ones**.
Given a level index (and the difficulty knobs that index maps to), it
deterministically produces a complete `LevelConfig` — a floor layout, the ordered
queue of stack targets, and the pool of arithmetic cards dealt onto the floor.
Crucially, every level it emits is **solvable by construction**: the generator
builds the target queue first, then deals *exactly* three cards for each time a
result appears in that queue, so the solvability invariant (`LevelData.is_solvable`,
ADR-0003 — for every result R, `card_count == 3 × occurrences in the queue`) holds
structurally rather than being sampled-and-checked. Because generation is a pure
function of a seed, the same level index always yields the same level — reproducible,
testable, and shareable later for daily challenges. For the player, this is what
turns a 3-level demo into a real game: levels never run out, and difficulty rises
smoothly (operand magnitude, the number of distinct results in play, layout depth)
as they progress — always fair, never unwinnable.

## Player Fantasy

*"I'm getting sharper, and the game always meets me there."*

Each board asks a little more than the last — bigger numbers, more stacks to track
— but it is **always fair and always solvable**, so when the player clears it, the
win is unmistakably *theirs*. Twenty levels in, they solve a board they couldn't
have touched on day one, at the same calm pace, and the feeling isn't "this got
hard" — it's *"I can do this now."* The difficulty curve is felt as a personal
growth curve. This is the brain-training, streak-keeper promise made real: a reason
to return that is **self-improvement, not consumption**.

Two things protect that feeling. First, **fairness is the precondition** (echoing
the Overview's "always fair, never unwinnable"): the moment a board feels cheap,
spiky, or impossible, the player stops crediting their own growth and starts blaming
the game. Second, the **calm never breaks** — the puzzles are an endless, unhurried
stream the player can dissolve into on the bus or in the bath; they look up and
twenty minutes have passed, with no "end of demo," no jarring spike, no board that
feels recycled.

**Anti-goals (do not "juice retention" the wrong way):** the competence loop must be
powered by *felt growth*, never *fear of loss*. No countdown timers, no "don't break
your streak!" guilt, no speed scoring — those import frantic energy and violate the
"calm, not frantic" pillar. Endlessness must feel *open-ended*, not merely
technically infinite (no difficulty plateau that reads as a wall). And "a solution
exists" is not the same promise as "the player can recover from a reasonable
mistake" — generated levels must feel fair to *play*, not just be provably solvable.

## Detailed Design

### Core Rules

1. **Pure & deterministic.** The generator is a node-free `core/` function
   (ADR-0001): `generate(params) -> LevelConfig`. The same `(seed, params)` always
   yields an identical `LevelConfig` — a single seeded `RandomNumberGenerator` is the
   only randomness, consumed in a fixed step order.
2. **Params, not level index.** The generator's input is a `GeneratorParams` record:
   `seed`, `layout_id`, `D` (distinct results), `R_min`/`R_max` (result range),
   `max_operand`, `allow_queue_repeats`. The **difficulty schedule** (§Tuning Knobs)
   maps a level index `N → params`; the generator itself never sees `N`.
3. **Derive the queue length.** `L = Layouts.SLOT_COUNTS[layout_id] / 3` (= 4 / 6 / 5
   for layout 0 / 1 / 2). The card pool must fill every slot, so `#cards == slot_count`
   and `len(target_queue) == L`.
4. **Pick the result set.** Candidate results = integers in `[R_min, R_max]` that have
   at least one operand pair `(a,b)` with `a,b ≥ 1`, `a,b ≤ max_operand`, `a+b = R`.
   Clamp `D` to `min(D, L, #candidates)` (warn if clamped); draw `D` distinct results
   without replacement (seeded).
5. **Build the target queue (length L).** Place one of each chosen result, then fill
   the remaining `L − D` slots with seeded repeats drawn from the chosen set (if
   `allow_queue_repeats = false`, force `D = L`); shuffle. The **first `STACK_COUNT`
   (4) entries are the starting stack targets** — duplicates among them are allowed
   (the engine routes to whichever matching stack has room).
6. **Build the card pool by construction.** For each result `R` appearing `k` times in
   the queue, create **exactly `3k` cards** (`STACK_CAPACITY × k`). This makes the
   solvability invariant *structural*: total cards `= 3L = slot_count`, and
   `#cards(R) = 3 × queue_count(R)` for every `R` (ADR-0003 holds by construction,
   never by filtering).
7. **Choose operands per card.** For result `R`, valid first operands are
   `a ∈ [max(1, R−max_operand), min(max_operand, R−1)]`, with `b = R − a` (see
   §Formulas). Vary `a` across the same-result cards so a board isn't all "1 + 1".
8. **Assign cards to layout slots.** Deterministically shuffle the slot indices and
   assign each card a `layout_slot` + `layout_layer` from the layout geometry.
   Exposure (tappability) derives from position/layer only — independent of which
   result lands where — so every assignment stays reachable (no covered-card lock).
9. **Assemble & self-check.** Return a `LevelConfig` with `level_id = 0` (the
   "generated, not authored" marker). A debug `assert(LevelData.is_solvable(...))` is a
   self-check only — by construction it cannot fail; if it ever does, that's a
   generator bug, not a bad param (surface it, never retry).

### States and Transitions

The generator is a pure function with a forward-only internal pipeline (no retry
loop, no rejection sampling):

| State | Entry | Exit | Work |
|-------|-------|------|------|
| `INIT` | `generate(params)` | always | validate/clamp params, seed RNG |
| `PICK_RESULTS` | after INIT | always | choose `D` distinct results (Rule 4) |
| `BUILD_QUEUE` | after PICK_RESULTS | always | construct the length-`L` target queue (Rule 5) |
| `BUILD_POOL` | after BUILD_QUEUE | always | emit `3k` cards per result + operands (Rules 6–7) |
| `ASSIGN_SLOTS` | after BUILD_POOL | always | deterministic slot/layer assignment (Rule 8) |
| `VALIDATE` | after ASSIGN_SLOTS | pass→`DONE`, fail→`ERROR` | debug `is_solvable` assert (Rule 9) |
| `DONE` | validation passes | — | return `LevelConfig` |
| `ERROR` | empty candidate pool / incoherent params | — | `push_error`, return `null`; caller handles |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Difficulty schedule** (§Tuning Knobs, data resource) | feeds in | `level index N → GeneratorParams` (bands, curves); the only place `N` is interpreted |
| **`LevelData`** (autoload) | calls this | `get_level(n)` returns an *authored* level for `n` within the authored range, else **generates** one seeded by `n` (see §Dependencies for the `level_id` coordination) |
| **`Layouts`** (`core/`) | reads | `SLOT_COUNTS[layout_id]` (queue length) and the per-slot `{pos, layer}` geometry |
| **`Exposure`** (`core/`) | invariant | derives tappability from `pos`/`layer` only; the generator's slot shuffle never affects reachability |
| **`CardData`** | produces | one per slot via `CardData.create(a, b, layer, slot)` (`result = a+b`) |
| **`BoardModel.from_config`** | consumes | accepts the generated `LevelConfig` exactly as it does an authored one |
| **`LevelData.is_solvable`** | verifies | the by-construction guarantee; also the test gate (§Acceptance Criteria) |

## Formulas

### 1. Queue length (from layout)
`L = Layouts.SLOT_COUNTS[layout_id] / 3`

| Var | Type | Range | Description |
|-----|------|-------|-------------|
| `layout_id` | int | {0,1,2} | layout preset |
| `L` | int | {4,6,5} | target-queue length = stack-clears in the level |

Always integer: `SLOT_COUNTS = [12,18,15]`, all divisible by `STACK_CAPACITY = 3`.

### 2. Card count per result (the solvability identity)
`cards(R) = STACK_CAPACITY × queue_count(R) = 3 × queue_count(R)`
`total_cards = Σ_R cards(R) = 3 × L = slot_count`

This *is* ADR-0003 (`is_solvable`), satisfied by construction (Core Rule 6). Output:
`total_cards` always equals the layout's slot count exactly — no padding/trim.

### 3. Operand selection (per card)
For a card with result `R` and within-result index `i` (0-based over its
`3·queue_count(R)` cards):
```
a_min(R) = max(1, R − max_operand)
a_max(R) = min(max_operand, R − 1)
span(R)  = a_max(R) − a_min(R) + 1
operand_a = a_min(R) + (i mod span(R))
operand_b = R − operand_a
```
| Var | Type | Range | Description |
|-----|------|-------|-------------|
| `R` | int | `[R_min, R_max]` | the card's result |
| `max_operand` | int | `1 … R_max` | per-operand cap |
| `a_min, a_max` | int | `1 … R−1` | valid first-operand window |
| `span(R)` | int | `1 … R−1` | # valid first operands |
| `i` | int | `0 … 3·k−1` | within-result index (round-robin over pairs) |
| `operand_a, operand_b` | int | `[1, max_operand]` | the printed addends; `a+b = R` always |

**Output range:** both operands in `[1, max_operand]`; result always exactly `R`.
**Worked example** (`R=7, max_operand=5`): `a_min=2, a_max=5, span=4` → cards read
`2+5, 3+4, 4+3, 5+2`, then wrap. **Degenerate:** `R=2` → `span=1` → always "1 + 1"
(valid, low-variety; raise `R_min` to avoid).

### 4. Valid-result predicate (candidate filter)
`has_valid_pair(R, max_operand) = (max(1, R−max_operand) ≤ min(max_operand, R−1))`

A result is a candidate only if this holds (else no legal addition pair fits the
magnitude cap).

### 5. Distinct-result clamp
`D_eff = clamp(D, 1, min(L, count(candidates)))` — warn the caller when `D_eff < D`.

### 6. Difficulty curve — `R_max(N)` (the schedule's magnitude ramp)
Piecewise, gently-sloped, soft-capped (level index `N`, 1-based):
```
R_max(N) =
  N ≤ 12 : 12                                   (Gentle — fixed)
  N ≤ 28 : 12 + ⌊(N−12)/4⌋                       (Rising → 16)
  N ≤ 52 : 16 + ⌊(N−28)/6⌋                       (Flowing → 20)
  N ≤ 84 : 20 + ⌊(N−52)/10⌋                      (Cruising → ~23)
  N > 84 : min(23 + ⌊(N−84)/20⌋, 30)            (Endless — soft cap 30)
```
| Var | Type | Range | Description |
|-----|------|-------|-------------|
| `N` | int | ≥ 1 | level index |
| `R_max(N)` | int | `12 … 30` | result ceiling for that level |

**Output range:** monotonic non-decreasing, 12→30, plateau at 30 (no wall — variety
past 30 comes from result-set / operand / layout permutation, not bigger sums).
**Constraint:** per-level deltas are capped (`ΔR_max ≤ 2`, `ΔD ≤ 1`) and staggered so
no two knobs step on the same level (see §Tuning Knobs). All coefficients are
data-driven, not hardcoded.

## Edge Cases

- **If `D > L`** (more distinct results requested than queue slots): clamp
  `D_eff = min(D, L)` and warn the caller. The level generates with fewer distinct
  results; nothing breaks.
- **If the candidate pool (valid results in range) is smaller than `D_eff`**: clamp
  `D_eff` down to the pool size and warn.
- **If the candidate pool is empty** (e.g. `R_min=R_max` with no legal operand pair
  under `max_operand`): **hard error** — `push_error` with a diagnostic, return
  `null`. The caller (LevelData) must surface incoherent params; the generator never
  invents a level.
- **If `span(R) == 1`** (only one legal pair, e.g. `R=2` → "1+1"): emit the single
  pair for every card of that result. Valid but low-variety — raise `R_min` (≥ 3) to
  avoid in non-trivial bands.
- **If `allow_queue_repeats == false` but `D_eff < L`** (can't fill `L` distinct slots
  from fewer values): promote to `allow_queue_repeats = true` and warn. The level is
  still correct; the caller should raise `D` or `R_max` to supply more candidates.
- **If `L = 4` and `D = 1`** (degenerate: every card the same result): valid by the
  invariant but trivial. Not a generator bug — guard via a **minimum interesting `D`
  per layout** in the schedule (suggest `D ≥ 2` for layout 0; `D ≥ 3` for layouts 1/2).
- **If the debug `is_solvable` self-check fails in `VALIDATE`**: this is a **generator
  bug**, not a bad param — surface it (assert/crash in debug), never retry and never
  suppress. By construction it cannot happen; if it does, Core Rules 5–6 are broken.
- **If the same `(seed, params)` is generated twice**: the output is byte-identical
  (single seeded RNG, fixed draw order). This is a guarantee, not a hazard — it
  underpins reproducible levels and the determinism test.
- **Schedule-level spike windows (tuning, not generator faults)** — flagged for
  playtest: the `D 4→5` + layout change near level 20, and the first 18-card layout at
  level ~29, are the highest perceived-difficulty steps. The stagger rule (no two
  knobs on one level) and capped deltas mitigate them; if win-rate drops below ~60%
  there, slide the `D` step later or slow the `R_max` slope (data-driven, no code).

## Dependencies

[To be designed]

## Tuning Knobs

[To be designed]

## Acceptance Criteria

[To be designed]

## Open Questions

[To be designed]
