# ADR-0012: Replace the Hint booster with the Picker booster — `pick_card()` / `use_picker()`, drop `hint_score`

## Status
Accepted (2026-06-13 — ratifies the M3-review action item #2 "Record Hint→Picker decision as
an ADR"; story S4-000 of Sprint 4. Records a design change already implemented in commits 9149eec
and 82ac588 and synced into the GDD / registry / UX docs on 2026-06-15). Acceptance rests on the
approved `design/gdd/deck-economy.md` (Core Rule 8 rewritten as Picker) + the author's go-ahead.

**Authored note (2026-06-15):** this ADR is written retroactively to document a decision taken
and shipped on 2026-06-13. The code (`BoardModel.pick_card`, `WalletService.use_picker`) and the
removals (`hint_score`, `HINT_RESULT`, the Hint cost/weight knobs) already landed; the design docs
were brought into line on 2026-06-15. Nothing here proposes new code — it captures the *why*.

## Date
2026-06-13

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Economy |
| **Knowledge Risk** | LOW — pure GDScript; `pick_card` reuses the existing `_resolve_play` path, `use_picker` reuses the existing `spend` seam; no engine APIs |
| **References Consulted** | `design/gdd/deck-economy.md` (Core Rule 8/12, Formula 5 struck, AC-P01..P05, AC-M01a/b, EC-08); `core/board_model.gd` (`pick_card`, `_resolve_play`, `is_card_removed`); `autoloads/wallet_service.gd` (`use_picker`, `use_picker_from_stock`, `_picker_target_valid`, `_activate_picker`); `core/economy_enums.gd` (`BoosterType`, `FailReason`); `design/registry/entities.yaml`; `design/ux/booster-icons.md`; commits b20aaa0 (Hint), 9149eec + 82ac588 (Picker); ADR-0008 (`EconomyEvent`), ADR-0009 (TimeProvider) |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Full gdUnit4 suite green (433/433 at the change); AC-P01..P05 + AC-M01a asserted in `tests/test_wallet_service.gd` and `tests/test_board_model_picker_reshuffle.gd`; no `EconomyEvent` payload carries a `result`/operands/`solution_text` field (AC-M01a). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (model/view + core purity — the booster acts on board state, never the equation), ADR-0002 (event-sourced replay — a pick resolves to ordinary board `GameEvent`s), ADR-0008 (`EconomyEvent` type — Picker emits `BOOSTER_ACTIVATED` / `BOOSTER_PRECONDITION_FAILED`, not a result-bearing event) |
| **Enables** | A direct, player-driven "dig" booster with no scoring heuristic to tune; the prototype buff-inventory `use_picker_from_stock` path |
| **Blocks** | Nothing — supersedes the Hint design (S3-007); Hint code was removed in the same change |
| **Supersedes** | The Hint booster (S3-007, commit b20aaa0): `core/hint_score.gd` (Formula 5), `WalletService.use_hint` / `notify_hint_consumed`, `EconomyEvent.HINT_RESULT`, the `ROUTES_/OPENS_/RELIEF_WEIGHT` and `HINT_COST_*` knobs, and `FailReason.ALREADY_IN_PROGRESS` / `NO_EXPOSED_CARD` |

## Context

### Problem Statement
The Hint booster (S3-007, commit b20aaa0) was the first booster built on the `WalletService`
spend seam. It computed a **scored highlight**: `core/hint_score.gd` implemented Formula 5,
`score = routes_directly × ROUTES_WEIGHT + opens_new_cards × OPENS_WEIGHT + discard_relief ×
RELIEF_WEIGHT`, and `best_card()` returned the single highest-scoring card (deterministic
lowest-`card_id` tie-break). `use_hint(board)` emitted `HINT_RESULT(card_id)` for the view to
surface that card to the player.

By design the Hint never emitted an arithmetic *answer* — it returned a `card_id` only (the
original AC-M01a). But it **selected and surfaced the best card for the player to act on**. That
is the routing decision the game otherwise asks the player to make by computing the equation and
matching the result. A booster that ranks cards by "which routes / opens / relieves best" is one
heuristic away from doing the player's thinking — it drifts toward the project's single hardest
constraint:

> **No booster/power-up that auto-solves the arithmetic (guts the core value prop).**
> — `CLAUDE.md` Forbidden Patterns

The CD-GDD-ALIGN review already flagged this as an accepted concern ("Hint routing-info leak —
acknowledged as intentional, note added", `design/gdd/deck-economy.md` Status block). The M3
review action item #2 asked to revisit and record the resolution.

### Constraints
- **The no-arithmetic-solving pillar is non-negotiable** (`CLAUDE.md`; GDD Core Rule 12;
  AC-M01a/b/M02). A booster may relax board/coverage constraints but must never compute, reveal,
  rank-by, or auto-route on a card's `result`.
- **Model/view split (ADR-0001).** The booster must act on `BoardModel`, emit board `GameEvent`s,
  and carry no tuning into `core/`.
- **The spend seam (ADR-0008) is fixed.** Any replacement must route through `WalletService.spend`
  with a precondition-before-spend ordering so a rejected use never charges.

### Requirements
- A booster that lets a player reach a **covered (lower-layer)** card — the one thing the base
  coverage rule forbids — **without** touching the arithmetic.
- No scoring heuristic: the *player* decides which card, so there is nothing to compute or tune.
- Drop-in on the existing economy surface (same precondition→spend→activate→emit shape as
  Reshuffle / Extra Discard).

## Decision

**Replace Hint with Picker.** The Picker plays a covered card *the player chose*, bypassing the
coverage rule; it carries **no scoring** and reveals **no answer**.

1. **`core/board_model.gd` — `pick_card(card_id)`** (board_model.gd:193). Plays a card regardless
   of coverage by **reusing the exact tap resolution** (`_resolve_play`, board_model.gd:277) minus
   the exposure precondition. Resolution is identical to a tap — route to a matching open stack,
   else discard, then cascade — so a pick is just a tap that skips the `is_exposed` check. A no-op
   when the card is already removed (`is_card_removed`) or the game is over. The booster is the
   only way to act on a not-yet-exposed card. No new arithmetic; determinism inherited from the
   deterministic board.

2. **`autoloads/wallet_service.gd` — `use_picker(board, card_id)`** (wallet_service.gd:521).
   Precondition→spend→activate, in order (no spend before a precondition fails):
   - `_picker_target_valid(board, card_id)` — board live and card still on the floor, else
     `BOOSTER_PRECONDITION_FAILED(PICKER, INVALID_TARGET)` (EC-08), no spend.
   - `spend(COINS, _config.picker_cost_coins)` — insufficient funds emits `SPEND_FAILED`, no play.
   - `_activate_picker` — increments `boosters_used_this_level`, calls `board.pick_card(card_id)`,
     emits `BOOSTER_ACTIVATED(PICKER)`, returns the board `GameEvent`s for the view.
   The prototype buff-inventory path `use_picker_from_stock` consumes one owned Picker instead of
   coins (`NO_STOCK` on empty), then shares `_activate_picker`.

3. **`core/economy_enums.gd`** — `BoosterType.HINT` → `BoosterType.PICKER`; `FailReason` gains
   `INVALID_TARGET` (Picker's only precondition) and drops `ALREADY_IN_PROGRESS` / `NO_EXPOSED_CARD`
   (the Hint had an in-progress/await-selection state; the Picker plays immediately, so neither
   exists).

4. **Removed entirely** (commits 9149eec + 82ac588): `core/hint_score.gd` (Formula 5) and its
   tests; `WalletService.use_hint` / `notify_hint_consumed` and `_hint_in_progress`;
   `EconomyEvent.HINT_RESULT` **kind** *and its `card_id` payload field*; the `EconomyConfig`
   `hint_cost_*` costs and `routes_/opens_/relief_weight` knobs; `BoardModel.newly_exposed_count`
   was retained only where still used by other systems.

5. **Cost knobs renamed `HINT_*` → `PICKER_*`** in `design/registry/entities.yaml`:
   `PICKER_COST_COINS = 120` (was `HINT_COST_COINS`), `PICKER_COST_GEMS = 3` (was
   `HINT_COST_GEMS`); the `ROUTES_/OPENS_/RELIEF_WEIGHT` scoring knobs are struck.

**The load-bearing distinction.** Hint *chose the card for you* (a scored routing decision, the
player's job). Picker *plays the card you chose* (a coverage relaxation, never the player's job).
Both never emit an answer — but only Picker also never makes the routing decision. The Picker
relaxes the **coverage/stacking** constraint and leaves the **mental-math computation** wholly to
the player, so the core value prop is structurally protected, not just heuristically tuned away
from the line.

### Why this satisfies the hard constraint
`board.pick_card` resolves to route/discard `GameEvent`s and nothing else; `_activate_picker`
emits only `BOOSTER_ACTIVATED(PICKER)`. No code path reads `CardData.result` to decide the
booster's effect — the player supplies `card_id` by their own arithmetic. The `EconomyEvent`
class has **no** `result` / operands / `solution_text` field for a pick to populate (AC-M01a).

## Alternatives Considered

### Alternative 1: Keep Hint, only stop emitting the answer
- **Description**: Retain the scored `best_card()` highlight; it already returned a `card_id`, not
  a result.
- **Cons**: The leak was never the *answer* — it was the **routing decision**. A scored "best
  card" highlight still does the player's thinking; tuning the weights only moves the line, it
  doesn't remove it.
- **Rejection Reason**: Fails the spirit of the no-arithmetic-solving pillar; leaves a heuristic
  that must be perpetually defended at design review.

### Alternative 2: Re-tune the Hint weights to be "weak"
- **Description**: Lower `ROUTES_/OPENS_/RELIEF_WEIGHT` so the hint is less decisive.
- **Cons**: Still a scoring function (cost to tune, test, and defend); "weak" is subjective and
  drifts; the player still receives a system-chosen card.
- **Rejection Reason**: Replaces a clear rule with a balancing act; the Picker removes the
  heuristic entirely (nothing to tune).

### Alternative 3: A "reveal any covered card's value" booster
- **Description**: Let the player peek a covered card's printed equation/result.
- **Cons**: Revealing a card's computed *result* is exactly the forbidden pattern; even revealing
  only the equation pulls the booster toward an information-advantage that erodes the math loop.
- **Rejection Reason**: Directly violates `CLAUDE.md` Forbidden Patterns / AC-M01b.

## Consequences

### Positive
- The Picker relaxes only **coverage**; the player still computes every result, so the
  no-arithmetic-solving pillar is structurally protected (no heuristic to police).
- No scoring function to author, test, balance, or defend — `Formula 5` and three weight knobs are
  deleted, shrinking the economy's tuning surface.
- `pick_card` reuses `_resolve_play`, so a pick behaves *byte-identically* to a tap (route /
  discard / cascade) and inherits the board's determinism and its existing test coverage.
- The Picker plays immediately, eliminating the Hint's in-progress/await state and its
  `ALREADY_IN_PROGRESS` failure path (simpler precondition surface: one reason, `INVALID_TARGET`).

### Negative / accepted trade-offs
- **Breaking change to the `EconomyEvent` kind set**: `HINT_RESULT` was removed from
  `EconomyEnums.EconomyEvent` values **along with its `card_id` payload field** — any subscriber
  matching on `HINT_RESULT` must be updated. Accepted: only the (now-deleted) Hint path and its
  tests emitted/consumed it; no persisted save data references it. (Documented in
  `design/registry/entities.yaml`: `# HINT_RESULT removed 2026-06-13`.)
- **Cost-knob rename `HINT_* → PICKER_*`**: any external reference to `HINT_COST_COINS` /
  `HINT_COST_GEMS` breaks. Accepted: the values are unchanged (120 coins / 3 gems); only the names
  moved, and `EconomyConfig` is the single source.
- **No answer / operands are ever revealed** — by construction. The Picker plays a card the player
  already chose *by their own arithmetic*; no `EconomyEvent` carries a result/operands/solution
  field, so there is nothing to leak (AC-M01a). This is a property, listed here for completeness,
  not a regression.

### Risks
- **A stale subscriber on `HINT_RESULT`** silently never fires. *Mitigation:* the enum value is
  gone, so any `match` arm referencing it is a compile/parse error or dead branch caught in
  review; the full suite (433/433) is green after removal.
- **A future booster re-introduces scoring/auto-routing.** *Mitigation:* AC-M02 makes any booster
  that must read `CardData.result` to determine its effect a design-review rejection; this ADR is
  the precedent.

### Documentation sync (already completed, 2026-06-15)
The implementation landed 2026-06-13 (9149eec) with a known follow-up: the GDD and registry still
described Hint. The sync pass shipped in 82ac588 and was finalised 2026-06-15:
- `design/gdd/deck-economy.md`: Core Rule 8 rewritten as Picker; Formula 5 struck ("§5 Hint
  scoring function — REMOVED"); Hint weight knobs struck; booster-set / cost / event / UI / EC-01 /
  EC-08 / tutorial references updated; AC-H* replaced by AC-P01..P05; AC-M01a/b restated for Picker.
- `design/registry/entities.yaml`: `hint_score` and `ROUTES_/OPENS_/RELIEF_WEIGHT` removed;
  `HINT_COST_*` → `PICKER_COST_*`; `HINT_RESULT` dropped from the `EconomyEvent` values.
- `design/ux/booster-icons.md`: the booster table and per-icon concept now describe Picker ("a
  downward finger/pointer passing through layer-bars"), the armed state, and `arm_picker()` wiring.

## GDD Requirements Addressed

| GDD System | Requirement | How addressed |
|------------|-------------|---------------|
| deck-economy.md | Core Rule 8 (Picker replaces Hint): player selects a covered card, played immediately (route/discard), bypassing coverage; access not answers | `BoardModel.pick_card` + `WalletService.use_picker` |
| deck-economy.md | Core Rule 12 (no booster touches arithmetic) | Pick resolves to board `GameEvent`s only; no `result` read or emitted |
| deck-economy.md | AC-P01..P05 (route / discard / invalid-target / insufficient-funds / no-arithmetic) | `use_picker` precondition→spend→activate; `_picker_target_valid` (EC-08); `_resolve_play` reuse |
| deck-economy.md | AC-M01a (no economy event carries result/operands/solution) | `EconomyEvent` has no such field; pick emits `BOOSTER_ACTIVATED` only |
| CLAUDE.md Forbidden Patterns | "No booster that auto-solves the arithmetic" | Picker removes the scored card-selection (Hint) that drifted toward it |

## Validation Criteria
- Full gdUnit4 suite green (433/433 at the change); the deleted `test_hint_score.gd` is gone and
  no test references `HINT_RESULT` / `use_hint`.
- AC-P01: a covered card matching an open stack → routed, `BOOSTER_ACTIVATED(PICKER)`, 120 coins
  spent, board `GameEvent`s returned.
- AC-P02: a covered card with no matching stack → played to discard (or LOSE if discard full),
  same resolution as a tap, coverage bypassed only.
- AC-P03: target already removed / board over → `BOOSTER_PRECONDITION_FAILED(PICKER,
  INVALID_TARGET)`, coins unchanged.
- AC-P04: coins < `PICKER_COST_COINS` → `SPEND_FAILED`, no play, `boosters_used_this_level`
  unchanged.
- AC-P05 / AC-M01a: a pick emits no `result`/operands/solution — only route/discard `GameEvent`s.
- Grep confirms `hint_score`, `HINT_RESULT`, `use_hint`, `ROUTES_/OPENS_/RELIEF_WEIGHT`, and
  `HINT_COST_*` are absent from `core/`, `autoloads/`, and the registry.

## Related Decisions
- ADR-0001 (model/view + core purity — Picker acts on `BoardModel`, no tuning in `core/`),
  ADR-0002 (event-sourced replay — a pick is replayed as ordinary board events), ADR-0008
  (`EconomyEvent` — the Picker's events; `HINT_RESULT` removed from its kind set).
- Supersedes S3-007 (Hint, commit b20aaa0). Implemented in commits 9149eec + 82ac588.
- `design/gdd/deck-economy.md` (Core Rule 8/12, AC-P01..P05, AC-M01a/b); `design/registry/entities.yaml`;
  `design/ux/booster-icons.md`; `CLAUDE.md` Forbidden Patterns.
