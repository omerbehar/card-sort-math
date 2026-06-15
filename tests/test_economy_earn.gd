extends GdUnitTestSuite
## Unit tests for [EconomyEarn] — streak + milestone earn math (S3-010).
##
## Coverage:
##   - streak_bonus: the full day-1..7 schedule, cycle wrap (day 8/14), guards.
##   - next_streak_day: first login, same-day idempotency, consecutive advance,
##     missed-day floor reset (AC-EF04), backward-clock defence.
##   - milestone_coin_gift / tutorial_gem_gift / level_clear_gem_gift tables.
##   - Config-driven: custom EconomyConfig values flow through (no hardcoding).
##
## All functions are pure; day keys are passed as plain ints (TimeProvider is the
## caller's concern), so every assertion is deterministic and clock-free.
##
## Source: design/gdd/deck-economy.md Rules 16–18, AC-EF03/EF04/EF05/EF06.


func _config() -> EconomyConfig:
	# Default knobs — matches the GDD Tuning Knob table.
	return EconomyConfig.new()


# ---------------------------------------------------------------------------
# streak_bonus — the Rule 16 schedule within a 7-day cycle
# ---------------------------------------------------------------------------

func test_streak_bonus_day_1_is_zero() -> void:
	assert_int(EconomyEarn.streak_bonus(1, _config())).is_equal(0)


func test_streak_bonus_days_2_to_4_are_25() -> void:
	var cfg := _config()
	assert_int(EconomyEarn.streak_bonus(2, cfg)).is_equal(25)
	assert_int(EconomyEarn.streak_bonus(3, cfg)).is_equal(25)
	assert_int(EconomyEarn.streak_bonus(4, cfg)).is_equal(25)


func test_streak_bonus_days_5_to_6_are_50() -> void:
	var cfg := _config()
	assert_int(EconomyEarn.streak_bonus(5, cfg)).is_equal(50)
	assert_int(EconomyEarn.streak_bonus(6, cfg)).is_equal(50)


func test_streak_bonus_day_7_is_100() -> void:
	# AC-EF03: the weekly anchor bonus added to the daily-challenge base.
	assert_int(EconomyEarn.streak_bonus(7, _config())).is_equal(100)


func test_streak_bonus_day_8_wraps_to_new_cycle_zero() -> void:
	# Rule 16: day 8 is day 1 of the next cycle → +0.
	assert_int(EconomyEarn.streak_bonus(8, _config())).is_equal(0)


func test_streak_bonus_day_14_is_day_7_anchor() -> void:
	# Two full cycles in: day 14 == cycle position 7 → 100.
	assert_int(EconomyEarn.streak_bonus(14, _config())).is_equal(100)


func test_streak_bonus_day_11_is_day_4_position() -> void:
	# day 11 → cycle position 4 → 25.
	assert_int(EconomyEarn.streak_bonus(11, _config())).is_equal(25)


func test_streak_bonus_zero_day_is_zero() -> void:
	assert_int(EconomyEarn.streak_bonus(0, _config())).is_equal(0)


func test_streak_bonus_negative_day_is_zero() -> void:
	assert_int(EconomyEarn.streak_bonus(-5, _config())).is_equal(0)


func test_streak_bonus_honours_custom_config() -> void:
	# Proves the values are config-driven, not hardcoded in core/.
	var cfg := EconomyConfig.new()
	cfg.streak_day_2_to_4_bonus = 11
	cfg.streak_day_5_to_6_bonus = 22
	cfg.streak_day_7_bonus = 33
	assert_int(EconomyEarn.streak_bonus(3, cfg)).is_equal(11)
	assert_int(EconomyEarn.streak_bonus(6, cfg)).is_equal(22)
	assert_int(EconomyEarn.streak_bonus(7, cfg)).is_equal(33)


# ---------------------------------------------------------------------------
# next_streak_day — Rule 16 transition table (AC-EF04)
# ---------------------------------------------------------------------------

func test_next_streak_day_first_login_starts_at_1() -> void:
	# prev <= 0 → no prior login → day 1, regardless of the day keys.
	assert_int(EconomyEarn.next_streak_day(0, -1, 20000, _config())).is_equal(1)


func test_next_streak_day_same_day_is_idempotent() -> void:
	# delta == 0 → returns the same streak day (a second login today does not advance).
	assert_int(EconomyEarn.next_streak_day(4, 20000, 20000, _config())).is_equal(4)


func test_next_streak_day_consecutive_day_advances() -> void:
	# delta == 1 → +1.
	assert_int(EconomyEarn.next_streak_day(4, 20000, 20001, _config())).is_equal(5)


func test_next_streak_day_day_7_rolls_over_to_8() -> void:
	# AC-EF04: a natural day-8 rollover (no miss) continues the streak into 8.
	assert_int(EconomyEarn.next_streak_day(7, 20000, 20001, _config())).is_equal(8)


func test_next_streak_day_missed_one_day_resets_to_floor() -> void:
	# AC-EF04: a missed day resets to STREAK_RESET_FLOOR (3), NOT 0.
	assert_int(EconomyEarn.next_streak_day(6, 20000, 20002, _config())).is_equal(3)


func test_next_streak_day_missed_many_days_resets_to_floor() -> void:
	# A long lapse still lands on the floor, never below.
	assert_int(EconomyEarn.next_streak_day(20, 20000, 20100, _config())).is_equal(3)


func test_next_streak_day_backward_clock_is_defensive_noop() -> void:
	# delta < 0 (bad/rolled-back clock) → keep the prior streak, never crash.
	assert_int(EconomyEarn.next_streak_day(5, 20000, 19995, _config())).is_equal(5)


func test_next_streak_day_reset_floor_is_config_driven() -> void:
	var cfg := EconomyConfig.new()
	cfg.streak_reset_floor = 1
	assert_int(EconomyEarn.next_streak_day(6, 20000, 20005, cfg)).is_equal(1)


# ---------------------------------------------------------------------------
# milestone_coin_gift — Rule 17 one-time coin table (AC-EF05)
# ---------------------------------------------------------------------------

func test_milestone_coin_gift_level_5_is_100() -> void:
	# AC-EF05: reaching level 5 awards 100 coins.
	assert_int(EconomyEarn.milestone_coin_gift(5, _config())).is_equal(100)


func test_milestone_coin_gift_all_table_levels() -> void:
	var cfg := _config()
	assert_int(EconomyEarn.milestone_coin_gift(10, cfg)).is_equal(150)
	assert_int(EconomyEarn.milestone_coin_gift(25, cfg)).is_equal(200)
	assert_int(EconomyEarn.milestone_coin_gift(50, cfg)).is_equal(300)
	assert_int(EconomyEarn.milestone_coin_gift(100, cfg)).is_equal(500)
	assert_int(EconomyEarn.milestone_coin_gift(200, cfg)).is_equal(750)


func test_milestone_coin_gift_non_milestone_is_zero() -> void:
	var cfg := _config()
	assert_int(EconomyEarn.milestone_coin_gift(6, cfg)).is_equal(0)
	assert_int(EconomyEarn.milestone_coin_gift(1, cfg)).is_equal(0)
	assert_int(EconomyEarn.milestone_coin_gift(0, cfg)).is_equal(0)


func test_milestone_coin_gift_honours_custom_table() -> void:
	var cfg := EconomyConfig.new()
	cfg.milestone_coin_gifts = {3: 42}
	assert_int(EconomyEarn.milestone_coin_gift(3, cfg)).is_equal(42)
	assert_int(EconomyEarn.milestone_coin_gift(5, cfg)).is_equal(0)


# ---------------------------------------------------------------------------
# Gem gifts — Rule 18 (AC-EF06 + every-10-levels drip)
# ---------------------------------------------------------------------------

func test_tutorial_gem_gift_is_15() -> void:
	# AC-EF06: tutorial completion awards 15 gems.
	assert_int(EconomyEarn.tutorial_gem_gift(_config())).is_equal(15)


func test_tutorial_gem_gift_is_config_driven() -> void:
	var cfg := EconomyConfig.new()
	cfg.gem_gift_tutorial = 7
	assert_int(EconomyEarn.tutorial_gem_gift(cfg)).is_equal(7)


func test_level_clear_gem_gift_on_multiples_of_10() -> void:
	var cfg := _config()
	assert_int(EconomyEarn.level_clear_gem_gift(10, cfg)).is_equal(5)
	assert_int(EconomyEarn.level_clear_gem_gift(20, cfg)).is_equal(5)
	assert_int(EconomyEarn.level_clear_gem_gift(100, cfg)).is_equal(5)


func test_level_clear_gem_gift_zero_off_cadence() -> void:
	var cfg := _config()
	assert_int(EconomyEarn.level_clear_gem_gift(15, cfg)).is_equal(0)
	assert_int(EconomyEarn.level_clear_gem_gift(9, cfg)).is_equal(0)


func test_level_clear_gem_gift_zero_levels_is_zero() -> void:
	# 0 % 10 == 0 but no levels cleared → no gift.
	assert_int(EconomyEarn.level_clear_gem_gift(0, _config())).is_equal(0)
