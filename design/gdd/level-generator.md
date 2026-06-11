# Level Generator

> **Status**: Designed — all 8 sections complete, CD gate addressed (S2-001); pending independent `/design-review`
> **Author**: omer.behar + agents (S2-001)
> **Last Updated**: 2026-06-10
> **Implements Pillar**: Content engine — endless, difficulty-scaled, always-solvable levels
> **Creative Director Review (CD-GDD-ALIGN)**: CONCERNS (addressed) 2026-06-10 — the
> "fair to play, not just provably solvable" gap is closed by the recoverability guard
> (Core Rule 10, the knife's-edge edge case, `min_recovery_margin`, AC-32); the
> visible→hidden-target on-ramp and the perceived-recycling-at-depth notes are in Open
> Questions for the M2 playtest.

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
10. **Recoverability guard (fair to play, not just provably solvable).** Solvability
    (Rules 5–6) guarantees a *perfect-play* solution exists; it does **not** bound how
    much slack a *fallible* player has before the discard row fills. The engine's
    `DISCARD_SLOTS` buffer + the PULL mechanic are the recovery mechanism; the generator
    must not deal a board that forces a reasonable player into the discard cap. It bounds
    "forcedness" primarily **by construction** — exposure-independence (Rule 8) means no
    covered-card lock; `D ≤ STACK_COUNT` in early bands keeps every target visible; and
    `max_repeats_per_result ≤ 2` limits buried same-value cards. As a backstop, a
    constructed level is checked for a minimum **recovery margin** (`min_recovery_margin`,
    §Tuning Knobs); a board that fails is re-seeded — the *one* permitted, bounded re-roll
    (a small fixed attempt cap), distinct from solvability which never needs one.
    Determinism is preserved: the re-roll is seed-derived, so the same `(seed, params)`
    always lands on the same final level. *(The exact recoverability metric and
    `min_recovery_margin` value are flagged to ADR-0007 + the game-designer — see Open
    Questions.)*

### States and Transitions

The generator is a pure function with an essentially forward-only pipeline: no
rejection sampling for solvability (it is by construction), and the only loop is the
bounded, deterministic recoverability re-seed of Rule 10 (a backstop that should rarely
fire):

| State | Entry | Exit | Work |
|-------|-------|------|------|
| `INIT` | `generate(params)` | always | validate/clamp params, seed RNG |
| `PICK_RESULTS` | after INIT | always | choose `D` distinct results (Rule 4) |
| `BUILD_QUEUE` | after PICK_RESULTS | always | construct the length-`L` target queue (Rule 5) |
| `BUILD_POOL` | after BUILD_QUEUE | always | emit `3k` cards per result + operands (Rules 6–7) |
| `ASSIGN_SLOTS` | after BUILD_POOL | always | deterministic slot/layer assignment (Rule 8) |
| `VALIDATE` | after ASSIGN_SLOTS | solvable + recoverable → `DONE`; recoverability-fail → re-seed (bounded, Rule 10); solvability-fail → `ERROR` | debug `is_solvable` assert (Rule 9) + recovery-margin check (Rule 10) |
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
- **If a constructed board is a knife's-edge** (< `min_recovery_margin` discard
  headroom under a "route-greedily but make one suboptimal tap" simulation, despite
  being provably solvable): re-seed deterministically and rebuild — the single permitted
  recoverability re-roll (Rule 10), capped at a small fixed number of attempts. If the
  cap is hit (should be vanishingly rare given the construction bounds), fall back to the
  most-recoverable candidate and warn. This protects "recover from a reasonable mistake"
  without touching the solvability guarantee.
- **Schedule-level spike windows (tuning, not generator faults)** — flagged for
  playtest: the `D 4→5` + layout change near level 20, and the first 18-card layout at
  level ~29, are the highest perceived-difficulty steps. The stagger rule (no two
  knobs on one level) and capped deltas mitigate them; if win-rate drops below ~60%
  there, slide the `D` step later or slow the `R_max` slope (data-driven, no code).

## Dependencies

**This system depends on:**

| System | Hard/Soft | Interface |
|--------|-----------|-----------|
| `Layouts` (`core/`) | Hard | `SLOT_COUNTS[layout_id]` (→ queue length) + per-slot `{pos, layer}` geometry |
| `LevelConfig` / `CardData` (`data/`) | Hard | the output types it constructs (`LevelConfig` + `CardData.create`) |
| `LevelData` (autoload) | Hard | `is_solvable` (the invariant gate) + `STACK_COUNT=4` / `STACK_CAPACITY=3`; and the `get_level` dispatch (authored vs. generated — see below) |
| `Exposure` (`core/`) | Soft (invariant) | tappability derives from `pos`/`layer` only, so any slot assignment stays reachable — the generator must not assume otherwise |
| **Difficulty schedule** resource (`assets/data/difficulty_schedule.tres`) | Hard | the `level index N → GeneratorParams` mapping (bands/curves); data-driven, no hardcoded values |
| ADR-0003 (solvability) · ADR-0001 (pure/node-free) · ADR-0004 (typed + gdUnit4) | Hard | architectural constraints the generator is built within |

**Systems that depend on this:**

| System | Direction | Nature |
|--------|-----------|--------|
| `LevelData.get_level(n)` | Depends on this | generates a solvable level for any `n` beyond the authored range |
| Scoring / stars (S2-011) | Depends on this | scores play on generated levels (no direct coupling — levels just feed the board) |
| Operation worlds (M2, future) | Depends on this | each world supplies its own schedule + result domain and reuses the same generator |
| Daily challenge (M3, future) | Depends on this | reuses deterministic seeding for a shared, reproducible level |

**New components/conventions introduced** (registry + ADR candidates):
- `GeneratorParams` — the input record (seed + difficulty params).
- `_has_valid_operand_pair(R, max_operand)` and `_fisher_yates_shuffle(arr, rng)` — pure `core/` helpers.
- `difficulty_schedule.tres` — the data-driven `N → params` config.
- **`level_id = 0` convention** = "generated, not authored" — **needs coordination with
  `LevelData.get_level`** (currently 1-based authored IDs). → captured in the **S2-002
  ADR (ADR-0007)**.

**Reverse references to maintain (bidirectional):**
- `design/systems-index.md` — add a **Level Generator** row (M2 / Content engine). *(added with this GDD)*
- `design/gdd/level-and-solvability.md` — note that levels past the authored set are now generator-produced (still bound by the same invariant).
- `autoloads/level_data.gd` doc comment — document the authored-vs-generated dispatch and `level_id = 0`.
- **ADR-0007** (S2-002) — the construction algorithm, determinism, and the `level_id` dispatch decision.

## Tuning Knobs

All values live in `assets/data/difficulty_schedule.tres` (data-driven per the
gameplay rules — no hardcoded tuning) so a designer can retune via remote config
without an app update.

| Knob | Category | Default / Safe range | Affects · what breaks at the extremes |
|------|----------|---------------------|----------------------------------------|
| `R_max` per band | Curve | 12 → 30 (cap 30) | Result magnitude / cognitive load. Too high → rote recall, not mental math (breaks "calm, sharper-not-strained"); too low → trivial. |
| `R_min` | Curve | 2 (raise to 4–5 late) | Floors triviality. `R_min = 2` allows the "1+1" degenerate (low variety). |
| `D` (distinct results) per band | Curve | 4 → 6, **always ≤ L** | Working-memory load (targets to track). `D > STACK_COUNT(4)` → hidden targets appear only after a clear; `D = 1` → trivial. |
| `max_operand` | Curve | tied to `R_max` | Operand magnitude within a result; narrows/loosens the valid pair set (`span`). Too small → empty candidate pool (error). |
| `layout_cycle` | Gate | `[0, 2, 1, 2]` (late game) | Structural pacing / "new look." Any permutation of `{0,1,2}`. Drives the breather sawtooth (12-card layout ~every 4 levels). |
| `max_repeats_per_result` | Curve | 0 → 2 | Strategic depth (buried same-value cards). > 2 → too many buried cards of one type → perceived unfairness. |
| `knob_stagger_window` | Gate | 4 (range 3–6) | Anti-spike: at most one knob steps per window. Smaller → spikes; the rule is the core fairness guard. |
| Band `level_start` / `level_end` | Gate | per the 5 bands | Session-length pacing; band edges are remote-config tunable. |
| **Win-rate target** per band | Guardrail | 65–80% first-attempt | Below ~60% → too hard (slow the slope / slide the step); above 80% → no challenge. |
| Min interesting `D` per layout | Guardrail | ≥2 (L0), ≥3 (L1/L2) | Prevents the trivial all-one-result board. |
| `min_recovery_margin` | Guardrail | 1–2 discard slots (of `DISCARD_SLOTS=5`) | **Fair-to-play floor** (Core Rule 10): minimum headroom a fallible player has before the discard cap. Higher = more forgiving; 0 = knife's-edge allowed (do not ship). Exact metric → ADR-0007 / playtest. |

**The 5 bands** (starting points for playtest calibration):

| Band | Levels | Layout | `D` | `R_max` | Feel |
|------|--------|--------|-----|---------|------|
| Gentle | 1–12 | 0 (12) | 4 | 12 | all 4 targets visible; small sums; zero memory load |
| Rising | 13–28 | 2 (15) | 4→5 | →16 | first hidden target; slightly bigger sums |
| Flowing | 29–52 | 1 (18) | 5→6 | →20 | full 3-layer depth; memory engaged |
| Cruising | 53–84 | cycle | 5–6 | →~23 | layout rotation; variety is the reward |
| Endless | 85+ | cycle | 5–6 | cap 30 | magnitude plateau; novelty from variety, not bigger sums |

**Variety axes** (all seed-derived, no extra knobs) keep same-band levels fresh:
result-set selection (`C(R_max−R_min, D)` combinations — hundreds to ~376k),
queue-order shuffle (which targets start visible), operand-pair variety, and which
result gets repeated. **Note:** operations (subtraction, ×, ÷) are **worlds**, not an
endless-mode knob — each world ships its own schedule from a lower `R_max`; never mix
operations within one generated level.

## Acceptance Criteria

**Resolutions baked in** (from the QA review): warnings surface via a
`GeneratorResult { config, warnings: Array[String] }` wrapper (recorded in ADR-0007);
the stagger rule is **strict per-level**; AC-13 tests operand *coverage*, not an exact
sequence. `[B]` = BLOCKING (automated logic/integration); `[A]` = ADVISORY (playtest).

**Group 1 — Solvability & determinism**
- **AC-01 [B]** GIVEN 100 seeds (0–99) + valid params, WHEN each is generated, THEN `is_solvable` is `true` for all 100 (the headline property test).
- **AC-02 [B]** Same property loop across all 3 layouts (300 calls) → all solvable.
- **AC-03 [B]** Same `(seed, params)` twice → field-identical `LevelConfig` (queue + every card's fields).
- **AC-04 [B]** Seeds 7 vs 8, else identical → at least one queue entry or card result differs.

**Group 2 — Structure / counts**
- **AC-05 [B]** `card_pool.size()` == `SLOT_COUNTS[layout_id]` (12/18/15).
- **AC-06 [B]** `target_queue.size()` == slot_count/3 (4/6/5).
- **AC-07 [B]** For every result R: `#cards(R) == 3 × queue_count(R)` (the identity, checked independently of `is_solvable`).
- **AC-08 [B]** `layout_slot` values are a permutation of `range(slot_count)` (each slot exactly once).
- **AC-09 [B]** `config.level_id == 0` (generated marker).

**Group 3 — Operands**
- **AC-10 [B]** Every card: `result == operand_a + operand_b`.
- **AC-11 [B]** Every card: `operand_a, operand_b ∈ [1, max_operand]`.
- **AC-12 [B]** Every card's `result ∈ [R_min, R_max]`.
- **AC-13 [B]** For a result R with `span(R) ≥ 2`, the pool contains ≥2 distinct `operand_a` for R (operand variety; coverage form).
- **AC-14 [B]** Forcing `R=2` (`span=1`) → every such card is "1 + 1".

**Group 4 — Clamps & edge cases**
- **AC-15 [B]** `D=10 > L=4` → exactly 4 distinct results + a warning in `result.warnings`.
- **AC-16 [B]** Candidate pool < D → `D_eff = min(L, #candidates)`, warning, config solvable.
- **AC-17 [B]** Empty candidate pool (`R_min=R_max=10, max_operand=4`) → returns `null` + `push_error` (push_error assertion advisory if gdUnit4 cannot spy it).
- **AC-18 [B]** `allow_queue_repeats=false` with `D_eff < L` → queue length L, solvable, promotion warning.
- **AC-19 [B]** A harness that breaks Rules 5–6 (4k cards) → the VALIDATE assert fires; no config returned, no retry (advisory if asserts are stripped in CI).
- **AC-20 [A]** `D=1` → solvable, queue all one result, 12 same-result cards (degenerate but valid).

**Group 5 — Difficulty schedule**
- **AC-21 [B]** `R_max(N)` at N∈{1,12,13,28,29,52,53,84,85,200} == {12,12,12,16,16,20,20,23,23,28}.
- **AC-22 [B]** `R_max(N)` non-decreasing over N=1…200.
- **AC-23 [B]** `R_max(N) ≤ 30` for N=85…1000 (soft cap).
- **AC-24 [B]** `ΔR_max(N,N+1) ∈ {0,1,2}` over N=1…200.
- **AC-25 [B]** `ΔD(N,N+1) ∈ {0,1}` over N=1…200.
- **AC-26 [B]** **Stagger (strict per-level):** at every N, the set of changed knobs among `{R_max, D, layout_id, R_min, max_operand}` has size ≤ 1.
- **AC-27 [A]** Playtest levels 18–22 & 27–31: first-attempt win-rate 55–80% (human).

**Group 6 — Integration (`LevelData.get_level`)**
- **AC-28 [B]** Authored levels 1–3 unchanged (regression guard).
- **AC-29 [B]** `get_level(4)` (past authored) → non-null, `level_id==0`, solvable.
- **AC-30 [B]** `get_level(50)` twice → field-identical.
- **AC-31 [B]** A generated level feeds `BoardModel.from_config` cleanly and a tap on an exposed card returns a non-empty event list (playable end-to-end).

**Group 7 — Recoverability (fair-to-play, Core Rule 10)**
- **AC-32 [B]** GIVEN the seed sweep (AC-01 params), WHEN each generated level is played by a "route-greedily but make exactly one suboptimal/forced tap" simulated player, THEN the player still reaches WIN (never LOSE) — i.e. every level retains ≥ `min_recovery_margin` discard headroom. *(The simulation definition is pinned in ADR-0007; until then this AC is the spec.)*

## Open Questions

- **Warning surface** — adopt a `GeneratorResult { config, warnings: Array[String] }`
  wrapper (vs. `push_warning`)? Leaning yes (testable, no global side-effects). →
  **decide in ADR-0007 (S2-002)**.
- **`level_id = 0` dispatch** — exact `LevelData.get_level(n)` logic for
  authored-vs-generated, and the seed derivation from `n` (e.g. `seed = n`, or a
  hashed/world-salted seed). → **ADR-0007**.
- **Stagger semantics** — resolved here as *strict per-level* (≤1 knob change per
  level); `knob_stagger_window` then governs minimum spacing between steps within a
  band. Confirm this reading holds when the schedule data is authored. → **ADR-0007 /
  schedule data**.
- **More authored layouts (Phase 2)** — open-endedness currently cycles 3 layouts
  `[0,2,1,2]`. Adding layout variants (a `depth_layers` knob, new slot counts) would
  deepen late-game variety; data-driven, no code change. Owner: level-designer, post-M2.
- **Difficulty calibration** — band edges, `R_max` slope, and win-rate targets
  (65–80%) are starting points; real values come from playtest data (AC-27). Owner:
  game-designer, during M2 playtest.
- **Procedural layouts (later)** — should the generator eventually produce its own
  layouts (positions/layers) rather than only choosing among authored presets? Out of
  scope for S2-003; revisit if authored-layout variety becomes the bottleneck.
- **Recoverability metric (CD gate must-fix)** — the exact "k-mistake recoverability"
  simulation and the `min_recovery_margin` value need defining with the game-designer
  and the discard/PULL rules. → **ADR-0007** + M2 playtest. The construction bounds
  (exposure-independence, `D ≤ STACK_COUNT` early, `max_repeats ≤ 2`) are the first line;
  the re-seed backstop and AC-32 are the safety net.
- **Visible→hidden target on-ramp (CD soft note)** — the first hidden target (~level 20,
  Rising band) is a *new cognitive mode* (working-memory hold), not just a bigger number;
  the stagger rule doesn't soften a category change. Consider telegraphing / delaying the
  first hidden target. Owner: game-designer, M2 playtest.
- **Perceived recycling at depth (CD soft note)** — past ~level 300 freshness rests
  entirely on combinatorial variety; the Player Fantasy fears "recycled-feeling" boards.
  Add a perceived-recycling metric to the M2 playtest. Owner: game-designer.
