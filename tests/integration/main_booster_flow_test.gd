extends GdUnitTestSuite
## Integration tests — drive the REAL Main scene (full node tree + autoloads), not
## pure core classes. Uses gdUnit4's scene_runner to instantiate scenes/main/main.tscn,
## advance frames, and assert the model↔view wiring behaves end-to-end:
## board build, a tap routing/discarding, and the three boosters (Picker, Reshuffle,
## Extra Discard Slot) via the WalletService autoload.
##
## Still headless/CI-safe (no display): cards, tweens, and signals run in the live tree.
## Source: design/gdd/deck-economy.md (boosters); ADR-0001 (model/view seam).

const MAIN := "res://scenes/main/main.tscn"
const COINS := EconomyEnums.Currency.COINS
const LEVEL_WIN := EconomyEnums.EarnSource.LEVEL_WIN


# Loads Main, suppresses the tutorial coach, funds the wallet, and settles a few frames.
func _boot() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	WalletService.earn(COINS, 2000, LEVEL_WIN)   # enough for any booster
	return runner


func _first_covered_card(main: Variant) -> int:
	var model = main._model
	for i in main._config.card_pool.size():
		if not model.is_card_removed(i) and not model.is_exposed(i):
			return i
	return -1


func test_scene_builds_board_and_discard_row() -> void:
	var runner = await _boot()
	var main = runner.scene()
	assert_object(main).is_not_null()
	assert_object(main._model).is_not_null()
	# DiscardRow renders the model's base capacity (5 slots).
	assert_int(main._discard.slot_count()).is_equal(BoardModel.DISCARD_SLOTS)
	# FloorArea spawned one card node per card in the level.
	assert_int(main._floor._cards.size()).is_equal(main._config.card_pool.size())


func test_tapping_an_exposed_card_resolves_it() -> void:
	var runner = await _boot()
	var main = runner.scene()
	var model = main._model
	var exposed: Array[int] = model.exposed_cards()
	assert_bool(exposed.is_empty()).is_false()
	var cid: int = exposed[0]
	main._on_card_tapped(cid)
	await runner.simulate_frames(30)             # let the fly animation finish
	assert_bool(model.is_card_removed(cid)).is_true()


func test_picker_plays_a_covered_card_in_scene() -> void:
	var runner = await _boot()
	var main = runner.scene()
	var model = main._model
	var cid: int = _first_covered_card(main)
	assert_int(cid).is_not_equal(-1)             # the pile has a covered card
	assert_bool(model.is_exposed(cid)).is_false()
	var coins_before: int = WalletService.balance(COINS)

	main.pick(cid)                                # plays it through WalletService.use_picker
	await runner.simulate_frames(30)

	assert_bool(model.is_card_removed(cid)).is_true()                 # covered card played
	assert_int(WalletService.balance(COINS)).is_equal(coins_before - 120)  # picker cost


func test_reshuffle_repermutes_the_floor_in_scene() -> void:
	var runner = await _boot()
	var main = runner.scene()
	var model = main._model
	var floor_before: int = model.floor_count()
	var coins_before: int = WalletService.balance(COINS)

	main.reshuffle_now()
	await runner.simulate_frames(30)

	assert_int(WalletService.reshuffle_count).is_greater(0)           # booster fired
	assert_int(WalletService.balance(COINS)).is_equal(coins_before - 250)  # reshuffle cost
	assert_int(model.floor_count()).is_equal(floor_before)            # card set preserved
	# Routable guarantee (AC-R09): at least one exposed card routes or opens coverage.
	var routable := false
	for c in model.exposed_cards():
		if model.newly_exposed_count(c) > 0:
			routable = true
			break
	assert_bool(routable).is_true()


func test_extra_discard_grows_the_discard_row_in_scene() -> void:
	var runner = await _boot()
	var main = runner.scene()
	main.expand_discard()
	await runner.simulate_frames(5)
	# Model and view both reflect the extra slot.
	assert_int(main._model.active_discard_slots()).is_equal(6)
	assert_int(main._discard.slot_count()).is_equal(6)


# --- terminal states (WIN / LOSE) ------------------------------------------

# An exposed card that will NOT route to any open stack (so a tap discards it).
func _exposed_discardable(main: Variant) -> int:
	var model = main._model
	for cid in model.exposed_cards():
		var r: int = model.result_of(cid)
		var routes := false
		for s in BoardModel.STACK_COUNT:
			if not model.is_stack_locked(s) and model.stack_target(s) == r \
					and model.stack_count(s) < BoardModel.STACK_CAPACITY:
				routes = true
				break
		if not routes:
			return cid
	return -1


func test_losing_in_scene_shows_result_and_does_not_advance() -> void:
	# Real play: keep discarding non-routing cards until the discard row overflows
	# (LOSE). Assert the controller surfaces the result screen and progression does
	# NOT advance (a loss leaves GameManager.current_level unchanged).
	var runner = await _boot()
	var main = runner.scene()
	var model = main._model
	var level_before: int = GameManager.current_level

	var guard := 0
	while not model.is_game_over() and guard < 40:
		var cid: int = _exposed_discardable(main)
		if cid == -1:
			break
		main._on_card_tapped(cid)
		var wait := 0
		while main.is_input_locked() and not model.is_game_over() and wait < 25:
			wait += 1
			await runner.simulate_frames(3)
		guard += 1
	await runner.simulate_frames(10)

	assert_bool(model.is_lost()).is_true()
	assert_object(main._result_screen).is_not_null()
	assert_int(GameManager.current_level).is_equal(level_before)   # loss does not advance


func test_winning_in_scene_shows_result_and_advances() -> void:
	# A full real-level win is layout/economy dependent, so we drive the controller's
	# terminal WIN handling directly with a WIN GameEvent (the same event BoardModel
	# emits when the floor empties). Asserts the controller shows the result screen
	# and advances progression via GameManager.complete_level.
	var runner = await _boot()
	var main = runner.scene()
	var level_before: int = GameManager.current_level

	await main._play_event(GameEvent.win())
	await runner.simulate_frames(10)

	assert_object(main._result_screen).is_not_null()
	assert_int(GameManager.current_level).is_equal(level_before + 1)   # win advances
