# Deck Economy

> **Status**: Designed (pending independent /design-review)
> **Author**: omer.behar + agents
> **Last Updated**: 2026-06-12
> **Implements Pillar**: Meta/Retention — currencies, boosters, spend sinks that power player progression without trivialising the math
> **Creative Director Review (CD-GDD-ALIGN)**: CONCERNS (accepted) 2026-06-12 — cleared for programmer handoff. 4 accepted concerns: streak reset-to-0 loss-aversion risk (watch at M3); "double reward" ad framing (keep quiet/dismissible in UX); Hint routing-info leak (acknowledged as intentional, note added); Reshuffle-into-stuck feels unfair (UX messaging item). No redesigns required.

## Overview

The Deck Economy is CardSortMath's currency and booster layer: a two-currency model
(**Coins**, soft; **Gems**, hard) underpinned by a pure, node-free `WalletData` record
persisted via `SaveService`. Coins are earned passively through play — level wins, daily
challenges, rewarded ads — and spent on four consumable boosters: **Hint** (highlights the
single most productive tap without revealing the arithmetic answer), **Undo** (reverts the
last tap), **Reshuffle** (redistributes cards across the floor while preserving the
solvability invariant), and **Extra Discard Slot** (adds a temporary sixth discard buffer
for the current level). Gems are the premium currency, acquired via IAP or milestone gifts,
and spent on cosmetics, currency conversion, and booster bundles. From the player's
perspective the economy converts *cleared floors into stored calm*: a growing coin reserve
that says "you've earned the right to take it easy when you need to." From the
infrastructure side, every transaction flows through an atomic `WalletService.spend()` that
checks balance and emits a `GameEvent` before the booster activates; a failed spend never
partially commits. All IAP and ad-based earn paths are gated through `ComplianceService`
(ADR-0005): child users earn coins through play alone and are never shown an IAP surface.
The hard constraint binding the entire system: **no booster may auto-solve arithmetic or
reveal a card's result** — math remains the mechanic, every tap is the player's own work.

## Player Fantasy

*"My tools. My pace. My arithmetic."*

Most floors you solve bare-handed. The coins accumulate quietly — a byproduct of clearing boards
— and the boosters sit in a tidy toolbox you rarely need to open. When you do reach for one, it
is deliberate, occasional, and purposeful: a Reshuffle to reopen a path that closed, an Undo
to correct a tap you knew the moment you made it. The anchor moment is not rescue — it is
*self-sufficiency*. You had what you needed because you earned it. The booster validates your
**planning**, it never replaces your **arithmetic**.

The economy's coercion test: choosing *not* to spend feels just as rewarding as spending. Every
clean clear you finish without touching the wallet earns an efficiency bonus and a small
self-satisfaction that no booster can substitute. The reserve grows anyway. You are accumulating
calm for future floors, not grinding to stay playable on the current one. This is the calm
toolbox of a craftsperson, not the power-up queue of an action game.

Critically: all four boosters act on **board state** (layout, history, buffer capacity), never on
the **equation**. Hint highlights a productive *tap destination*; the player still computes `7 + 6`.
Undo reverses a *routing* decision; the player still knows the result was 13. Reshuffle changes
*coverage*; the card values are unchanged. Extra Discard Slot buys *buffer space*; the player
still matches every result themselves. Because the tools act on arrangement and the player acts on
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
   - Checks balance ≥ amount; if false, returns false, no mutation.
   - If true: deducts `amount`, emits `GameEvent.CURRENCY_SPENT`, activates booster.
   - The booster activation and the deduction happen in the same frame before any yield.
   - If the booster activation fails (e.g. Undo with no prior tap), the deduction is
     rolled back (re-credits the amount) and an `ECONOMY_ROLLBACK` event is emitted.
   `WalletService.earn(currency, amount, source) → void`:
   - Adds `amount`, clamps to `MAX_BALANCE`, emits `GameEvent.CURRENCY_EARNED`.

5. **ComplianceService gates every non-play earn path.** Before granting coins from a
   rewarded ad or gems from IAP, the economy checks
   `ComplianceService.can_show_ads()` / `can_show_iap()`. If the check fails (child
   user or consent not granted), the earn does not fire and the UI must not surface the
   offer. The economy never calls `SaveService.data.age_band` directly.

6. **Child mode (age_band = CHILD):** Only the play-based coin faucet (level wins + daily
   challenge) is active. No ad-based coins, no IAP. Booster buttons remain visible and
   functional — children can earn and spend coins exactly as adult players do, they just
   cannot watch an ad or buy a pack to top up. This keeps the core economy feel consistent
   without exposing minors to a spend surface.

#### Boosters

7. **Four consumable boosters.** Each booster costs coins (or optionally gems at a
   premium rate — see Formulas). A booster is available when its precondition is met
   AND the player can afford it. The UI shows it greyed-out if unaffordable but the
   precondition is met, so players know it exists without feeling blocked.

8. **Hint.** Precondition: ≥1 exposed card. Effect: highlight the exposed card with the
   highest `hint_score` (see Formulas). The highlight is a visual cue only — it does
   NOT reveal the result, does NOT auto-tap, and does NOT show a sum. The player still
   computes the arithmetic and still makes the tap. Duration: until the next tap or level
   end, whichever comes first. Undo does NOT reverse a Hint (no board state changed).
   *Design note (intentional):* the Hint surfaces **routing** information — "this card
   belongs on a stack that's currently open" — without surfacing computation. An attentive
   player can infer which open targets exist from the stack row, but they must still compute
   the card's result to confirm and route it. This is deliberate: Hint is a planning aid,
   not an arithmetic aid. Any change that causes the view to display the card's result value
   as part of the hint highlight violates this design intent and must be rejected.

9. **Undo.** Precondition: ≥1 tap has been made this level AND the last action was not a
   level-start or a cascade (see Edge Cases). Effect: replay the `BoardModel` event log
   from the initial state to `event_count − 1`, restoring the board to the state before
   the last voluntary tap. This includes restoring the discard state and any partial stack
   progress. Stack-clear cascades are a special case: Undo steps back to just before the
   tap that triggered the clear, not to mid-cascade (atomic at the tap boundary).

10. **Reshuffle.** Precondition: board is not in a WIN state; level not yet cleared. Effect:
    re-generate the floor layout (slot positions and coverage layers) using a
    `reshuffle_seed` derived from the original level seed and the current reshuffle count
    (see Formulas). The **card set** (which cards exist) and the **target queue** are
    unchanged. The new layout must pass `LevelData.is_solvable()` (by construction — same
    card counts, same queue). Exposure is reset: all layers reassigned from the new layout.
    The discard row is NOT cleared (cards already discarded stay discarded). The reshuffle
    count increments; a warning fires if count reaches the cap (see Tuning Knobs).

11. **Extra Discard Slot.** Precondition: `_active_discard_slots < MAX_DISCARD_SLOTS`
    (the current discard slot count is below the maximum). Default `MAX_DISCARD_SLOTS = 7`
    (tuning knob), so the booster can be used twice per level at default settings. Effect:
    increments `BoardModel._active_discard_slots` by 1 for the remainder of this level,
    opening one new empty slot immediately. Resets to `DISCARD_SLOTS = 5` at level end
    (win, lose, or quit). If `_active_discard_slots == MAX_DISCARD_SLOTS`, the booster
    is blocked — `BOOSTER_PRECONDITION_FAILED` returned without deducting coins.

12. **No booster touches arithmetic.** This is the hard constraint. Hint routes the tap;
    the player computes. Undo reverses routing; the player recomputes. Reshuffle reshuffles
    positions; card values are unchanged. Extra Discard widens the buffer; the math
    remains the player's own. Any future booster idea that reveals a result, auto-routes
    a card, or solves an exercise must be rejected.

#### Earn Rates (provisional — calibrate from playtest)

13. **Level-win coin earn.** Scaled by star rating (stars awarded by the Scoring system,
    per S2-011 GDD when authored):
    - 1 star: **40 coins**
    - 2 stars: **55 coins**
    - 3 stars: **75 coins**
    Target: average 2-star performance yields ~55 coins/level, supporting ~750 coins/day
    for an engaged player (9 levels + daily challenge + occasional ad).

14. **Daily challenge coin earn.** **150 coins** for completing the daily challenge (once
    per day; resets at midnight UTC).

15. **Rewarded ad earn.** **60 coins** per completed rewarded ad. Cap: 3 rewarded ads per
    day (max 180 coins/day from ads; cap resets at midnight UTC). A 2× level-reward
    multiplier (doubles the win coins for one level) may substitute for the flat 60 coins
    as a post-level ad format. Gated by `ComplianceService.can_show_ads()`; zero for
    CHILD users.

16. **Streak bonuses.** Additive on top of the daily challenge coin on a given day:
    - Days 2–4 of login streak: +25 coins/day
    - Days 5–6: +50 coins/day
    - Day 7: +100 coins (weekly anchor; streak resets to 1 on the 8th day)
    A missed day resets the streak counter to 0.

17. **Milestone coin gifts.** Fixed one-time coin packages at level-completion milestones
    (see Tuning Knobs for the milestone table). Not repeatable.

18. **Gem gifts (free drips — milestone-only, Option A).**
    - Tutorial completion: 15 gems (one-time)
    - Every 10 levels cleared: 5 gems (ongoing)
    - First 3-star on any new operation world: 10 gems (per world, up to 5 worlds = 50 gems)
    - Daily-challenge 7-day streak maintained: 10 gems (weekly)
    - Major achievement unlocks: 3–10 gems each (~20–30 gems total over full playthrough)
    Lifetime free-gem estimate for a year-one engaged player: ~715 gems. No daily login gem
    drip (would devalue IAP small packs). No coin→gem conversion.

#### Spend Rates (provisional — calibrate from playtest)

19. **Booster coin costs** (ordered by power / disruption, ascending):
    - Hint: **120 coins**
    - Undo: **180 coins**
    - Reshuffle: **250 coins**
    - Extra Discard Slot: **350 coins**
    At ~750 coins/day engaged income, a non-paying player can afford roughly 1 Hint every
    2.4 days or 1 Extra Discard Slot every 7 days of play — occasional, not routine.

20. **Booster gem costs** (premium convenience; 1 gem ≈ 35 coin equivalent):
    - Hint: **3 gems**
    - Undo: **5 gems**
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
    | Booster 5-Pack | $1.99 | 5× Hint OR 5× Undo OR mixed |
    | Premium Bundle | $4.99 | Remove Ads + 150 gems + 2,000 coins |

    All prices are USD base; localized price points applied at store level.

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
| `undos_used` | `0` | Each Undo use (tracked for analytics and future star penalty) |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **SaveService** | Writes to | `WalletData` fields serialised in `SaveData.wallet_coins` and `SaveData.wallet_gems`; persisted on every earn/spend via `SaveService.save_game()`. |
| **BoardModel** | Commands | Undo calls `BoardModel.replay_to(event_index - 1)`; Reshuffle calls `LevelGenerator.generate(reshuffle_params)`; Extra Discard Slot sets `BoardModel.discard_capacity = 6`. |
| **ComplianceService** | Queries | `can_show_ads()` before ad earn; `can_show_iap()` before IAP surface. |
| **GameManager** | Receives signals from | Level win/lose events trigger coin earn (star-weighted). |
| **LevelData** / **LevelGenerator** | Calls into | Reshuffle calls the generator with `reshuffle_params` to produce a new layout for the same card set and queue. |
| **HUD / UI** | Reads from | Wallet balance displayed in HUD via `WalletService.data`; booster button states derive from balance + preconditions. |
| **Analytics** | Emits to | `CURRENCY_EARNED`, `CURRENCY_SPENT`, `BOOSTER_ACTIVATED`, `ECONOMY_ROLLBACK` events. |
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

**Output Range:** 40–90 coins per level win under normal play.
**Example:** Player wins a level with 2 stars, not the first win today → `55 + 0 = 55 coins`.
**Example:** Player wins first level of the day with 3 stars → `75 + 15 = 90 coins`.

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
| streak_bonus | 37 | Average over days 1–7 cycle (~25+25+25+50+50+100/7) |
| ads/day | 1.5 | Opt-in rate estimate for adult casual audience |
| coins_per_ad | 60 | Fixed per completed rewarded ad |

**Design target:** ~750 coins/day for an engaged non-paying adult player.
At that income, time-to-afford for each booster:

| Booster | Cost | Days of play |
|---------|------|-------------|
| Hint | 120 | 0.16 (every ~2.4 days; ~4 per session if saving) |
| Undo | 180 | 0.24 |
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

### 5. Hint scoring function

The hint score is defined as:

`hint_score(card_id, board_state) = routes_directly(r, board_state) × ROUTES_WEIGHT`
`                                  + opens_new_cards(card_id, board_state) × OPENS_WEIGHT`
`                                  + discard_relief(r, board_state) × RELIEF_WEIGHT`

Where:
- `r = board_state.result_of(card_id)`
- `routes_directly(r, bs)` = 1 if at least one stack has `target == r` AND `count < STACK_CAPACITY`; else 0
- `opens_new_cards(card_id, bs)` = count of cards that become newly exposed if `card_id` is removed (cards for which card_id is the last remaining coverer)
- `discard_relief(r, bs)` = count of cards in discard whose result == r (they'll be pulled free when this result's stack clears)

**Tie-break:** lowest `card_id` (deterministic).

**Variables:**

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `r` | int | level result domain | Arithmetic result of this card |
| `routes_directly` | bool→int | {0, 1} | 1 if this card can directly fill an open stack slot right now |
| `opens_new_cards` | int | 0 – total_floor_cards | Cards that become exposed by removing this card |
| `discard_relief` | int | 0 – DISCARD_SLOTS | Matching cards in discard that would eventually be freed |
| `ROUTES_WEIGHT` | int | 200 (tuning knob) | Strongly prefers a directly-routing card |
| `OPENS_WEIGHT` | int | 10 (tuning knob) | Each newly exposed card adds value |
| `RELIEF_WEIGHT` | int | 5 (tuning knob) | Each discard card with matching result adds modest value |

**Output Range:** 0 (no useful tap: no routing, no exposure gain) to approximately 200 + (total_floor_cards × 10) + (DISCARD_SLOTS × 5). Practical upper bound ~585 on an 18-card board. Score is purely ordinal — magnitude has no meaning outside comparison.

**Example:** Board has 3 exposed cards.
- Card 2 (result 7): routes_directly=1 (200), opens 2 cards (20), 0 in discard (0) → **score = 220** ← selected
- Card 5 (result 9): routes_directly=0 (0), opens 3 cards (30), 1 in discard (5) → score = 35
- Card 8 (result 7): routes_directly=1 (200), opens 0 cards (0), 0 in discard (0) → score = 200

Winner: Card 2 (220). Hint highlights card 2.

---

### 6. Reshuffle seed formula

`reshuffle_seed = hash(str(level_id) + ":" + str(level_start_timestamp) + ":" + str(reshuffle_count))`

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `level_id` | int | 1 – unbounded | Identifier of the current level (`LevelConfig.level_id`) |
| `level_start_timestamp` | int | Unix epoch seconds | Timestamp when the level was entered; prevents same-seed replay across sessions |
| `reshuffle_count` | int | [1, MAX_RESHUFFLES] | Increments per use; guarantees two reshuffles on same level ≠ same layout |
| `reshuffle_seed` | int | any | GDScript `hash()` result; passed as `rng.seed` to the layout shuffler only |

The reshuffle does NOT call `LevelGenerator.generate()`. It only re-runs the `_fisher_yates_shuffle(slot_indices, reshuffle_rng)` step (Level Generator Core Rule 8). The card pool and target queue are preserved exactly; `is_solvable()` holds by the same structural argument as the original generation.

**Example:** `level_id=42`, `level_start_timestamp=1_718_000_000`, first reshuffle: `hash("42:1718000000:1")`.
**Example:** Second reshuffle of the same level: `hash("42:1718000000:2")` — different seed, different layout.

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

---

### 8. Daily ad-earn cap

`ads_watched_today' = ads_watched_today + 1`  (only if `ads_watched_today < MAX_ADS_PER_DAY`)

`MAX_ADS_PER_DAY = 3`

`earn_available = (ads_watched_today < MAX_ADS_PER_DAY) AND ComplianceService.can_show_ads()`

**Output:** Boolean; determines whether the rewarded ad button is shown.
**Example:** Player has watched 2 ads today → button shows. After 3rd ad → button hides until midnight UTC reset.

## Edge Cases

- **EC-01 — Zero balance, buy attempt:** If `coins = 0` and player taps Hint (120 coins): `WalletData.spend(COINS, 120)` guard fails → `SPEND_FAILED(COINS, 120, 0)` emitted → `WalletService` does NOT call any board mutation → UI shows "not enough coins" toast. Board state is unchanged.

- **EC-02 — Undo at level start (0 taps):** If player activates Undo as their first action (`tap_history` is empty): `WalletService` checks `tap_history.size() == 0` before spending → `BOOSTER_PRECONDITION_FAILED` returned → `spend` is NOT called → coins unchanged → UI shows "nothing to undo" feedback.

- **EC-03 — Undo after a cascade:** If the last tap triggers a compound event sequence (STACK_CLEARED + multiple PULL events): the entire compound sequence is atomically reversed. Undo records only `card_id`, not events. The board lands in the exact state before that tap: card is back on the floor and exposed, stacks at their pre-tap counts, discard in its pre-tap state. Cascades are not partially undone — the tap boundary is atomic.

- **EC-04 — Undo reverses LOSE state:** If the most recent tap triggered `LOSE` (discard full + card was tapped): Undo is still available (`tap_history.size() ≥ 1`). After Undo, `board.is_lost() == false`; board returns to pre-lose state. This is the primary Undo rescue case. 180 coins are deducted.

- **EC-05 — Reshuffle when board is stuck (discard full, no legal move):** If all 5 discard slots are full and every exposed card has no matching open stack: this is the primary Reshuffle use case. Precondition `NOT board.is_game_over()` passes (the board is stuck but not yet lost — LOSE triggers on the next attempted tap, not on the state itself). `spend(COINS, 250)` is attempted. On success, new layout is generated; the discard remains intact (5 cards). If no newly exposed card routes directly, the board is still stuck, but the player has more time to evaluate. **No refund if the reshuffled board is also stuck.**

- **EC-06 — Extra Discard Slot when discard is already full (5 cards):** If all 5 slots are occupied: precondition `_active_discard_slots < MAX_DISCARD_SLOTS` (5 < 7) passes. `spend(COINS, 350)` is attempted. On success, `_active_discard_slots = 6`, a 6th empty slot opens immediately. The board is NOT in LOSE state. Player can now tap one more card. This is the primary Extra Discard Slot use case.

- **EC-07 — Extra Discard Slot at maximum (already expanded twice):** If `_active_discard_slots == MAX_DISCARD_SLOTS (7)`: `BOOSTER_PRECONDITION_FAILED` returned. `spend` is not called. Coins unchanged. The UI button is greyed out with a visual indicator that maximum slots have been reached.

- **EC-08 — Two simultaneous Hint requests (double-tap):** If `_hint_in_progress == true` when a second Hint tap arrives: the second request is rejected before `spend` is called. No second coin deduction. No second computation. `BOOSTER_PURCHASE_FAILED` with reason `ALREADY_IN_PROGRESS` is emitted for the second tap. `_hint_in_progress` clears when the view signals the first result is consumed.

- **EC-09 — Transaction failure mid-level (atomic rollback):** If `spend(COINS, 180)` returns `true` (coins deducted) but the board mutation subsequently raises an unexpected error: `WalletService` calls `earn(COINS, 180, SOURCE_ROLLBACK)` to restore the balance → emits `TRANSACTION_ROLLED_BACK(COINS, 180)` → board mutation is not applied → board remains in its pre-activation state → error is logged. `SOURCE_ROLLBACK` is the ONLY valid context for this earn source.

- **EC-10 — Daily reward cap reached, rewarded ad attempted:** If the daily REWARDED_AD coin cap (e.g. 500) is already hit: `DailyCapTracker` computes remaining = 0 → `WalletData.earn` is NOT called → `EARN_CAP_REACHED(REWARDED_AD)` emitted → UI shows "daily limit reached." The ad impression was already shown — no refund.

- **EC-11 — Partial cap earn:** If 40 coins of daily cap remain and a 60-coin rewarded ad completes: `WalletService` clamps to 40 → `WalletData.earn(COINS, 40, REWARDED_AD)` is called → 40 coins credited → `EARNED(COINS, 40, REWARDED_AD, ...)` emitted. Player receives partial reward.

- **EC-12 — Child user (age_band = CHILD) attempts IAP:** If `ComplianceService.is_restricted() == true` and player taps a "Buy Gems" button: `WalletService` checks compliance before initiating IAP → IAP flow is NOT initiated → `IAPService` is never called → no balance change → UI shows parental-approval message. `WalletService` never reads `age_band` directly.

- **EC-13 — Gem-to-coin conversion at daily cap:** If player has already converted 50 gems today (`DAILY_GEM_CONVERT_CAP`) and attempts another conversion: the conversion is blocked → `EARN_CAP_REACHED(GEM_CONVERT)` emitted → coins unchanged.

- **EC-14 — Earn of 0 amount (logic error guard):** If any code path calls `earn(currency, 0, source)`: this is rejected pre-check as a logic error → no mutation → no event emitted → error is logged. Similarly, `spend(currency, 0)` returns `false` without emitting `SPEND_FAILED` (0-amount spend is a caller bug).

- **EC-15 — Reshuffle on an already-won board:** If `board.is_won() == true` when `use_booster(RESHUFFLE)` is called: `BOOSTER_PRECONDITION_FAILED` returned. Coins unchanged. (This edge case should be impossible in normal play but must be defended defensively.)

## Dependencies

**This system depends on:**

| System | Hard/Soft | Interface |
|--------|-----------|-----------|
| **Save Service** (`core/save_data.gd`, `autoloads/save_service.gd`) | Hard | Wallet balance (coins, gems) is persisted inside `SaveData`; `WalletService` reads/writes through `SaveService.data`. Schema migration on `SaveData._migrate()` must handle wallet fields. |
| **ComplianceService** (`autoloads/compliance_service.gd`) | Hard | IAP and ad-based coin/gem rewards require `ComplianceService.can_collect_personal_data()` / `can_show_ads()` to pass. Economy never reads `age_band` directly (ADR-0005). Child users earn coins through level wins only. |
| **BoardModel** (`core/board_model.gd`) | Hard | Boosters that mutate board state (Undo, Reshuffle, Extra Discard Slot) must do so through `BoardModel` — never by writing view state directly. Undo replays the event log to state N−1. Reshuffle calls a new generation of slot assignments preserving card set + queue. Extra Discard Slot temporarily expands the discard capacity constant that `BoardModel` enforces. |
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
| **First-Time Tutorial** (`core/tutorial_logic.gd`) | Soft | Tutorial may introduce Hint at a scripted moment (see `first-time-tutorial.md`). Economy must be live for tutorial to demonstrate it. |

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
| `MAX_ADS_PER_DAY` | 3 | 1–10 | Low → frustrating cap; High → ad farming negates progression intent |
| `STREAK_DAY_2_TO_4_BONUS` | 25 | 10–50 | Additive on daily challenge; keeps streak meaningful |
| `STREAK_DAY_5_TO_6_BONUS` | 50 | 25–100 | Escalation; too high → streak anxiety (breaks "calm, not frantic") |
| `STREAK_DAY_7_BONUS` | 100 | 50–200 | Weekly anchor; too high → users feel punished for missing a day. **Live-ops lever:** if streak anxiety appears in M3 data (churn spike on day 8, negative reviews about streaks), the *first* adjustment is to soften the reset (streak freeze item, or reset to a floor like day 3 instead of day 1) — not to raise coin rewards, which only inflates income without reducing anxiety. |
| `DAILY_COINS_CAP` | 500 | 200–1,500 | Low → frustrates engaged non-payers; High → ad farming yields too much |
| `DAILY_GEM_CONVERT_CAP` | 50 | 10–200 | Low → gems stay premium; High → soft-to-premium conversion undermines IAP |

### Booster costs

| Knob | Default | Safe Range | What breaks at extremes |
|------|---------|-----------|------------------------|
| `HINT_COST_COINS` | 120 | 60–250 | Low → every-board Hint use (boosters feel free, not earned); High → never used, system dead |
| `UNDO_COST_COINS` | 180 | 80–350 | Low → Undo every mistake; puzzle depth diluted. High → feel like a punishing tax on mistakes |
| `RESHUFFLE_COST_COINS` | 250 | 100–500 | Low → Reshuffle is the default response to any difficulty; High → never purchased |
| `EXTRA_DISCARD_COST_COINS` | 350 | 150–600 | Low → discard pressure loses teeth as a mechanic; High → "rescue at any cost" moment feels predatory |
| `HINT_COST_GEMS` | 3 | 1–10 | Gem costs should scale at ~1 gem : 35 coins parity rate |
| `UNDO_COST_GEMS` | 5 | 2–15 | — |
| `RESHUFFLE_COST_GEMS` | 7 | 3–20 | — |
| `EXTRA_DISCARD_COST_GEMS` | 10 | 5–25 | — |
| `GEM_TO_COIN_RATE` | 25 | 10–35 | Must stay below booster-parity rate (35); above 35 = gems to coins is better than buying boosters directly (breaks IAP value) |

### Balance limits

| Knob | Default | Safe Range | What breaks at extremes |
|------|---------|-----------|------------------------|
| `COINS_MAX` | 999,999 | 50,000–unbounded | Very low cap → hoarders hit ceiling and see "coins wasted"; essentially no gameplay effect above ~10,000 |
| `GEMS_MAX` | 9,999 | 1,000–unbounded | Very low → IAP whale is blocked; no gameplay effect above ~5,000 |
| `MAX_DISCARD_SLOTS` | 7 | 6–8 | 6 = one extra slot ever; 8 = player can stack 3 extra slots (very forgiving) |

### Hint algorithm weights

| Knob | Default | Safe Range | What breaks at extremes |
|------|---------|-----------|------------------------|
| `ROUTES_WEIGHT` | 200 | 100–500 | Low → Hint may highlight an exposure-chaining card over a directly routing one; High → Hint always picks a routing card even if a non-routing move is strategically better |
| `OPENS_WEIGHT` | 10 | 5–30 | Low → exposure gain becomes irrelevant; High → Hint prefers uncovering over routing |
| `RELIEF_WEIGHT` | 5 | 1–15 | Low → discard relief never factors in; High → Hint over-focuses on discard pressure |

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
- Hint highlight: a visual indicator on the target card (glow, pulse, or arrow) — must be
  distinguishable in colorblind mode (shape cue, not color-only).
- Undo activation: a brief board-reversal animation; the card visually "un-routes."
- Reshuffle activation: a shuffle/deal animation as cards reposition to the new layout.
- Extra Discard Slot activation: the discard row expands to show the new slot.

**Audio** (owned by the Audio GDD when authored):
- Booster purchase: a satisfying "spend" SFX distinct from the level-clear SFX.
- Insufficient funds: a gentle negative tone (not harsh; respects the calm tone).
- Hint activation: a soft highlight chime.

No new art assets or shaders are required by the economy model itself.

## UI Requirements

### Wallet HUD (in-game)
- **Coin balance display:** visible during gameplay in the HUD (top bar). Shows current coin count with a coin icon. Updates in real-time on earn/spend. No Gem balance displayed during gameplay (gems are a menu-layer currency).
- **Booster tray:** four booster buttons in the HUD (Hint / Undo / Reshuffle / Extra Discard Slot). Each button shows:
  - Icon for the booster type
  - Coin cost label
  - Greyed-out state if coin balance < cost (but button is still visible — player knows it exists)
  - Disabled state if the precondition is unmet (e.g. Undo greyed out at start; Extra Discard greyed out at MAX_DISCARD_SLOTS)
  - Active indicator while Hint is in-progress (preventing double-tap)
- **No IAP surface during gameplay.** Economy-related IAP/gem purchase offers appear only on pre-level screens, post-level screens, or the dedicated shop screen. Never as a mid-puzzle interruption.

### Level pre/post screens
- **Pre-level booster selection** (optional feature, post-M3): allow players to equip 1 booster per level before starting (deliberate spend, not panic spend). Shows coin cost and current balance.
- **Post-level earn summary:** "You earned +N coins" card with the earn breakdown (base + star bonus + streak). Rewarded ad offer: "Watch an ad to double your reward" button — only if `ComplianceService.can_show_ads()` is true.

### Shop / currency screen (menu layer)
- **Coin balance + Gem balance:** both visible in the shop header.
- **IAP catalog:** all SKUs from Tuning Knobs §IAP catalog. Clearly priced in real currency (e.g. "$3.99"). No dark patterns (e.g. no "Buy Now — Limited Time!" without a real expiry).
- **Rewarded ad coin earn button:** "Watch ad for +60 coins" button — shows remaining daily ad count. Hidden if ads unavailable (CHILD user, consent denied, or daily cap reached).
- **Gem-to-coin conversion:** accessible in the shop. Shows rate (1 gem = 25 coins) and daily cap.
- **Remove Ads SKU** displayed prominently if ads are currently showing; de-listed if already purchased (no need to surface what the player already owns).

### Accessibility requirements
- Hint highlight must use a shape/motion cue, not only color (colorblind accessibility — consistent with `StackPalette` Okabe-Ito pattern in `data/stack_palette.gd`).
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

## Acceptance Criteria

`[B]` = BLOCKING (automated unit/integration test). `[A]` = ADVISORY (manual check or playtest).

### Wallet — spend

- **AC-W01 [B]** GIVEN `coins = 100`, WHEN `spend(COINS, 30)`, THEN returns `true`, `coins == 70`, `SPENT(COINS, 30, 70)` emitted.
- **AC-W02 [B]** GIVEN `coins = 20`, WHEN `spend(COINS, 30)`, THEN returns `false`, `coins == 20` unchanged, `SPEND_FAILED(COINS, 30, 20)` emitted.
- **AC-W03 [B]** GIVEN `coins = 0`, WHEN `spend(COINS, 1)`, THEN returns `false`, `coins == 0`, `SPEND_FAILED` emitted.
- **AC-W04 [B]** GIVEN any balance, WHEN `spend(COINS, 0)`, THEN returns `false` without emitting any event and without mutating balance (logic-error guard).
- **AC-W05 [B]** GIVEN `coins = 100` and `spend(COINS, 50)` succeeds → `coins = 50`. WHEN board mutation raises error and rollback executes. THEN `coins == 100`, `TRANSACTION_ROLLED_BACK(COINS, 50)` emitted.

### Wallet — earn

- **AC-W06 [B]** GIVEN `coins = 400`, WHEN `earn(COINS, 55, LEVEL_WIN)`, THEN `coins == 455`, `EARNED(COINS, 55, LEVEL_WIN, 455)` emitted.
- **AC-W07 [B]** GIVEN `coins = COINS_MAX − 10`, WHEN `earn(COINS, 100, LEVEL_WIN)`, THEN `coins == COINS_MAX`, `EARNED(COINS, 10, LEVEL_WIN, COINS_MAX)` emitted (actual credited = 10, clamped).
- **AC-W08 [B]** GIVEN any balance, WHEN `earn(COINS, 0, LEVEL_WIN)`, THEN no mutation, no event emitted (logic-error guard).

### Daily cap

- **AC-C01 [B]** GIVEN daily REWARDED_AD coins already at `DAILY_COINS_CAP` (500), WHEN `earn(COINS, 60, REWARDED_AD)` would be requested, THEN `earn` is NOT called on `WalletData`, `coins` unchanged, `EARN_CAP_REACHED(REWARDED_AD)` emitted.
- **AC-C02 [B]** GIVEN daily REWARDED_AD coins at 460 (cap = 500), WHEN 60 REWARDED_AD coins attempted, THEN only 40 coins credited, `EARNED(COINS, 40, REWARDED_AD, ...)` emitted.
- **AC-C03 [B]** GIVEN daily REWARDED_AD coins at cap, WHEN `earn(COINS, 55, LEVEL_WIN)`, THEN 55 coins credited without cap interference (LEVEL_WIN is uncapped).

### Hint booster

- **AC-H01 [B]** GIVEN a board with 3 exposed cards with hint_scores 220, 35, 200 (per Section D worked example), WHEN `use_booster(HINT)` is called, THEN `HINT_RESULT(card_id=2)` emitted and 120 coins deducted.
- **AC-H02 [B]** GIVEN two exposed cards with identical hint_scores, WHEN Hint is used, THEN the card with the lower `card_id` is returned (deterministic tiebreak).
- **AC-H03 [B]** GIVEN 0 exposed cards (edge case), WHEN `use_booster(HINT)`, THEN `BOOSTER_PRECONDITION_FAILED` returned, coins unchanged.
- **AC-H04 [B]** GIVEN Hint is in-progress (`_hint_in_progress == true`), WHEN a second Hint activation arrives, THEN no second cost deducted, no second event emitted, `BOOSTER_PURCHASE_FAILED(ALREADY_IN_PROGRESS)` emitted.
- **AC-H05 [B]** GIVEN a card whose result matches an open stack target, WHEN `hint_score` is computed, THEN `routes_directly` component contributes exactly `ROUTES_WEIGHT` (default 200) to the total score.

### Undo booster

- **AC-U01 [B]** GIVEN level starts with board state S0, player taps card A → board state S1. WHEN `use_booster(UNDO)`, THEN board is back to state S0, card A exposed on floor, stack count restored, 180 coins deducted.
- **AC-U02 [B]** GIVEN player taps card B triggering a cascade (STACK_CLEARED + 2 PULLs). WHEN Undo is used. THEN board returns to exact state before card B was tapped; cascade fully reversed (stacks, discard, floor all restored).
- **AC-U03 [B]** GIVEN `tap_history.size() == 0`. WHEN `use_booster(UNDO)`. THEN `BOOSTER_PRECONDITION_FAILED` returned, coins unchanged.
- **AC-U04 [B]** GIVEN last tap triggered `LOSE`. WHEN `use_booster(UNDO)`. THEN `board.is_lost() == false`, board in pre-lose state, 180 coins deducted.
- **AC-U05 [B]** GIVEN taps [A, B]. After first Undo, `tap_history == [A]`. After second Undo, `tap_history == []`. After third Undo attempt, `BOOSTER_PRECONDITION_FAILED` returned.
- **AC-U06 [B]** GIVEN Extra Discard Slot was activated, then player makes tap T, then uses Undo. THEN tap T is reverted AND `_active_discard_slots` is still 6 (slot not removed by Undo).

### Reshuffle booster

- **AC-R01 [B]** GIVEN a valid board. WHEN Reshuffle is used. THEN `new_board._result_of == original._result_of`, `new_board._target_queue == original._target_queue`, `new_board._removed == original._removed`, 250 coins deducted.
- **AC-R02 [B]** GIVEN 4 cards already removed. WHEN Reshuffle is used. THEN those 4 cards remain removed in the new board; stack state, discard, and draw index are all preserved.
- **AC-R03 [B]** GIVEN any valid board state. WHEN Reshuffle is used. THEN `LevelData.is_solvable(new_board) == true` (solvability invariant preserved).
- **AC-R04 [B]** GIVEN `reshuffle_count = 1` and `reshuffle_count = 2` on the same level/session. THEN the two reshuffle seeds differ and the resulting layouts differ.
- **AC-R05 [B]** GIVEN `board.is_won() == true`. WHEN `use_booster(RESHUFFLE)`. THEN `BOOSTER_PRECONDITION_FAILED` returned, coins unchanged.
- **AC-R06 [B]** GIVEN `tap_history` has 3 entries. WHEN Reshuffle is used. THEN `tap_history` is empty afterwards; subsequent Undo attempt returns `BOOSTER_PRECONDITION_FAILED`.
- **AC-R07 [B]** GIVEN discard full (5 cards), all exposed cards have no matching open stack. WHEN Reshuffle is used. THEN new board has same discard state, new layout, 250 coins deducted; no automatic win or lose is triggered by the reshuffle itself.

### Extra Discard Slot booster

- **AC-E01 [B]** GIVEN `_active_discard_slots == 5`, `MAX_DISCARD_SLOTS == 7`. WHEN `use_booster(EXTRA_DISCARD_SLOT)`. THEN `_active_discard_slots == 6`, `_discard.size() == 6` (new slot is −1/empty), 350 coins deducted.
- **AC-E02 [B]** GIVEN Extra Discard Slot activated. WHEN player uses Undo on a subsequent tap. THEN tap is reverted AND `_active_discard_slots` remains 6 (slot persists through Undo).
- **AC-E03 [B]** GIVEN Extra Discard Slot was used during a level. WHEN level ends (win, lose, or abandon). THEN `_active_discard_slots` resets to `DISCARD_SLOTS` (5) for the next level.
- **AC-E04 [B]** GIVEN `_active_discard_slots == MAX_DISCARD_SLOTS == 7`. WHEN `use_booster(EXTRA_DISCARD_SLOT)`. THEN `BOOSTER_PRECONDITION_FAILED` returned, coins unchanged.
- **AC-E05 [B]** GIVEN all 5 discard slots occupied (board is one tap from LOSE). WHEN `use_booster(EXTRA_DISCARD_SLOT)` is called. THEN a 6th empty slot is immediately available; `board.is_lost()` is still `false`; player can tap one more card.

### Compliance / IAP gating

- **AC-CL01 [B]** GIVEN `ComplianceService.is_restricted() == true`. WHEN player initiates a Gem IAP. THEN `IAPService` is never called, no balance change, UI receives appropriate blocked signal.
- **AC-CL02 [B]** Structural: `grep -n "age_band" autoloads/wallet_service.gd` returns no matches. All compliance checks route through `ComplianceService`.

### Integration: Economy + BoardModel

- **AC-I01 [B]** GIVEN a real `BoardModel` and 1 tap in `tap_history`. WHEN `use_booster(UNDO)` via `WalletService`. THEN the board returned by replay is field-identical to the initial board state.
- **AC-I02 [B]** GIVEN `coins = 180`, Undo costs 180. If board replay raises an error. THEN `coins == 180` after rollback completes (EC-09 path); `TRANSACTION_ROLLED_BACK` emitted.

### Boundary / economy calibration

- **AC-B01 [B]** GIVEN `coins = 0`. WHEN all four coin-cost boosters are attempted. THEN `spend` returns `false` for all; no board state changes.
- **AC-B02 [B]** GIVEN `coins = COINS_MAX − 1`. WHEN `earn(COINS, 2, LEVEL_WIN)`. THEN `coins == COINS_MAX`, actual credited = 1.
- **AC-B03 [A]** Playtest target: engaged non-paying adult player earns 600–900 coins per day across 3 sessions of 3 levels each, daily challenge, and ≤3 rewarded ads. Time-to-afford a Hint through pure play: 2–4 days. Time-to-afford an Extra Discard Slot: 5–8 days. Verify against real session data at M3 soft launch.
- **AC-B04 [A]** Booster use rate target: non-paying player uses ≤1 booster per 5 levels on average. If observed rate is higher, booster costs should be increased. If 0% of players use boosters (economics too punishing), reduce costs.

### No-arithmetic-solving constraint (hard rule)

- **AC-M01 [B]** GIVEN any board state, WHEN Hint is used, THEN `HINT_RESULT` event contains only a `card_id` — no result value, no operands, no solution text. The view layer must NOT render the card's arithmetic result as part of the hint highlight.
- **AC-M02 [B]** Code review gate: no `WalletService`, `WalletData`, or booster activation path reads or exposes `CardData.result` to the player. Any future booster that would require reading `result` to determine its effect must be rejected at design review.

## Open Questions

- **Booster cost calibration** — the costs (120/180/250/350 coins) are provisional and derived from genre analysis (Royal Match, Triple Tile benchmarks). Real values come from M3 soft-launch data: booster use rate, daily coin income, and time-to-afford measurements. If booster use rate < 2% of levels, costs are likely too high; if > 15%, too low. Owner: economy-designer, during M3 playtest.

- **Star-rating interaction with earn** — this GDD assumes the Scoring/Stars system (S2-011, not yet authored) defines star ratings per level. The earn rates (40/55/75 by star) depend on what "1, 2, 3 stars" means mechanically (fewest discards? fastest clear?). If stars are not implemented by M3, fall back to a flat earn rate (e.g. 50 coins per win) until the Scoring GDD is authored. Owner: game-designer, during S2-011.

- **Undo implementation risk** — Undo requires `tap_history` replay (O(N) replay per Undo). For typical levels (≤40 taps) this is negligible. On very long Endless-band levels (many undos + many taps before each), replay time should be profiled. If it exceeds ~16ms, switch to a snapshot-per-tap strategy. This is a deliberate technical risk flagged for architecture review when implementing. Owner: lead-programmer, at implementation spike.

- **Extra Discard Slot requires BoardModel change** — `BoardModel` currently uses `DISCARD_SLOTS` as a constant. Adding Extra Discard Slot requires adding `_active_discard_slots: int` as a mutable field (AC-E01). This is a non-trivial change to an already-tested system (87 unit tests). **ADR candidate** — the approach (mutable override vs. per-level config parameter) should be decided before implementation. Owner: lead-programmer / godot-gdscript-specialist, when scoping the economy sprint.

- **Gem drip calibration** — the gem milestone table is provisional. At ~715 lifetime gems for a year-one non-payer, they can buy 7–14 cosmetics or ~238 Hints. If this feels too generous (devalues IAP gem packs), reduce the every-10-levels drip from 5 gems to 3. If too stingy (players feel blocked from cosmetics), increase. Real calibration requires M3 store conversion data. Owner: economy-designer.

- **Child-mode daily challenge and streak access** — this GDD allows CHILD users to access daily challenges and streak bonuses (coins only, no ads, no IAP). Confirm with the compliance review at M4 that daily-challenge mechanics do not trigger "excessive frequency of engagement" concerns under GDPR-K or COPPA. Owner: legal review, pre-M4.

- **Booster bundle pricing on store** — the $1.99 Booster 5-Pack SKU needs store policy review. Some app stores have restrictions on "consumable bundles" that require individual item prices to be disclosed. Confirm with the release-manager at M4 before submission. Owner: release-manager.

- **Remote config integration** — all economy values live in `EconomyConfig` resource (`assets/data/economy_config.tres`). At M4, these should be server-configurable via Remote Config (A/B testable without an app update). The `EconomyConfig` loader should fall back to the local `.tres` file if remote config is unavailable. Owner: tools-programmer / devops-engineer, during M4.
