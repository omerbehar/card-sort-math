extends GdUnitTestSuite
## Recoverability backstop tests (S2-003b, GDD Core Rule 10 / AC-32, AC-34).
## The sim is a *necessary, not sufficient* fairness check; AC-27 (human
## playtest) is the real gate.

const SEED_COUNT: int = 60


# --- AC-32: generated levels (recovery enabled, margin 1) win under the
# greedy + one-mistake player with >= 1 free discard slot throughout. ---
func test_generated_levels_are_recoverable() -> void:
	var data := DifficultyScheduleData.new()
	for n in [1, 8, 13, 21, 29, 40, 53]:
		for seed in range(SEED_COUNT):
			var params := DifficultySchedule.params_for(n, data, seed)
			var result := LevelGenerator.generate(params)
			assert_object(result.config) \
				.override_failure_message("level %d seed %d: null" % [n, seed]).is_not_null()
			var outcome := RecoverabilitySimulator.run(result.config)
			assert_bool(outcome.won) \
				.override_failure_message("level %d seed %d: not won under one mistake" % [n, seed]) \
				.is_true()
			assert_int(outcome.headroom) \
				.override_failure_message("level %d seed %d: headroom %d < margin" % [n, seed, outcome.headroom]) \
				.is_greater_equal(data.min_recovery_margin)


# --- AC-34: when every attempt "fails" the recovery check, generate still
# returns a non-null, solvable fallback level and warns that the cap was hit. ---
func test_cap_exhaustion_returns_solvable_fallback_with_warning() -> void:
	var always_fail := func(_config: LevelConfig, _margin: int) -> bool: return false
	var params := GeneratorParams.create(0, 4, 3, 12, 6, 1)
	params.min_recovery_margin = 1
	params.recovery_attempt_cap = 4

	var result := LevelGenerator.generate(params, always_fail)

	assert_object(result.config).is_not_null()
	assert_bool(Solvability.is_solvable(result.config)).is_true()
	var has_cap_warning: bool = false
	for w: String in result.warnings:
		if w.contains("cap"):
			has_cap_warning = true
	assert_bool(has_cap_warning).is_true()


# --- An accepted re-seed is deterministic: same params twice -> identical level
# even when recovery is enabled. ---
func test_recovery_enabled_generation_is_deterministic() -> void:
	var data := DifficultyScheduleData.new()
	var a := LevelGenerator.generate(DifficultySchedule.params_for(40, data, 99)).config
	var b := LevelGenerator.generate(DifficultySchedule.params_for(40, data, 99)).config
	assert_array(a.target_queue).is_equal(b.target_queue)
	assert_int(a.card_pool.size()).is_equal(b.card_pool.size())
	for i in range(a.card_pool.size()):
		assert_int(a.card_pool[i].result).is_equal(b.card_pool[i].result)
		assert_int(a.card_pool[i].operand_a).is_equal(b.card_pool[i].operand_a)
		assert_int(a.card_pool[i].layout_slot).is_equal(b.card_pool[i].layout_slot)


# --- A first-attempt recoverable level is returned unchanged (no fallback warning). ---
func test_recoverable_level_has_no_cap_warning() -> void:
	var data := DifficultyScheduleData.new()
	var result := LevelGenerator.generate(DifficultySchedule.params_for(8, data, 3))
	assert_object(result.config).is_not_null()
	for w: String in result.warnings:
		assert_bool(w.contains("cap")).is_false()
