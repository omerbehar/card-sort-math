extends GdUnitTestSuite
## Tests for [BoardModel] — routing, stack clears, the cascade, win and lose.


# Builds a model whose every card is exposed (no coverage), so taps are free.
func _open_model(results: Array[int], queue: Array[int]) -> BoardModel:
	var covered_by: Dictionary = {}
	for i in results.size():
		covered_by[i] = [] as Array[int]
	return BoardModel.new(results, covered_by, queue)


func _kinds(events: Array[GameEvent]) -> Array:
	var out: Array = []
	for e: GameEvent in events:
		out.append(e.kind)
	return out


func test_card_routes_to_matching_stack() -> void:
	# Stacks start as targets 7,9,11,13; a single 7 routes to stack 0.
	var model := _open_model([7, 9, 11, 13, 5, 5], [7, 9, 11, 13])
	var events := model.tap_card(0)
	assert_array(_kinds(events)).is_equal([GameEvent.Kind.ROUTE])
	assert_int(events[0].stack_index).is_equal(0)
	assert_int(model.stack_count(0)).is_equal(1)


func test_card_with_no_matching_stack_goes_to_discard() -> void:
	# Result 5 matches none of the stacks 7,9,11,13.
	var model := _open_model([5, 5, 5, 7, 7, 7], [7, 9, 11, 13])
	var events := model.tap_card(0)
	assert_array(_kinds(events)).is_equal([GameEvent.Kind.DISCARD])
	assert_int(events[0].discard_slot).is_equal(0)
	assert_int(model.discard_card(0)).is_equal(0)


func test_third_matching_card_clears_stack() -> void:
	# Three 7s fill stack 0; queue has no fifth entry, so new target is none.
	var model := _open_model([7, 7, 7, 0, 0, 0], [7, 9, 11, 13])
	model.tap_card(0)
	model.tap_card(1)
	var events := model.tap_card(2)
	var kinds := _kinds(events)
	assert_bool(kinds.has(GameEvent.Kind.STACK_CLEARED)).is_true()
	assert_int(model.stack_count(0)).is_equal(0)
	assert_int(model.stack_target(0)).is_equal(BoardModel.NO_TARGET)


func test_full_cascade_pulls_from_discard_and_re_clears() -> void:
	# Stacks 7,99,99,99; the next queued target (index 4) is 5.
	# Cards 0,1,2 are 5s (no stack -> discard); 3,4,5 are 7s.
	# Tapping the third 7 clears stack 0, draws target 5, and pulls the three
	# discarded 5s back in -> stack refills to 3 -> clears again.
	var model := _open_model([5, 5, 5, 7, 7, 7], [7, 99, 99, 99, 5])
	model.tap_card(0)
	model.tap_card(1)
	model.tap_card(2)
	assert_int(model.discard_card(0)).is_equal(0)
	model.tap_card(3)
	model.tap_card(4)
	var events := model.tap_card(5)

	assert_array(_kinds(events)).is_equal([
		GameEvent.Kind.ROUTE,
		GameEvent.Kind.STACK_CLEARED,  # cleared with three 7s, new target 5
		GameEvent.Kind.PULL,           # pull discarded 5 (card 0)
		GameEvent.Kind.PULL,           # pull discarded 5 (card 1)
		GameEvent.Kind.PULL,           # pull discarded 5 (card 2)
		GameEvent.Kind.STACK_CLEARED,  # refilled to 3 -> clears again
		GameEvent.Kind.WIN,            # floor now empty
	])
	# Discard emptied by the pull-back.
	for slot in BoardModel.DISCARD_SLOTS:
		assert_int(model.discard_card(slot)).is_equal(-1)
	assert_bool(model.is_won()).is_true()


func test_win_when_floor_cleared() -> void:
	var model := _open_model([7, 7, 7], [7, 9, 11, 13])
	model.tap_card(0)
	model.tap_card(1)
	var events := model.tap_card(2)
	assert_bool(_kinds(events).has(GameEvent.Kind.WIN)).is_true()
	assert_bool(model.is_won()).is_true()


func test_lose_when_discard_overflows() -> void:
	# Six cards of result 5; no stack/queue ever matches 5. After 5 discards
	# the sixth tap has nowhere to go -> LOSE.
	var model := _open_model([5, 5, 5, 5, 5, 5], [7, 9, 11, 13])
	for i in range(5):
		model.tap_card(i)
	var events := model.tap_card(5)
	assert_array(_kinds(events)).is_equal([GameEvent.Kind.LOSE])
	assert_bool(model.is_lost()).is_true()


func test_taps_ignored_after_game_over() -> void:
	var model := _open_model([5, 5, 5, 5, 5, 5], [7, 9, 11, 13])
	for i in range(6):
		model.tap_card(i)
	assert_bool(model.is_lost()).is_true()
	# Any further tap is a no-op.
	assert_array(model.tap_card(0)).is_empty()


func test_tap_on_covered_card_is_noop() -> void:
	# Card 0 is covered by card 1; tapping 0 does nothing until 1 is removed.
	# Card 2 stays on the floor so clearing 0 and 1 doesn't trigger a win.
	var covered_by: Dictionary = {
		0: [1] as Array[int], 1: [] as Array[int], 2: [] as Array[int],
	}
	var model := BoardModel.new([7, 9, 5], covered_by, [7, 9, 11, 13])
	assert_array(model.tap_card(0)).is_empty()
	# Removing the coverer exposes card 0.
	model.tap_card(1)
	assert_array(_kinds(model.tap_card(0))).is_equal([GameEvent.Kind.ROUTE])
