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
const FLOOR_ORIGIN: Vector2 = Vector2(0.0, 300.0)
const DISCARD_WARN_AT: int = 4

var _model: BoardModel
var _config: LevelConfig

var _floor: FloorArea
var _stacks: Array[Stack] = []
var _discard: DiscardRow
var _hud: Hud

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

	for i in BoardModel.STACK_COUNT:
		var stack := Stack.new()
		stack.position = Vector2(STACK_XS[i], STACK_Y)
		add_child(stack)
		stack.setup(i, -1)
		_stacks.append(stack)
		_stack_cards.append([])

	_discard = DiscardRow.new()
	_discard.position = DISCARD_ORIGIN
	add_child(_discard)
	for _i in BoardModel.DISCARD_SLOTS:
		_discard_cards.append(-1)

	# Cosmetic chrome (header + tool bar + zoom slider) on its own layer.
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	_hud = Hud.new()
	hud_layer.add_child(_hud)


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
	JuiceService.burst(self, _stacks[stack_index].position + Vector2(36.0, 24.0))
	JuiceService.punch(_stacks[stack_index])

	await _stacks[stack_index].play_clear()


func _update_discard_warning() -> void:
	var filled: int = 0
	for card_id: int in _discard_cards:
		if card_id != -1:
			filled += 1
	_discard.set_warning(filled >= DISCARD_WARN_AT)


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
