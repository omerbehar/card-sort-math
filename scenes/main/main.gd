extends Node2D
## Board controller: builds the [BoardModel] for the current level, wires the
## view nodes, and replays the model's [GameEvent] list as animations — locking
## input until the whole (possibly cascading) sequence finishes.

const CARD_FLY: float = 0.28
# Screenshot layout (390x844 portrait): stacks under the header, discard below
# them, the floor pile in the central play area, tool bar at the bottom.
const STACK_XS: Array[float] = [14.0, 108.0, 202.0, 296.0]
const STACK_Y: float = 112.0
const DISCARD_ORIGIN: Vector2 = Vector2(7, 250)
const FLOOR_ORIGIN: Vector2 = Layouts.FLOOR_ORIGIN
const DISCARD_WARN_AT: int = 4
# Offset from a stack's origin to its centre, where the clear burst spawns.
const STACK_BURST_OFFSET: Vector2 = Vector2(36.0, 24.0)

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

# Visual bookkeeping kept in lockstep with the model by replaying events in order.
var _stack_cards: Array = []    # per stack: Array of card_ids currently shown
var _discard_cards: Array = []  # per slot: card_id, or -1 when empty
var _input_locked: bool = false

@onready var _overlay: Control = $Overlay/Root
@onready var _overlay_label: Label = $Overlay/Root/Label


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
	# Live-recolour the stacks when the colorblind palette is toggled in-game.
	SettingsService.changed.connect(_on_setting_changed)


## (Re)starts level [param n]: rebuilds the model and floor, resets the view.
func start_level(n: int) -> void:
	_config = LevelData.get_level(n)
	_model = BoardModel.from_config(_config)
	GameManager.start_level(n)

	for cards in _stack_cards:
		cards.clear()
	for i in _discard_cards.size():
		_discard_cards[i] = -1
	_overlay.visible = false
	_input_locked = false

	_floor.spawn(_config)
	for i in _stacks.size():
		_stacks[i].set_target(_model.stack_target(i))
	_discard.set_warning(false)
	_floor.refresh_exposure(_model)
	if _hud != null:
		_hud.refresh()

	_arm_tutorial(n)


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
	_tutorial_state = TutorialState.new()
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
	if _overlay.visible:
		_dismiss_overlay()
		return
	if _input_locked or _model.is_game_over():
		return
	var events := _model.tap_card(card_id)
	if events.is_empty():
		return
	# Feed the committed tap to the tutorial coach (S1-010) before animating.
	if is_instance_valid(_coach):
		_coach.on_committed_tap(events)
	_input_locked = true
	await _play_events(events)
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
		GameEvent.Kind.WIN:
			JuiceService.haptic(40)
			GameManager.complete_level()
			_show_overlay("You Win!")
		GameEvent.Kind.LOSE:
			JuiceService.haptic(60)
			GameManager.fail_level()
			_show_overlay("Game Over")


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
		await card.fly_to(_discard.slot_global_position(slot), CARD_FLY)


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


func _update_discard_warning() -> void:
	var filled: int = 0
	for card_id: int in _discard_cards:
		if card_id != -1:
			filled += 1
	_discard.set_warning(filled >= DISCARD_WARN_AT)


func _open_pause() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return
	get_tree().paused = true
	_pause_menu = PauseMenu.new()
	# Keep the menu live while the rest of the tree is paused.
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.resumed.connect(_close_pause)
	_pause_menu.home_pressed.connect(_on_home_pressed)
	_hud_layer.add_child(_pause_menu)


func _close_pause() -> void:
	_pause_menu = null
	get_tree().paused = false


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


func _show_overlay(text: String) -> void:
	_overlay_label.text = "%s\n\n(tap to continue)" % text
	_overlay.visible = true


func _dismiss_overlay() -> void:
	_overlay.visible = false
	start_level(GameManager.current_level)


func _unhandled_input(event: InputEvent) -> void:
	if not _overlay.visible:
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		_dismiss_overlay()
