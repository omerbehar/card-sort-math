extends GdUnitTestSuite
## Tests for [EconomyConfig] defaults and .tres instance integrity — S3-002.
##
## Coverage:
##   - EconomyConfig.new() exposes expected GDD defaults (spot-check key knobs).
##   - load("res://assets/data/economy_config.tres") returns an EconomyConfig
##     whose knobs match the script defaults (catches a malformed or stale .tres).
##
## Note: loading a resource in a *test* is intentional and explicitly permitted by
## the coding standards ("The no-load() rule applies to core/, not tests."). The
## point of the .tres load test is to verify the file imports cleanly and that its
## values agree with what the scripts declare.
##
## Source: design/gdd/deck-economy.md §Tuning Knobs;
##         design/registry/entities.yaml (constants entries).


# ---------------------------------------------------------------------------
# EconomyConfig.new() — default value spot-checks
# ---------------------------------------------------------------------------

func test_defaults_coins_win_flat_fallback() -> void:
	# Producer-flagged bridging knob; must exist and default to 50.
	var cfg := EconomyConfig.new()
	assert_int(cfg.coins_win_flat_fallback).is_equal(50)


func test_defaults_picker_cost_coins() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.picker_cost_coins).is_equal(120)


func test_defaults_reshuffle_cost_coins() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.reshuffle_cost_coins).is_equal(250)


func test_defaults_extra_discard_cost_coins() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.extra_discard_cost_coins).is_equal(350)


func test_defaults_gem_to_coin_rate() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.gem_to_coin_rate).is_equal(25)


func test_defaults_max_discard_slots() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.max_discard_slots).is_equal(7)


func test_defaults_coins_max() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.coins_max).is_equal(999999)


func test_defaults_gems_max() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.gems_max).is_equal(9999)


func test_defaults_spend_confirm_threshold() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.spend_confirm_threshold).is_equal(250)


func test_defaults_coins_win_1_star() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.coins_win_1_star).is_equal(40)


func test_defaults_coins_win_2_star() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.coins_win_2_star).is_equal(55)


func test_defaults_coins_win_3_star() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.coins_win_3_star).is_equal(75)


func test_defaults_clean_clear_bonus() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.clean_clear_bonus).is_equal(20)


func test_defaults_daily_coins_cap() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.daily_coins_cap).is_equal(500)


func test_defaults_daily_gem_convert_cap() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.daily_gem_convert_cap).is_equal(50)


func test_defaults_streak_reset_floor() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.streak_reset_floor).is_equal(3)


func test_defaults_max_ads_per_day() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.max_ads_per_day).is_equal(3)


func test_defaults_picker_cost_gems() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.picker_cost_gems).is_equal(3)


func test_defaults_reshuffle_cost_gems() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.reshuffle_cost_gems).is_equal(7)


func test_defaults_extra_discard_cost_gems() -> void:
	var cfg := EconomyConfig.new()
	assert_int(cfg.extra_discard_cost_gems).is_equal(10)


# ---------------------------------------------------------------------------
# .tres instance — integrity check
# This load catches a malformed .tres (bad ext_resource path, missing script,
# wrong class) and a drift between the script defaults and any values baked
# into the .tres. Loading in tests is explicitly permitted.
# ---------------------------------------------------------------------------

func test_tres_loads_as_economy_config_instance() -> void:
	# Arrange / Act
	var cfg: Resource = load("res://assets/data/economy_config.tres")
	# Assert: file exists and is the right type
	assert_bool(cfg != null).is_true()
	assert_bool(cfg is EconomyConfig).is_true()


func test_tres_coins_win_flat_fallback_matches_default() -> void:
	var cfg := load("res://assets/data/economy_config.tres") as EconomyConfig
	assert_int(cfg.coins_win_flat_fallback).is_equal(50)


func test_tres_picker_cost_coins_matches_default() -> void:
	var cfg := load("res://assets/data/economy_config.tres") as EconomyConfig
	assert_int(cfg.picker_cost_coins).is_equal(120)


func test_tres_max_discard_slots_matches_default() -> void:
	var cfg := load("res://assets/data/economy_config.tres") as EconomyConfig
	assert_int(cfg.max_discard_slots).is_equal(7)


func test_tres_gem_to_coin_rate_matches_default() -> void:
	var cfg := load("res://assets/data/economy_config.tres") as EconomyConfig
	assert_int(cfg.gem_to_coin_rate).is_equal(25)


func test_tres_coins_max_matches_default() -> void:
	var cfg := load("res://assets/data/economy_config.tres") as EconomyConfig
	assert_int(cfg.coins_max).is_equal(999999)


func test_tres_spend_confirm_threshold_matches_default() -> void:
	var cfg := load("res://assets/data/economy_config.tres") as EconomyConfig
	assert_int(cfg.spend_confirm_threshold).is_equal(250)
