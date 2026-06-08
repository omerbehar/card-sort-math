# Floor Exposure

> **Status**: Implemented
> **Author**: Reverse-engineered from `core/exposure.gd`, `core/layouts.gd`
> **Last Updated**: 2026-06-08
> **Last Verified**: 2026-06-08
> **Implements Pillar**: Calm-not-frantic (spatial planning)

## Summary

Determines which floor cards are tappable. Cards are placed on layers; a card on
a higher layer that overlaps a lower card "covers" it. A card is **exposed**
(tappable) only once all cards covering it have been removed. This turns a flat
pile into a puzzle of order.

> **Quick reference** — Layer: `Foundation` · Priority: `MVP` · Key deps: `Layouts`

## Overview

A level's layout is an ordered list of placements, each `{pos: Vector2, layer:
int}`. Cards visually overlap; a higher-layer card sitting on top of a lower one
hides part of it. Exposure formalizes this: you can only tap a card nothing is
resting on. As you clear cards, previously buried cards become reachable. Because
coverage only ever points from a higher layer down to a lower one, the relation
is a DAG — clearing top-down always eventually exposes everything, so no card is
permanently trapped.

## Player Fantasy

"I can see the whole pile and plan my route — peel the top, reveal what's
underneath, and work down to the bottom." Calm, readable spatial reasoning, not
hidden information.

## Detailed Design

### Core Rules

- A **placement** is `{pos: Vector2, layer: int}`; its index in the layout array
  is the card's `slot` and stable `card_id`.
- Card dimensions: `CARD_W = 72`, `CARD_H = 96` (a placement's rect is
  `Rect2(pos, Vector2(CARD_W, CARD_H))`).
- **Coverage**: card `H` covers card `L` iff `H.layer > L.layer` **and** their
  rects intersect. `compute_covered_by(placements)` returns `card_id → Array[int]`
  of coverers.
- **Exposed**: `is_exposed(card_id)` is true iff the card is not removed and every
  coverer of it has been removed.
- `exposed_cards(removed, covered_by)` returns all currently-tappable card ids.
- Exposure is **derived, never stored as gameplay state** — it is recomputed from
  the immutable coverage graph plus the current `removed` set.

### Layouts (current presets)

| Layout | Cards | Shape | Used by |
|--------|-------|-------|---------|
| 0 | 12 | 6 base / 4 mid / 2 top (pyramid-ish) | Level 1 |
| 1 | 18 | 8 base / 6 mid / 4 top | Level 2 |
| 2 | 15 | 6 base / 6 mid / 3 top | Level 3 |

`Layouts.SLOT_COUNTS = [12, 18, 15]` lets Level data assert card-pool size
matches the layout.

### Interactions with Other Systems

- **Card Routing & Stacks** calls `is_exposed` before allowing a tap and updates
  the `removed` set when a card leaves the floor.
- **Layouts** is the sole input: change positions/layers and exposure changes for
  free — no separate coverage authoring.

## Formulas

### Coverage test

```
covers(H, L) = (H.layer > L.layer) AND rect(H).intersects(rect(L))
rect(p) = Rect2(p.pos, Vector2(CARD_W, CARD_H))
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| layer | int | 0..N | Layouts | Stacking depth; higher = on top |
| pos | Vector2 | viewport coords | Layouts | Top-left of the card rect |
| CARD_W / CARD_H | float | 72 / 96 | `Layouts` consts | Card footprint |

### Exposed test

```
exposed(c) = (c ∉ removed) AND (∀ k ∈ covered_by[c]: k ∈ removed)
```

**Example**: a top card (layer 2) covers two mid cards; until it is removed those
two report `exposed = false`.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|-------------------|-----------|
| Card with no coverers | Exposed from the start | Top of its column |
| Equal-layer overlap | Not coverage | Coverage requires strictly higher layer (keeps DAG acyclic) |
| Already-removed card | `is_exposed` false | Not on the floor |
| Partial overlap | Counts as coverage | Any rect intersection covers |
| Disconnected card (overlaps nothing) | Always exposed | Reachable immediately |

## Dependencies

| System | Direction | Nature |
|--------|-----------|--------|
| Layouts | This depends on it | Placements (pos + layer) are the only input |
| Card Routing & Stacks | Depends on this | Tappability gate + removal updates |

## Tuning Knobs

| Parameter | Current | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|-----------|--------------------|--------------------|
| `CARD_W` / `CARD_H` | 72 / 96 | layout-dependent | More overlap → more coverage → harder | Less overlap → easier |
| Layout depth (# layers) | 2–3 | 1–4 | Deeper burial → more planning | Shallower → trivial |
| Overlap offset (grid `dx`,`dy`) | per layout | — | Tighter spacing → more coverage | Looser → less |

## Acceptance Criteria

- [x] A card under a higher overlapping card is not exposed until the cover is removed (test_exposure).
- [x] Equal-layer overlap does not create coverage.
- [x] `exposed_cards` returns exactly the not-removed, fully-uncovered cards.
- [x] Coverage graph is acyclic (top-down clearing exposes all cards).
- [ ] Exposure recompute for a full board completes in < 0.5 ms.

## Open Questions

| Question | Owner | Resolution |
|----------|-------|-----------|
| Procedurally generate layouts with guaranteed reachability? | level-designer | Roadmap (Phase 1 generator) |
