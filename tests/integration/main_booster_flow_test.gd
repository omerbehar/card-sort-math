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

# A guaranteed-losable level: 12 cards all result 9, stacks open on 1/2/3/4 — so
# nothing ever routes; every tap discards. After the 5 base slots fill, the next
# tap overflows the discard → LOSE. Deterministic, independent of the real level.
func _losable_config() -> LevelConfig:
	var cfg := LevelConfig.new()
	cfg.level_id = 1
	cfg.layout_id = 0
	cfg.target_queue = [1, 2, 3, 4] as Array[int]   # no stack ever targets 9
	var placements := Layouts.get_layout(0)
	var pool: Array[CardData] = []
	for slot in 12:
		pool.append(CardData.create(4, 5, int(placements[slot].layer), slot))  # 4+5 = 9
	cfg.card_pool = pool
	return cfg


func test_losing_real_play_in_scene_shows_result_and_does_not_advance() -> void:
	# Real play to a LOSE: load the controlled losable level, tap exposed cards
	# (all discard) until the discard overflows, then assert the result screen shows
	# and progression does NOT advance (a loss leaves current_level unchanged).
	var runner = await _boot()
	var main = runner.scene()
	main.load_level_config(_losable_config(), BoardModel.STACK_COUNT)
	await runner.simulate_frames(5)
	var model = main._model
	var level_before: int = GameManager.current_level

	var guard := 0
	while not model.is_game_over() and guard < 20:
		var exposed: Array[int] = model.exposed_cards()
		if exposed.is_empty():
			break
		main._on_card_tapped(exposed[0])
		var wait := 0
		while main.is_input_locked() and not model.is_game_over() and wait < 80:
			wait += 1
			await runner.simulate_frames(2, 32)
		guard += 1
	# The terminal tap's event chain (route/clear → WIN, or → LOSE) finishes on its
	# own coroutine; wait for the controller to surface the result screen.
	var settle := 0
	while not is_instance_valid(main._result_screen) and settle < 150:
		settle += 1
		await runner.simulate_frames(2, 32)

	assert_bool(model.is_lost()).is_true()
	assert_object(main._result_screen).is_not_null()
	assert_int(GameManager.current_level).is_equal(level_before)   # loss does not advance


# A trivially-winnable level: 12 cards all result 5, with exactly four 5s in the
# queue (solvability: 12 == 3×4). With all four stacks open on 5, every card routes
# — a guaranteed win by tapping whatever is exposed, no RNG, no discards.
func _winnable_config() -> LevelConfig:
	var cfg := LevelConfig.new()
	cfg.level_id = 1
	cfg.layout_id = 0                       # 12 placements (Layouts.SLOT_COUNTS[0])
	cfg.target_queue = [5, 5, 5, 5] as Array[int]
	var placements := Layouts.get_layout(0)
	var pool: Array[CardData] = []
	for slot in 12:
		pool.append(CardData.create(2, 3, int(placements[slot].layer), slot))  # 2+3 = 5
	cfg.card_pool = pool
	return cfg


func test_winning_real_play_in_scene_advances() -> void:
	# Real play to a WIN: load the controlled winnable level (all 4 stacks open),
	# tap exposed cards until the floor empties, then assert the result screen shows
	# and progression advances (GameManager.complete_level).
	var runner = await _boot()
	var main = runner.scene()
	main.load_level_config(_winnable_config(), BoardModel.STACK_COUNT)
	await runner.simulate_frames(5)
	var model = main._model
	var level_before: int = GameManager.current_level

	var guard := 0
	while not model.is_game_over() and guard < 60:
		var exposed: Array[int] = model.exposed_cards()
		if exposed.is_empty():
			break
		main._on_card_tapped(exposed[0])
		var wait := 0
		while main.is_input_locked() and not model.is_game_over() and wait < 80:
			wait += 1
			await runner.simulate_frames(2, 32)
		guard += 1
	# The terminal tap's event chain (route/clear → WIN, or → LOSE) finishes on its
	# own coroutine; wait for the controller to surface the result screen.
	var settle := 0
	while not is_instance_valid(main._result_screen) and settle < 150:
		settle += 1
		await runner.simulate_frames(2, 32)

	assert_bool(model.is_won()).is_true()
	assert_object(main._result_screen).is_not_null()
	assert_int(GameManager.current_level).is_equal(level_before + 1)   # win advances


func test_adding_a_deck_unlocks_a_stack_in_scene() -> void:
	# The prototype opens one stack; the rest are locked "decks" added in-game.
	# Tapping a locked deck opens the two-option UnlockPopup (watch ad / pay coins);
	# choosing the (stubbed, free) ad path adds it: the stack unlocks and draws its
	# target from the queue.
	var runner = await _boot()
	var main = runner.scene()
	var model = main._model
	var locked := -1
	for s in BoardModel.STACK_COUNT:
		if model.is_stack_locked(s):
			locked = s
			break
	assert_int(locked).is_not_equal(-1)             # there is a locked deck to add

	# The request shows the prompt rather than unlocking silently.
	main._on_unlock_requested(locked)
	await runner.simulate_frames(2)
	assert_object(main._unlock_popup).is_not_null()  # two-option prompt is shown
	assert_bool(model.is_stack_locked(locked)).is_true()  # not unlocked until a choice

	# Choose the free "watch ad" unlock path.
	main._unlock_popup.watch_ad_pressed.emit()
	var wait := 0
	while main.is_input_locked() and wait < 30:
		wait += 1
		await runner.simulate_frames(3)
	await runner.simulate_frames(5)

	assert_bool(model.is_stack_locked(locked)).is_false()                 # deck added
	assert_int(model.stack_target(locked)).is_not_equal(BoardModel.NO_TARGET)  # drew a target


func test_paying_coins_unlocks_a_deck_and_deducts_the_cost() -> void:
	# The coin path of the UnlockPopup spends real coins through WalletService:
	# choosing "pay" unlocks the deck and deducts UNLOCK_COST from the balance.
	var runner = await _boot()                       # funds the wallet with 2000 coins
	var main = runner.scene()
	var model = main._model
	var locked := -1
	for s in BoardModel.STACK_COUNT:
		if model.is_stack_locked(s):
			locked = s
			break
	assert_int(locked).is_not_equal(-1)
	var before: int = WalletService.balance(COINS)

	main._on_unlock_requested(locked)
	await runner.simulate_frames(2)
	assert_object(main._unlock_popup).is_not_null()
	main._unlock_popup.pay_coins_pressed.emit()      # choose the coin path
	var wait := 0
	while main.is_input_locked() and wait < 30:
		wait += 1
		await runner.simulate_frames(3)
	await runner.simulate_frames(5)

	assert_bool(model.is_stack_locked(locked)).is_false()             # deck added
	assert_int(WalletService.balance(COINS)).is_equal(before - main.UNLOCK_COST)  # coins spent


# --- buff inventory (count → free use; zero → watch-ad / pay-coins popup) ---

const EXTRA_DISCARD := EconomyEnums.BoosterType.EXTRA_DISCARD
const RESHUFFLE := EconomyEnums.BoosterType.RESHUFFLE


# Forces a booster's owned count to exactly [param n] on the live WalletService.
func _set_stock(type: int, n: int) -> void:
	while WalletService.booster_count(type) > n:
		WalletService.consume_booster(type)
	if WalletService.booster_count(type) < n:
		WalletService.grant_booster(type, n - WalletService.booster_count(type))


func test_buff_with_stock_is_used_for_free() -> void:
	var runner = await _boot()
	var main = runner.scene()
	_set_stock(EXTRA_DISCARD, 2)
	var coins_before: int = WalletService.balance(COINS)

	main._on_booster_pressed(EXTRA_DISCARD)          # count > 0 → consume one, no popup
	await runner.simulate_frames(5)

	assert_object(main._buff_popup).is_null()                         # no popup shown
	assert_int(WalletService.booster_count(EXTRA_DISCARD)).is_equal(1)  # one consumed
	assert_int(WalletService.balance(COINS)).is_equal(coins_before)   # free (no coin spend)
	assert_int(main._model.active_discard_slots()).is_equal(6)        # buff took effect


func test_buff_at_zero_opens_popup_and_watch_ad_uses_it() -> void:
	var runner = await _boot()
	var main = runner.scene()
	_set_stock(RESHUFFLE, 0)

	main._on_booster_pressed(RESHUFFLE)              # count == 0 → popup, no reshuffle yet
	await runner.simulate_frames(2)
	assert_object(main._buff_popup).is_not_null()
	assert_int(WalletService.reshuffle_count).is_equal(0)

	main._buff_popup.watch_ad_pressed.emit()         # free stub: grant + use immediately
	await runner.simulate_frames(20)
	assert_int(WalletService.reshuffle_count).is_greater(0)           # reshuffle fired


func test_buff_at_zero_pay_coins_uses_it_and_deducts() -> void:
	var runner = await _boot()
	var main = runner.scene()
	_set_stock(EXTRA_DISCARD, 0)
	var coins_before: int = WalletService.balance(COINS)

	main._on_booster_pressed(EXTRA_DISCARD)          # count == 0 → popup
	await runner.simulate_frames(2)
	assert_object(main._buff_popup).is_not_null()

	main._buff_popup.pay_coins_pressed.emit()        # coin path: spend + use immediately
	await runner.simulate_frames(10)
	assert_int(main._model.active_discard_slots()).is_equal(6)        # buff took effect
	assert_int(WalletService.balance(COINS)) \
		.is_equal(coins_before - WalletService.booster_coin_cost(EXTRA_DISCARD))


# --- debug "Reset Inventory" button (Settings, debug builds only) -----------

const PICKER := EconomyEnums.BoosterType.PICKER


func test_debug_reset_button_resets_coins_and_every_buff_via_pause_menu() -> void:
	# End-to-end: from an off-target inventory, pressing the real Settings debug
	# button restocks every buff to 3 and coins to 1000, and refreshes the coin HUD.
	var runner = await _boot()
	var main = runner.scene()
	# Arrange: drive the inventory away from the reset target so the change is observable.
	_set_stock(PICKER, 0)
	_set_stock(RESHUFFLE, 5)
	_set_stock(EXTRA_DISCARD, 1)

	# Open the pause menu and grab the debug button (built only in debug builds).
	main._open_pause()
	await runner.simulate_frames(2)
	assert_object(main._pause_menu).is_not_null()
	var btn: Button = main._pause_menu._buttons.get("debug_reset")
	assert_object(btn).is_not_null()

	# Act: press the real button → debug_reset_pressed → main._on_debug_reset.
	btn.pressed.emit()
	await runner.simulate_frames(2)

	# Assert: coins and every buff reset to the debug constants…
	assert_int(WalletService.balance(COINS)).is_equal(main.DEBUG_RESET_COINS)
	assert_int(WalletService.booster_count(PICKER)).is_equal(main.DEBUG_RESET_BOOSTERS)
	assert_int(WalletService.booster_count(RESHUFFLE)).is_equal(main.DEBUG_RESET_BOOSTERS)
	assert_int(WalletService.booster_count(EXTRA_DISCARD)).is_equal(main.DEBUG_RESET_BOOSTERS)
	# …and the coin HUD label reflects the new balance.
	assert_str(main._coins_label.text).is_equal("🪙 %d" % main.DEBUG_RESET_COINS)

	main._close_pause()                              # restore the tree's paused flag


func test_debug_reset_button_is_gated_to_debug_builds() -> void:
	# The button is built only when OS.is_debug_build(); tests run as a debug build, so
	# it must exist here. Locks the gating contract (no debug control in release).
	var runner = await _boot()
	var main = runner.scene()
	main._open_pause()
	await runner.simulate_frames(2)
	assert_bool(main._pause_menu._buttons.has("debug_reset")).is_equal(OS.is_debug_build())
	main._close_pause()
