extends GdUnitTestSuite
## Property + structure tests for the by-construction level generator (S2-003a,
## GDD level-generator, ADR-0007). Covers the acceptance criteria that do not
## need the difficulty schedule. DEFERRED: AC-21..27 (schedule -> S2-003b),
## AC-28..31 (LevelData wiring -> S2-004), AC-32..35 (recoverability -> S2-003b).

const SEED_COUNT: int = 100


# --- helpers --------------------------------------------------------------

func _generate(params: GeneratorParams) -> LevelConfig:
	var result := LevelGenerator.generate(params)
	assert_object(result.config).is_not_null()
	return result.config


# Groups a pool's cards by result -> array of operand_a values.
func _operand_a_by_result(config: LevelConfig) -> Dictionary:
	var by_result: Dictionary = {}
	for card: CardData in config.card_pool:
		if not by_result.has(card.result):
			by_result[card.result] = []
		by_result[card.result].append(card.operand_a)
	return by_result


func _span(result_value: int, max_operand: int) -> int:
	var a_min: int = maxi(1, result_value - max_operand)
	var a_max: int = mini(max_operand, result_value - 1)
	return a_max - a_min + 1


# --- Group 1: solvability & determinism -----------------------------------

func test_generate_layout0_all_seeds_are_solvable() -> void:
	# AC-01 — the headline property test.
	for seed in range(SEED_COUNT):
		var config := _generate(GeneratorFixtures.layout_0(seed))
		assert_bool(Solvability.is_solvable(config)) \
			.override_failure_message("seed %d not solvable" % seed).is_true()


func test_generate_all_layouts_all_seeds_are_solvable() -> void:
	# AC-02 — 300 calls across the three fixtures.
	for seed in range(SEED_COUNT):
		for params: GeneratorParams in GeneratorFixtures.all(seed):
			var config := _generate(params)
			assert_bool(Solvability.is_solvable(config)).is_true()


func test_generate_same_params_twice_is_field_identical() -> void:
	# AC-03 — determinism.
	var a := _generate(GeneratorFixtures.layout_0(42))
	var b := _generate(GeneratorFixtures.layout_0(42))
	assert_array(a.target_queue).is_equal(b.target_queue)
	assert_int(a.card_pool.size()).is_equal(b.card_pool.size())
	for i in range(a.card_pool.size()):
		var ca: CardData = a.card_pool[i]
		var cb: CardData = b.card_pool[i]
		assert_int(ca.operand_a).is_equal(cb.operand_a)
		assert_int(ca.operand_b).is_equal(cb.operand_b)
		assert_int(ca.result).is_equal(cb.result)
		assert_int(ca.layout_slot).is_equal(cb.layout_slot)
		assert_int(ca.layout_layer).is_equal(cb.layout_layer)


func test_generate_distinct_seeds_yield_distinct_queues() -> void:
	# AC-04 — no seed collision across a spread of seeds.
	var seeds: Array[int] = [0, 1, 7, 8, 42, 43, 99, 100]
	var seen: Dictionary = {}
	for seed in seeds:
		var key := str(_generate(GeneratorFixtures.layout_0(seed)).target_queue)
		seen[key] = true
	assert_int(seen.size()).is_equal(seeds.size())


# --- Group 2: structure / counts ------------------------------------------

func test_card_pool_size_matches_layout_slot_count() -> void:
	# AC-05.
	for params: GeneratorParams in GeneratorFixtures.all(3):
		var config := _generate(params)
		assert_int(config.card_pool.size()).is_equal(Layouts.SLOT_COUNTS[params.layout_id])


func test_target_queue_length_is_slot_count_over_three() -> void:
	# AC-06.
	for params: GeneratorParams in GeneratorFixtures.all(3):
		var config := _generate(params)
		assert_int(config.target_queue.size()).is_equal(Layouts.SLOT_COUNTS[params.layout_id] / 3)


func test_cards_per_result_is_three_times_queue_count() -> void:
	# AC-07 — the identity, checked independently of is_solvable.
	var config := _generate(GeneratorFixtures.layout_1(11))
	var queue_counts: Dictionary = {}
	for t: int in config.target_queue:
		queue_counts[t] = int(queue_counts.get(t, 0)) + 1
	var card_counts: Dictionary = {}
	for card: CardData in config.card_pool:
		card_counts[card.result] = int(card_counts.get(card.result, 0)) + 1
	for r: int in card_counts:
		assert_int(int(card_counts[r])).is_equal(3 * int(queue_counts[r]))


func test_layout_slots_are_a_canonical_permutation() -> void:
	# AC-08 — permutation AND canonical ordering (pool[i].layout_slot == i).
	for params: GeneratorParams in GeneratorFixtures.all(5):
		var config := _generate(params)
		for i in range(config.card_pool.size()):
			assert_int(config.card_pool[i].layout_slot).is_equal(i)


func test_generated_config_is_marked_generated() -> void:
	# AC-09.
	var config := _generate(GeneratorFixtures.layout_0(0))
	assert_bool(config.is_generated()).is_true()
	assert_int(config.level_id).is_equal(LevelConfig.GENERATED_ID)


# --- Group 3: operands -----------------------------------------------------

func test_every_card_result_equals_operand_sum() -> void:
	# AC-10.
	for params: GeneratorParams in GeneratorFixtures.all(8):
		var config := _generate(params)
		for card: CardData in config.card_pool:
			assert_int(card.operand_a + card.operand_b).is_equal(card.result)


func test_operands_within_max_operand_bounds() -> void:
	# AC-11.
	for params: GeneratorParams in GeneratorFixtures.all(8):
		var config := _generate(params)
		for card: CardData in config.card_pool:
			assert_bool(card.operand_a >= 1 and card.operand_a <= params.max_operand).is_true()
			assert_bool(card.operand_b >= 1 and card.operand_b <= params.max_operand).is_true()


func test_results_within_configured_range() -> void:
	# AC-12.
	var params := GeneratorFixtures.layout_0(8)
	var config := _generate(params)
	for card: CardData in config.card_pool:
		assert_bool(card.result >= params.result_min and card.result <= params.result_max).is_true()


func test_operand_round_robin_covers_the_window() -> void:
	# AC-13 — for every result the distinct operand_a count equals
	# min(span(R), card_count), proving the round-robin advances (not stuck at i=0).
	var params := GeneratorFixtures.layout_0(8)
	var config := _generate(params)
	var by_result := _operand_a_by_result(config)
	for r: int in by_result:
		var values: Array = by_result[r]
		var distinct: Dictionary = {}
		for v: int in values:
			distinct[v] = true
		var expected: int = mini(_span(r, params.max_operand), values.size())
		assert_int(distinct.size()) \
			.override_failure_message("result %d: expected %d distinct operand_a, got %d"
				% [r, expected, distinct.size()]).is_equal(expected)


func test_degenerate_result_two_is_one_plus_one() -> void:
	# AC-14 — span(2)=1 -> every card "1 + 1".
	var params := GeneratorParams.create(0, 1, 2, 2, 1, 0)
	var config := _generate(params)
	for card: CardData in config.card_pool:
		assert_int(card.operand_a).is_equal(1)
		assert_int(card.operand_b).is_equal(1)


# --- Group 4: clamps & edge cases -----------------------------------------

func test_distinct_results_above_queue_length_is_clamped_and_warned() -> void:
	# AC-15 — D=10 > L=4 -> 4 distinct results + a warning.
	var params := GeneratorParams.create(0, 10, 3, 12, 6, 1)
	var result := LevelGenerator.generate(params)
	assert_object(result.config).is_not_null()
	var distinct: Dictionary = {}
	for t: int in result.config.target_queue:
		distinct[t] = true
	assert_int(distinct.size()).is_equal(4)
	assert_int(result.warnings.size()).is_greater(0)


func test_candidate_pool_smaller_than_distinct_is_clamped() -> void:
	# AC-16 — few candidates -> clamp down, warn, still solvable.
	# R in [10,12], max_operand=6 -> valid results {10,11,12}? 11:max(1,5)=5<=min(6,10)=6 ok;
	# 12:max(1,6)=6<=min(6,11)=6 ok; 10:max(1,4)=4<=min(6,9)=6 ok -> 3 candidates < D=4.
	var params := GeneratorParams.create(1, 4, 10, 12, 6, 2)
	var result := LevelGenerator.generate(params)
	assert_object(result.config).is_not_null()
	assert_bool(Solvability.is_solvable(result.config)).is_true()
	assert_int(result.warnings.size()).is_greater(0)


func test_empty_candidate_pool_returns_null_config() -> void:
	# AC-17a — R_min=R_max=10, max_operand=4 -> no legal pair -> null (no crash).
	var params := GeneratorParams.create(0, 4, 10, 10, 4, 0)
	var result := LevelGenerator.generate(params)
	assert_object(result.config).is_null()


func test_invalid_params_return_null_config() -> void:
	# AC-17c — max_operand=0 and layout_id out of range each error out.
	assert_object(LevelGenerator.generate(GeneratorParams.create(0, 4, 3, 12, 0, 0)).config).is_null()
	assert_object(LevelGenerator.generate(GeneratorParams.create(3, 4, 3, 12, 6, 0)).config).is_null()


func test_no_repeats_with_few_distinct_promotes_and_solves() -> void:
	# AC-18 — allow_queue_repeats=false but distinct < L -> promote, warn, solvable.
	# layout 1 (L=6), only 3 candidates [10,12] range -> distinct 3 < 6.
	var params := GeneratorParams.create(1, 6, 10, 12, 6, 4, false)
	var result := LevelGenerator.generate(params)
	assert_object(result.config).is_not_null()
	assert_int(result.config.target_queue.size()).is_equal(6)
	assert_bool(Solvability.is_solvable(result.config)).is_true()
	assert_int(result.warnings.size()).is_greater(0)


func test_solvability_rejects_broken_config() -> void:
	# AC-19a — the pure oracle catches an invariant break (4 cards for a once-queued result).
	var config := LevelConfig.new()
	config.target_queue = [7, 7, 7, 7]
	config.card_pool = [
		CardData.create(3, 4, 0, 0),
		CardData.create(3, 4, 0, 1),
		CardData.create(3, 4, 0, 2),
		CardData.create(3, 4, 0, 3),
	]
	assert_bool(Solvability.is_solvable(config)).is_false()


func test_single_distinct_result_is_valid() -> void:
	# AC-20 — D=1 degenerate but valid by construction.
	var params := GeneratorParams.create(0, 1, 5, 5, 3, 0)
	var config := _generate(params)
	assert_bool(Solvability.is_solvable(config)).is_true()
	assert_int(config.card_pool.size()).is_equal(12)
	for t: int in config.target_queue:
		assert_int(t).is_equal(5)
	for card: CardData in config.card_pool:
		assert_int(card.result).is_equal(5)


# --- Provenance & authored-collision guard --------------------------------

func test_provenance_round_trips() -> void:
	# (Supports AC-35 in spirit; full LevelData dispatch is S2-004.)
	var params := GeneratorParams.create(0, 4, 3, 12, 6, 42, true, 1, 7)
	var config := _generate(params)
	assert_int(config.seed).is_equal(42)
	assert_int(config.world_id).is_equal(1)
	assert_int(config.level_index).is_equal(7)


func test_fresh_config_is_not_generated() -> void:
	# Sentinel guard: a bare LevelConfig (default level_id = -1) is not "generated".
	assert_bool(LevelConfig.new().is_generated()).is_false()


# --- Group 5: operation worlds (subtraction / multiplication / division / mixed) ---

# Builds a single-operation level and asserts it is solvable, every card prints
# the requested operation, and each card's operands evaluate back to its result.
func _assert_world(operation: int, result_max: int, max_operand: int) -> LevelConfig:
	var params := GeneratorParams.create(
		0, 4, 2, result_max, max_operand, 7, true, 0, 0, [operation] as Array[int])
	var config := _generate(params)
	assert_bool(Solvability.is_solvable(config)).is_true()
	for card: CardData in config.card_pool:
		assert_int(card.operation).is_equal(operation)
		assert_int(Operation.apply(card.operand_a, card.operand_b, card.operation)) \
			.is_equal(card.result)
		assert_bool(card.operand_a >= 1 and card.operand_a <= max_operand).is_true()
		assert_bool(card.operand_b >= 1 and card.operand_b <= max_operand).is_true()
	return config


func test_subtraction_world_is_solvable_and_all_minus() -> void:
	_assert_world(Operation.Type.SUBTRACT, 6, 10)


func test_multiplication_world_is_solvable_and_all_times() -> void:
	_assert_world(Operation.Type.MULTIPLY, 16, 8)


func test_division_world_is_solvable_and_all_divide() -> void:
	_assert_world(Operation.Type.DIVIDE, 8, 10)


func test_operation_worlds_are_solvable_across_seeds() -> void:
	for op: int in [Operation.Type.SUBTRACT, Operation.Type.MULTIPLY, Operation.Type.DIVIDE]:
		for seed in range(20):
			var params := GeneratorParams.create(
				1, 4, 2, 16, 10, seed, true, 0, 0, [op] as Array[int])
			var config := _generate(params)
			assert_bool(Solvability.is_solvable(config)) \
				.override_failure_message("op %d seed %d unsolvable" % [op, seed]).is_true()


func test_mixed_world_uses_multiple_operations_and_stays_solvable() -> void:
	# All four operations allowed: the board must remain solvable and actually mix
	# operations (more than one distinct operator appears across the pool).
	var params := GeneratorParams.create(
		1, 5, 2, 16, 10, 3, true, 0, 0, Operation.ALL)
	var config := _generate(params)
	assert_bool(Solvability.is_solvable(config)).is_true()
	var ops_seen: Dictionary = {}
	for card: CardData in config.card_pool:
		ops_seen[card.operation] = true
		assert_int(Operation.apply(card.operand_a, card.operand_b, card.operation)) \
			.is_equal(card.result)
	assert_int(ops_seen.size()).is_greater(1)


func test_mixed_world_is_deterministic() -> void:
	# Per-card operation choice draws from the seeded RNG, so it must reproduce.
	var params := GeneratorParams.create(1, 5, 2, 16, 10, 99, true, 0, 0, Operation.ALL)
	var a := _generate(params)
	var b := _generate(params)
	for i in range(a.card_pool.size()):
		assert_int(a.card_pool[i].operation).is_equal(b.card_pool[i].operation)
		assert_int(a.card_pool[i].operand_a).is_equal(b.card_pool[i].operand_a)
		assert_int(a.card_pool[i].operand_b).is_equal(b.card_pool[i].operand_b)
