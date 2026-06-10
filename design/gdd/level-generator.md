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

[To be designed]

### States and Transitions

[To be designed]

### Interactions with Other Systems

[To be designed]

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
