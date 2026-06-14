extends GdUnitTestSuite
## LevelData generated-dispatch integration tests (S2-004, ADR-0007, AC-28..31).
## Authored levels 1..3 stay hand-authored; levels beyond are generated and must
## be solvable, deterministic, and playable end to end.


# --- AC-28: authored levels 1..3 are unchanged and not flagged generated. ---
func test_authored_levels_are_not_generated() -> void:
	for n in range(1, LevelData.level_count() + 1):
		var config := LevelData.get_level(n)
		assert_bool(config.is_generated()) \
			.override_failure_message("authored level %d reads as generated" % n).is_false()
		assert_int(config.level_id).is_equal(n)
		assert_bool(LevelData.is_solvable(config)).is_true()


func test_authored_operands_match_legacy_split() -> void:
	# Regression guard for retiring _split_operands -> OperandPicker: level 1's
	# first cards must read exactly as before (1+4, 2+5, 3+6, 4+7).
	var config := LevelData.get_level(1)
	assert_str(config.card_pool[0].exercise_text()).is_equal("1 + 4")
	assert_str(config.card_pool[1].exercise_text()).is_equal("2 + 5")
	assert_str(config.card_pool[2].exercise_text()).is_equal("3 + 6")
	assert_str(config.card_pool[3].exercise_text()).is_equal("4 + 7")


# --- AC-29: the first level past the authored set is generated and solvable. ---
func test_first_generated_level_is_solvable() -> void:
	var config := LevelData.get_level(LevelData.level_count() + 1)
	assert_bool(config.is_generated()).is_true()
	assert_int(config.level_id).is_equal(LevelConfig.GENERATED_ID)
	assert_bool(LevelData.is_solvable(config)).is_true()


# --- AC-30: a deep generated level is reproducible and carries provenance. ---
func test_deep_generated_level_is_reproducible() -> void:
	var a := LevelData.get_level(50)
	var b := LevelData.get_level(50)
	assert_bool(a.is_generated()).is_true()
	assert_bool(LevelData.is_solvable(a)).is_true()
	assert_array(a.target_queue).is_equal(b.target_queue)
	assert_int(a.card_pool.size()).is_equal(b.card_pool.size())
	for i in range(a.card_pool.size()):
		assert_int(a.card_pool[i].result).is_equal(b.card_pool[i].result)
		assert_int(a.card_pool[i].operand_a).is_equal(b.card_pool[i].operand_a)
	# Provenance: seed = world_for_level(n) * WORLD_STRIDE + n, level_index = n.
	assert_int(a.seed).is_equal(LevelData.world_for_level(50) * LevelData.WORLD_STRIDE + 50)
	assert_int(a.level_index).is_equal(50)


# --- AC-31: a generated level is playable end to end. ---
func test_generated_level_is_playable() -> void:
	var config := LevelData.get_level(40)
	var board := BoardModel.from_config(config)
	var exposed := board.exposed_cards()
	assert_array(exposed).is_not_empty()
	var events := board.tap_card(exposed[0])
	assert_array(events).is_not_empty()


# --- Generated levels stay solvable across a spread of indices. ---
func test_generated_levels_are_solvable_across_indices() -> void:
	for n in [4, 13, 21, 29, 53, 85, 150]:
		var config := LevelData.get_level(n)
		assert_bool(config.is_generated()) \
			.override_failure_message("level %d not generated" % n).is_true()
		assert_bool(LevelData.is_solvable(config)) \
			.override_failure_message("level %d not solvable" % n).is_true()


# --- Operation worlds: every WORLD_SIZE levels advances one operation, then mix. ---
func test_world_for_level_maps_bands_to_operations() -> void:
	# Levels 1-5 +, 6-10 −, 11-15 ×, 16-20 ÷, 21+ mixed.
	assert_int(LevelData.world_for_level(1)).is_equal(0)
	assert_int(LevelData.world_for_level(5)).is_equal(0)
	assert_int(LevelData.world_for_level(6)).is_equal(1)
	assert_int(LevelData.world_for_level(11)).is_equal(2)
	assert_int(LevelData.world_for_level(16)).is_equal(3)
	assert_int(LevelData.world_for_level(21)).is_equal(LevelData.MIXED_WORLD_ID)
	assert_int(LevelData.world_for_level(99)).is_equal(LevelData.MIXED_WORLD_ID)


func test_single_operation_worlds_print_only_that_operation() -> void:
	# A representative generated level in each single-operation band prints one op.
	var bands := {
		8: Operation.Type.SUBTRACT,
		13: Operation.Type.MULTIPLY,
		18: Operation.Type.DIVIDE,
	}
	for n: int in bands:
		var config := LevelData.get_level(n)
		assert_bool(LevelData.is_solvable(config)).is_true()
		for card: CardData in config.card_pool:
			assert_int(card.operation) \
				.override_failure_message("level %d card op mismatch" % n) \
				.is_equal(bands[n])


func test_mixed_world_level_mixes_operations() -> void:
	var config := LevelData.get_level(25)
	assert_bool(LevelData.is_solvable(config)).is_true()
	var ops_seen: Dictionary = {}
	for card: CardData in config.card_pool:
		ops_seen[card.operation] = true
	assert_int(ops_seen.size()).is_greater(1)


# Every result in a generated level must read at least OPERAND_OPTIONS_MIN distinct
# ways, so equal-result cards aren't the same exercise (the "1 × 7" variety bug).
func test_generated_results_offer_at_least_three_distinct_exercises() -> void:
	# One level per world: addition, subtraction, multiplication, division, mixed.
	for n in [4, 8, 13, 18, 25, 33]:
		var config := LevelData.get_level(n)
		assert_bool(LevelData.is_solvable(config)) \
			.override_failure_message("level %d not solvable" % n).is_true()
		var exercises_by_result: Dictionary = {}
		for card: CardData in config.card_pool:
			if not exercises_by_result.has(card.result):
				exercises_by_result[card.result] = {}
			exercises_by_result[card.result][card.exercise_text()] = true
		for result: int in exercises_by_result:
			assert_int((exercises_by_result[result] as Dictionary).size()) \
				.override_failure_message(
					"level %d, result %d shows only %s — needs >= %d distinct exercises"
					% [n, result, str((exercises_by_result[result] as Dictionary).keys()), LevelData.OPERAND_OPTIONS_MIN]) \
				.is_greater_equal(LevelData.OPERAND_OPTIONS_MIN)


# A multiply-world level must never use a prime result (it would read all "1 × p").
func test_multiplication_world_excludes_prime_results() -> void:
	var config := LevelData.get_level(13)
	var primes := {2: true, 3: true, 5: true, 7: true, 11: true, 13: true, 17: true, 19: true, 23: true}
	for card: CardData in config.card_pool:
		assert_bool(primes.has(card.result)) \
			.override_failure_message("multiply level uses prime result %d" % card.result).is_false()
