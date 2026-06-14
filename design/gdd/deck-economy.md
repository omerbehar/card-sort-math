# Deck Economy

> **Status**: Approved (post-/design-review revision accepted 2026-06-12) — ready for programmer handoff
> **Author**: omer.behar + agents
> **Last Updated**: 2026-06-12
> **Implements Pillar**: Meta/Retention — currencies, boosters, spend sinks that power player progression without trivialising the math
> **Creative Director Review (CD-GDD-ALIGN)**: CONCERNS (accepted) 2026-06-12 — cleared for programmer handoff. 4 accepted concerns: streak reset loss-aversion risk; "double reward" ad framing (keep quiet/dismissible in UX); Hint routing-info leak (acknowledged as intentional, note added); Reshuffle-into-stuck feels unfair.
> **Independent /design-review (2026-06-12)**: NEEDS REVISION → revised. Resolutions: efficiency bonus now mechanized (`CLEAN_CLEAR_BONUS`); streak reset softened to a day-3 floor; Extra Discard Slot reframed purchase-ahead-only (no rescue); Reshuffle now guarantees a routable card; canonical `EconomyEvent` type introduced; `ComplianceService` method names corrected to `is_restricted()`; Undo replay approach specified against the real `BoardModel`; Hint ceiling corrected 585→405; streak average corrected 37→39; rollback uses a pre-spend snapshot; `DAILY_COINS_CAP` scope declared (ad-earn only).
> **Scope change (2026-06-12)**: **Undo booster removed** by design decision. The booster set is now **three** — Hint, Reshuffle, Extra Discard Slot. All Undo rules, costs, edge cases, acceptance criteria, and registry constants are struck; Core Rule 9 is tombstoned to keep `Core Rule N` cross-references stable. Rationale and full ripple list recorded in `design/gdd/reviews/deck-economy-review-log.md`. The surviving pre-implementation decisions are ratified in **ADR-0008** (`EconomyEvent` type), **ADR-0009** (injectable `TimeProvider` seam — still required for Reshuffle determinism + daily caps/streaks), and **ADR-0010** (Extra Discard Slot board change).
> **Scope change (2026-06-13)**: **Hint booster replaced by Picker.** The booster set is **Picker, Reshuffle, Extra Discard Slot**. Picker lets the player play any covered (lower-layer) card immediately (`BoardModel.pick_card` / `WalletService.use_picker`), bypassing coverage but never revealing the arithmetic answer (Core Rule 12 holds). Removed with Hint: the `hint_score` formula and its `ROUTES/OPENS/RELIEF_WEIGHT` knobs, the `HINT_RESULT` event, the `_hint_in_progress` double-tap path (`ALREADY_IN_PROGRESS`/`NO_EXPOSED_CARD` reasons), and `HINT_COST_*` (now `PICKER_COST_*`). `BoosterType.HINT → PICKER`; new `FailReason.INVALID_TARGET`.
> **Scope change (2026-06-13b)**: **Prototype locked-deck unlock + buff inventory added.** Locked stacks are added via a two-option watch-ad / pay-coins popup (`UnlockPopup`); boosters gain a persisted owned count (`SaveData` schema **v5**) consumed for free on use, with the same watch-ad / pay-coins top-up at zero stock. New `FailReason.NO_STOCK`; new `EconomyConfig.starting_booster_count`; `WalletService` gains `booster_count` / `grant_booster` / `consume_booster` / `*_from_stock` + a `booster_stock_changed` signal. Partially diverges from Rule 19 (coins-per-use) — see the **Prototype Addendum** section for full rules, edge cases, and open items.

## Overview

The Deck Economy is CardSortMath's currency and booster layer: a two-currency model
(**Coins**, soft; **Gems**, hard) underpinned by a pure, node-free `WalletData` record
persisted via `SaveService`. Coins are earned passively through play — level wins, daily
challenges, rewarded ads — and spent on three consumable boosters: **Picker** (plays a
covered lower-layer card the player chooses, without revealing the arithmetic answer), **Reshuffle**
(redistributes cards across the floor while preserving the solvability invariant), and
**Extra Discard Slot** (adds a temporary sixth discard buffer for the current level). Gems are the premium currency, acquired via IAP or milestone gifts,
and spent on cosmetics, currency conversion, and booster bundles. From the player's
perspective the economy converts *cleared floors into stored calm*: a growing coin reserve
that says "you've earned the right to take it easy when you need to." From the
infrastructure side, every transaction flows through an atomic `WalletService.spend()` that
checks balance and emits an `EconomyEvent` (a separate event type from the board's `GameEvent`
— see Detailed Design §Economy Events) before the booster activates; a failed spend never
partially commits, and a mid-transaction error restores the exact pre-spend balance from a
snapshot (not via `earn()`). All IAP and ad-based earn paths are gated through `ComplianceService`
(ADR-0005): child users earn coins through play alone and are never shown an IAP surface.
The hard constraint binding the entire system: **no booster may auto-solve arithmetic or
reveal a card's result** — math remains the mechanic, every tap is the player's own work.

## Player Fantasy

*"My tools. My pace. My arithmetic."*

Most floors you solve bare-handed. The coins accumulate quietly — a byproduct of clearing boards
— and the boosters sit in a tidy toolbox you rarely need to open. When you do reach for one, it
is deliberate, occasional, and purposeful: a Reshuffle to reopen a path that closed, an Extra
Discard Slot bought ahead to give yourself more thinking room. The anchor moment is not rescue — it is
*self-sufficiency*. You had what you needed because you earned it. The booster validates your
**planning**, it never replaces your **arithmetic**.

The economy's coercion test: choosing *not* to spend feels just as rewarding as spending. Every
clean clear you finish without touching the wallet earns an efficiency bonus and a small
self-satisfaction that no booster can substitute. The reserve grows anyway. You are accumulating
calm for future floors, not grinding to stay playable on the current one. This is the calm
toolbox of a craftsperson, not the power-up queue of an action game.

Critically: all three boosters act on **board state** (layout, buffer capacity), never on
the **equation**. Picker grants *access* to a covered card; the player still computes `7 + 6`.
Reshuffle changes *coverage*; the card values are unchanged. Extra Discard Slot buys *buffer space* — purchased
ahead, while the player still has room, as a deliberate "give me more thinking space" choice,
not a panic-button when the discard is already full; the player still matches every result themselves. Because the tools act on arrangement and the player acts on
arithmetic, the two layers never blur. Playing with boosters feels as mathematically substantive
as playing without them. The edu value prop survives every spend.

**Anti-goals (do not compromise):**
- No booster that reveals a result, computes an exercise, or routes a card automatically.
- No economy pressure that makes a stuck board feel like a pay wall — if the wallet is empty,
  the board remains solvable; boosters are quality-of-life, not progression gates.
- No mid-puzzle IAP prompts. The economy surface belongs in the HUD and menus, never as a pop-up
  interrupting arithmetic focus.

## Detailed Design

### Core Rules

#### Currencies

1. **Two-currency model, strictly separated.** Coins (soft) and Gems (hard) are never
   fungible in the premium direction: players can convert Gems → Coins at a penalised rate
   (see Formulas), but never Coins → Gems. This prevents coin grinding from substituting
   for IAP.

2. **Coins are earned; Gems are purchased or gifted.**
   - Coins faucets: level win (stars-weighted), daily challenge completion, rewarded ad
     (daily capped), streak bonuses, milestone gifts.
   - Gem faucets: IAP purchases (all SKUs), milestone gifts (sparse), daily login streaks
     (very sparse). No rewarded-ad gem earn — that path is strictly coins.

3. **Wallet state is `WalletData` in `core/`, persisted via `SaveService`.**  
   `WalletData { coins: int, gems: int }` — both ≥ 0, both ≤ `MAX_BALANCE`
   (see Tuning Knobs). `WalletService` (autoload) wraps all reads and writes.

4. **Every transaction is atomic.** `WalletService.spend(currency, amount) → bool`:
   - Captures `pre_spend_balance = wallet[currency]` before any mutation.
   - Checks balance ≥ amount; if false, returns false, no mutation.
   - If true: deducts `amount`, emits `EconomyEvent.CURRENCY_SPENT`, activates booster.
   - The deduction and the board mutation are committed synchronously in the same call stack —
     before the resulting events are returned to the view layer for animation — so a save at any
     point reflects a complete transaction (no partial state). (This is implementation atomicity;
     the *view* animates asynchronously and is not expected to update simultaneously.)
   - If the booster activation fails its precondition (e.g. Reshuffle on a won board, or Extra Discard at the slot cap `MAX_DISCARD_SLOTS`), no deduction was committed.
     If a board mutation raises an unexpected error mid-transaction, the balance is restored by
     **direct assignment** `wallet[currency] = pre_spend_balance` (NOT via `earn()`, which would
     be silently truncated by the `MAX_BALANCE` clamp near the cap), and an
     `EconomyEvent.TRANSACTION_ROLLED_BACK` event is emitted.
   `WalletService.earn(currency, amount, source) → void`:
   - Adds `amount`, clamps to `MAX_BALANCE`, emits `EconomyEvent.CURRENCY_EARNED`.

5. **ComplianceService gates every non-play earn path.** Before granting coins from a
   rewarded ad or gems from IAP, the economy checks `not ComplianceService.is_restricted()`
   (the actual `ComplianceService` API exposes `is_adult()`, `is_restricted()`,
   `can_collect_personal_data()`, `can_show_targeted_ads()`, `can_use_advertising_id()` — there
   is no `can_show_ads()`/`can_show_iap()`; `is_restricted()` is the correct gate, and treats
   the UNKNOWN age band as restricted). `can_show_targeted_ads()` governs ad *personalisation*
   only, not whether a rewarded ad may be shown, so it is NOT the gate here. If the check fails
   (child/restricted user), the earn does not fire and the UI must not surface the offer. The
   economy never calls `SaveService.data.age_band` directly.

6. **Child mode (age_band = CHILD):** Only the play-based coin faucet (level wins + daily
   challenge) is active. No ad-based coins, no IAP. Booster buttons remain visible and
   functional — children can earn and spend coins exactly as adult players do, they just
   cannot watch an ad or buy a pack to top up. This keeps the core economy feel consistent
   without exposing minors to a spend surface.

#### Boosters

7. **Three consumable boosters.** Each booster costs coins (or optionally gems at a
   premium rate — see Formulas). A booster is available when its precondition is met
   AND the player can afford it. The UI shows it greyed-out if unaffordable but the
   precondition is met, so players know it exists without feeling blocked.

8. **Picker (replaces Hint, 2026-06-13).** Precondition: the chosen card is still on the
   floor and the board is not over. Effect: the player selects any **covered (lower-layer)**
   card and it is played immediately — routed to a matching open stack, or sent to discard if
   none — exactly as a normal tap would resolve, but bypassing the coverage rule. This is the
   only way to act on a card that is not yet exposed. Any depth is reachable.
   *Design note (intentional):* the Picker grants **access**, not **answers**. The player still
   reads the card's equation and the board still routes it by its computed result; the booster
   only lifts the coverage restriction so a buried card can be played now. It NEVER reveals or
   displays the card's arithmetic result — the no-arithmetic-solving pillar (Core Rule 12) holds.
   *Why it replaced Hint:* Hint surfaced routing information via a scored highlight; the Picker is
   a more direct, player-driven dig tool with no scoring heuristic to tune.

9. **~~Undo~~ — REMOVED (2026-06-12).** The Undo booster was cut from the design. The booster
   set is **Picker, Reshuffle, Extra Discard Slot** (Hint replaced by Picker 2026-06-13). This rule number is retained as a tombstone so
   that `Core Rule N` cross-references elsewhere in the document stay stable; there is no Undo
   precondition, cost, event, replay coordinator, or `tap_history` in the economy. See the
   scope-change note in the Status block and `design/gdd/reviews/deck-economy-review-log.md` for
   the rationale and full ripple list.

10. **Reshuffle.** Precondition: board is not in a WIN state; level not yet cleared. Effect:
    re-generate the floor layout (slot positions and coverage layers) using a
    `reshuffle_seed` derived from the original level seed and the current reshuffle count
    (see Formulas). The **card set** (which cards exist) and the **target queue** are
    unchanged. The new layout must pass `LevelData.is_solvable()` (by construction — same
    card counts, same queue). Exposure is reset: all layers reassigned from the new layout.
    The discard row is NOT cleared (cards already discarded stay discarded). The reshuffle
    count increments; a warning fires if count reaches the cap (see Tuning Knobs).
    **Routable-card guarantee (fairness).** The reshuffle must produce a layout in which at least
    one exposed card routes directly (its result matches an open, non-full stack target) OR opens
    further coverage — i.e. the post-reshuffle board is never *immediately* stuck. Implementation:
    the slot shuffle is re-rolled with successive `reshuffle_count` seeds until this predicate
    holds (bounded retry; satisfiable because the board is solvable by invariant). A 250-coin
    Reshuffle is therefore *always* meaningful — the player never spends to remain stuck. See
    Formula 6 and EC-05.

11. **Extra Discard Slot (rescue allowed).** Precondition:
    `_active_discard_slots < MAX_DISCARD_SLOTS` (the slot cap) only.
    **Revision (2026-06-14):** the original "purchase-ahead-only" second clause
    (`occupied_discard_cards < _active_discard_slots` — blocked when the row is full) was
    **removed**: it made the booster unresponsive exactly when a player reaches for it (row 5/5),
    which read as broken. The booster may now be bought/used when the row is full, adding a slot
    as a rescue, up to the cap. Default `MAX_DISCARD_SLOTS = 7`
    (tuning knob), so it can be bought twice per level at default settings, ahead of need.
    **Single mechanism (no contradiction):** the effect is to increment a mutable
    `BoardModel._active_discard_slots` by 1 (NOT a one-shot `discard_capacity = 6`) and append
    one empty (`-1`) slot to `_discard` immediately. **Real-codebase refactor:** `board_model.gd`
    currently uses `const DISCARD_SLOTS = 5` in three instance-capacity loops (init,
    `_first_empty_discard`, `_pull_matching`); all three must iterate `_active_discard_slots`
    instead. (`core/recoverability_simulator.gd` also reads `DISCARD_SLOTS` in three places — those
    **stay** on the base constant: generation-time recoverability is judged at base capacity, never
    the runtime-expanded board. See ADR-0010.) `BoardModel`
    exposes `expand_discard()` (uncapped append); `WalletService` enforces the
    `MAX_DISCARD_SLOTS` cap so `BoardModel` stays free of economy-config knowledge (ADR candidate,
    Open Questions). Resets to `DISCARD_SLOTS = 5` at level end (win, lose, or quit). If the
    precondition fails (at max, or discard full), `BOOSTER_PRECONDITION_FAILED` is returned
    without deducting coins.

12. **No booster touches arithmetic.** This is the hard constraint. Picker grants access to a
    covered card; the player computes. Reshuffle reshuffles positions; card values are unchanged. Extra
    Discard widens the buffer; the math remains the player's own. Any future booster idea
    that reveals a result, auto-routes a card, or solves an exercise must be rejected.

#### Economy Events (canonical)

Economy events are **a separate type from the board's `GameEvent`** (`core/game_event.gd`,
whose `Kind` enum and `card_id`/`stack_index`/`discard_slot` payload are board-domain only).
Cramming currency events into `GameEvent` would carry dead payload and entangle the
view/model seam. The economy defines `EconomyEvent` (a lightweight `core/` `RefCounted` with its
own `Kind` enum), emitted by `WalletService` as a typed signal; the HUD and Analytics subscribe
to that signal. The canonical event names are:

| `EconomyEvent.Kind` | Emitted when | Payload |
|---------------------|--------------|---------|
| `CURRENCY_EARNED` | `earn()` credits a balance | `currency`, `amount` (actual credited, post-clamp), `source`, `new_balance` |
| `CURRENCY_SPENT` | `spend()` deducts a balance | `currency`, `amount`, `new_balance` |
| `SPEND_FAILED` | `spend()` rejected for insufficient funds | `currency`, `amount`, `balance` |
| `EARN_CAP_REACHED` | a daily cap blocks (fully or partially) an earn | `source` |
| `TRANSACTION_ROLLED_BACK` | a mid-transaction error restored the pre-spend balance | `currency`, `amount` |
| `BOOSTER_ACTIVATED` | a booster successfully activated | `booster_type` |
| `BOOSTER_PRECONDITION_FAILED` | a booster precondition was unmet (no spend) | `booster_type`, `reason` |
| `BOOSTER_PURCHASE_FAILED` | a purchase was rejected (e.g. double-tap) | `booster_type`, `reason` |
| `IAP_BLOCKED` | a restricted user's IAP attempt was blocked | `sku`, `reason` |

The Acceptance Criteria use shorthand (`SPENT(...)`, `EARNED(...)`, etc.); these map 1:1 to the
`EconomyEvent.Kind` names above. The class name (`EconomyEvent` vs. extending `GameEvent`) is
ratified by the ADR candidate in Open Questions.

#### Earn Rates (provisional — calibrate from playtest)

13. **Level-win coin earn.** Scaled by star rating (stars awarded by the Scoring system,
    per S2-011 GDD when authored):
    - 1 star: **40 coins**
    - 2 stars: **55 coins**
    - 3 stars: **75 coins**
    Target: average 2-star performance yields ~55 coins/level, supporting ~750 coins/day
    for an engaged player (9 levels + daily challenge + occasional ad).

    **Clean-clear efficiency bonus (mechanizes the "not-spending feels as good as spending"
    pillar).** A level cleared with **zero booster spend** awards an additional
    `CLEAN_CLEAR_BONUS = 20 coins` on top of the star-weighted win coins (see Formula 1b). This
    is the concrete, testable reward that makes choosing *not* to spend its own positive outcome
    rather than a mere absence of cost — the reserve grows *faster* when you solve bare-handed.
    The bonus is forfeited the moment any coin- or gem-cost booster is activated during the
    level (Picker/Reshuffle/Extra Discard). It does not stack per-booster (it is binary:
    clean or not). Tuning knob: `CLEAN_CLEAR_BONUS` (see Tuning Knobs).

14. **Daily challenge coin earn.** **150 coins** for completing the daily challenge (once
    per day; resets at midnight UTC).

15. **Rewarded ad earn.** **60 coins** per completed rewarded ad. Cap: 3 rewarded ads per
    day (max 180 coins/day from ads; cap resets at midnight UTC). A 2× level-reward
    multiplier (doubles the win coins for one level) may substitute for the flat 60 coins
    as a post-level ad format. Gated by `not ComplianceService.is_restricted()`; zero for
    CHILD/restricted users.

    **Cap scope (canonical).** `DAILY_COINS_CAP` (default 500, Tuning Knobs) applies to
    **rewarded-ad coin income only** (`source == REWARDED_AD`). Level wins, the daily challenge,
    streak bonuses, milestone gifts, and the clean-clear bonus are **uncapped**. Gem→coin
    conversion is governed by its **own** separate `DAILY_GEM_CONVERT_CAP` (50 gems/day), not by
    `DAILY_COINS_CAP`. Therefore the ~750 coins/day income headline (Formula 2) is reachable —
    only the ~180 coins/day ad slice is capped, and the cap binds before the income target. The
    `MAX_ADS_PER_DAY = 3` count cap and the `DAILY_COINS_CAP` coin cap both apply to ads;
    whichever binds first stops further ad earn.

16. **Streak bonuses.** Additive on top of the daily challenge coin on a given day:
    - Day 1: +0 (no streak yet)
    - Days 2–4 of login streak: +25 coins/day
    - Days 5–6: +50 coins/day
    - Day 7: +100 coins (weekly anchor)
    **Reset behavior (canonical, calm-not-frantic):** natural day-8 rollover continues the streak
    into a new cycle (day 8 = day 1 of the next week, +0). A **missed day** does NOT reset to 0 —
    it resets to a **floor of day 3** (`STREAK_RESET_FLOOR = 3`, Tuning Knob), so a lapse costs
    momentum but never wipes the player back to nothing. This deliberately softens loss-aversion:
    the streak is a gentle retention hook, not an anxiety spike. (Replaces the earlier
    reset-to-0/reset-to-1 ambiguity; the M3 watch item is now only "does the day-3 floor still
    feel calm in live data," not a redesign.)

17. **Milestone coin gifts.** Fixed one-time coin packages at level-completion milestones
    (see Tuning Knobs for the milestone table). Not repeatable.

18. **Gem gifts (free drips — milestone-only, Option A).**
    - Tutorial completion: 15 gems (one-time)
    - Every 10 levels cleared: 5 gems (ongoing)
    - First 3-star on any new operation world: 10 gems (per world, up to 5 worlds = 50 gems)
    - Daily-challenge 7-day streak maintained: 10 gems (weekly)
    - Major achievement unlocks: 3–10 gems each (~20–30 gems total over full playthrough)
    Lifetime free-gem estimate for a year-one engaged player: ~660 gems (itemized: tutorial 15 +
    level-milestones ~50 + world-first-3★ 50 + weekly streak ~520 + achievements ~25). No *daily*
    login gem drip. **Caveat (honest):** the weekly-streak gem (10/week ≈ 1.43/day) is the
    dominant source (~79%) and is functionally close to a slow daily drip — its calibration vs.
    IAP gem-pack conversion must be watched at M3 (Open Questions: Gem drip calibration). No
    coin→gem conversion.

#### Spend Rates (provisional — calibrate from playtest)

19. **Booster coin costs** (ordered by power / disruption, ascending):
    - Picker: **120 coins**
    - Reshuffle: **250 coins**
    - Extra Discard Slot: **350 coins**
    At ~750 coins/day engaged income, a non-paying player can afford roughly 1 Picker every
    2.4 days or 1 Extra Discard Slot every 7 days of play — occasional, not routine.

20. **Booster gem costs** (premium convenience; 1 gem ≈ 35 coin equivalent):
    - Picker: **3 gems**
    - Reshuffle: **7 gems**
    - Extra Discard Slot: **10 gems**

21. **Gem-to-coin conversion (penalised, downward only).** Players may convert
    gems → coins at `1 gem = 25 coins` (below the 35-coin booster-parity rate).
    Daily cap: 50 gems converted per day. This provides a utility floor (never truly
    stuck) while preserving IAP value. **No coin → gem conversion exists.**

22. **Remove Ads IAP.** Costs **$3.99** (store-price-point decision, not a gem amount).
    Includes 500 bonus coins as a launch sweetener. Does NOT include gems (preserving
    gem IAP value). Removes interstitials and banner ads permanently; optional rewarded
    ads remain available for coin earn. Requires receipt restore on reinstall.

23. **IAP catalog (launch SKUs):**

    | SKU | Price | Contents |
    |-----|-------|----------|
    | Remove Ads | $3.99 | Ad-free + 500 bonus coins |
    | Starter Pack (first-time, exp. session 3) | $1.99 | 200 gems + 1× each booster |
    | Coin Pack S | $0.99 | 1,500 coins |
    | Coin Pack M | $2.99 | 5,500 coins |
    | Coin Pack L | $9.99 | 22,000 coins |
    | Gem Pack S | $1.99 | 100 gems |
    | Gem Pack M | $4.99 | 280 gems |
    | Gem Pack L | $9.99 | 600 gems |
    | Gem Pack XL | $19.99 | 1,400 gems |
    | Booster 5-Pack | $1.99 | 5× Picker OR 5× Reshuffle OR mixed |
    | Premium Bundle | $4.99 | Remove Ads + 150 gems + 2,000 coins |

    All prices are USD base; localized price points applied at store level.

    **Anchor-SKU note (intentional):** the Premium Bundle ($4.99) is strictly richer than
    standalone Remove Ads ($3.99) — it adds 150 gems + 1,500 coins for $1 more, so a player who
    wants ad removal is *meant* to see the Bundle as the obvious upgrade. Remove Ads is retained
    as a deliberate **anchor** (and for players who only want ad removal at the lowest price), not
    as a sincere best-value option. Flagged for store-policy review (Open Questions); if anchoring
    is undesired at launch, reduce the Bundle's gem content to 100 or raise its price to $5.99.

### States and Transitions

The economy has no complex FSM — it is a set of balance mutations gated by predicates.
The only meaningful level-scoped state is the `extra_discard_active` flag and the
`reshuffle_count`. These are reset at level boundaries.

| State | Scope | Entry | Exit |
|-------|-------|-------|------|
| `IDLE` | Always | App start / after any transaction | Any spend or earn event |
| `SPENDING` | Transaction | `WalletService.spend()` called | Transaction committed or rolled back → `IDLE` |
| `EARNING` | Transaction | `WalletService.earn()` called | Balance updated → `IDLE` |
| `EXTRA_DISCARD_ACTIVE` | Per-level | Player activates Extra Discard Slot | Level ends (win/lose/quit) |

Per-level state (owned by `WalletService` for the duration of a level, cleared on level end):

| Field | Default | Mutated by |
|-------|---------|-----------|
| `extra_discard_active` | `false` | Extra Discard Slot booster activation |
| `reshuffle_count` | `0` | Each Reshuffle use |
| `boosters_used_this_level` | `0` | Incremented on any booster activation; gates the clean-clear efficiency bonus (`== 0` at win → bonus awarded) |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **SaveService** | Writes to | `WalletData` fields serialised in `SaveData.wallet_coins` and `SaveData.wallet_gems`; persisted on every earn/spend via `SaveService.save_game()`. |
| **BoardModel** | Commands | Reshuffle calls a new `LevelGenerator.reshuffle(config, seed)` helper (NOT `generate()` — see Formula 6). Extra Discard Slot calls `BoardModel.expand_discard()` (increments mutable `_active_discard_slots`, appends a slot). |
| **ComplianceService** | Queries | `not is_restricted()` before ad earn and before any IAP surface (the API has no `can_show_ads()`/`can_show_iap()`). |
| **GameManager** | Receives signals from | Level win/lose events trigger coin earn (star-weighted). |
| **LevelData** / **LevelGenerator** | Calls into | Reshuffle calls a `LevelGenerator.reshuffle(config, seed)` helper that re-permutes slot assignments only (preserving card set + target queue) and enforces the routable-card guarantee. It does NOT call `generate()` (which would rebuild results/queue and violate AC-R01). |
| **HUD / UI** | Reads from | Wallet balance displayed in HUD via `WalletService.data`; booster button states derive from balance + preconditions. |
| **Analytics** | Emits to | `EconomyEvent` signals: `CURRENCY_EARNED`, `CURRENCY_SPENT`, `BOOSTER_ACTIVATED`, `TRANSACTION_ROLLED_BACK`, `EARN_CAP_REACHED` (see §Economy Events). Distinct from board `GameEvent`s. |
| **IAP Service** (planned) | Receives calls from | On verified purchase, IAP service calls `WalletService.earn(GEMS, amount, SOURCE_IAP)`. |
| **Ad Service** (planned) | Receives calls from | On completed rewarded ad, Ad service calls `WalletService.earn(COINS, REWARDED_AD_COINS, SOURCE_REWARDED_AD)` — after checking the daily cap. |

## Formulas

### 1. Level-win coin reward

The level-win coin reward is defined as:

`coins_earned = BASE_WIN_COINS[stars] + (first_win_bonus if first_win_today else 0)`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Star rating | `stars` | int | {1, 2, 3} | Awarded by Scoring system (S2-011) |
| Base reward | `BASE_WIN_COINS[stars]` | int | {40, 55, 75} | Lookup: 1★=40, 2★=55, 3★=75 |
| First-win flag | `first_win_today` | bool | {true, false} | True for the first level cleared each calendar day |
| First-win bonus | `first_win_bonus` | int | 15 | Flat addition; only once per day |

**Output Range:** 40–90 coins per level win under normal play (before the clean-clear bonus).
**Example:** Player wins a level with 2 stars, not the first win today → `55 + 0 = 55 coins`.
**Example:** Player wins first level of the day with 3 stars → `75 + 15 = 90 coins`.

---

### 1b. Clean-clear efficiency bonus

Mechanizes the "not-spending feels as good as spending" pillar. Added at level win:

`clean_clear_bonus = CLEAN_CLEAR_BONUS if boosters_used_this_level == 0 else 0`

`total_win_coins = BASE_WIN_COINS[stars] + (first_win_bonus if first_win_today else 0) + clean_clear_bonus`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Boosters used | `boosters_used_this_level` | int | ≥ 0 | Count of booster activations this level (per-level state) |
| Clean-clear bonus | `CLEAN_CLEAR_BONUS` | int | 20 (tuning knob) | Flat coin bonus for a zero-spend clear |

**Output Range:** total_win_coins is 40–110 coins (90 max from Formula 1 + 20 clean bonus).
**Example:** First win of the day, 3 stars, no boosters used → `75 + 15 + 20 = 110 coins`.
**Example:** 2-star win using one Reshuffle → `55 + 0 + 0 = 55 coins` (bonus forfeited).

---

### 2. Daily income model (design calibration — not a runtime formula)

This formula is used to calibrate the economy, not computed at runtime.

`daily_income = (sessions/day × levels/session × avg_coins/level) + daily_challenge_coins + streak_bonus + (ads/day × coins_per_ad)`

| Variable | Design target | Description |
|----------|--------------|-------------|
| sessions/day | 3 | Engaged non-paying adult player |
| levels/session | 3 | ~9 min session |
| avg_coins/level | 55 | 2-star average (before daily bonus) |
| daily_challenge_coins | 150 | One per day |
| streak_bonus | 39 | Average over a 7-day cycle: `(0+25+25+25+50+50+100)/7 = 275/7 ≈ 39.3` (day 1 = 0) |
| first_win_bonus | 15 | One per calendar day, first level win only (Formula 1) |
| clean_clear_bonus (modeled) | ~120 | If most of the ~9 daily levels are cleared without boosters: `9 × 20 × (clean-clear rate)`; at an ~67% clean rate ≈ 120 |
| ads/day | 1.5 | Opt-in rate estimate for adult casual audience |
| coins_per_ad | 60 | Fixed per completed rewarded ad |

**Design target:** ~750 coins/day in *spendable baseline* (excluding the clean-clear bonus, which
is the reward for NOT spending and so should not be modeled as routine spend income). Baseline:
`(3×3×55) + 150 + 39 + 15 + (1.5×60) = 495 + 150 + 39 + 15 + 90 = 789` coins/day. The clean-clear
bonus adds on top for players who solve bare-handed, *widening* the gap between spending and
saving in favor of saving — exactly the pillar intent.
At that income, time-to-afford for each booster:

| Booster | Cost | Days of play |
|---------|------|-------------|
| Picker | 120 | 0.16 (every ~2.4 days; ~4 per session if saving) |
| Reshuffle | 250 | 0.33 |
| Extra Discard Slot | 350 | 0.47 |

This is deliberately generous — the economy is not a grind gate. The costs create *meaningful choice*, not *frustrating friction*.

---

### 3. Spend transaction

The spend transaction is defined as:

`can_spend(currency, amount) = wallet[currency] ≥ amount`

`wallet[currency]' = wallet[currency] − amount`  (applied only if `can_spend` is true)

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Currency | `currency` | enum | {COINS, GEMS} | Which balance to check |
| Amount | `amount` | int | [1, MAX_BALANCE] | The spend amount |
| Current balance | `wallet[currency]` | int | [0, MAX_BALANCE] | Balance before transaction |
| New balance | `wallet[currency]'` | int | [0, MAX_BALANCE] | Balance after deduction |

**Output:** `true` if transaction succeeded (balance deducted); `false` if insufficient funds (no mutation).
**Example:** `wallet.coins = 200`, `spend(COINS, 120)` → `wallet.coins = 80`, returns `true`.
**Example:** `wallet.coins = 80`, `spend(COINS, 120)` → `wallet.coins = 80` unchanged, returns `false`.

---

### 4. Earn transaction

The earn transaction is defined as:

`wallet[currency]' = min(wallet[currency] + amount, MAX_BALANCE)`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Currency | `currency` | enum | {COINS, GEMS} | Which balance to credit |
| Amount | `amount` | int | [1, MAX_BALANCE] | The earn amount |
| MAX_BALANCE | `MAX_BALANCE` | int | 999,999 | Hard cap on any single currency balance |

**Output Range:** `wallet[currency]'` in `[0, MAX_BALANCE]`. Earn is always capped; no overflow.
**Example:** `wallet.coins = 999,500`, `earn(COINS, 750)` → `wallet.coins = 999,999` (clamped).

---

### 5. ~~Hint scoring function~~ — REMOVED (Picker replaced Hint, 2026-06-13)

The Picker booster has **no scoring function** — the *player* chooses which covered card to
play, so there is no heuristic to compute or tune. The former `hint_score` formula and its
`ROUTES_WEIGHT` / `OPENS_WEIGHT` / `RELIEF_WEIGHT` knobs are struck.

Picker behaviour is fully specified by Core Rule 8 and resolves through `BoardModel.pick_card`,
which reuses the normal tap resolution (route to a matching open stack, else discard) but skips
the exposure check. No new math; determinism is inherited from the deterministic board model.

---

### 6. Reshuffle seed formula

`reshuffle_seed = mix(level_id, level_start_timestamp, reshuffle_count)`

where `mix(...)` is an **explicit integer mix** (NOT GDScript `hash()`), defined in **ADR-0009**:

```
s = level_id * MIX_A
s = (s ^ level_start_timestamp) * MIX_B
s = (s ^ reshuffle_count) * MIX_C
s = s ^ (s >> 16)
reshuffle_seed = s & 0x7FFFFFFFFFFFFFFF      # non-negative 63-bit; passed straight to rng.seed
```

**Why not `hash()`:** GDScript `hash()` is implementation-defined and **not stable across platforms
or Godot versions** — ADR-0007 §2 bans it for any value fed to `rng.seed`, because it would break
cross-device reshuffle reproducibility (daily-challenge identity, shareable seeds). The explicit
integer mix is pure 64-bit arithmetic (deterministic wrap-around), stable everywhere, and changes for
any difference in `level_start_timestamp` (cross-session anti-replay) or `reshuffle_count`
(consecutive reshuffles). The exact `MIX_*` constants are pinned and property-tested at the Reshuffle
dev-story. `level_start_timestamp` is read through the injectable `TimeProvider` seam (ADR-0009), never
`Time.get_unix_time_from_system()` directly. Cross-level seed collisions are harmless (different card
sets → solvability still holds; at worst a déjà-vu layout).

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `level_id` | int | 1 – unbounded | Identifier of the current level (`LevelConfig.level_id`) |
| `level_start_timestamp` | int | Unix epoch seconds | From `TimeProvider.unix_seconds()` at level entry (ADR-0009); prevents same-seed replay across sessions |
| `reshuffle_count` | int | [1, MAX_RESHUFFLES] | Increments per use; guarantees two reshuffles on same level ≠ same layout |
| `reshuffle_seed` | int | [0, 2^63−1] | Explicit integer mix (ADR-0009); passed as `rng.seed` to the layout shuffler only |

The reshuffle does NOT call `LevelGenerator.generate()` (that would rebuild results and the
target queue, violating AC-R01). A dedicated `LevelGenerator.reshuffle(config, seed)` helper only
re-runs the `_fisher_yates_shuffle(slot_indices, reshuffle_rng)` step (Level Generator Core Rule
8) and recomputes coverage. The card pool and target queue are preserved exactly; `is_solvable()`
holds by the same structural argument as the original generation.

**Routable-card guarantee.** After shuffling, the helper checks the predicate "≥1 exposed card
routes directly OR opens further coverage." If it fails, it re-rolls with the next
`reshuffle_count` seed (bounded retry, e.g. ≤8 attempts) until it holds — guaranteed satisfiable
because the board is solvable. This makes EC-05 "spend-and-still-stuck" impossible.

**Example:** `level_id=42`, `level_start_timestamp=1_718_000_000`, first reshuffle: `mix(42, 1_718_000_000, 1)` — a fixed integer, reproducible on every platform.
**Example:** Second reshuffle of the same level: `mix(42, 1_718_000_000, 2)` — different `reshuffle_count` → different seed, different layout.

---

### 7. Gem-to-coin conversion

`coins_received = gems_spent × GEM_TO_COIN_RATE`

`GEM_TO_COIN_RATE = 25`  (below the 35-coin booster-parity rate, deliberately penalised)

**Variables:**

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `gems_spent` | int | [1, 50] | Capped at daily conversion limit |
| `GEM_TO_COIN_RATE` | int | 25 (fixed) | Coins per gem; must remain below the booster-equivalence rate |
| `coins_received` | int | [25, 1,250] | At the daily cap of 50 gems: max 1,250 coins/day from conversion |

**Output Range:** 25 (1 gem) to 1,250 (50 gems, daily cap).
**Example:** Player converts 10 gems → 250 coins.
**Note:** `gems_spent = 0` cannot reach this formula — it is rejected upstream by EC-14 (0-amount
guard). Conversion-coins count against `DAILY_GEM_CONVERT_CAP` (50 gems), NOT `DAILY_COINS_CAP`.

---

### 8. Daily ad-earn cap

`ads_watched_today' = ads_watched_today + 1`  (only if `ads_watched_today < MAX_ADS_PER_DAY`)

`MAX_ADS_PER_DAY = 3`

`earn_available = (ads_watched_today < MAX_ADS_PER_DAY) AND (ad_coins_today < DAILY_COINS_CAP) AND (not ComplianceService.is_restricted())`

**Output:** Boolean; determines whether the rewarded ad button is shown.
**Example:** Player has watched 2 ads today → button shows. After 3rd ad → button hides until midnight UTC reset.

## Edge Cases

- **EC-01 — Zero balance, buy attempt:** If `coins = 0` and player buys the Picker (120 coins): `WalletData.spend(COINS, 120)` guard fails → `SPEND_FAILED(COINS, 120, 0)` emitted → `WalletService` does NOT call any board mutation → UI shows "not enough coins" toast. Board state is unchanged.

- **EC-02 — _(removed: Undo cut 2026-06-12)_**
- **EC-03 — _(removed: Undo cut 2026-06-12)_**
- **EC-04 — _(removed: Undo cut 2026-06-12)_**

- **EC-05 — Reshuffle when board is stuck (discard full, no legal move):** If all discard slots are full and every exposed card has no matching open stack: a valid Reshuffle use. Precondition `NOT board.is_game_over()` passes (the board is stuck but not yet lost — LOSE triggers on the next attempted tap, not on the state itself). `spend(COINS, 250)` is attempted. On success, the new layout is produced under the **routable-card guarantee** (Core Rule 10 / Formula 6): it is re-rolled until at least one exposed card routes directly or opens coverage. The discard remains intact. **The reshuffled board is therefore never immediately stuck — the player always gets a meaningful move for their 250 coins, so the "spend-and-still-stuck, no refund" failure mode is designed out.**

- **EC-06 — Extra Discard Slot when discard is already full (purchase-ahead-only → BLOCKED):** If all current discard slots are occupied, the precondition `occupied_discard_cards < _active_discard_slots` **fails**: `BOOSTER_PRECONDITION_FAILED(EXTRA_DISCARD, reason=DISCARD_FULL)` is returned, no coins deducted. Extra Discard Slot is a *proactive* buy made while room remains — it is deliberately NOT a one-tap-from-LOSE rescue button. The UI greys the button when the discard is full and surfaces "buy earlier — no room to expand into now." (Reshuffle, with its routable guarantee, is the tool for an already-full board.)

- **EC-07 — Extra Discard Slot at maximum (already expanded twice):** If `_active_discard_slots == MAX_DISCARD_SLOTS (7)`: `BOOSTER_PRECONDITION_FAILED` returned. `spend` is not called. Coins unchanged. The UI button is greyed out with a visual indicator that maximum slots have been reached.

- **EC-08 — Picker invalid target:** If the player activates the Picker and the chosen card is no longer on the floor (already removed) or the board is over, `use_picker` rejects it **before** `spend` is called: `BOOSTER_PRECONDITION_FAILED(PICKER, INVALID_TARGET)` is emitted, no coins are deducted, no board mutation occurs. (The Picker plays immediately, so there is no in-progress/double-tap state — the former Hint `ALREADY_IN_PROGRESS` path no longer exists.)

- **EC-09 — Transaction failure mid-level (atomic rollback via snapshot):** If `spend(COINS, 250)` returns `true` (coins deducted for a Reshuffle) but the board mutation subsequently raises an unexpected error: `WalletService` restores the balance by **direct assignment** `wallet.coins = pre_spend_balance` (the value captured before the deduction) → emits `TRANSACTION_ROLLED_BACK(COINS, 250)` → board mutation is not applied → board remains in its pre-activation state → error is logged. **Rollback must NOT use `earn()`** — near `MAX_BALANCE` the clamp would silently truncate the re-credit and the player would lose coins (see AC-W05b). Snapshot assignment restores the exact pre-spend value regardless of proximity to the cap.

- **EC-10 — Daily reward cap reached, rewarded ad attempted:** If the daily REWARDED_AD coin cap (e.g. 500) is already hit: `DailyCapTracker` computes remaining = 0 → `WalletData.earn` is NOT called → `EARN_CAP_REACHED(REWARDED_AD)` emitted → UI shows "daily limit reached." The ad impression was already shown — no refund.

- **EC-11 — Partial cap earn:** If 40 coins of daily cap remain and a 60-coin rewarded ad completes: `WalletService` clamps to 40 → `WalletData.earn(COINS, 40, REWARDED_AD)` is called → 40 coins credited → `EARNED(COINS, 40, REWARDED_AD, ...)` emitted. Player receives partial reward.

- **EC-12 — Child user (age_band = CHILD) attempts IAP:** If `ComplianceService.is_restricted() == true` and player taps a "Buy Gems" button: `WalletService` checks compliance before initiating IAP → IAP flow is NOT initiated → `IAPService` is never called → no balance change → UI shows parental-approval message. `WalletService` never reads `age_band` directly.

- **EC-13 — Gem-to-coin conversion at daily cap:** If player has already converted 50 gems today (`DAILY_GEM_CONVERT_CAP`) and attempts another conversion: the conversion is blocked → `EARN_CAP_REACHED(GEM_CONVERT)` emitted → coins unchanged.

- **EC-14 — Earn of 0 amount (logic error guard):** If any code path calls `earn(currency, 0, source)`: this is rejected pre-check as a logic error → no mutation → no event emitted → error is logged. Similarly, `spend(currency, 0)` returns `false` without emitting `SPEND_FAILED` (0-amount spend is a caller bug).

- **EC-15 — Reshuffle on an already-won board:** If `board.is_won() == true` when `use_booster(RESHUFFLE)` is called: `BOOSTER_PRECONDITION_FAILED` returned. Coins unchanged. (This edge case should be impossible in normal play but must be defended defensively.)

- **EC-16 — _(removed: Undo cut 2026-06-12)_**

## Dependencies

**This system depends on:**

| System | Hard/Soft | Interface |
|--------|-----------|-----------|
| **Save Service** (`core/save_data.gd`, `autoloads/save_service.gd`) | Hard | Wallet balance (coins, gems) is persisted inside `SaveData`; `WalletService` reads/writes through `SaveService.data`. **Schema bump required:** `SaveData` currently has no wallet fields and `CURRENT_SCHEMA_VERSION = 1`. Adding `wallet_coins`/`wallet_gems` bumps it to 2 with an explicit `_migrate()` step (`if version == 1: out["wallet_coins"] = 0; out["wallet_gems"] = 0; version = 2`). `from_dict()` defaults missing keys to 0. |
| **ComplianceService** (`autoloads/compliance_service.gd`) | Hard | IAP and ad-based coin/gem rewards require `not ComplianceService.is_restricted()` to pass (the API has no `can_show_ads()`/`can_show_iap()`; `is_restricted()` is the canonical gate and treats UNKNOWN as restricted — see Core Rule 5). Economy never reads `age_band` directly (ADR-0005). Child users earn coins through level wins only. |
| **BoardModel** (`core/board_model.gd`) | Hard | Boosters that mutate board state (Reshuffle, Extra Discard Slot) must do so through `BoardModel` — never by writing view state directly. Reshuffle calls a new generation of slot assignments preserving card set + queue. Extra Discard Slot expands the mutable `_active_discard_slots` that `BoardModel` enforces (ADR-0010). |
| **LevelData / Level Generator** (`autoloads/level_data.gd`, `core/level_generator.gd`) | Hard | Reshuffle must produce a level that satisfies `LevelData.is_solvable()` (ADR-0003). The generator's `pick_operands` helper and solvability invariant constrain what a valid reshuffle can look like. |
| **ADR-0001** (model/view split) | Hard | `WalletData` is a pure `core/` `RefCounted`; `WalletService` is the autoload wrapper. Economy never touches Node tree or scene state. |
| **ADR-0003** (solvability invariant) | Hard | Reshuffle must preserve `card_count == 3 × queue_occurrences(R)` for every result R. |
| **ADR-0005** (audience positioning) | Hard | All IAP/ad-earn paths check `ComplianceService`; child users get coins-only mode. |
| **Difficulty Schedule** (`assets/data/difficulty_schedule.tres`) | Soft | Win-rate target 75–85% calibrated *without* boosters (per level-generator GDD); if economy makes boosters too cheap and usage rates climb, this assumption breaks and the schedule needs re-calibration. Data-level coupling only. |

**Systems that depend on this:**

| System | Direction | Nature |
|--------|-----------|--------|
| **Level Generator** (design-level) | Hard design dep | Long-tail player fantasy at the R_max plateau (level ~85+) *requires* meta-progression (XP/stars/unlocks) to be live. Deck Economy is the faucet side of that meta-progression. (No code coupling — generator never reads wallet state.) |
| **Scoring / Stars** (planned, S2-011) | Soft | Stars earned per level are a coin faucet. The star formula and coin-per-star rate must be agreed between this GDD and the Scoring GDD. |
| **IAP Service** (planned, M4) | Hard | `IAPService` calls `WalletService.earn(GEMS, amount, SOURCE_IAP)` after a verified purchase. Economy defines the gem amounts; IAPService does not own them. |
| **Ad Service** (planned, M4) | Hard | `AdService` calls `WalletService.earn(COINS, amount, SOURCE_REWARDED_AD)` after a completed rewarded ad. Rate and daily cap defined here. |
| **Analytics** (planned, M5) | Soft | Economy emits `GameEvent`s (`booster_activated`, `currency_earned`, `currency_spent`) that the analytics layer subscribes to. |
| **HUD / UI** (`scenes/ui/`) | Soft | Wallet balance displayed in HUD. Booster buttons in game UI. UI reads `WalletService.data`; never mutates wallet directly. |
| **First-Time Tutorial** (`core/tutorial_logic.gd`) | Soft | Tutorial may introduce the Picker at a scripted moment (see `first-time-tutorial.md`). Economy must be live for tutorial to demonstrate it. |

**Provisional assumptions** (undesigned dependencies):
- *Scoring/Stars GDD* is not yet written. The coin-per-star rate used in this GDD is a starting proposal, not a final figure.
- *IAP Service / Ad Service* are not yet designed. The gem earn amounts and ad coin caps defined here are design targets; the service implementations must respect them.

## Tuning Knobs

All economy values live in an `EconomyConfig` resource (`assets/data/economy_config.tres`) so a designer can retune via remote config without a code change.

### Earn rates

| Knob | Default | Safe Range | What breaks at extremes |
|------|---------|-----------|------------------------|
| `COINS_WIN_1_STAR` | 40 | 20–80 | Low → players feel unrewarded; High → boosters trivially affordable |
| `COINS_WIN_2_STAR` | 55 | 35–100 | Must stay between 1-star and 3-star values |
| `COINS_WIN_3_STAR` | 75 | 50–150 | High → 3-star grind is economically worth it; Low → stars feel cosmetic |
| `COINS_DAILY_CHALLENGE` | 150 | 75–300 | Low → daily challenge feels unrewarded; High → daily engagement is buy-pass |
| `COINS_REWARDED_AD` | 60 | 30–120 | Low → ads don't feel worth watching; High → ad farming dominates earn |
| `CLEAN_CLEAR_BONUS` | 20 | 0–50 | Coin bonus for a zero-booster-spend level clear. 0 → the "not-spending feels good" pillar is unmechanized; High → over-rewards trivial bare-handed wins and inflates coin supply |
| `MAX_ADS_PER_DAY` | 3 | 1–10 | Low → frustrating cap; High → ad farming negates progression intent |
| `STREAK_DAY_2_TO_4_BONUS` | 25 | 10–50 | Additive on daily challenge; keeps streak meaningful |
| `STREAK_DAY_5_TO_6_BONUS` | 50 | 25–100 | Escalation; too high → streak anxiety (breaks "calm, not frantic") |
| `STREAK_DAY_7_BONUS` | 100 | 50–200 | Weekly anchor; too high → users feel punished for missing a day. **Live-ops lever:** if streak anxiety still appears in M3 data even with the day-3 reset floor, soften further (streak-freeze item) — not raise coin rewards, which only inflates income without reducing anxiety. |
| `STREAK_RESET_FLOOR` | 3 | 1–4 | Day the streak falls back to on a missed day (Core Rule 16). 1 → harsher (closer to a full reset); 4 → barely any penalty. 3 is the calm-not-frantic default — a lapse costs momentum, never wipes to zero. |
| `DAILY_COINS_CAP` | 500 | 200–1,500 | **Scope: rewarded-ad coin income only** (Rule 15). Level/challenge/streak/milestone/clean-clear are uncapped; gem-conversion uses its own cap. Low → frustrates ad-watchers; High → ad farming yields too much |
| `DAILY_GEM_CONVERT_CAP` | 50 | 10–200 | Low → gems stay premium; High → soft-to-premium conversion undermines IAP |

### Booster costs

| Knob | Default | Safe Range | What breaks at extremes |
|------|---------|-----------|------------------------|
| `PICKER_COST_COINS` | 120 | 60–250 | Low → every-board Picker use (boosters feel free, not earned); High → never used, system dead |
| `RESHUFFLE_COST_COINS` | 250 | 100–500 | Low → Reshuffle is the default response to any difficulty; High → never purchased |
| `EXTRA_DISCARD_COST_COINS` | 350 | 150–600 | Low → discard pressure loses teeth as a mechanic; High → "rescue at any cost" moment feels predatory |
| `PICKER_COST_GEMS` | 3 | 1–10 | Gem costs should scale at ~1 gem : 35 coins parity rate |
| `RESHUFFLE_COST_GEMS` | 7 | 3–20 | — |
| `EXTRA_DISCARD_COST_GEMS` | 10 | 5–25 | — |
| `GEM_TO_COIN_RATE` | 25 | 10–35 | Must stay below booster-parity rate (35); above 35 = gems to coins is better than buying boosters directly (breaks IAP value) |

### Balance limits

| Knob | Default | Safe Range | What breaks at extremes |
|------|---------|-----------|------------------------|
| `COINS_MAX` | 999,999 | 50,000–unbounded | Very low cap → hoarders hit ceiling and see "coins wasted"; essentially no gameplay effect above ~10,000 |
| `GEMS_MAX` | 9,999 | 1,000–unbounded | Very low → IAP whale is blocked; no gameplay effect above ~5,000 |
| `MAX_DISCARD_SLOTS` | 7 | 6–8 | 6 = one extra slot ever; 8 = player can stack 3 extra slots (very forgiving) |

### ~~Hint algorithm weights~~ — REMOVED (Picker has no scoring, 2026-06-13)

The `ROUTES_WEIGHT` / `OPENS_WEIGHT` / `RELIEF_WEIGHT` knobs are struck — the Picker is
player-driven and has no scoring heuristic to tune.

### Milestone coin gift table (one-time)

| Level milestone | Coin gift |
|----------------|-----------|
| Level 5 (first session end) | 100 coins |
| Level 10 | 150 coins |
| Level 25 | 200 coins |
| Level 50 | 300 coins |
| Level 100 | 500 coins |
| Level 200 | 750 coins |

### Gem gift table (free drips, one-time)

| Trigger | Gem gift |
|---------|---------|
| Tutorial completion | 15 gems |
| Every 10 levels cleared | 5 gems |
| First 3-star on any new operation world | 10 gems |
| Daily challenge 7-day streak maintained | 10 gems (weekly) |
| Major achievement unlocks | 3–10 gems each |

## Visual/Audio Requirements

The Deck Economy is a data/infrastructure system. It does not own any visual or audio assets
directly; it emits `GameEvent`s that the view layer and audio layer respond to.

**Expected view-layer responses** (not specified here — owned by the View GDD and art-direction):
- Coin earn: a brief "+N coins" float-up label and coin icon, played at the earn source (stack
  clear, level-complete screen, ad completion).
- Coin spend (booster purchase): a brief "−N coins" label near the booster button.
- Picker activation: an arming cue, then the chosen covered card lifts out and flies to its
  stack/discard (the played-card animation) — must read in colorblind mode (shape/motion cue).
- Reshuffle activation: a shuffle/deal animation as cards reposition to the new layout.
- Extra Discard Slot activation: the discard row expands to show the new slot.

**Audio** (owned by the Audio GDD when authored):
- Booster purchase: a satisfying "spend" SFX distinct from the level-clear SFX.
- Insufficient funds: a gentle negative tone (not harsh; respects the calm tone).
- Picker activation: a soft "select / lift" chime.

No new art assets or shaders are required by the economy model itself.

## UI Requirements

### Wallet HUD (in-game)
- **Coin balance display:** visible during gameplay in the HUD (top bar). Shows current coin count with a coin icon. Updates in real-time on earn/spend. No Gem balance displayed during gameplay (gems are a menu-layer currency).
- **Booster tray:** three booster buttons in the HUD (Picker / Reshuffle / Extra Discard Slot). Each button shows:
  - Icon for the booster type
  - Coin cost label
  - Greyed-out state if coin balance < cost (but button is still visible — player knows it exists)
  - Disabled state if the precondition is unmet (e.g. Reshuffle greyed out on a won board; Extra Discard greyed out only at MAX_DISCARD_SLOTS — it is allowed when the discard row is full, as a rescue)
  - Armed indicator while the Picker is awaiting the player's card selection
- **Spend confirmation (anti-misfire).** Boosters costing **≥ 250 coins** (Reshuffle, Extra
  Discard Slot) require a one-step confirm ("Spend 250 coins? [Confirm] [Cancel]") before
  deduction. Picker (120) is one-tap (low cost). Threshold lives in `EconomyConfig`
  (`SPEND_CONFIRM_THRESHOLD = 250`). This protects the
  "deliberate, occasional" spend feel and prevents fat-finger loss of a half-day's coins.
- **Distinguishable failure feedback.** Greyed buttons must communicate *why*: an **unaffordable**
  booster (balance < cost) shows a coin-tinted grey + "not enough coins" on tap; a
  **precondition-failed** booster (discard full / at max slots / won board) shows a neutral
  grey + a context message on tap. The two states must be visually distinct, and tapping an
  invalid Picker target gives a brief pulse (EC-08) — no failure is silent.
- **HUD layout budget (must be solved by the UX spec, not the single top bar).** Three 44×44pt
  booster buttons (132pt) + a 6-digit coin balance (~100pt at large-text scale) + padding exceed
  a 390pt-wide portrait bar once safe-area insets apply. The booster tray therefore moves to the
  **bottom** of the play area (thumb-reachable) with the coin balance top-right; the single
  "top bar" constraint is dropped. UX spec owns the final arrangement; 44pt targets are
  non-negotiable.
- **No IAP surface during gameplay.** Economy-related IAP/gem purchase offers appear only on pre-level screens, post-level screens, or the dedicated shop screen. Never as a mid-puzzle interruption.

### Level pre/post screens
- **Pre-level booster selection** (optional feature, post-M3): allow players to equip 1 booster per level before starting (deliberate spend, not panic spend). Shows coin cost and current balance.
- **Post-level earn summary:** "You earned +N coins" card with the earn breakdown (base + star
  bonus + streak + clean-clear bonus when earned). **CTA hierarchy:** the primary **Continue**
  action is the most prominent element and reachable in one tap with zero interaction with any ad
  offer. The "Watch an ad to double your reward" offer is a clearly secondary, dismissible element
  — never the primary CTA (avoids the dark pattern of friction on the non-monetizing path). The
  ad offer is **hidden** (not just disabled) when the player is restricted (`is_restricted()`) OR
  the daily ad cap is exhausted (`ads_watched_today >= MAX_ADS_PER_DAY` or `ad_coins_today >=
  DAILY_COINS_CAP`), so a player can never watch a full ad and then receive nothing (EC-10). The
  double-reward offer is shown **at most once per session**, not after every level.

### Shop / currency screen (menu layer)
- **Coin balance + Gem balance:** both visible in the shop header.
- **IAP catalog:** all SKUs from Tuning Knobs §IAP catalog. Clearly priced in real currency (e.g. "$3.99"). No dark patterns (e.g. no "Buy Now — Limited Time!" without a real expiry).
- **Rewarded ad coin earn button:** "Watch ad for +60 coins" button — shows remaining daily ad count. Hidden if ads unavailable (CHILD user, consent denied, or daily cap reached).
- **Gem-to-coin conversion:** accessible in the shop. Shows rate (1 gem = 25 coins) and daily cap.
- **Remove Ads SKU** displayed prominently if ads are currently showing; de-listed if already purchased (no need to surface what the player already owns).

### Accessibility requirements
- Picker arming + selection must use a shape/motion cue, not only color (colorblind accessibility — consistent with `StackPalette` Okabe-Ito pattern in `data/stack_palette.gd`).
- Booster buttons must have minimum 44×44pt tap targets (mobile touch accessibility).
- Coin and gem amounts must use large-text-mode-compatible font scaling.
- "Insufficient funds" feedback must not be silent — a toast or icon pulse ensures the player understands why the booster didn't activate.

> **📌 UX Flag — Deck Economy**: This system has UI requirements. In Phase 4 (Pre-Production), run `/ux-design` to create UX specs for:
> - **Booster tray** (HUD element, in-game)
> - **Post-level earn summary card**
> - **Shop / currency screen**
> - **Pre-level booster selection** (if implemented in M3)
>
> Stories that reference UI for any of these should cite `design/ux/[screen].md`, not this GDD directly. Note this in the systems index.
>
> **Pre-UX decisions now resolved in this GDD (so `/ux-design` can start without stalling):**
> spend-confirm policy (≥250-coin threshold), distinguishable failure feedback (unaffordable vs
> precondition), HUD layout (bottom booster tray + top-right balance), ad-offer CTA hierarchy +
> cap-gating + once-per-session, and Reshuffle-into-stuck (designed out via the routable-card
> guarantee). The UX spec owns visual arrangement; these interaction contracts are fixed.

## Acceptance Criteria

`[B]` = BLOCKING (automated unit/integration test). `[A]` = ADVISORY (manual check or playtest).

> **Event-name convention:** AC shorthand (`SPENT(...)`, `EARNED(...)`, `SPEND_FAILED(...)`,
> `TRANSACTION_ROLLED_BACK(...)`, `BOOSTER_ACTIVATED(...)`, etc.) maps 1:1 to the `EconomyEvent.Kind`
> names defined in Detailed Design §Economy Events. Tests assert against those canonical enum
> values (a separate type from board `GameEvent`).

### Clean-clear efficiency bonus

- **AC-EFF01 [B]** GIVEN a level won with `boosters_used_this_level == 0` and a 2-star result, WHEN the win is scored, THEN `earn(COINS, 55 + 20, LEVEL_WIN)` is granted (`CLEAN_CLEAR_BONUS = 20` added).
- **AC-EFF02 [B]** GIVEN a level won after at least one booster was activated (`boosters_used_this_level ≥ 1`), WHEN the win is scored, THEN no clean-clear bonus is added (only the star-weighted + first-win coins).
- **AC-EFF03 [B]** GIVEN `CLEAN_CLEAR_BONUS = 0` (knob disabled), WHEN any level is won clean, THEN no bonus is added (the mechanic is fully knob-gated).

### Wallet — spend

- **AC-W01 [B]** GIVEN `coins = 100`, WHEN `spend(COINS, 30)`, THEN returns `true`, `coins == 70`, `SPENT(COINS, 30, 70)` emitted.
- **AC-W02 [B]** GIVEN `coins = 20`, WHEN `spend(COINS, 30)`, THEN returns `false`, `coins == 20` unchanged, `SPEND_FAILED(COINS, 30, 20)` emitted.
- **AC-W03 [B]** GIVEN `coins = 0`, WHEN `spend(COINS, 1)`, THEN returns `false`, `coins == 0`, `SPEND_FAILED` emitted.
- **AC-W04 [B]** GIVEN any balance, WHEN `spend(COINS, 0)`, THEN returns `false` without emitting any event and without mutating balance (logic-error guard).
- **AC-W05 [B]** GIVEN a stub `BoardModel` configured to raise on its mutation, AND `coins = 100`, WHEN `spend(COINS, 50)` succeeds (deducting to 50) and the board mutation then raises, THEN `WalletService` restores by snapshot assignment → `coins == 100`, `TRANSACTION_ROLLED_BACK(COINS, 50)` emitted.
- **AC-W05b [B]** GIVEN `coins = COINS_MAX − 5`, `spend(COINS, 250)` succeeds (→ `COINS_MAX − 255`), WHEN the board mutation raises and rollback fires, THEN `coins == COINS_MAX − 5` exactly (snapshot restore — NOT an `earn(250)` that the `MAX_BALANCE` clamp would truncate). This is the regression test for the EC-09 clamp defect.

### Wallet — earn

- **AC-W06 [B]** GIVEN `coins = 400`, WHEN `earn(COINS, 55, LEVEL_WIN)`, THEN `coins == 455`, `EARNED(COINS, 55, LEVEL_WIN, 455)` emitted.
- **AC-W07 [B]** GIVEN `coins = COINS_MAX − 10`, WHEN `earn(COINS, 100, LEVEL_WIN)`, THEN `coins == COINS_MAX`, `EARNED(COINS, 10, LEVEL_WIN, COINS_MAX)` emitted (actual credited = 10, clamped).
- **AC-W08 [B]** GIVEN any balance, WHEN `earn(COINS, 0, LEVEL_WIN)`, THEN no mutation, no event emitted (logic-error guard).

### Daily cap

- **AC-C01 [B]** GIVEN daily REWARDED_AD coins already at `DAILY_COINS_CAP` (500), WHEN `earn(COINS, 60, REWARDED_AD)` would be requested, THEN `earn` is NOT called on `WalletData`, `coins` unchanged, `EARN_CAP_REACHED(REWARDED_AD)` emitted.
- **AC-C02 [B]** GIVEN daily REWARDED_AD coins at 460 (cap = 500), WHEN 60 REWARDED_AD coins attempted, THEN only 40 coins credited, `EARNED(COINS, 40, REWARDED_AD, ...)` emitted.
- **AC-C03 [B]** GIVEN daily REWARDED_AD coins at cap, WHEN `earn(COINS, 55, LEVEL_WIN)`, THEN 55 coins credited without cap interference (LEVEL_WIN is uncapped).

### Picker booster (replaces Hint, 2026-06-13)

- **AC-P01 [B]** GIVEN a covered card whose result matches an open stack target and ≥120 coins, WHEN `use_picker(board, card_id)` is called, THEN the card is played (routed), `BOOSTER_ACTIVATED(PICKER)` emitted, 120 coins deducted, and the board `GameEvent`s are returned for the view.
- **AC-P02 [B]** GIVEN a covered card with no matching open stack, WHEN `use_picker` is called, THEN the card is played to discard (or LOSE if the discard is full) — the same resolution as a tap, bypassing coverage only.
- **AC-P03 [B]** GIVEN the target card is already removed (or the board is over), WHEN `use_picker` is called, THEN `BOOSTER_PRECONDITION_FAILED(PICKER, INVALID_TARGET)` is returned and coins are unchanged.
- **AC-P04 [B]** GIVEN coins < `PICKER_COST_COINS`, WHEN `use_picker` is called, THEN `SPEND_FAILED` is emitted, no card is played, and `boosters_used_this_level` is unchanged.
- **AC-P05 [B]** GIVEN any board state, WHEN the Picker plays a card, THEN no arithmetic result/operands/solution is emitted or displayed — only board `GameEvent`s (route/discard) flow (no-arithmetic-solving pillar holds).

### Undo booster — REMOVED (2026-06-12)

_Undo was cut from the design. AC-U01–U07 are withdrawn. No Undo behaviour is tested or implemented._

### Reshuffle booster

- **AC-R01 [B]** GIVEN a valid board. WHEN Reshuffle is used. THEN `new_board._result_of == original._result_of`, `new_board._target_queue == original._target_queue`, `new_board._removed == original._removed`, 250 coins deducted.
- **AC-R02 [B]** GIVEN 4 cards already removed. WHEN Reshuffle is used. THEN those 4 cards remain removed in the new board; stack state, discard, and draw index are all preserved.
- **AC-R03 [B]** GIVEN any valid board state. WHEN Reshuffle is used. THEN `LevelData.is_solvable(new_board) == true` (solvability invariant preserved).
- **AC-R04 [B]** GIVEN `level_id = 42` and an **injected** `level_start_timestamp = 1_718_000_000` (via a `TimeProvider` seam, not `Time.get_unix_time_from_system()`), WHEN Reshuffle runs with `reshuffle_count = 1` then `2`, THEN `reshuffle_seed == mix(42, 1_718_000_000, 1)` and `mix(42, 1_718_000_000, 2)` respectively (the explicit integer mix of Formula 6 / ADR-0009 — **not** `hash()`), the value is reproducible run-to-run, the two seeds differ, and the two slot-assignment arrays differ. (Determinism requires the injected clock + the platform-stable integer mix — see ADR-0009.)
- **AC-R08 [B]** GIVEN `level_id = 42`, `reshuffle_count = 1`, injected timestamps `T1 = 1_718_000_000` and `T2 = 1_718_000_001`, WHEN Reshuffle runs with each, THEN the two seeds differ and the two layouts differ (cross-session anti-replay).
- **AC-R09 [B]** GIVEN a board that is currently stuck (discard full, no exposed card routes), WHEN Reshuffle runs, THEN the resulting layout has ≥1 exposed card that routes directly or opens coverage (routable-card guarantee; the board is never immediately stuck post-reshuffle).
- **AC-R05 [B]** GIVEN `board.is_won() == true`. WHEN `use_booster(RESHUFFLE)`. THEN `BOOSTER_PRECONDITION_FAILED` returned, coins unchanged.
- **AC-R07 [B]** GIVEN discard full (5 cards), all exposed cards have no matching open stack. WHEN Reshuffle is used. THEN new board has same discard state, new layout, 250 coins deducted; no automatic win or lose is triggered by the reshuffle itself.

### Extra Discard Slot booster

- **AC-E01 [B]** GIVEN `_active_discard_slots == 5`, `MAX_DISCARD_SLOTS == 7`. WHEN `use_booster(EXTRA_DISCARD_SLOT)`. THEN `_active_discard_slots == 6`, `_discard.size() == 6` (new slot is −1/empty), 350 coins deducted.
- **AC-E03 [B]** GIVEN Extra Discard Slot was used during a level. WHEN level ends (win, lose, or abandon). THEN `_active_discard_slots` resets to `DISCARD_SLOTS` (5) for the next level.
- **AC-E04 [B]** GIVEN `_active_discard_slots == MAX_DISCARD_SLOTS == 7`. WHEN `use_booster(EXTRA_DISCARD_SLOT)`. THEN `BOOSTER_PRECONDITION_FAILED` returned, coins unchanged.
- **AC-E05 [B]** (revised 2026-06-14) GIVEN the discard row is full (`occupied_discard_cards == _active_discard_slots`) and below the slot cap. WHEN `use_booster(EXTRA_DISCARD_SLOT)` is called. THEN it succeeds: one slot is added (`_active_discard_slots` +1), coins/stock are spent, and `BOOSTER_ACTIVATED(EXTRA_DISCARD)` is emitted — i.e. it works as a rescue. (The former "purchase-ahead-only / DISCARD_FULL block" was removed; only AC-E04's cap still gates it.)
- **AC-E06 [B]** GIVEN `_active_discard_slots == 5` with only 3 cards occupied (room remains). WHEN `use_booster(EXTRA_DISCARD_SLOT)`. THEN it succeeds: `_active_discard_slots == 6`, `_discard.size() == 6`, 350 coins deducted (proactive purchase while room remains).

### Compliance / IAP gating

- **AC-CL01 [B]** GIVEN `ComplianceService.is_restricted() == true`, WHEN `WalletService.initiate_iap(SKU_GEM_PACK_S)` is called, THEN (a) `IAPService.purchase()` is never called, (b) `gems` is unchanged, (c) `IAP_BLOCKED(sku=GEM_PACK_S, reason=COMPLIANCE_RESTRICTED)` is emitted.
- **AC-CL02 [B]** Behavior test (replaces the prior grep gate): GIVEN a stub `SaveData` with `age_band = CHILD` injected directly into `WalletService` (bypassing nothing — `WalletService` must still consult `ComplianceService`), WHEN `earn(COINS, 60, SOURCE_REWARDED_AD)` is requested, THEN the earn is blocked, proving the gate routes through `ComplianceService.is_restricted()` and not a direct `age_band` read.
- **AC-CL03 [A]** Code-review gate (advisory): no `WalletService`/`WalletData` source reads `SaveData.age_band` directly — verified at PR review.

### Child-mode earn (play-based earn is NOT gated)

- **AC-CH01 [B]** GIVEN `ComplianceService.is_restricted() == true` (child user), WHEN player wins a level and `earn(COINS, 55, LEVEL_WIN)` is requested, THEN `coins` increases by 55 and `CURRENCY_EARNED` is emitted (play earn is uncapped and ungated).
- **AC-CH02 [B]** GIVEN `is_restricted() == true`, WHEN `earn(COINS, 60, SOURCE_REWARDED_AD)` is requested, THEN the earn is blocked, `coins` unchanged (ad earn IS gated).

### Gem→coin conversion (Formula 7)

- **AC-GC01 [B]** GIVEN `gems = 20`, `coins = 100`, WHEN `convert_gems_to_coins(10)`, THEN `gems == 10`, `coins == 350`, both `CURRENCY_SPENT(GEMS, 10, 10)` and `CURRENCY_EARNED(COINS, 250, GEM_CONVERT, 350)` emitted.
- **AC-GC02 [B]** GIVEN `daily_gem_convert_used == 50` (cap), WHEN `convert_gems_to_coins(1)`, THEN blocked, `gems` unchanged, `EARN_CAP_REACHED(GEM_CONVERT)` emitted (EC-13).
- **AC-GC03 [B]** GIVEN `gems = 5`, WHEN `convert_gems_to_coins(10)`, THEN returns `false`, no balance change, `SPEND_FAILED(GEMS, 10, 5)` emitted.

### Earn triggers (Formula 1, Rules 13–18)

- **AC-EF01 [B]** GIVEN `first_win_today == true`, 3-star clean clear, WHEN scored, THEN `earn(COINS, 75 + 15 + 20, LEVEL_WIN)` (Formula 1 + 1b worked example = 110).
- **AC-EF02 [B]** GIVEN two level wins on the same calendar day, THEN the first applies `first_win_bonus = 15`, the second applies `0`.
- **AC-EF03 [B]** GIVEN login-streak day 7, WHEN the daily challenge completes, THEN `earn(COINS, 150 + 100, DAILY_CHALLENGE)` (base + streak bonus).
- **AC-EF04 [B]** GIVEN a missed day, THEN `streak_count` resets to `STREAK_RESET_FLOOR` (3), not 0; GIVEN a natural day-8 rollover (no miss), `streak_count` continues into the next cycle.
- **AC-EF05 [B]** GIVEN level 5 reached for the first time, THEN `earn(COINS, 100, MILESTONE_GIFT)` fires exactly once; subsequent visits do not re-fire.
- **AC-EF06 [B]** GIVEN tutorial completion, THEN `earn(GEMS, 15, MILESTONE_GIFT)` fires exactly once.

### Integration: Economy + BoardModel

- **AC-I01 [B]** GIVEN a real `BoardModel` and `coins = 250`. WHEN `use_booster(RESHUFFLE)` via `WalletService`. THEN the new board preserves `_result_of`, `_target_queue`, and `_removed` (AC-R01), `LevelData.is_solvable(new_board) == true`, and 250 coins are deducted.
- **AC-I02 [B]** GIVEN `coins = 250`, Reshuffle costs 250. If the board mutation raises an error. THEN `coins == 250` after rollback completes (EC-09 path); `TRANSACTION_ROLLED_BACK` emitted.

### Boundary / economy calibration

- **AC-B01 [B]** GIVEN `coins = 0`. WHEN all three coin-cost boosters are attempted. THEN `spend` returns `false` for all; no board state changes.
- **AC-B02 [B]** GIVEN `coins = COINS_MAX − 1`. WHEN `earn(COINS, 2, LEVEL_WIN)`. THEN `coins == COINS_MAX`, actual credited = 1.
- **AC-B03 [A]** Playtest target: engaged non-paying adult player earns 600–900 coins/day. **Measurement:** sum `CURRENCY_EARNED` events (sources `LEVEL_WIN`, `DAILY_CHALLENGE`, `REWARDED_AD`, streak, clean-clear) per device-day from the M3 analytics export, filtered to non-paying players with ≥3 sessions that day. **Pass:** p50 daily earn ∈ [600, 900]. **Decision rule:** p50 < 600 → raise earn or lower costs; p50 > 900 → lower earn or raise costs. Owner: economy-designer, within 2 weeks of soft launch.
- **AC-B04 [A]** Booster use-rate target: ≤1 booster per 5 levels on average. **Measurement:** `count(BOOSTER_ACTIVATED) / count(level_completed)` per non-paying cohort over a rolling 7-day window. **Decision rule:** rate > 0.20 → raise booster costs; rate ≈ 0 (economics too punishing) → lower costs. Owner: economy-designer, M3.

### No-arithmetic-solving constraint (hard rule)

- **AC-M01a [B]** GIVEN any board state, WHEN the Picker plays a card, THEN no economy event carries a `result`, `operands`, or `solution_text` field (the `EconomyEvent` class has no such field); only board route/discard `GameEvent`s flow.
- **AC-M01b [A]** Visual gate: activating the Picker does not display any card's computed result value (covered cards show their equation, never the answer). Screenshot + lead sign-off in `production/qa/evidence/`.
- **AC-M02 [A]** Code-review gate (advisory): no `WalletService`, `WalletData`, or booster activation path reads or exposes `CardData.result` to the player. Any future booster that would require reading `result` to determine its effect must be rejected at design review.

## Prototype Addendum — Locked Decks & Buff Inventory

> **Status**: Prototype (implemented 2026-06-13, this branch). Two player-facing
> additions that sit *beside* the core rules above and partially diverge from them.
> Documented here for traceability; **to be reconciled into the main rules (and an
> ADR opened) when these leave prototype.** Both are validated by automated tests
> (`tests/test_wallet_service.gd`, `tests/test_save_data.gd`,
> `tests/integration/main_booster_flow_test.gd`) and screenshot evidence.

### Addendum Overview

1. **Locked-deck unlock.** A level opens with only `PROTO_OPEN_COUNT` stacks active;
   the remaining stacks render as locked "decks." Tapping a locked deck opens a
   two-option modal (`UnlockPopup`): **Watch Ad** (prototype stub — free unlock; no
   ad SDK yet) or **Pay** `UNLOCK_COST` coins (real, atomic `WalletService.spend`).
2. **Buff inventory.** The three boosters (Picker / Reshuffle / Extra Discard) now
   have a **persisted owned count** instead of being purely coins-per-use. A tap
   consumes one for **free**; at **zero count** the same two-option modal appears
   (**Watch Ad** → grant +1 free; **Pay** `booster_coin_cost` → coin path) and the
   buff is **granted and used immediately**.

### Addendum Player Fantasy

The toolbox metaphor (Player Fantasy, above) is preserved and sharpened: you *hold*
tools, you don't rent them per use. Running out is a gentle, opt-in moment — "grab
one more" via an ad or a small coin spend — never a hard wall. Locked decks frame
extra stacks as an *earned expansion* of your sorting space, not a paywall: the ad
path means a player is never blocked for lack of coins.

### Addendum Detailed Rules

**Locked decks**
- LD-1. Stacks `[0, PROTO_OPEN_COUNT)` start open; the rest start locked
  (`BoardModel.is_stack_locked`). A locked deck shows a "+" with the coin price.
- LD-2. Tapping a locked deck emits `Stack.unlock_requested`; the controller opens
  `UnlockPopup` (one at a time; suppressed while input is locked or a result screen is up).
- LD-3. **Watch Ad** unlocks for free (stub). **Pay** spends `UNLOCK_COST` coins via
  `WalletService.spend(COINS, UNLOCK_COST, on_committed)`; the deck is added inside
  `on_committed` so a rejected spend leaves the board untouched (Core Rule 4).
- LD-4. The Pay button is disabled when `coins < UNLOCK_COST`; Watch Ad stays available.
- LD-5. No compliance gate on the ad option yet (deferred — see Addendum Open Items).

**Buff inventory**
- BI-1. Each booster has a persisted count (`SaveData.boosters_picker` /
  `_reshuffle` / `_extra_discard`), seeded **once** from
  `EconomyConfig.starting_booster_count` (gated by `SaveData.boosters_seeded`).
- BI-2. The HUD tile shows the owned count; an empty buff dims and shows a "+" cue.
- BI-3. **Tap with count > 0:** consume one for free (`WalletService.consume_booster`)
  and activate via the `*_from_stock` path (no coin spend). `boosters_used_this_level`
  still increments (clean-clear bonus forfeited — Formula 1b holds).
- BI-4. **Tap at count 0:** open `UnlockPopup`. **Watch Ad** → `grant_booster(+1)`
  then activate from stock (net free use). **Pay** → the coin path (`use_picker` /
  `use_reshuffle` / `use_extra_discard`) spends `booster_coin_cost` and activates now.
- BI-5. Activation precondition checks (INVALID_TARGET / WON_BOARD / AT_MAX /
  DISCARD_FULL) run *before* any consume or spend, exactly as in Core Rules 8/10/11.
  An empty-stock `*_from_stock` call emits `BOOSTER_PRECONDITION_FAILED(NO_STOCK)`.
- BI-6. **Divergence note:** for normal taps this *replaces* the coins-per-use model
  (Rule 19). Rule 19's per-booster coin costs are retained and now serve as the
  **top-up "Pay" price** at zero stock. The coin-spend `use_*` methods are unchanged.

### Addendum Formulas

| Value | Symbol | Default | Source |
|-------|--------|---------|--------|
| Locked-deck unlock price | `UNLOCK_COST` | 100 coins | `scenes/main/main.gd` (prototype constant — not yet an `EconomyConfig` knob) |
| Open stacks at level start | `PROTO_OPEN_COUNT` | 1 | `scenes/main/main.gd` |
| Starting buff count (each) | `starting_booster_count` | 3 | `EconomyConfig` |
| Buff top-up "Pay" price | `booster_coin_cost(type)` | 120 / 250 / 350 | Rule 19 (`EconomyConfig`) |

Buff top-up uses the existing spend transaction (Formula 3). Locked-deck Pay:
`can_unlock = coins ≥ UNLOCK_COST`; on success `coins' = coins − UNLOCK_COST`.

### Addendum Edge Cases

- **EC-LD1 — Pay with insufficient coins:** Pay button disabled; if reached anyway,
  `WalletService.spend` returns false (`SPEND_FAILED`), board untouched, popup dismissed.
- **EC-LD2 — Dismiss without choosing:** backdrop tap or ✕ closes the popup; the deck
  stays locked; no spend, no board change.
- **EC-BI1 — Consume at zero:** `consume_booster` returns false (no underflow); UI never
  reaches this because a zero count routes to the popup instead.
- **EC-BI2 — `*_from_stock` with empty stock (defensive):** emits
  `BOOSTER_PRECONDITION_FAILED(NO_STOCK)`, no activation.
- **EC-BI3 — Seed-once:** a player who spends all of a buff to 0 is **not** re-granted on
  reload (`boosters_seeded` stays true). A v4→v5 migrated (or fresh) save is seeded once.
- **EC-BI4 — Pay-path precondition fail (e.g. Extra Discard at the slot cap):** no coins spent,
  no count change (preconditions run before payment).

### Addendum Dependencies

| System | Direction | Interface |
|--------|-----------|-----------|
| **SaveService** (`core/save_data.gd`) | Writes to | Booster counts persist in `SaveData` (schema **v5**: `boosters_picker/reshuffle/extra_discard` + `boosters_seeded`); migrated from v4 with a seed-on-next-load step. |
| **HUD** (`scenes/ui/hud.gd`) | Reads from | Tile count badge from `WalletService.booster_count`; refreshed on the `booster_stock_changed` signal. |
| **BoardModel** | Commands | `is_stack_locked` / `unlock_stack` (locked decks); `*_from_stock` activation reuses the same board effects as the coin path. |

### Addendum Tuning Knobs

- `starting_booster_count` (`EconomyConfig`, default 3, safe 0–10) — buffs each player
  starts with. 0 makes every first use go through the top-up popup.
- `UNLOCK_COST` / `PROTO_OPEN_COUNT` (prototype constants in `main.gd`) — promote to
  `EconomyConfig` when locked decks leave prototype.

### Addendum Acceptance Criteria

- **AC-LD1 [Logic]** Tapping a locked deck shows `UnlockPopup` and does NOT unlock until a
  choice is made (`test_adding_a_deck_unlocks_a_stack_in_scene`).
- **AC-LD2 [Logic]** Choosing Pay debits exactly `UNLOCK_COST` and unlocks the stack
  (`test_paying_coins_unlocks_a_deck_and_deducts_the_cost`).
- **AC-BI1 [Logic]** A buff with stock is used for free (count −1, coins unchanged)
  (`test_buff_with_stock_is_used_for_free`).
- **AC-BI2 [Logic]** At zero stock, the popup shows; Watch Ad grants and uses the buff
  (`test_buff_at_zero_opens_popup_and_watch_ad_uses_it`); Pay spends `booster_coin_cost`
  and uses it (`test_buff_at_zero_pay_coins_uses_it_and_deducts`).
- **AC-BI3 [Logic]** Counts persist across a WalletService reload and are not re-seeded
  after spending to zero (`test_booster_counts_persist_in_savedata_and_survive_reload`,
  `test_seed_does_not_re_grant_after_spending_to_zero`).
- **AC-BI4 [Logic]** Save schema migrates v4→v5 with counts at 0 and `boosters_seeded`
  false (`test_migrate_v4_to_v5_sets_booster_fields_and_unseeded`).

### Addendum Open Items

- **Promote prototype constants** (`UNLOCK_COST`, `PROTO_OPEN_COUNT`) to `EconomyConfig`.
- **Compliance gate the ad option** (ADR-0005) for restricted/child users before the ad
  SDK lands (M4) — currently ungated.
- **Reconcile with Rule 19** and open an ADR: decide whether buffs are inventory-first
  (this prototype) or coins-per-use (original) for production, and update the core rules.
- **Locked-deck unlock cost balance** is unauthored (placeholder 100); needs a design pass.

## Open Questions

- **Booster cost calibration** — the costs (120/250/350 coins) are provisional and derived from genre analysis (Royal Match, Triple Tile benchmarks). Real values come from M3 soft-launch data: booster use rate, daily coin income, and time-to-afford measurements. If booster use rate < 2% of levels, costs are likely too high; if > 15%, too low. Owner: economy-designer, during M3 playtest.

- **Star-rating interaction with earn** — this GDD assumes the Scoring/Stars system (S2-011, not yet authored) defines star ratings per level. The earn rates (40/55/75 by star) depend on what "1, 2, 3 stars" means mechanically (fewest discards? fastest clear?). If stars are not implemented by M3, fall back to a flat earn rate (e.g. 50 coins per win) until the Scoring GDD is authored. Owner: game-designer, during S2-011.

- **Undo booster — REMOVED (2026-06-12).** Undo was cut from the design; the prior replay-from-initial / `tap_history` coordinator open question is withdrawn. No coordinator, `tap_history`, or replay seam is built. (Recorded here for traceability; see the Status scope-change note and the review log.)

- **`EconomyEvent` type — RESOLVED in ADR-0008.** Economy events are a separate `core/` `RefCounted` + `Kind` enum (distinct from board `GameEvent`), emitted via `WalletService` signals. Ratified by ADR-0008.

- **Injectable clock (`TimeProvider`) for determinism — RESOLVED in ADR-0009.** Formula 6 uses `level_start_timestamp`, and daily caps/streaks use the calendar day. `WalletService`/`LevelData` read time through an injectable `core/` `TimeProvider` seam (default wraps `Time`, tests inject a fixed clock), never `Time.get_unix_time_from_system()` directly — keeps AC-R04/R08 deterministic and headless-safe. Ratified by ADR-0009. (This seam survives the Undo removal: Reshuffle determinism + daily caps/streaks still require it.)

- **Extra Discard Slot BoardModel change — RESOLVED in ADR-0010.** `BoardModel` currently uses `const DISCARD_SLOTS = 5` in **three** instance-capacity loops (init, `_first_empty_discard`, `_pull_matching`); all three iterate the mutable `_active_discard_slots`, and `BoardModel` gains an `expand_discard()` method. The **three** additional `DISCARD_SLOTS` reads in `core/recoverability_simulator.gd` (lines 23/47/103) deliberately **stay** on the base constant (generation-time recoverability is evaluated at base capacity). Mutable field + uncapped `expand_discard()` on `BoardModel`, with `WalletService` enforcing `MAX_DISCARD_SLOTS` (keeps `BoardModel` free of economy-config knowledge). Ratified by ADR-0010.

- **Gem drip calibration** — the gem milestone table is provisional. At ~715 lifetime gems for a year-one non-payer, they can buy 7–14 cosmetics or ~238 Pickers. If this feels too generous (devalues IAP gem packs), reduce the every-10-levels drip from 5 gems to 3. If too stingy (players feel blocked from cosmetics), increase. Real calibration requires M3 store conversion data. Owner: economy-designer.

- **Child-mode daily challenge and streak access** — this GDD allows CHILD users to access daily challenges and streak bonuses (coins only, no ads, no IAP). Confirm with the compliance review at M4 that daily-challenge mechanics do not trigger "excessive frequency of engagement" concerns under GDPR-K or COPPA. Owner: legal review, pre-M4.

- **Booster bundle pricing on store** — the $1.99 Booster 5-Pack SKU needs store policy review. Some app stores have restrictions on "consumable bundles" that require individual item prices to be disclosed. Confirm with the release-manager at M4 before submission. Owner: release-manager.

- **Remote config integration** — all economy values live in `EconomyConfig` resource (`assets/data/economy_config.tres`). At M4, these should be server-configurable via Remote Config (A/B testable without an app update). The `EconomyConfig` loader should fall back to the local `.tres` file if remote config is unavailable. Owner: tools-programmer / devops-engineer, during M4.
