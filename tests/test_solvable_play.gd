extends GdUnitTestSuite
## Proves every authored level is winnable through actual play (not merely
## count-solvable) by running a greedy auto-player against the [BoardModel]:
## always route an exposed card if a matching stack has room, otherwise discard
## an exposed card. Catches layouts that would dead-end or overflow discard.


func test_every_level_is_winnable_by_greedy_play() -> void:
	for n in range(1, LevelData.level_count() + 1):
		var model := BoardModel.from_config(LevelData.get_level(n))
		var won := _greedy_solve(model)
		assert_bool(won) \
			.override_failure_message("Level %d was not winnable by greedy play" % n) \
			.is_true()


func _greedy_solve(model: BoardModel) -> bool:
	var guard: int = 0
	while not model.is_game_over() and guard < 10000:
		guard += 1
		var route_pick: int = -1
		var discard_pick: int = -1
		for card_id: int in model.exposed_cards():
			if _has_open_stack(model, model.result_of(card_id)):
				route_pick = card_id
				break
			elif discard_pick == -1:
				discard_pick = card_id
		var pick: int = route_pick if route_pick != -1 else discard_pick
		if pick == -1:
			return false  # no legal move
		model.tap_card(pick)
	return model.is_won()


func _has_open_stack(model: BoardModel, result: int) -> bool:
	for i in BoardModel.STACK_COUNT:
		if model.stack_target(i) == result and model.stack_count(i) < BoardModel.STACK_CAPACITY:
			return true
	return false
