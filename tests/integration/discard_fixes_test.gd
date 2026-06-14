extends GdUnitTestSuite
## Integration tests for the discard-buff + discard-row fixes (2026-06-14), driving
## the REAL Main scene (full node tree + autoloads):
##   1. Extra Discard works when the row is full (5/5) — adds a 6th slot (rescue).
##   2. Growing the row re-homes the cards already in it to their re-centred slots
##      (they must not sit between slots).
##   3. Unlocking a deck auto-assigns matching discarded cards onto it (pull-back),
##      and the card view actually moves from the discard to the stack.
##
## Source: design/gdd/deck-economy.md (Extra Discard, EC-07), ADR-0010 (2026-06-14
## update: discard-full no longer blocks the booster); ADR-0001 (model/view seam).

const MAIN := "res://scenes/main/main.tscn"
const COINS := EconomyEnums.Currency.COINS
const EXTRA_DISCARD := EconomyEnums.BoosterType.EXTRA_DISCARD


func _boot() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


# All-discard board: 12 cards all result 99, no stack ever targets 99 — every tap
# discards. Deterministic, independent of the real level content.
func _all_discard_config() -> LevelConfig:
	var cfg := LevelConfig.new()
	cfg.level_id = 1
	cfg.layout_id = 0
	cfg.target_queue = [1, 2, 3, 4] as Array[int]
	var placements := Layouts.get_layout(0)
	var pool: Array[CardData] = []
	for slot in 12:
		pool.append(CardData.create(90, 9, int(placements[slot].layer), slot))  # 90+9 = 99
	cfg.card_pool = pool
	return cfg


# Taps exposed cards until [param n] cards sit in the discard, waiting for each
# fly animation to settle. Returns once the row holds n cards (or the board ends).
func _discard_until(runner: Variant, main: Variant, n: int) -> void:
	var guard := 0
	while main._model.occupied_discard_count() < n and not main._model.is_game_over() and guard < 20:
		var exposed: Array[int] = main._model.exposed_cards()
		if exposed.is_empty():
			break
		main._on_card_tapped(exposed[0])
		var wait := 0
		while main.is_input_locked() and wait < 80:
			wait += 1
			await runner.simulate_frames(2, 32)
		guard += 1


func test_extra_discard_works_when_row_is_full() -> void:
	var runner = await _boot()
	var main = runner.scene()
	main.load_level_config(_all_discard_config(), BoardModel.STACK_COUNT)
	await runner.simulate_frames(5)
	WalletService.grant_booster(EXTRA_DISCARD, 1)
	var stock: int = WalletService.booster_count(EXTRA_DISCARD)   # autoload is shared across tests

	await _discard_until(runner, main, BoardModel.DISCARD_SLOTS)   # fill 5/5
	assert_int(main._model.occupied_discard_count()).is_equal(5)
	assert_int(main._model.active_discard_slots()).is_equal(5)

	# Press the booster at 5/5 — it must now respond and add a slot (the bug fix).
	main.extra_discard_from_stock()
	await runner.simulate_frames(20)

	assert_int(main._model.active_discard_slots()).is_equal(6)    # model grew
	assert_int(main._discard.slot_count()).is_equal(6)            # view grew
	assert_int(WalletService.booster_count(EXTRA_DISCARD)).is_equal(stock - 1)  # one consumed


func test_growing_the_row_repositions_existing_discard_cards() -> void:
	var runner = await _boot()
	var main = runner.scene()
	main.load_level_config(_all_discard_config(), BoardModel.STACK_COUNT)
	await runner.simulate_frames(5)
	WalletService.grant_booster(EXTRA_DISCARD, 1)

	await _discard_until(runner, main, 3)                         # 3 cards in the row
	main.extra_discard_from_stock()                              # 5 → 6 (row re-centres)
	await runner.simulate_frames(60)                            # let the re-home slide finish

	# Every occupied discard card sits on its (re-centred) slot, not between slots.
	# Without the fix the cards stay ~26px off (the recentre delta); 4px tolerance
	# cleanly distinguishes "re-homed" from "stranded between slots".
	for slot in main._discard_cards.size():
		var card_id: int = main._discard_cards[slot]
		if card_id == -1:
			continue
		var card = main._floor.get_card(card_id)
		assert_object(card).is_not_null()
		var want: Vector2 = main._discard.slot_global_position(slot)
		assert_vector(card.global_position).is_equal_approx(want, Vector2(4.0, 4.0))


# Board with one open stack (target 5) and locked decks; six 5s + six 9s. A tapped
# 9 discards (no open 9-stack) until deck 1 is unlocked and draws 9.
func _locked_deck_config() -> LevelConfig:
	var cfg := LevelConfig.new()
	cfg.level_id = 1
	cfg.layout_id = 0
	cfg.target_queue = [5, 9, 5, 9] as Array[int]   # 5×2, 9×2 → 6 cards each (solvable)
	var placements := Layouts.get_layout(0)
	var pool: Array[CardData] = []
	for slot in 12:
		var result: int = 5 if slot % 2 == 0 else 9
		var a: int = 2 if result == 5 else 4
		var b: int = result - a
		pool.append(CardData.create(a, b, int(placements[slot].layer), slot))
	cfg.card_pool = pool
	return cfg


func test_unlocking_a_deck_pulls_matching_discarded_cards_onto_it() -> void:
	var runner = await _boot()
	var main = runner.scene()
	WalletService.earn(COINS, 2000, EconomyEnums.EarnSource.LEVEL_WIN)
	main.load_level_config(_locked_deck_config(), 1)             # only stack 0 (target 5) open
	await runner.simulate_frames(5)
	var model = main._model

	# Discard an exposed 9 (no open 9-stack yet, so it can't route).
	var nine := -1
	for cid in model.exposed_cards():
		if model.result_of(cid) == 9:
			nine = cid
			break
	assert_int(nine).is_not_equal(-1)
	main._on_card_tapped(nine)
	var wait := 0
	while main.is_input_locked() and wait < 80:
		wait += 1
		await runner.simulate_frames(2, 32)
	# The 9 is now sitting in the discard.
	assert_bool(main._discard_cards.has(nine)).is_true()

	# Unlock deck 1 via the real prompt (free watch-ad path): it draws target 9 and
	# must pull the discarded 9 back out onto the stack.
	main._on_unlock_requested(1)
	await runner.simulate_frames(2)
	assert_object(main._unlock_popup).is_not_null()
	main._unlock_popup.watch_ad_pressed.emit()
	wait = 0
	while main.is_input_locked() and wait < 80:
		wait += 1
		await runner.simulate_frames(2, 32)
	await runner.simulate_frames(10)

	# The discarded 9 was pulled out of the discard (view slot freed) and onto deck 1.
	assert_bool(main._discard_cards.has(nine)).is_false()
	assert_int(model.stack_count(1)).is_greater(0)              # it landed on the unlocked deck
