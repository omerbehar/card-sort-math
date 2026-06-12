# ADR-0008: `EconomyEvent` — a separate `core/` event type from board `GameEvent`

## Status
Accepted (2026-06-12 — ratifies an Open Question of the approved `design/gdd/deck-economy.md`;
unblocks the Deck Economy sprint). Acceptance rests on the GDD's approval + the author's
go-ahead to implement; no fresh-context re-review was required for a decision the GDD already
specifies in §Economy Events.

## Date
2026-06-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — pure `RefCounted` value type + a typed `signal`; no post-cutoff APIs |
| **References Consulted** | `design/gdd/deck-economy.md` (§Economy Events, AC-M01a); `core/game_event.gd`; `design/registry/entities.yaml` (`EconomyEvent`, `EarnSource`); ADR-0001 (model/view + core purity), ADR-0002 (event-sourced view replay), ADR-0004 (typed GDScript + gdUnit4) |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Confirm a typed `signal economy_event(event: EconomyEvent)` connects and marshals a `RefCounted` payload under the Mobile renderer build (trivially true in 4.x; covered by the unit suite that asserts emitted events). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (core purity — `EconomyEvent` is a node-free `RefCounted`), ADR-0004 (static typing + gdUnit4) |
| **Enables** | The entire Deck Economy implementation: `WalletService`, `WalletData`, booster activation, Analytics/HUD subscription. ~19 economy ACs assert against `EconomyEvent.Kind` names. |
| **Blocks** | Deck Economy sprint stories that emit or assert economy events cannot start until this is Accepted. |
| **Ordering Note** | Sibling of ADR-0009 (TimeProvider) and ADR-0010 (Extra Discard). Independent of both — may be implemented first. |

## Context

### Problem Statement
The Deck Economy must report currency and booster outcomes (earned, spent, spend-failed,
cap-reached, rolled-back, booster activated/failed, hint resolved, IAP blocked) to the HUD and
to Analytics. The board layer already has an event type, `core/game_event.gd` (`GameEvent`),
produced by `BoardModel.tap_card()` and replayed by the view (ADR-0002). The open question the
GDD flags: **do economy events reuse/extend `GameEvent.Kind`, or are they a distinct type?**

### Constraints
- `core/` is pure, node-free, deterministic, and statically typed (ADR-0001, ADR-0004).
- `GameEvent`'s payload is board-domain only: `kind`, `card_id`, `stack_index`, `discard_slot`,
  `new_target` (see `core/game_event.gd`). It is consumed by the view's replay loop
  (`scenes/main/main.gd`) which exhaustively matches on `GameEvent.Kind`.
- The economy's payloads are a different shape: `currency`, `amount`, `source`, `new_balance`,
  `booster_type`, `reason`, `sku` — none of which `GameEvent` carries.
- **Hard rule (AC-M01a):** the `HINT_RESULT` economy event must carry **only** `card_id` — never
  `result`, `operands`, or `solution_text`. The type's payload is a compile-time guardrail for the
  no-arithmetic-solving pillar.

### Requirements
- A typed, node-free event the `WalletService` autoload can emit via signal and that HUD +
  Analytics can subscribe to, without coupling either to board internals.
- Exhaustive, testable `Kind` enum matching the GDD's canonical table 1:1 (AC shorthand
  `SPENT(...)`, `EARNED(...)`, etc. map to these names).
- Must not enlarge `GameEvent`'s payload or its view-replay match with dead currency fields.

## Decision

Introduce **`EconomyEvent`** as its own pure `core/` type — `class_name EconomyEvent extends
RefCounted` — entirely separate from `GameEvent`. It carries its own `Kind` enum and the union of
economy payload fields, with static factory constructors mirroring `GameEvent`'s style. The
`WalletService` autoload owns a single typed signal that carries it; HUD and Analytics subscribe.
`GameEvent` is **untouched** — board and economy events never share a type, a signal, or a
consumer.

### Architecture Diagram
```
core/economy_event.gd  (PURE RefCounted — no Node, no scene)
      ▲ constructed by
WalletService (autoload)  ──signal economy_event(event: EconomyEvent)──▶ HUD (scenes/ui/)
      │  earn() / spend() / use_booster() / convert_gems_to_coins()      └▶ Analytics (M5)
      ▼ commands (board mutation only; returns GameEvent[] as today)
BoardModel (core/) ──tap_card()/reshuffle()/expand_discard()──▶ Array[GameEvent]  (UNCHANGED seam)
```
Two event channels, deliberately disjoint: `GameEvent` (board → view replay, ADR-0002) and
`EconomyEvent` (wallet → HUD/Analytics). They never cross.

### Key Interfaces
```gdscript
class_name EconomyEvent
extends RefCounted

enum Kind {
    CURRENCY_EARNED,             # currency, amount (actual, post-clamp), source, new_balance
    CURRENCY_SPENT,              # currency, amount, new_balance
    SPEND_FAILED,                # currency, amount, balance
    EARN_CAP_REACHED,            # source
    TRANSACTION_ROLLED_BACK,     # currency, amount
    BOOSTER_ACTIVATED,           # booster_type
    BOOSTER_PRECONDITION_FAILED, # booster_type, reason
    BOOSTER_PURCHASE_FAILED,     # booster_type, reason
    HINT_RESULT,                 # card_id ONLY (AC-M01a — no result/operands/solution_text)
    IAP_BLOCKED,                 # sku, reason
}

var kind: Kind
var currency: int = -1          # WalletData.Currency (COINS/GEMS); -1 when N/A
var amount: int = 0
var source: int = -1            # EarnSource enum; -1 when N/A
var new_balance: int = -1
var booster_type: int = -1      # BoosterType enum; -1 when N/A
var reason: int = -1            # failure-reason enum; -1 when N/A
var card_id: int = -1           # HINT_RESULT only
var sku: int = -1               # IAP_BLOCKED only

# Static factories per Kind (mirrors GameEvent.route()/discard()/… style), e.g.:
static func currency_earned(currency: int, amount: int, source: int, new_balance: int) -> EconomyEvent
static func currency_spent(currency: int, amount: int, new_balance: int) -> EconomyEvent
static func spend_failed(currency: int, amount: int, balance: int) -> EconomyEvent
static func hint_result(card_id: int) -> EconomyEvent   # sets ONLY card_id
# …one factory per Kind…
```
`WalletService` exposes: `signal economy_event(event: EconomyEvent)`.

Enum value types (`Currency`, `EarnSource`, `BoosterType`, failure `reason`) are defined on the
owning pure types (`WalletData` / a small `EconomyEnums`); they are plain ints in the payload so
`EconomyEvent` stays a leaf with no economy-config dependency. `HINT_RESULT`'s factory sets only
`card_id`, structurally enforcing AC-M01a (tested by AC-M01a: payload contains no result/operands).

**`sku` is an internal SKU enum (int), not a store product string.** AC-CL01 writes
`IAP_BLOCKED(sku=GEM_PACK_S, …)` — a token from a launch-SKU enum (the IAP catalog in the GDD),
mapped to platform store product identifiers by the (planned, M4) `IAPService`. Keeping it an int
matches the rest of the union payload and the AC's enum-style token; the engine never sees a store
string at this layer. If a later decision needs the raw store identifier in the event, that is an
additive change owned by the IAP ADR, not this one.

## Alternatives Considered

### Alternative 1: Extend `GameEvent.Kind` with economy kinds
- **Description**: Add `CURRENCY_EARNED`, `BOOSTER_ACTIVATED`, … to the existing `GameEvent.Kind`
  enum and reuse `GameEvent` for both domains.
- **Pros**: One event type; one signal pattern to learn.
- **Cons**: Carries dead payload (currency events have no `stack_index`/`discard_slot`; board
  events have no `currency`/`amount`); pollutes the view's exhaustive `GameEvent.Kind` replay
  match with kinds it must explicitly ignore; couples the board/view seam to economy churn (every
  new economy event touches the board type and its tests). Entangles ADR-0002's replay contract
  with wallet concerns.
- **Rejection Reason**: Violates the clean board/view seam for zero benefit; the two domains have
  disjoint payloads and disjoint consumers.

### Alternative 2: Plain `Dictionary` / signal-arg-per-event
- **Description**: Emit untyped `Dictionary` payloads, or one bespoke signal per event with
  positional args (`currency_spent(currency, amount, new_balance)`, …).
- **Pros**: No new class; flexible.
- **Cons**: Untyped — breaks ADR-0004's static-typing mandate; no compile-time guard for the
  AC-M01a "card_id only" rule; per-signal explosion makes Analytics subscription a wide fan-in;
  tests assert on stringly-typed keys. The GDD explicitly calls for a typed `EconomyEvent`.
- **Rejection Reason**: Fails the typing standard and the AC-M01a structural guarantee.

## Consequences

### Positive
- Board/view seam (ADR-0001/0002) is untouched; `GameEvent` stays board-domain-pure.
- A single typed signal carries every economy outcome; HUD and Analytics share one subscription.
- `HINT_RESULT`'s factory enforces the no-arithmetic-solving pillar at the type level.
- The `Kind` enum is the single source of truth the ~19 economy ACs assert against.

### Negative / accepted trade-offs
- A second event type + factory surface to maintain. Accepted: the alternative (one bloated type)
  is worse, and the factory style already exists for `GameEvent`, so the idiom is familiar.
- `EconomyEvent` uses a wide "union" payload (most fields `-1`/`0` per kind). Accepted as the
  idiomatic GDScript trade-off (matches `GameEvent`, which already does this); a per-kind subclass
  hierarchy would be heavier with no test benefit.

### Risks
- **Drift between the `Kind` enum and the GDD table.** *Mitigation:* the enum is copied verbatim
  from the GDD §Economy Events table and registry `EconomyEvent` entity; a unit test enumerates
  `Kind.keys()` against the expected set.
- **A future booster needs `result` in its event.** *Mitigation:* explicitly forbidden by AC-M01a
  / AC-M02 — such a design must be rejected at review, not accommodated in the payload.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| deck-economy.md | §Economy Events: "a separate type from the board's `GameEvent` … `EconomyEvent` (a lightweight `core/` `RefCounted` with its own `Kind` enum), emitted by `WalletService` as a typed signal" | Exactly this type + signal; `GameEvent` untouched |
| deck-economy.md | AC-M01a: `HINT_RESULT` payload is `card_id` only | `hint_result(card_id)` factory sets only `card_id`; no result/operand fields exist for that kind |
| deck-economy.md | AC shorthand (`SPENT`/`EARNED`/…) maps 1:1 to canonical kinds; Analytics + HUD subscribe | `Kind` enum is the canonical set; one `economy_event` signal feeds both subscribers |

## Performance Implications
- **CPU**: one `RefCounted` allocation per economy event (event-frequency, not per-frame); negligible.
- **Memory**: a handful of ints per event; freed when consumers drop the reference.
- **Load Time**: none.
- **Network**: none.

## Migration Plan
Purely additive — no existing code changes. New file `core/economy_event.gd`; the
`signal economy_event` lives on the new `WalletService` autoload (created by the economy sprint).
`GameEvent`, `BoardModel`, and the view replay loop are not modified by this ADR.

## Validation Criteria
- A unit test asserts `EconomyEvent.Kind` has exactly the 10 canonical names from the GDD table.
- Tests for `earn()`/`spend()`/`use_booster()` assert the emitted `EconomyEvent.kind` + payload
  fields per AC (AC-W01..W08, AC-H01..H05, AC-R*, AC-E*, AC-C*, AC-GC*, AC-CL*, AC-CH*).
- AC-M01a: a test inspects a `HINT_RESULT` event and asserts no `result`/`operands`/`solution_text`.

## Related Decisions
- ADR-0001 (model/view + core purity), ADR-0002 (event-sourced view replay — the *board* channel,
  kept disjoint), ADR-0004 (typed GDScript + gdUnit4).
- ADR-0009 (TimeProvider), ADR-0010 (Extra Discard Slot) — sibling Deck Economy ADRs.
- `design/gdd/deck-economy.md` (§Economy Events, Acceptance Criteria); `design/registry/entities.yaml`.
