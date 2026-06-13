extends GdUnitTestSuite
## Tests for BoardModel.pick_card (Picker booster) and BoardModel.reshuffle
## (Reshuffle booster, ADR-0009). Pure, node-free BoardModel instances.
## Source: design/gdd/deck-economy.md (Picker; Reshuffle Core Rule 10 / Formula 6).


# A two-layer pile: cards 3/4/5 (layer 1) cover cards 0/1/2 (layer 0) at the same
# x positions. Initially only 3/4/5 are exposed.
func _layered_placements() -> Array:
	return [
		{pos = Vector2(0, 0), layer = 0}, {pos = Vector2(100, 0), layer = 0}, {pos = Vector2(200, 0), layer = 0},
		{pos = Vector2(0, 0), layer = 1}, {pos = Vector2(100, 0), layer = 1}, {pos = Vector2(200, 0), layer = 1},
	]


func _layered_board() -> BoardModel:
	var placements := _layered_placements()
	var covered_by := Exposure.compute_covered_by(placements)
	# results 1..6; queue routes the low results so taps don't all discard.
	return BoardModel.new([1, 2, 3, 4, 5, 6], covered_by, [1, 2, 3, 4])


# ---------------------------------------------------------------------------
# pick_card — plays a covered card (Picker)
# ---------------------------------------------------------------------------

func test_pick_card_plays_a_covered_card() -> void:
	# Card 0 (result 1) is covered by card 3; not normally tappable. pick_card plays
	# it: result 1 matches stack 0's target (queue[0]==1) → it routes.
	var board := _layered_board()
	assert_bool(board.is_exposed(0)).is_false()
	var events := board.pick_card(0)
	assert_bool(events.is_empty()).is_false()
	assert_bool(board.is_card_removed(0)).is_true()


func test_pick_card_noop_on_removed_card() -> void:
	var board := _layered_board()
	board.pick_card(3)                       # remove an exposed card
	assert_bool(board.is_card_removed(3)).is_true()
	var events := board.pick_card(3)         # already gone
	assert_bool(events.is_empty()).is_true()


func test_tap_card_still_requires_exposure() -> void:
	# Regression: tap_card must NOT play a covered card (only pick_card may).
	var board := _layered_board()
	var events := board.tap_card(0)          # card 0 is covered
	assert_bool(events.is_empty()).is_true()
	assert_bool(board.is_card_removed(0)).is_false()


# ---------------------------------------------------------------------------
# reshuffle — preserves state, deterministic, routable guarantee
# ---------------------------------------------------------------------------

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_reshuffle_preserves_results_and_removed() -> void:
	# AC-R01/R02: results and the removed set are unchanged; only coverage changes.
	var board := _layered_board()
	board.pick_card(0)                        # remove one card (now in a stack)
	var results_before: Array[int] = []
	for i in 6:
		results_before.append(board.result_of(i))

	board.reshuffle(_layered_placements(), _rng(123))

	for i in 6:
		assert_int(board.result_of(i)).is_equal(results_before[i])   # results intact
	assert_bool(board.is_card_removed(0)).is_true()                  # stays removed
	assert_int(board.floor_count()).is_equal(5)                      # 6 - 1


func test_reshuffle_is_deterministic_for_a_seed() -> void:
	# AC-R04: same seed → identical layout (reproducible run-to-run).
	var a := _layered_board()
	var b := _layered_board()
	var assign_a := a.reshuffle(_layered_placements(), _rng(777))
	var assign_b := b.reshuffle(_layered_placements(), _rng(777))
	assert_array(assign_a).is_equal(assign_b)


func test_reshuffle_differs_across_seeds() -> void:
	# AC-R04/R08: different seeds → different slot-assignment arrays.
	var a := _layered_board()
	var b := _layered_board()
	var assign_a := a.reshuffle(_layered_placements(), _rng(1))
	var assign_b := b.reshuffle(_layered_placements(), _rng(2))
	assert_array(assign_a).is_not_equal(assign_b)


func test_reshuffle_guarantees_a_routable_move() -> void:
	# AC-R09: after reshuffle at least one exposed card routes directly or opens
	# coverage (removing it would expose another card) — never immediately stuck.
	var board := _layered_board()
	board.reshuffle(_layered_placements(), _rng(42))
	var routable := false
	for cid in board.exposed_cards():
		if board.newly_exposed_count(cid) > 0:
			routable = true
			break
		for s in BoardModel.STACK_COUNT:
			if board.stack_target(s) == board.result_of(cid) \
					and board.stack_count(s) < BoardModel.STACK_CAPACITY:
				routable = true
				break
	assert_bool(routable).is_true()
