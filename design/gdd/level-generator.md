# Level Generator

> **Status**: **Approved** (2026-06-11) — all 8 sections complete; CD gate addressed (S2-001);
> 4 Open Questions pinned by ADR-0007 (S2-002); independent `/design-review` (NEEDS REVISION)
> addressed — 7 Gate-A + 5 Gate-B items applied and accepted (see `reviews/level-generator-review-log.md`)
> **Author**: omer.behar + agents (S2-001, S2-002, design-review revision)
> **Last Updated**: 2026-06-11
> **Implements Pillar**: Content engine — endless, difficulty-scaled, always-solvable levels
> **Creative Director Review (CD-GDD-ALIGN)**: CONCERNS (addressed) 2026-06-10.
> **Independent /design-review**: NEEDS REVISION (2026-06-11, 5 specialists + CD) — architecture
> sound; Gate-A correctness fixes (empty-pool clamp ordering, canonical `card_pool` sort,
> `GENERATED_ID` sentinel, unified `pick_operands`, pinned `D 4→5 @ N=21`, fixture/AC hardening)
> and Gate-B design fixes (R_max-plateau meta-progression dependency, AC-32 provisional+honest
> reframe, operand-variety accounting, Gentle-band reshape, win-rate retarget) applied this pass.

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

**The long-tail fantasy is a shared responsibility (load-bearing dependency).** The
difficulty curve delivers *in-session* felt growth, but the magnitude axis intentionally
plateaus at `R_max = 30` from level ~85 (skill at mental addition is logarithmic — past 30
a bigger sum is no longer a bigger achievement). Beyond the plateau, the "I'm getting
sharper" signal and the *cross-session* reason to return are carried by the
**meta-progression economy** (XP / player level, stars, operation-world unlocks — see
`docs/GAME_PLAN.md`), not by this generator. This is a deliberate split, but it means the
generator's fantasy is **incomplete on its own**: if the meta-progression layer is not live
by the time players reach the Endless band in volume, the curve reads as the very treadmill
the anti-goals forbid. Recorded as a hard design-level dependency in §Dependencies.

## Detailed Design

### Core Rules

1. **Pure & deterministic.** The generator is a node-free `core/` function
   (ADR-0001): `generate(params) -> GeneratorResult` (the result wraps the
   `LevelConfig` and a `warnings: Array[String]` — see §Open Questions / ADR-0007).
   The same `(seed, params)` always yields an identical `LevelConfig` — a single
   seeded `RandomNumberGenerator` is the only randomness, consumed in a fixed step
   order.
2. **Params, not level index.** The generator's input is a `GeneratorParams` record:
   `seed`, `layout_id`, `D` (distinct results), `R_min`/`R_max` (result range),
   `max_operand`, `allow_queue_repeats`. The **difficulty schedule** (§Tuning Knobs)
   maps a level index `N → params`; the generator itself never sees `N`.
3. **Derive the queue length.** `L = Layouts.SLOT_COUNTS[layout_id] / 3` (= 4 / 6 / 5
   for layout 0 / 1 / 2). The card pool must fill every slot, so `#cards == slot_count`
   and `len(target_queue) == L`.
4. **Pick the result set.** Candidate results = integers in `[R_min, R_max]` that have
   at least one operand pair `(a,b)` with `a,b ≥ 1`, `a,b ≤ max_operand`, `a+b = R`.
   **Guard first:** if `#candidates == 0` (or `max_operand < 1`, or `layout_id ∉ {0,1,2}`),
   this is the hard-error path — `push_error` and return early (Edge Cases); do **not**
   reach the clamp. The empty-pool check MUST precede the clamp, because `clampi(D, 1, 0)`
   returns `1` in Godot (when `min > max` the macro yields `min`), which would otherwise
   draw 1 result from an empty set and crash. Only with `#candidates ≥ 1`: clamp `D` to
   `min(D, L, #candidates)` (warn if clamped); draw `D` distinct results without
   replacement (seeded, Fisher–Yates over the candidate list).
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
8. **Assign cards to layout slots.** Deterministically shuffle the slot indices
   (seeded `_fisher_yates_shuffle`, never `Array.shuffle()`/`pick_random()` — those use
   the global RNG and silently break determinism) and assign each card a `layout_slot` +
   `layout_layer` from the layout geometry. Exposure (tappability) derives from
   position/layer only — independent of which result lands where — so every assignment
   stays reachable (no covered-card lock). **Canonical ordering (determinism-critical):**
   before storing into the `LevelConfig`, sort `card_pool` ascending by `layout_slot`. The
   pool's array order must be a pure function of the final slot assignment, never of RNG
   draw order — otherwise insertion order leaks into `is_solvable`'s Dictionary iteration
   and the recoverability sim's greedy tap order, breaking byte-identical determinism.
9. **Assemble & self-check.** Return a `LevelConfig` with `level_id =
   LevelConfig.GENERATED_ID` (= 0, the "generated, not authored" marker; queryable
   via `is_generated()`) plus provenance (`seed`, `world_id`, `level_index`). A debug `assert(LevelData.is_solvable(...))` is a
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
    always lands on the same final level. The recovery check is an **injected** predicate
    (a function the generator accepts, not a hard-coded call), so the sim is deterministic
    in tests and the cap-exhaustion fallback path is exercisable (AC-34). **This check is a
    *necessary*, not *sufficient*, fairness guarantee:** the greedy + one-mistake sim
    models a fallible player coarsely (it does not capture arithmetic misreads or multiple
    sequential errors), so the *real* fairness gate is the human playtest (AC-27). The
    automated sim ships at a **provisional `min_recovery_margin = 1`** so AC-32 can gate
    merges today; the calibrated value lands at M2.

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
**Guard:** `layout_id` must be in `{0,1,2}`; an out-of-range index is an `INIT` hard error
(`push_error`, return null) — never a silent array out-of-bounds.

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
**Proof both operands stay in range** (so AC-11 holds by construction): `operand_a ∈
[a_min, a_max]`; `operand_b = R − operand_a`. `operand_b ≥ 1` since `operand_a ≤ a_max ≤
R−1`; `operand_b ≤ max_operand` since `operand_a ≥ a_min ≥ R − max_operand`. ∎
**Worked example** (`R=7, max_operand=5`): `a_min=2, a_max=5, span=4` → cards read
`2+5, 3+4, 4+3, 5+2`, then wrap. **Degenerate:** `R=2` → `span=1` → always "1 + 1"
(valid, low-variety; raise `R_min` to avoid).

**Commutative pairs are intentional.** `2+5` and `5+2` are distinct *cards* (the round-robin
emits both) even though they are the same arithmetic *fact*. This is a deliberate
pedagogical choice — seeing both orders reinforces commutativity in a mental-math game — so
the generator does **not** canonicalize `a ≤ b`. Consequence for variety accounting: the
number of distinct *facts* for a result is `⌈span(R)/2⌉`, roughly half the card-face count;
the §Tuning Knobs variety figures are stated in distinct-fact terms.

**Single source of operand truth (no divergence).** Operand selection lives in one pure
helper — `pick_operands(result, index, max_operand) -> Vector2i` — used by **both** the
generator (`index` = within-result index `i`, configured `max_operand`) and the authored
path in `LevelData` (`index` = slot, `max_operand = result − 1` to preserve current
behaviour). This retires the legacy `LevelData._split_operands`, whose `1 + slot %
(result−1)` formula is unbounded by `max_operand` and would otherwise violate AC-11 on a
high-result authored level. Both paths route through `pick_operands`, so they are tested
once and can never diverge.

### 4. Valid-result predicate (candidate filter)
`has_valid_pair(R, max_operand) = (max(1, R−max_operand) ≤ min(max_operand, R−1))`

A result is a candidate only if this holds (else no legal addition pair fits the
magnitude cap).

### 5. Distinct-result clamp
`D_eff = clamp(D, 1, min(L, count(candidates)))` — warn the caller when `D_eff < D`.
**Precondition:** this expression is only evaluated once `count(candidates) ≥ 1` has been
asserted (Core Rule 4). When `count(candidates) == 0`, `min(L, 0) = 0` and Godot's
`clampi(D, 1, 0)` returns `1` (not `0`), so the empty-pool case must be caught *before*
the clamp, never *by* it.

### 6. Difficulty curve — `R_max(N)` (the schedule's magnitude ramp)
Piecewise, gently-sloped, soft-capped (level index `N`, 1-based). The Gentle band is **not
flat** — after a 5-level onboarding plateau it makes two small steps to 12, so the player
sees evidence of growth inside the first session (not 12 unchanging levels):
```
R_max(N) =
  N ≤ 5  : 10                                   (Onboarding — flat, 5 levels)
  N ≤ 12 : min(10 + ⌊(N−4)/2⌋, 12)              (Gentle ramp → 11 at N=6, 12 at N=8)
  N ≤ 28 : 12 + ⌊(N−12)/4⌋                       (Rising → 16)
  N ≤ 52 : 16 + ⌊(N−28)/6⌋                       (Flowing → 20)
  N ≤ 84 : 20 + ⌊(N−52)/10⌋                      (Cruising → ~23)
  N > 84 : min(23 + ⌊(N−84)/20⌋, 30)            (Endless — soft cap 30)
```
| Var | Type | Range | Description |
|-----|------|-------|-------------|
| `N` | int | ≥ 1 | level index |
| `R_max(N)` | int | `10 … 30` | result ceiling for that level |

Continuity check: `R_max(12) = min(10+⌊8/2⌋,12) = 12`, `R_max(13) = 12+⌊1/4⌋ = 12` — no jump.
**Output range:** monotonic non-decreasing, 10→30, plateau at 30. The plateau is
**intentional**: past level 85 the magnitude axis stops and the long-tail progression is
owned by the meta-progression economy (XP / stars / operation-world unlocks), not by bigger
sums — see §Dependencies (hard dependency) and the Player Fantasy note. Per-level variety
past 30 still comes from result-set / operand / layout permutation.
**Constraint:** the formula's actual per-level delta is always `ΔR_max ∈ {0,1}` (every
band steps `+1` at most, never `+2`); `ΔD ∈ {0,1}`. Knobs are staggered so no two step on
the same level (see §Tuning Knobs, and the strict-per-level AC-26). All coefficients are
data-driven, not hardcoded.

## Edge Cases

- **If `D > L`** (more distinct results requested than queue slots): clamp
  `D_eff = min(D, L)` and warn the caller. The level generates with fewer distinct
  results; nothing breaks.
- **If the candidate pool (valid results in range) is smaller than `D_eff`**: clamp
  `D_eff` down to the pool size and warn.
- **If the candidate pool is empty** (e.g. `R_min=R_max` with no legal operand pair
  under `max_operand`): **hard error** — `push_error` with a diagnostic, return
  `null`. This check runs **before** the `D` clamp (Formula 5): `clampi(D,1,0)` would
  otherwise return `1` and draw from nothing. The caller (LevelData) must surface
  incoherent params; the generator never invents a level.
- **If `max_operand < 1` or `layout_id ∉ {0,1,2}`** (incoherent params): **hard error**
  in `INIT` — `push_error`, return `null`. Never a silent array out-of-bounds or an
  all-results-rejected empty pool.
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
| **Meta-progression economy** (XP / player level, stars, operation-world unlocks — `docs/GAME_PLAN.md`) | **Hard (design-level, not code)** | No code coupling (correctly decoupled — the generator never reads progression state), but the generator's long-tail Player Fantasy **requires** this layer to be live before players reach the Endless band (R_max plateau, level ~85+) in volume. Without it, the post-plateau curve is a treadmill. Owner/sequencing: this layer must be scheduled before, or alongside, the Endless band shipping to real players. |

**Systems that depend on this:**

| System | Direction | Nature |
|--------|-----------|--------|
| `LevelData.get_level(n)` | Depends on this | generates a solvable level for any `n` beyond the authored range |
| Scoring / stars (S2-011) | Depends on this | scores play on generated levels (no direct coupling — levels just feed the board) |
| Operation worlds (M2, future) | Depends on this | each world supplies its own schedule + result domain and reuses the same generator |
| Daily challenge (M3, future) | Depends on this | reuses deterministic seeding for a shared, reproducible level |

**New components/conventions introduced** (registry + ADR candidates):
- `GeneratorParams` — the input record (seed, `world_id`, `level_index` + difficulty params), a `RefCounted`.
- `GeneratorResult { config, warnings: Array[String] }` — the output wrapper, a `RefCounted`.
- `pick_operands(result, index, max_operand) -> Vector2i` — the **single** pure operand splitter shared by the generator and the authored `LevelData` path (retires `LevelData._split_operands`).
- `_has_valid_operand_pair(R, max_operand)` and `_fisher_yates_shuffle(arr, rng)` — pure `core/` helpers (never `Array.shuffle()`/`pick_random()`).
- `RecoverabilitySimulator.run(config, mistake_mode)` — pure greedy+1-mistake sim reusing `BoardModel`, with an injected recovery predicate (Core Rule 10 / AC-32 / AC-34).
- `core/difficulty_schedule.gd` — pure `N → params` mapper; takes the schedule **data** (`DifficultyScheduleData extends Resource`, a `RefCounted`) as a typed argument — never a `Node`/autoload — so `core/` stays node-free. `LevelData` is the only layer that `load()`s the `.tres`.
- **`LevelConfig.GENERATED_ID` (= 0) + `is_generated()`** = "generated, not authored",
  with provenance fields (`seed`, `world_id`, `level_index`) on the `LevelConfig`.
  Coordinates with `LevelData.get_level` (1-based authored IDs). → pinned in **ADR-0007**.

**Reverse references to maintain (bidirectional):**
- `design/systems-index.md` — add a **Level Generator** row (M2 / Content engine). *(added with this GDD)*
- `design/gdd/level-and-solvability.md` — note that levels past the authored set are now generator-produced (still bound by the same invariant).
- `autoloads/level_data.gd` doc comment — document the authored-vs-generated dispatch and `LevelConfig.GENERATED_ID` / `is_generated()`.
- **ADR-0007** (S2-002) — the construction algorithm, determinism, and the `level_id` dispatch decision.

## Tuning Knobs

All values live in `assets/data/difficulty_schedule.tres` (data-driven per the
gameplay rules — no hardcoded tuning) so a designer can retune via remote config
without an app update.

| Knob | Category | Default / Safe range | Affects · what breaks at the extremes |
|------|----------|---------------------|----------------------------------------|
| `R_max` per band | Curve | 10 → 30 (cap 30) | Result magnitude / cognitive load. Too high → rote recall, not mental math (breaks "calm, sharper-not-strained"); too low → trivial. |
| `R_min` per band | Curve | 2 → 5 (scheduled per band, see table) | Floors triviality. `R_min = 2` allows the "1+1" degenerate (low variety); raised to 3 from Rising onward to thin out low-`span` repeats. |
| `D` (distinct results) per band | Curve | 4 → 6, **always ≤ L** | Working-memory load (targets to track). `D > STACK_COUNT(4)` → hidden targets appear only after a clear; `D = 1` → trivial. |
| `max_operand` | Curve | tied to `R_max` | Operand magnitude within a result; narrows/loosens the valid pair set (`span`). Too small → empty candidate pool (error). |
| `layout_cycle` | Gate | `[0, 2, 1, 2]` (late game) | Structural pacing / "new look." Any permutation of `{0,1,2}`. Drives the breather sawtooth (12-card layout ~every 4 levels). |
| `max_repeats_per_result` | Curve | 0 → 2 | Strategic depth (buried same-value cards). > 2 → too many buried cards of one type → perceived unfairness. |
| `knob_stagger_window` | Gate | 4 (range 3–6) | Anti-spike: at most one knob steps per window. Smaller → spikes; the rule is the core fairness guard. |
| Band `level_start` / `level_end` | Gate | per the 5 bands | Session-length pacing; band edges are remote-config tunable. |
| **Win-rate target** per band | Guardrail | **75–85% first-attempt** (floor 70%) | Calibrated for a *calm, boosterless brain-training* audience (peers: Lumosity/Peak/Elevate sit ~75–85%), **not** the 65–80% of competitive/booster-driven puzzlers — a 35% fail rate here reads as churn, not retry, and violates the "calm, not frantic" pillar. Below ~70% → too hard (slow the slope / slide the step); above ~88% → no challenge. Re-examine once a booster economy exists (failure then has an economic meaning). |
| Min interesting `D` per layout | Guardrail | ≥2 (L0), ≥3 (L1/L2) | Prevents the trivial all-one-result board. |
| `min_recovery_margin` | Guardrail | **provisional 1** discard slot (of `DISCARD_SLOTS=5`); range 1–2 | **Fair-to-play floor** (Core Rule 10): minimum headroom a fallible player retains before the discard cap, under the AC-32 sim. Ships at the provisional value **1** so AC-32 can gate merges today; the playtest-calibrated value lands at M2. Higher = more forgiving; 0 = knife's-edge (do not ship). |

**The 5 bands** (starting points for playtest calibration):

| Band | Levels | Layout | `D` | `R_min` | `R_max` | Feel |
|------|--------|--------|-----|---------|---------|------|
| Gentle | 1–12 | 0 (12) | 4 | 2 | 10→12 | all 4 targets visible; onboarding flat 1–5, then two small steps (11 @ N6, 12 @ N8) so growth is felt early |
| Rising | 13–28 | 2 (15) | 4, **→5 @ N=21** | 3 | →16 | layout 2 stable from N=13; first hidden target deferred to N=21 (8 stable-layout levels first) |
| Flowing | 29–52 | 1 (18) | 5→6 | 3 | →20 | full 3-layer depth; memory engaged |
| Cruising | 53–84 | cycle | 5–6 | 4 | →~23 | layout rotation; variety is the reward |
| Endless | 85+ | cycle | 5–6 | 5 | cap 30 | magnitude plateau (intentional); long-tail progression owned by meta-progression, novelty from variety |

**Stagger pin (determinism-critical for AC-26):** the `D 4→5` step is fixed at **level 21**,
never at a band boundary. This keeps it off N=29 (where layout steps 2→1) so no two knobs
ever change on the same level. The step is also ≥8 levels after the layout-2 introduction
(N=13), so the player meets the new *spatial* layout and the new *cognitive mode* (hidden
target) as two separated events, not one compound spike. `R_min` raises one step per band
edge as shown; it is a scheduled knob like the others (subject to the same strict stagger).

**Variety axes** (all seed-derived, no extra knobs) keep same-band levels fresh:
result-set selection, queue-order shuffle (which targets start visible), operand-pair
variety, and which result gets repeated. **Honest accounting:** the result-set combination
count is `C(#candidates, D)` where `#candidates` is the number of valid results in
`[R_min, R_max]` (≤ `R_max − R_min + 1`, and smaller when `max_operand` excludes high-end
results) — *not* a fixed "~376k". It ranges from ~210 in the Gentle band to a low-six-figure
ceiling only at the top of Endless. Crucially, *combinatorial* variety ≫ *perceived*
variety: the player reads card faces, whose distinct-fact count per result is `⌈span(R)/2⌉`
(commutative pairs are the same fact). Past ~level 300 this perceived-variety ceiling — not
the combinatorial one — is what the "never recycled-feeling" promise rests on; it is tracked
as an explicit M2 playtest metric (Open Questions), and the long-tail freshness backstop is
the meta-progression layer and future operation worlds, not bigger combinatorics. **Note:** operations (subtraction, ×, ÷) are **worlds**, not an
endless-mode knob — each world ships its own schedule from a lower `R_max`; never mix
operations within one generated level.

## Acceptance Criteria

**Resolutions baked in** (from the QA review): warnings surface via a
`GeneratorResult { config, warnings: Array[String] }` wrapper (recorded in ADR-0007);
the stagger rule is **strict per-level**; AC-13 tests operand *coverage*, not an exact
sequence. `[B]` = BLOCKING (automated logic/integration); `[A]` = ADVISORY (playtest).

**Canonical test fixtures** (shared helper `tests/unit/generator/generator_fixtures.gd`; every
AC that says "valid params" means one of these — no ad-hoc param sets):
- `VALID_PARAMS_LAYOUT_0 = { layout_id=0, D=4, R_min=3, R_max=12, max_operand=6, allow_queue_repeats=true }`
  (guarantees R=7 with `span(7)=4` and R=3 with `span(3)=2` appear in candidates, so AC-13 is non-vacuous)
- `VALID_PARAMS_LAYOUT_1 = { layout_id=1, D=5, R_min=3, R_max=16, max_operand=8, allow_queue_repeats=true }`
- `VALID_PARAMS_LAYOUT_2 = { layout_id=2, D=4, R_min=3, R_max=14, max_operand=7, allow_queue_repeats=true }`

**Prerequisite artifact:** `assets/data/difficulty_schedule.tres` (and its `DifficultyScheduleData`
resource type) must exist before the Group 5 schedule ACs can run; create the skeleton with the
band table values in S2-003 before authoring those tests.

**Group 1 — Solvability & determinism**
- **AC-01 [B]** GIVEN `VALID_PARAMS_LAYOUT_0`, WHEN `generate(seed, params)` runs for `seed ∈ [0,99]`, THEN `result.config` is non-null and `is_solvable(result.config)` is `true` for all 100 (the headline property test).
- **AC-02 [B]** Same loop for all three canonical fixtures (300 calls) → all non-null and solvable.
- **AC-03 [B]** Same `(seed, params)` twice → field-identical `LevelConfig` (queue + every card's fields, in the same array order — see AC-08 canonical ordering).
- **AC-04 [B]** Seeds `{0,1,7,8,42,43,99,100}` with `VALID_PARAMS_LAYOUT_0` → all 8 `target_queue` arrays mutually distinct (no seed collision; stronger than a single 7-vs-8 pair).

**Group 2 — Structure / counts**
- **AC-05 [B]** `card_pool.size()` == `SLOT_COUNTS[layout_id]` (12/18/15).
- **AC-06 [B]** `target_queue.size()` == slot_count/3 (4/6/5).
- **AC-07 [B]** For every result R: `#cards(R) == 3 × queue_count(R)` (the identity, checked independently of `is_solvable`).
- **AC-08 [B]** `layout_slot` values are a permutation of `range(slot_count)` (each slot exactly once), **and** `card_pool` is sorted ascending by `layout_slot` (canonical ordering — `card_pool[i].layout_slot == i`), so array order is independent of RNG draw order.
- **AC-09 [B]** `config.is_generated()` is `true` and `config.level_id == LevelConfig.GENERATED_ID` (= 0).

**Group 3 — Operands**
- **AC-10 [B]** Every card: `result == operand_a + operand_b`.
- **AC-11 [B]** Every card: `operand_a, operand_b ∈ [1, max_operand]`.
- **AC-12 [B]** Every card's `result ∈ [R_min, R_max]`.
- **AC-13 [B]** GIVEN `VALID_PARAMS_LAYOUT_0`: the cards for R=7 (`span=4`) show ≥2 distinct `operand_a`, and across R=3's three cards (`span=2`) exactly 2 distinct `operand_a` appear — i.e. the round-robin reaches `min(span(R), 3·queue_count(R))` distinct first-operands (not a stuck `i=0`).
- **AC-14 [B]** Forcing `R=2` (`span=1`) → every such card is "1 + 1".

**Group 4 — Clamps & edge cases**
- **AC-15 [B]** `D=10 > L=4` → exactly 4 distinct results + a warning in `result.warnings`.
- **AC-16 [B]** Candidate pool < D → `D_eff = min(L, #candidates)`, warning, config solvable.
- **AC-17a [B]** Empty candidate pool (`R_min=R_max=10, max_operand=4`) → `generate` returns `null` (the guard fires *before* the clamp; no crash). Asserted on the return value.
- **AC-17b [A]** Same params → `push_error` is called with a diagnostic containing "candidate"/"pool" (advisory — `push_error` is not spy-able in headless gdUnit4; verify in debug output).
- **AC-17c [B]** `max_operand = 0` and `layout_id = 3` (out of `{0,1,2}`) each → `generate` returns `null` (invalid-param guards, INIT state).
- **AC-18 [B]** `allow_queue_repeats=false` with `D_eff < L` → queue length L, solvable, promotion warning.
- **AC-19a [B]** A pure `_validate_pool(config)` helper, GIVEN a `LevelConfig` with 4 cards for a result that appears once in the queue (invariant broken), returns `false` (tests the validation logic without relying on `assert()` or process death).
- **AC-19b [A]** In a debug build, `generate` with params engineered to break Rules 5–6 terminates on the `assert` rather than returning a bad config (advisory — `assert` is stripped in release CI; manual debug-build check at each milestone).
- **AC-20 [B]** `D=1` (`{layout_id=0, D=1, R_min=5, R_max=5, max_operand=3}`) → non-null, solvable, `target_queue` all 5, 12 cards all `result==5` (degenerate but valid by construction — promoted to BLOCKING since the generator must handle it).

**Group 5 — Difficulty schedule** *(require `difficulty_schedule.tres` to exist)*
- **AC-21 [B]** `R_max(N)` at N∈{1,5,6,8,13,16,28,29,52,53,84,85,200} == {10,10,11,12,12,13,16,16,20,20,23,23,28} (pins the onboarding plateau, both Gentle steps, and the first step inside each later segment — not only band boundaries).
- **AC-22 [B]** `R_max(N)` non-decreasing over N=1…200.
- **AC-23 [B]** `R_max(N) ≤ 30` for N=85…1000 (soft cap).
- **AC-24 [B]** `ΔR_max(N,N+1) ∈ {0,1}` over N=1…200 (the formula never steps by 2; the tighter bound catches future slope drift).
- **AC-25 [B]** `ΔD(N,N+1) ∈ {0,1}` over N=1…200.
- **AC-26 [B]** **Stagger (strict per-level):** at every consecutive (N, N+1), the set of changed knobs among `{R_max, D, layout_id, R_min, max_operand}` has size ≤ 1. In particular the `D 4→5` step occurs at N=21 (not 29) and the schedule has no level where two knobs change — verified against `difficulty_schedule.tres`.
- **AC-27 [A]** Playtest the transition levels (onboarding 4–8, first hidden target 19–23, first 18-card layout 27–31): first-attempt win-rate within 70–85% (human). **Rollback rule:** if levels 19–23 fall below 65%, slide the `D 4→5` step from N=21 toward N=25 (schedule-data change, no code) and re-test.

**Group 6 — Integration (`LevelData.get_level`)**
- **AC-28 [B]** Authored levels 1–3 unchanged (regression guard) **and** `is_generated()` is `false` for each (the GENERATED_ID sentinel does not collide with authored configs).
- **AC-29 [B]** `get_level(4)` (past authored) → non-null, `is_generated()`, solvable.
- **AC-30 [B]** `get_level(50)` twice → field-identical.
- **AC-31 [B]** A generated level feeds `BoardModel.from_config` cleanly and a tap on an exposed card returns a non-empty event list (playable end-to-end).

**Group 7 — Recoverability (fair-to-play, Core Rule 10)**
- **AC-32 [B]** GIVEN the AC-01/AC-02 canonical seed sweep, WHEN each level is run through `RecoverabilitySimulator.run(config, mistake_mode=FORCED_DISCARD_ONCE)` — greedy routing with exactly one forced discard (on turn `⌊L/2⌋`, discard the exposed card with the lowest result instead of stacking) reusing `BoardModel` — THEN the sim reaches WIN with `discard_headroom ≥ min_recovery_margin` (**provisional 1**). This is a *necessary, not sufficient* fairness check (it coarsely models human error); the real gate is the AC-27 human playtest. The provisional threshold gates merges now; the calibrated value replaces it at M2.
- **AC-33 [B]** GIVEN a generated level with `D == STACK_COUNT (4)`, the first 4 `target_queue` entries (the starting stack targets, Core Rule 5) are all distinct and are exactly the chosen result set — no hidden starting target when `D=4`.
- **AC-34 [B]** GIVEN an injected recovery-check stub that always returns `false` (every re-seed "fails"), `generate` still returns a non-null, solvable `LevelConfig` (the most-recoverable fallback after the attempt cap) and `result.warnings` records that the cap was hit.
- **AC-35 [B]** GIVEN `generate` with `world_id=1, level_index=7, seed=42`, the returned `config` carries `seed==42`, `world_id==1`, `level_index==7` (provenance round-trips for daily-challenge reuse).

## Open Questions

- **Warning surface** — **RESOLVED (ADR-0007):** adopt a
  `GeneratorResult { config, warnings: Array[String] }` wrapper (a `RefCounted`),
  not `push_warning` — testable and free of global side-effects.
- **Generated-marker & seed dispatch** — **RESOLVED (ADR-0007):** the generated
  marker is `LevelConfig.GENERATED_ID` (= 0) via `is_generated()`, with provenance
  fields (`seed`, `world_id`, `level_index`) carried on the `LevelConfig`. The seed
  is an explicit integer `world_id * WORLD_STRIDE + level_index` (`WORLD_STRIDE =
  1_000_000`) — **not** `hash()`, which is implementation-defined and unstable
  across Godot versions/platforms. `LevelData.get_level(n)` returns the authored
  level for `n` in range, else generates one seeded by that formula.
- **Stagger semantics** — **RESOLVED (ADR-0007):** *strict per-level* (≤1 knob
  change per level); `knob_stagger_window` governs minimum spacing between steps
  within a band. The `N → params` mapping is computed by the pure
  `core/difficulty_schedule.gd` from `assets/data/difficulty_schedule.tres`
  (the generator never `load()`s the resource itself).
- **More authored layouts (Phase 2)** — open-endedness currently cycles 3 layouts
  `[0,2,1,2]`. Adding layout variants (a `depth_layers` knob, new slot counts) would
  deepen late-game variety; data-driven, no code change. Owner: level-designer, post-M2.
- **Difficulty calibration** — band edges and `R_max` slope are starting points; real
  values come from playtest data (AC-27). The win-rate target was **retargeted to 75–85%
  (floor 70%)** for the calm/boosterless audience (was 65–80% — see §Tuning Knobs). A
  heuristic cognitive-load model `CL(N)` (weighting the orthogonal `R_max` recall axis and
  `D` working-memory axis) would make the schedule falsifiable *before* playtest — a
  recommended addition. Owner: game-designer + economy-designer, during M2 playtest.
- **Procedural layouts (later)** — should the generator eventually produce its own
  layouts (positions/layers) rather than only choosing among authored presets? Out of
  scope for S2-003; revisit if authored-layout variety becomes the bottleneck.
- **Recoverability metric** — **RESOLVED (ADR-0007); threshold provisional:** the metric is
  a pure greedy + 1-mistake simulation reusing `BoardModel` via an **injected** recovery
  predicate (so the sim is deterministic and the fallback path is testable — AC-34). It is a
  *necessary, not sufficient* fairness check; the human playtest (AC-27) is the real gate. A
  failing board is re-seeded deterministically (`base_seed + attempt × 7919`) and rebuilt —
  the one permitted, bounded re-roll (Rule 10). `min_recovery_margin` **ships at the
  provisional value 1** so AC-32 gates merges now; the calibrated value lands at M2.
  Construction bounds (exposure-independence, `D ≤ STACK_COUNT` early, `max_repeats ≤ 2`) are
  the first line; the re-seed backstop and AC-32 are the safety net. *(A future enhancement
  could add a greedy + 2-mistake / arithmetic-misread sim mode for a stronger automated
  guarantee — deferred; AC-27 covers it for now.)*
- **Visible→hidden target on-ramp** — **ADDRESSED (schedule pin):** the first hidden target
  is deferred to **N=21**, ≥8 levels after the layout-2 introduction (N=13), so the new
  *spatial* layout and the new *cognitive mode* are separated events, not one compound spike;
  AC-27 carries a rollback rule (slide toward N=25 if win-rate dips). A telegraph/coaching
  beat at the first `D > STACK_COUNT` level is recommended for the UX layer (out of this
  GDD's scope; owner: ux-designer / game-designer, M2).
- **Perceived recycling at depth** — past ~level 300 freshness rests on *perceived* variety
  (span-limited, ≈half the combinatorial count — see §Tuning Knobs), not raw combinatorics;
  the long-tail freshness backstop is the **meta-progression layer + operation worlds** (now
  a hard design-level dependency, §Dependencies). Add a perceived-recycling metric (e.g.
  proportion of levels 100–200 sharing ≥3 card faces with a board in the prior 10 levels) to
  the M2 playtest. Owner: game-designer.
- **Meta-progression sequencing (strategic, resolved by user)** — the R_max=30 plateau is
  **intentional**; the long-tail "I'm getting sharper" signal is owned by meta-progression
  (XP/stars/operation-world unlocks), which must be live before players reach the Endless band
  in volume. This is a hard dependency, not an open question — but the *meta-progression GDD/ADR
  itself* is still unwritten and is the gating prerequisite for the Endless band shipping.
