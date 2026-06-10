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

[To be designed]

## Edge Cases

[To be designed]

## Dependencies

[To be designed]

## Tuning Knobs

[To be designed]

## Acceptance Criteria

[To be designed]

## Open Questions

[To be designed]
