class_name EconomyConfig
extends Resource
## All tuning knobs for the Deck Economy layer.
##
## Implements design/gdd/deck-economy.md §Tuning Knobs. Every scalar that
## controls earn rates, booster costs, balance limits, and Hint algorithm
## weights lives here so a designer can retune via remote config or a .tres
## swap without touching code (gameplay-code rule: no hardcoded tuning values
## in core/).
##
## Source: design/gdd/deck-economy.md §Tuning Knobs;
##         design/registry/entities.yaml (constants entries).
## Instance: assets/data/economy_config.tres (loaded by autoloads; never
## load()'d from core/).
##
## [b]Source of truth:[/b] the canonical default values live here as the
## [code]@export[/code] defaults. [code]economy_config.tres[/code] is intentionally
## an empty override sheet (script reference only, no stored values) — it inherits
## every default from this script, so there is exactly one place to read or change
## a default and no risk of the [code].tres[/code] drifting out of sync. A designer
## overrides a knob by setting it in the inspector (which then writes that single
## value into the [code].tres[/code]); unset knobs continue to track the script.

# ---------------------------------------------------------------------------
# Earn rates
# ---------------------------------------------------------------------------

## Coins awarded for a 1-star level win (Formula 1). Safe range: 20–80.
@export var coins_win_1_star: int = 40

## Coins awarded for a 2-star level win (Formula 1). Safe range: 35–100.
@export var coins_win_2_star: int = 55

## Coins awarded for a 3-star level win (Formula 1). Safe range: 50–150.
@export var coins_win_3_star: int = 75

## Flat earn per win used until the Scoring/Stars GDD (S2-011) is live.
## Prevents the star-weighted Formula 1 logic from being hardcoded.
## Producer flag: remove this knob when S2-011 ships. Safe range: 20–100.
@export var coins_win_flat_fallback: int = 50

## One-time per-day bonus for the first level cleared each calendar day
## (Formula 1). Safe range: 0–50.
@export var first_win_bonus: int = 15

## Coins for completing the daily challenge (Rule 14). Safe range: 75–300.
@export var coins_daily_challenge: int = 150

## Coins per completed rewarded ad (Rule 15). Safe range: 30–120.
@export var coins_rewarded_ad: int = 60

## Coin bonus for clearing a level with zero booster activations (Formula 1b).
## Mechanizes the "not-spending feels as good as spending" pillar. 0 disables
## the mechanic entirely. Safe range: 0–50.
@export var clean_clear_bonus: int = 20

## Maximum rewarded-ad views per day before the ad earn button is hidden
## (Rule 15 / Formula 8). Safe range: 1–10.
@export var max_ads_per_day: int = 3

## Additive streak bonus on the daily-challenge coin for days 2–4 of a
## login streak (Rule 16). Safe range: 10–50.
@export var streak_day_2_to_4_bonus: int = 25

## Additive streak bonus for days 5–6 (Rule 16). Safe range: 25–100.
@export var streak_day_5_to_6_bonus: int = 50

## Additive streak bonus for day 7 — the weekly anchor (Rule 16).
## Safe range: 50–200.
@export var streak_day_7_bonus: int = 100

## Day the login streak falls back to after a missed day (Rule 16).
## 3 is the calm-not-frantic default: a lapse costs momentum, never wipes to
## zero. Safe range: 1–4.
@export var streak_reset_floor: int = 3

## Daily cap that applies to REWARDED_AD coin income only (Rule 15 canonical
## scope). Level wins, challenge, streak, milestones, and clean-clear are
## uncapped; gem conversion uses daily_gem_convert_cap. Safe range: 200–1500.
@export var daily_coins_cap: int = 500

## Daily cap on gem-to-coin conversions in gems (Rule 21 / Formula 7).
## Safe range: 10–200.
@export var daily_gem_convert_cap: int = 50

# ---------------------------------------------------------------------------
# Booster costs
# ---------------------------------------------------------------------------

## Coin cost of the Picker booster (plays a chosen covered card). Safe range: 60–250.
@export var picker_cost_coins: int = 120

## Coin cost of the Reshuffle booster (Rule 19). Safe range: 100–500.
@export var reshuffle_cost_coins: int = 250

## Coin cost of the Extra Discard Slot booster (Rule 19). Safe range: 150–600.
@export var extra_discard_cost_coins: int = 350

## Gem cost of the Picker booster (Rule 20). Safe range: 1–10.
@export var picker_cost_gems: int = 3

## Gem cost of the Reshuffle booster (Rule 20). Safe range: 3–20.
@export var reshuffle_cost_gems: int = 7

## Gem cost of the Extra Discard Slot booster (Rule 20). Safe range: 5–25.
@export var extra_discard_cost_gems: int = 10

## Coins received per gem in a gem-to-coin conversion (Rule 21 / Formula 7).
## Must stay below the booster-parity rate (35); above 35 breaks IAP value.
## Safe range: 10–35.
@export var gem_to_coin_rate: int = 25

# ---------------------------------------------------------------------------
# Balance limits
# ---------------------------------------------------------------------------

## Hard cap on the coin balance (Formula 4). Upper cap enforced by
## WalletService.earn(); WalletData does not apply this so rollback (EC-09) is
## always exact via snapshot assignment. Safe range: 50000–unbounded.
@export var coins_max: int = 999999

## Hard cap on the gem balance (Formula 4). Same responsibility split as
## coins_max. Safe range: 1000–unbounded.
@export var gems_max: int = 9999

## Maximum discard slots after Extra Discard Slot booster expansions (Rule 11).
## Default 5-slot board can be expanded at most (max - 5) times per level.
## Safe range: 6–8.
@export var max_discard_slots: int = 7

# ---------------------------------------------------------------------------
# Miscellaneous
# ---------------------------------------------------------------------------

## Coin spend amount at or above which a one-step confirmation dialog is shown
## before deducting (UI anti-misfire rule; §UI Requirements). Safe range: 60–500.
@export var spend_confirm_threshold: int = 250

# ---------------------------------------------------------------------------
# Booster inventory (prototype: owned counts)
# ---------------------------------------------------------------------------

## How many of each booster a player starts a session with (prototype buff
## inventory). Tapping a booster consumes one for free; at zero, the player is
## offered a watch-ad / pay-coins top-up popup. Currently an in-memory, per-session
## stock seeded by WalletService (persistence is a follow-up). Safe range: 0–10.
@export var starting_booster_count: int = 3
