extends Node2D
## Board controller: builds the [BoardModel] for the current level, wires the
## view nodes, and replays the model's [GameEvent] list as animations — locking
## input until the whole (possibly cascading) sequence finishes.

const CARD_FLY: float = 0.28
# Screenshot layout (390x844 portrait): stacks under the header, discard below
# them, the floor pile in the central play area, tool bar at the bottom.
const STACK_XS: Array[float] = [14.0, 108.0, 202.0, 296.0]
const STACK_Y: float = 112.0
const DISCARD_ORIGIN: Vector2 = Vector2(195, 240)  # screen-centre x; DiscardRow self-centres its slots
const FLOOR_ORIGIN: Vector2 = Layouts.FLOOR_ORIGIN
const DISCARD_WARN_FREE_SLOTS: int = 1   # tint red when this many (or fewer) slots remain free
# Offset from a stack's origin to its centre, where the clear burst spawns.
const STACK_BURST_OFFSET: Vector2 = Vector2(36.0, 24.0)

# --- prototype: locked-decks ---
# Stacks that start OPEN; the rest are locked "decks" the player adds in-game.
# Tapping a locked deck opens the two-option UnlockPopup: watch a (stubbed) ad,
# or pay coins. The ad path is a prototype stub (free unlock; ad SDK deferred to
# M4); the coin path spends real coins through WalletService.
const PROTO_OPEN_COUNT: int = 1
const UNLOCK_COST: int = 100          # coin price of adding a locked deck
var _coins_label: Label = null
# The active unlock prompt; null when none is shown (only one at a time).
var _unlock_popup: UnlockPopup = null

var _model: BoardModel
var _config: LevelConfig

var _floor: FloorArea
var _stacks: Array[Stack] = []
var _discard: DiscardRow
var _hud: Hud
var _hud_layer: CanvasLayer
var _pause_menu: PauseMenu

## Tutorial overlay; null when not active (seen or not Level 1).
var _coach: CoachOverlay = null
## Mutable session counter for the tutorial coach; reset on each start_level(1).
var _tutorial_state: TutorialState = null
## Win/lose result screen; null when not shown (S1-020).
var _result_screen: ResultScreen = null

# Visual bookkeeping kept in lockstep with the model by replaying events in order.
var _stack_cards: Array = []    # per stack: Array of card_ids currently shown
var _discard_cards: Array = []  # per slot: card_id, or -1 when empty
var _input_locked: bool = false
# Picker booster (S3-012): when armed, the next tapped card (covered or not) is
# played as a Picker. _picker_use_stock chooses the payment path for that play:
# true → consume an owned Picker (free); false → spend coins (the popup "pay" path).
var _picker_armed: bool = false
var _picker_use_stock: bool = true
# Active buff-restock popup (out-of-stock top-up); null when none is shown.
var _buff_popup: UnlockPopup = null

@onready var _overlay_layer: CanvasLayer = $Overlay


func _ready() -> void:
	_build_board()
	AudioService.refresh_music()
	start_level(GameManager.current_level)


func _build_board() -> void:
	_floor = FloorArea.new()
	_floor.name = "FloorArea"
	_floor.position = FLOOR_ORIGIN
	add_child(_floor)
	_floor.card_tapped.connect(_on_card_tapped)

	var colorblind: bool = SettingsService.get_value("colorblind")
	for i in BoardModel.STACK_COUNT:
		var stack := Stack.new()
		stack.position = Vector2(STACK_XS[i], STACK_Y)
		add_child(stack)
		stack.setup(i, -1, colorblind)
		stack.unlock_requested.connect(_on_unlock_requested)
		_stacks.append(stack)
		_stack_cards.append([])

	_discard = DiscardRow.new()
	_discard.position = DISCARD_ORIGIN
	add_child(_discard)
	for _i in BoardModel.DISCARD_SLOTS:
		_discard_cards.append(-1)

	# Cosmetic chrome (header + tool bar + zoom slider) on its own layer.
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 1
	add_child(_hud_layer)
	_hud = Hud.new()
	_hud_layer.add_child(_hud)
	_hud.settings_pressed.connect(_open_pause)
	_hud.booster_pressed.connect(_on_booster_pressed)
	# Coin balance shown top-right, read from the real WalletService and kept in
	# sync with earns/spends via its economy_event signal.
	_coins_label = UiFactory.label(_hud_layer, "", Vector2(250, 12), Vector2(130, 28), 20, Color(1, 0.93, 0.5))
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var wallet := get_node_or_null("/root/WalletService")
	if wallet != null and wallet.has_signal("economy_event"):
		wallet.economy_event.connect(func(_e: Variant) -> void: _update_coins_hud())
	_update_coins_hud()
	# Live-recolour the stacks when the colorblind palette is toggled in-game.
	SettingsService.changed.connect(_on_setting_changed)


## (Re)starts level [param n]: rebuilds the model and floor, resets the view.
func start_level(n: int) -> void:
	GameManager.start_level(n)
	_setup_board(LevelData.get_level(n), PROTO_OPEN_COUNT)
	_arm_tutorial(n)


## Test/tool seam: rebuilds the board from an explicit [param config] (bypassing
## [LevelData]) with [param open_count] stacks open. Used by integration tests to
## load a controlled, winnable level. Does not re-fire [method GameManager.start_level]
## or the tutorial.
func load_level_config(config: LevelConfig, open_count: int = PROTO_OPEN_COUNT) -> void:
	_setup_board(config, open_count)


# Builds the model + view for [param config]. Shared by start_level (real levels)
# and load_level_config (test/tool configs).
func _setup_board(config: LevelConfig, open_count: int) -> void:
	_config = config
	_model = BoardModel.from_config(config, open_count)

	for cards in _stack_cards:
		cards.clear()
	_discard.set_slot_count(BoardModel.DISCARD_SLOTS)
	_discard_cards.clear()
	for _i in BoardModel.DISCARD_SLOTS:
		_discard_cards.append(-1)
	_input_locked = false
	_picker_armed = false

	_floor.spawn(_config)
	for i in _stacks.size():
		_stacks[i].set_target(_model.stack_target(i))
		# Prototype: show locked stacks as buyable "+" slots.
		_stacks[i].set_locked(_model.is_stack_locked(i), UNLOCK_COST)
	_discard.set_warning(false)
	_floor.refresh_exposure(_model)
	if _hud != null:
		_hud.refresh()


## Arms the first-time tutorial coach on level [param n] if the player has not
## seen it (S1-010). Picks one productive (or fallback) card at spawn, spawns the
## [CoachOverlay] on the HUD layer, and feeds it committed taps via
## [method _on_card_tapped]. On a fresh restart the prior coach is freed first
## (EC10); when no card is exposed the coach is not shown and the flag is left
## unset (R9 / AC_E0). See [code]design/gdd/first-time-tutorial.md[/code] §3.
func _arm_tutorial(n: int) -> void:
	# Free any prior coach so a rapid restart never double-overlays (EC10).
	if is_instance_valid(_coach):
		_coach.queue_free()
		_coach = null

	if not TutorialLogic.should_show(SaveService.data.tutorial_seen, n):
		return

	# Build the pure inputs for pick_target (no BoardModel reference leaks in).
	var exposed: Array[int] = _model.exposed_cards()
	var results: Dictionary = {}
	for c: int in exposed:
		results[c] = _model.result_of(c)
	var open_targets: Array[int] = []
	for i in BoardModel.STACK_COUNT:
		if _model.stack_count(i) < BoardModel.STACK_CAPACITY:
			var t: int = _model.stack_target(i)
			if t >= 0 and not open_targets.has(t):
				open_targets.append(t)

	var tid: int = TutorialLogic.pick_target(exposed, results, open_targets)
	if tid == -1:
		# E = ∅ (or no exposed card): do not spawn, do not set the flag (R9).
		return

	# Resolve and validate the target card BEFORE building the overlay, so the
	# defensive null path never spawns a one-frame overlay or leaves stale state.
	var card: Card = _floor.get_card(tid)
	if card == null:
		return

	var productive: bool = open_targets.has(results.get(tid, -1))
	# Reuse the session state across re-arms (reset the counter) rather than
	# allocating a fresh one each restart (EC10).
	if _tutorial_state == null:
		_tutorial_state = TutorialState.new()
	else:
		_tutorial_state.reset()
	_coach = CoachOverlay.new()
	_coach.name = "CoachOverlay"
	_coach.configure(_tutorial_state, SaveService.data, SaveService)
	_hud_layer.add_child(_coach)
	_coach.arm(card, productive)


## True while an event sequence is animating and taps are ignored. Exposed for
## tooling/integration drivers that need to wait for the board to go idle.
func is_input_locked() -> bool:
	return _input_locked


func _on_card_tapped(card_id: int) -> void:
	if is_instance_valid(_result_screen):
		return
	if _input_locked or _model.is_game_over():
		return
	# Picker booster (S3-012): the next tap plays the chosen card (covered or not),
	# then disarms. The armed payment path decides whether it consumes an owned
	# Picker (free) or spends coins.
	if _picker_armed:
		_picker_armed = false
		if _picker_use_stock:
			await pick_from_stock(card_id)
		else:
			await pick(card_id)
		return
	var events := _model.tap_card(card_id)
	if events.is_empty():
		return
	# Feed the committed tap to the tutorial coach (S1-010) before animating.
	if is_instance_valid(_coach):
		_coach.on_committed_tap(events)
	_input_locked = true
	await _play_events(events)
	# If that tap ended the board (WIN/LOSE shows the result screen), skip the
	# post-tap bookkeeping — it would run against a finished board.
	if is_instance_valid(_result_screen):
		return
	_floor.refresh_exposure(_model)
	_update_discard_warning()
	_input_locked = false


func _play_events(events: Array[GameEvent]) -> void:
	for event: GameEvent in events:
		await _play_event(event)


func _play_event(event: GameEvent) -> void:
	AudioService.play_event(event)
	match event.kind:
		GameEvent.Kind.ROUTE:
			await _into_stack(event.card_id, event.stack_index)
		GameEvent.Kind.DISCARD:
			await _into_discard(event.card_id, event.discard_slot)
		GameEvent.Kind.PULL:
			_discard_cards[event.discard_slot] = -1
			await _into_stack(event.card_id, event.stack_index)
		GameEvent.Kind.STACK_CLEARED:
			await _clear_stack(event.stack_index, event.new_target)
		GameEvent.Kind.UNLOCK:
			# Visual already swapped to the open slot in _on_unlock_requested;
			# just celebrate the open.
			JuiceService.haptic(15)
			JuiceService.punch(_stacks[event.stack_index])
		GameEvent.Kind.WIN:
			JuiceService.haptic(40)
			GameManager.complete_level()
			_show_result(ResultScreen.Mode.WIN)
		GameEvent.Kind.LOSE:
			JuiceService.haptic(60)
			GameManager.fail_level()
			_show_result(ResultScreen.Mode.LOSE)


func _into_stack(card_id: int, stack_index: int) -> void:
	var slot: int = _stack_cards[stack_index].size()
	_floor.lift(card_id, slot)
	_stack_cards[stack_index].append(card_id)
	_stacks[stack_index].set_filled(_stack_cards[stack_index].size())
	var card := _floor.get_card(card_id)
	if card != null:
		card.show_result()
		await card.fly_to(_stacks[stack_index].slot_global_position(slot), CARD_FLY)


func _into_discard(card_id: int, slot: int) -> void:
	_floor.lift(card_id)
	_discard_cards[slot] = card_id
	var card := _floor.get_card(card_id)
	if card != null:
		# Shrink the card to the (smaller) discard slot so it no longer overhangs
		# (S3-006). A later PULL flies it back at full scale via _into_stack.
		var slot_scale: float = DiscardRow.SLOT_W / Card.W
		await card.fly_to(_discard.slot_global_position(slot), CARD_FLY, slot_scale)


func _clear_stack(stack_index: int, new_target: int) -> void:
	var card_ids: Array = _stack_cards[stack_index]
	_stack_cards[stack_index] = []

	var tween := create_tween()
	tween.set_parallel(true)
	for card_id: int in card_ids:
		var card := _floor.get_card(card_id)
		if card != null:
			tween.tween_property(card, "scale", Vector2.ZERO, 0.18)
			tween.tween_property(card, "modulate:a", 0.0, 0.18)
	await tween.finished

	for card_id: int in card_ids:
		_floor.remove_card(card_id)
	_stacks[stack_index].set_target(new_target)

	# Juice: celebrate the clear (gated by reduced_motion / haptics settings).
	JuiceService.haptic(15)
	JuiceService.burst(self, _stacks[stack_index].position + STACK_BURST_OFFSET)
	JuiceService.punch(_stacks[stack_index])

	await _stacks[stack_index].play_clear()


# Prototype: locked-decks. A tapped locked stack opens the two-option UnlockPopup
# (watch ad / pay coins) instead of unlocking silently. The popup is view-only and
# emits intent; this controller runs the chosen unlock via _perform_unlock.
func _on_unlock_requested(stack_index: int) -> void:
	if _input_locked or is_instance_valid(_result_screen):
		return
	if is_instance_valid(_unlock_popup):
		return                                  # one prompt at a time
	if not _model.is_stack_locked(stack_index):
		return

	var wallet := get_node_or_null("/root/WalletService")
	var coins: int = wallet.balance(EconomyEnums.Currency.COINS) if wallet != null else 0

	var popup := UnlockPopup.new()
	popup.dismiss_on_backdrop = true            # tap-outside cancels (set before _ready)
	_unlock_popup = popup
	_overlay_layer.add_child(popup)
	popup.setup(UNLOCK_COST, coins >= UNLOCK_COST)
	popup.backdrop_pressed.connect(popup.close)
	popup.closed.connect(func() -> void: _unlock_popup = null)
	# Both choices dismiss the prompt, then run the matching unlock path.
	popup.watch_ad_pressed.connect(func() -> void:
		_dismiss_unlock_popup()
		_perform_unlock(stack_index, false))
	popup.pay_coins_pressed.connect(func() -> void:
		_dismiss_unlock_popup()
		_perform_unlock(stack_index, true))


func _dismiss_unlock_popup() -> void:
	if is_instance_valid(_unlock_popup):
		_unlock_popup.close()
	_unlock_popup = null


# Runs the chosen unlock for a locked deck. [param paid] true spends UNLOCK_COST
# coins atomically via WalletService (the deck is added only if the spend commits);
# false is the prototype "watch ad" stub — a free unlock until the ad SDK lands (M4).
# The board mutation + pulled-in-card animation are shared by both paths.
func _perform_unlock(stack_index: int, paid: bool) -> void:
	if _input_locked or is_instance_valid(_result_screen):
		return
	if not _model.is_stack_locked(stack_index):
		return

	var events: Array[GameEvent] = []
	if paid:
		# Atomic spend: the deck is unlocked inside on_committed so a rejected spend
		# (insufficient funds → SPEND_FAILED) leaves the board untouched (GDD Rule 4).
		var wallet := get_node_or_null("/root/WalletService")
		if wallet == null:
			return
		var ok: bool = wallet.spend(
			EconomyEnums.Currency.COINS, UNLOCK_COST,
			func() -> bool:
				events = _model.unlock_stack(stack_index)
				return true)
		if not ok:
			return                              # not enough coins; nothing changed
	else:
		events = _model.unlock_stack(stack_index)   # ad stub: free unlock

	# Swap the slot to its open look before animating the pulled-in cards.
	_stacks[stack_index].set_locked(false)
	_stacks[stack_index].set_target(_model.stack_target(stack_index))
	_update_coins_hud()

	_input_locked = true
	await _play_events(events)
	if is_instance_valid(_result_screen):
		return
	_floor.refresh_exposure(_model)
	_update_discard_warning()
	_input_locked = false


func _update_coins_hud() -> void:
	if _coins_label == null:
		return
	var wallet := get_node_or_null("/root/WalletService")
	var coins: int = wallet.balance(EconomyEnums.Currency.COINS) if wallet != null else 0
	_coins_label.text = "🪙 %d" % coins


func _update_discard_warning() -> void:
	var filled: int = 0
	for card_id: int in _discard_cards:
		if card_id != -1:
			filled += 1
	# Warn when only DISCARD_WARN_FREE_SLOTS (or fewer) empty slots remain. Scales
	# with the live capacity so the Extra Discard Slot booster pushes the warning
	# later (e.g. 4/5 at base, 6/7 once expanded) rather than firing at a fixed 4.
	var free_slots: int = _discard_cards.size() - filled
	_discard.set_warning(free_slots <= DISCARD_WARN_FREE_SLOTS)


## Grows the discard buffer by one slot — the Extra Discard Slot booster's
## model→view path (S3-006 / ADR-0010). Expands [BoardModel], mirrors the new
## capacity in the [DiscardRow] view, and extends the per-slot bookkeeping.
## NOTE: the booster *button* in the HUD is pending the economy-UI sprint; the
## eventual WalletService.use_extra_discard() success path drives this method.
func expand_discard() -> void:
	if _model == null:
		return
	_model.expand_discard()
	_discard.set_slot_count(_model.active_discard_slots())
	_discard_cards.append(-1)
	_update_discard_warning()


## Arms the Picker booster (S3-012): every surviving card becomes tappable so the
## player can choose a covered (lower-layer) card; the next tap plays it.
## [param use_stock] true consumes an owned Picker (free); false spends coins.
func arm_picker(use_stock: bool = true) -> void:
	if _model == null or _input_locked:
		return
	_picker_armed = true
	_picker_use_stock = use_stock
	_floor.set_pickable_all(_model)


## Plays [param card_id] through [method WalletService.use_picker] (covered or not),
## animating the returned board events. Spends picker_cost_coins; no-op if the
## wallet rejects it (insufficient funds / invalid target).
func pick(card_id: int) -> void:
	if _input_locked or _model.is_game_over():
		return
	var events: Array[GameEvent] = WalletService.use_picker(_model, card_id)
	await _resolve_pick(events)


## Picker played from owned stock (free), via [method WalletService.use_picker_from_stock].
## No-op if the wallet rejects it (invalid target / no Picker owned).
func pick_from_stock(card_id: int) -> void:
	if _input_locked or _model.is_game_over():
		return
	var events: Array[GameEvent] = WalletService.use_picker_from_stock(_model, card_id)
	await _resolve_pick(events)


# Shared post-pick view sync + animation for both Picker payment paths.
func _resolve_pick(events: Array[GameEvent]) -> void:
	_floor.refresh_exposure(_model)          # drop picker-mode tappability
	if events.is_empty():
		return
	_input_locked = true
	await _play_events(events)
	if is_instance_valid(_result_screen):
		return
	_floor.refresh_exposure(_model)
	_update_discard_warning()
	_input_locked = false


## Routes a booster-tray button press (Hud.booster_pressed). With an owned buff in
## stock the tap uses it for free; at zero stock it opens the watch-ad / pay-coins
## top-up popup (the buff parallel of the locked-deck unlock).
func _on_booster_pressed(booster_type: int) -> void:
	if _input_locked or _model == null or _model.is_game_over():
		return
	if is_instance_valid(_buff_popup):
		return
	if _wallet_booster_count(booster_type) > 0:
		_use_booster_from_stock(booster_type)
	else:
		_show_buff_popup(booster_type)


# Uses one owned buff (free): arms the Picker on stock, or fires the instant boosters.
func _use_booster_from_stock(booster_type: int) -> void:
	match booster_type:
		EconomyEnums.BoosterType.PICKER:
			arm_picker(true)
		EconomyEnums.BoosterType.RESHUFFLE:
			reshuffle_from_stock()
		EconomyEnums.BoosterType.EXTRA_DISCARD:
			extra_discard_from_stock()


# Owned count of [param booster_type] from the wallet; 0 if the autoload is absent.
func _wallet_booster_count(booster_type: int) -> int:
	var wallet := get_node_or_null("/root/WalletService")
	return wallet.booster_count(booster_type) if wallet != null else 0


## Opens the out-of-stock top-up popup for [param booster_type]: watch a (stubbed)
## ad or pay coins to get the buff and use it immediately. Reuses [UnlockPopup].
func _show_buff_popup(booster_type: int) -> void:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet == null:
		return
	var cost: int = wallet.booster_coin_cost(booster_type)
	var coins: int = wallet.balance(EconomyEnums.Currency.COINS)

	var popup := UnlockPopup.new()
	popup.dismiss_on_backdrop = true            # tap-outside cancels (set before _ready)
	_buff_popup = popup
	_overlay_layer.add_child(popup)
	# Prototype l10n: buff copy is built here (UnlockPopup._tr owns the deck strings).
	popup.setup(cost, coins >= cost,
		"OUT OF %s" % _buff_display_name(booster_type),
		"Watch an ad or pay coins to use it now.")
	popup.backdrop_pressed.connect(popup.close)
	popup.closed.connect(func() -> void: _buff_popup = null)
	popup.watch_ad_pressed.connect(func() -> void:
		_dismiss_buff_popup()
		_grant_and_use_buff(booster_type, false))
	popup.pay_coins_pressed.connect(func() -> void:
		_dismiss_buff_popup()
		_grant_and_use_buff(booster_type, true))


func _dismiss_buff_popup() -> void:
	if is_instance_valid(_buff_popup):
		_buff_popup.close()
	_buff_popup = null


# Resolves a buff top-up choice and uses the buff immediately. [param paid] true
# spends coins via the existing coin-path methods; false is the watch-ad stub —
# grant one free, then use it from stock.
func _grant_and_use_buff(booster_type: int, paid: bool) -> void:
	if _input_locked or _model == null or _model.is_game_over():
		return
	if paid:
		match booster_type:
			EconomyEnums.BoosterType.PICKER:
				arm_picker(false)               # coins spent at pick via use_picker
			EconomyEnums.BoosterType.RESHUFFLE:
				reshuffle_now()
			EconomyEnums.BoosterType.EXTRA_DISCARD:
				buy_extra_discard()
	else:
		var wallet := get_node_or_null("/root/WalletService")
		if wallet != null:
			wallet.grant_booster(booster_type, 1)
		_use_booster_from_stock(booster_type)


# Display name for the buff top-up popup title (prototype l10n).
func _buff_display_name(booster_type: int) -> String:
	match booster_type:
		EconomyEnums.BoosterType.PICKER: return "PICKER"
		EconomyEnums.BoosterType.RESHUFFLE: return "RESHUFFLE"
		EconomyEnums.BoosterType.EXTRA_DISCARD: return "EXTRA DISCARD"
		_: return "BOOSTER"


## Buys the Extra Discard Slot booster through the wallet (spends coins), then
## syncs the view. Distinct from [method expand_discard] (the no-spend path used by
## tooling/tests). No-op if the wallet rejects it (at max / discard full / broke).
func buy_extra_discard() -> void:
	if _model == null or _input_locked:
		return
	if WalletService.use_extra_discard(_model):
		_discard.set_slot_count(_model.active_discard_slots())
		_discard_cards.append(-1)
		_update_discard_warning()


## Extra Discard Slot from owned stock (free), via [method WalletService.use_extra_discard_from_stock].
## Syncs the view like [method buy_extra_discard]. No-op if rejected (at max / full / none owned).
func extra_discard_from_stock() -> void:
	if _model == null or _input_locked:
		return
	if WalletService.use_extra_discard_from_stock(_model):
		_discard.set_slot_count(_model.active_discard_slots())
		_discard_cards.append(-1)
		_update_discard_warning()


## Activates the Reshuffle booster (S3-009): re-permutes floor coverage via
## [method WalletService.use_reshuffle] and re-lays the cards to the new layout.
## No-op if the wallet rejects it (won board / insufficient funds).
func reshuffle_now() -> void:
	if _model == null or _input_locked:
		return
	var placements := Layouts.get_layout(_config.layout_id)
	var assignment: Array[int] = WalletService.use_reshuffle(_model, placements)
	_apply_reshuffle(assignment, placements)


## Reshuffle from owned stock (free), via [method WalletService.use_reshuffle_from_stock].
## Re-lays the floor like [method reshuffle_now]. No-op if rejected (won board / none owned).
func reshuffle_from_stock() -> void:
	if _model == null or _input_locked:
		return
	var placements := Layouts.get_layout(_config.layout_id)
	var assignment: Array[int] = WalletService.use_reshuffle_from_stock(_model, placements)
	_apply_reshuffle(assignment, placements)


# Shared re-lay of the floor to a new placement→card assignment (both Reshuffle paths).
func _apply_reshuffle(assignment: Array[int], placements: Array) -> void:
	if assignment.is_empty():
		return
	for p in assignment.size():
		var cid: int = assignment[p]
		if cid != -1:
			_floor.place_card_at(cid, placements[p].pos, placements[p].layer, 0.3)
	_floor.refresh_exposure(_model)


func _open_pause() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return
	get_tree().paused = true
	_pause_menu = PauseMenu.new()
	# Keep the menu live while the rest of the tree is paused.
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.resumed.connect(_close_pause)
	_pause_menu.home_pressed.connect(_on_home_pressed)
	_pause_menu.reset_tutorial_pressed.connect(_on_reset_tutorial)
	_hud_layer.add_child(_pause_menu)


func _close_pause() -> void:
	_pause_menu = null
	get_tree().paused = false


# Clears the first-time-tutorial flag from settings so the coach replays. Saved
# immediately; re-arms on the current level if eligible (the tutorial is gated to
# the early-game flow, so on a later level it simply replays next time it applies).
func _on_reset_tutorial() -> void:
	SaveService.data.tutorial_seen = false
	SaveService.save_game()
	_arm_tutorial(GameManager.current_level)


# No main-menu screen exists yet, so "home" restarts the current level. Rewire to
# scene navigation once a menu/world-map screen lands (M3).
func _on_home_pressed() -> void:
	_close_pause()
	start_level(GameManager.current_level)


# Recolours the live board when the colorblind palette setting changes.
func _on_setting_changed(key: String, value: bool) -> void:
	if key == "colorblind":
		for stack: Stack in _stacks:
			stack.apply_palette(value)


## Shows the win/lose result screen (S1-020). The screen owns no game state — it
## emits intent signals; this controller advances/retries via [method start_level].
func _show_result(result_mode: ResultScreen.Mode) -> void:
	if is_instance_valid(_result_screen):
		_result_screen.queue_free()
	_result_screen = ResultScreen.new()
	_result_screen.name = "ResultScreen"
	_result_screen.retry_pressed.connect(_dismiss_result)
	_result_screen.next_pressed.connect(_dismiss_result)
	_result_screen.home_pressed.connect(_dismiss_result)
	_overlay_layer.add_child(_result_screen)   # _ready adds the dim underneath
	_result_screen.setup(result_mode)           # content is built above the dim


func _dismiss_result() -> void:
	if is_instance_valid(_result_screen):
		# Animated self-dismiss (PopupBase.close); its backdrop keeps blocking board
		# input while it fades out over the freshly rebuilt board.
		_result_screen.close()
		_result_screen = null
	# WIN already advanced GameManager.current_level (complete_level); LOSE left it.
	# So this both advances on a win and retries on a loss.
	start_level(GameManager.current_level)
