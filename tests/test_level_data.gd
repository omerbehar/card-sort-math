extends GdUnitTestSuite
## Tests that every authored level is solvable by construction.


func test_all_authored_levels_are_solvable() -> void:
	for n in range(1, LevelData.level_count() + 1):
		var config := LevelData.get_level(n)
		assert_bool(LevelData.is_solvable(config)) \
			.override_failure_message("Level %d is not solvable" % n) \
			.is_true()


func test_card_pool_size_matches_layout() -> void:
	for n in range(1, LevelData.level_count() + 1):
		var config := LevelData.get_level(n)
		var expected: int = Layouts.SLOT_COUNTS[config.layout_id]
		assert_int(config.card_pool.size()).is_equal(expected)


func test_every_card_result_is_a_queued_target() -> void:
	for n in range(1, LevelData.level_count() + 1):
		var config := LevelData.get_level(n)
		for card: CardData in config.card_pool:
			assert_bool(config.target_queue.has(card.result)).is_true()


func test_is_solvable_rejects_broken_config() -> void:
	# Two cards of result 7 but the queue calls for exactly three (1 occurrence
	# x 3) -> count mismatch -> not solvable.
	var config := LevelConfig.new()
	config.target_queue = [7, 7, 7, 7]
	var pool: Array[CardData] = [
		CardData.create(3, 4, 0, 0),
		CardData.create(3, 4, 0, 1),
	]
	config.card_pool = pool
	assert_bool(LevelData.is_solvable(config)).is_false()


func test_next_target_draws_and_exhausts() -> void:
	var queue: Array[int] = [5, 7, 9, 11, 13]
	assert_int(LevelData.next_target(queue, 4)).is_equal(13)
	assert_int(LevelData.next_target(queue, 5)).is_equal(-1)
