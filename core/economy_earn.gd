class_name EconomyEarn
extends RefCounted
## Pure, deterministic streak + milestone earn math (S3-010).
##
## This module owns the *calculation* of login-streak coin bonuses and one-time
## milestone gifts. It is node-free, resource-free (it never [code]load()[/code]s
## anything), and clock-free: callers derive UTC day keys from an injected
## [TimeProvider] and pass them in as plain [int]s, exactly as [ReshuffleSeed.mix]
## takes an explicit timestamp. Every function is a pure mapping from its
## arguments — given the same inputs it always returns the same output, so the
## whole surface is headless-testable with no real clock (AC-EF04).
##
## [b]Scope boundary:[/b] this is earn *math* only. Wiring an earn into the wallet
## — the [code]earn(COINS, base + streak_bonus, DAILY_CHALLENGE)[/code] call, the
## "milestone fires exactly once" SaveData bookkeeping (AC-EF05), and the
## daily-challenge faucet itself — lives in [WalletService] and is deferred until
## the daily-challenge system is built (Sprint 3 note). The daily-challenge
## [i]base[/i] coin (Rule 14) is therefore NOT added here; [method streak_bonus]
## returns only the additive streak component (Rule 16).
##
## Source: design/gdd/deck-economy.md Rules 16–18, Formula 2, Tuning Knobs,
##         AC-EF03/EF04/EF05/EF06; ADR-0009 (TimeProvider seam).


## Length of one login-streak cycle in days. Day 8 is day 1 of the next cycle
## (Rule 16: "natural day-8 rollover continues the streak into a new cycle").
const STREAK_CYCLE_DAYS: int = 7


## Returns the additive coin bonus for a given login-streak day (Rule 16).
##
## [param streak_day] is 1-based and unbounded: it keeps climbing past 7, and the
## bonus repeats on a [constant STREAK_CYCLE_DAYS] cycle (day 8 → day-1 bonus,
## day 14 → day-7 bonus, …). The schedule within a cycle is:
## [codeblock]
## day 1        → 0                          (no streak yet)
## days 2–4     → config.streak_day_2_to_4_bonus  (25)
## days 5–6     → config.streak_day_5_to_6_bonus  (50)
## day 7        → config.streak_day_7_bonus       (100, weekly anchor)
## [/codeblock]
## This is the bonus ADDED to the daily-challenge base coin (Rule 14); the base
## itself is not included here. A non-positive [param streak_day] yields 0.
## [br][br]Worked example (AC-EF03): [code]streak_bonus(7, cfg) == 100[/code], so
## a day-7 daily-challenge completion earns [code]150 + 100[/code] coins.
static func streak_bonus(streak_day: int, config: EconomyConfig) -> int:
	if streak_day <= 0:
		return 0
	var pos_in_cycle: int = ((streak_day - 1) % STREAK_CYCLE_DAYS) + 1
	if pos_in_cycle == 1:
		return 0
	if pos_in_cycle <= 4:
		return config.streak_day_2_to_4_bonus
	if pos_in_cycle <= 6:
		return config.streak_day_5_to_6_bonus
	return config.streak_day_7_bonus  # pos_in_cycle == 7


## Computes the new login-streak day after a login on [param today_day_key]
## (Rule 16 transition table). [param last_day_key] / [param today_day_key] are
## UTC day keys from [method TimeProvider.utc_day_key]; [param prev_streak_day]
## is the streak day recorded at [param last_day_key].
##
## Transition table (calm-not-frantic reset):
## [codeblock]
## first login ever  (prev <= 0)        → 1
## same UTC day       (delta == 0)      → prev_streak_day            (idempotent)
## consecutive day    (delta == 1)      → prev_streak_day + 1        (continues cycles)
## missed one+ days   (delta >= 2)      → config.streak_reset_floor  (3, NOT 0)
## clock went backward(delta <  0)      → prev_streak_day            (defensive no-op)
## [/codeblock]
## The missed-day branch is the canonical loss-aversion softener: a lapse drops
## the player back to the day-3 floor, never to zero (AC-EF04). A natural day-8
## rollover hits the [code]delta == 1[/code] branch, so the streak continues to
## 8, 9, … and [method streak_bonus] wraps it into the next cycle.
static func next_streak_day(
		prev_streak_day: int,
		last_day_key: int,
		today_day_key: int,
		config: EconomyConfig,
) -> int:
	if prev_streak_day <= 0:
		return 1  # first streak day ever (no prior login)
	var delta: int = today_day_key - last_day_key
	if delta <= 0:
		return prev_streak_day  # same day (idempotent) or defensive against a backward clock
	if delta == 1:
		return prev_streak_day + 1  # consecutive day — continues into the next cycle on day 8
	return config.streak_reset_floor  # missed one or more days → floor, never 0


## Returns the one-time coin gift for reaching [param level] (Rule 17), or 0 if
## [param level] is not a milestone. Reads the [member EconomyConfig.milestone_coin_gifts]
## table ([code]{level: gift}[/code]).
##
## This reports the gift amount only; enforcing "fires exactly once, never on a
## revisit" (AC-EF05) is the caller's bookkeeping in SaveData, since this module
## holds no state. [code]milestone_coin_gift(5, cfg) == 100[/code].
static func milestone_coin_gift(level: int, config: EconomyConfig) -> int:
	return int(config.milestone_coin_gifts.get(level, 0))


## Returns the one-time gem gift for first-time tutorial completion (Rule 18,
## AC-EF06): [member EconomyConfig.gem_gift_tutorial] (15). The once-only
## guarantee is the caller's SaveData bookkeeping.
static func tutorial_gem_gift(config: EconomyConfig) -> int:
	return config.gem_gift_tutorial


## Returns the recurring gem gift for clearing [param levels_cleared] total
## levels (Rule 18: "Every 10 levels cleared: 5 gems"), or 0 when
## [param levels_cleared] is not a positive multiple of 10. Reads
## [member EconomyConfig.gem_gift_per_10_levels].
static func level_clear_gem_gift(levels_cleared: int, config: EconomyConfig) -> int:
	if levels_cleared > 0 and levels_cleared % 10 == 0:
		return config.gem_gift_per_10_levels
	return 0
