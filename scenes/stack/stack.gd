class_name Stack
extends Node2D
## One target stack: a Kenney rounded slot showing its target result, into which
## up to three matching cards are flown. View only — fill/clear state lives in
## [BoardModel]. The node origin (0,0) is the frame's top-left.

# The frame is card-sized: a placed card sits flush over it. The target number
# shows in the frame's centre until cards cover it; stacked cards fan down a few
# pixels so the pile reads as more than one.
const FRAME_W: float = Layouts.CARD_W
const FRAME_H: float = Layouts.CARD_H
const CARD_INSET_X: float = 0.0
const SLOT_TOP: float = 0.0
const SLOT_DY: float = 7.0

# Three-dot capacity indicator straddling the frame's bottom edge.
const DOT_SIZE: float = 16.0
const DOT_GAP: float = 5.0
const DOT_Y: float = FRAME_H - DOT_SIZE * 0.5
const DOT_Z: int = 130

## Emitted when a LOCKED stack is tapped (prototype: locked-decks). The board
## controller decides whether the unlock can be afforded (coins/ad).
signal unlock_requested(stack_index: int)

const _LOCK_GREEN: Color = Color(0.40, 0.78, 0.34)

var stack_index: int = -1
var target: int = -1
# Whether the colour-blind palette is active (see [StackPalette]).
var _colorblind: bool = false

var _frame: NinePatchRect
var _label: Label
var _dots: Array[Sprite2D] = []

# Prototype: locked-decks. The lock chrome is built lazily on first lock.
var _locked: bool = false
var _lock_button: Button = null
var _lock_plus: Label = null
var _lock_cost: Label = null


func setup(index: int, target_value: int, colorblind: bool = false) -> void:
	stack_index = index
	_colorblind = colorblind
	_build_visuals()
	set_target(target_value)


func _build_visuals() -> void:
	var slot_file: String = StackPalette.slot_file(stack_index, _colorblind)
	_frame = UiFactory.nine_patch(self, slot_file, Vector2.ZERO, Vector2(FRAME_W, FRAME_H), 16)
	_frame.self_modulate = StackPalette.tint(stack_index, _colorblind)

	# Target number, centred on the frame.
	_label = UiFactory.label(self, "", Vector2.ZERO, Vector2(FRAME_W, FRAME_H), 34, Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.12, 0.16, 0.26, 0.95))
	_label.add_theme_constant_override("outline_size", 6)

	# Capacity dots, centred on the frame's bottom edge, above the cards.
	var row_w: float = BoardModel.STACK_CAPACITY * DOT_SIZE + (BoardModel.STACK_CAPACITY - 1) * DOT_GAP
	var start_x: float = (FRAME_W - row_w) * 0.5
	for i in BoardModel.STACK_CAPACITY:
		var dot := UiFactory.sprite(self, "kenney/dot_empty.png",
			Vector2(start_x + i * (DOT_SIZE + DOT_GAP), DOT_Y), Vector2(DOT_SIZE, DOT_SIZE))
		dot.z_as_relative = false
		dot.z_index = DOT_Z
		_dots.append(dot)


func set_target(value: int) -> void:
	target = value
	if _label != null:
		_label.text = str(target) if target >= 0 else ""
	# Empty (no active target) stacks dim slightly, preserving the palette hue.
	var active: bool = target >= 0
	if _frame != null:
		var base: Color = _base_tint()
		base.a = 1.0 if active else 0.5
		_frame.self_modulate = base
	# A (re)targeted stack starts empty.
	set_filled(0)


# The frame's palette tint at full alpha (white for the default skin, an
# Okabe-Ito colour under the colorblind palette).
func _base_tint() -> Color:
	return StackPalette.tint(stack_index, _colorblind)


## Re-skins the frame for a palette change (e.g. the colorblind setting toggled
## while a level is in play). Preserves the current active/dim alpha.
func apply_palette(colorblind: bool) -> void:
	_colorblind = colorblind
	if _frame == null:
		return
	_frame.texture = load(UiFactory.UI_DIR + StackPalette.slot_file(stack_index, _colorblind))
	var tint: Color = _base_tint()
	tint.a = 1.0 if target >= 0 else 0.5
	_frame.self_modulate = tint


## Prototype: locked-decks. Shows/hides the locked "+" chrome over the slot. When
## [param locked], the slot reads as an unbuyable green "+" with a coin [param
## cost]; tapping it emits [signal unlock_requested]. When unlocked, the normal
## target/dots are restored by the caller via [method set_target].
func set_locked(locked: bool, cost: int = 0) -> void:
	_locked = locked
	if locked and _lock_button == null:
		_build_lock_chrome()
	if _lock_button != null:
		_lock_button.visible = locked
	if _lock_plus != null:
		_lock_plus.visible = locked
	if _lock_cost != null:
		_lock_cost.visible = locked
		_lock_cost.text = "%d" % cost
	if locked:
		_label.text = ""                 # hide any target number
		for d in _dots:
			d.visible = false
		_frame.self_modulate = _LOCK_GREEN
	else:
		for d in _dots:
			d.visible = true


func _build_lock_chrome() -> void:
	_lock_plus = UiFactory.label(self, "+", Vector2(0, -6), Vector2(FRAME_W, FRAME_H), 44, Color.WHITE)
	_lock_plus.add_theme_color_override("font_outline_color", Color(0.12, 0.30, 0.12, 0.9))
	_lock_plus.add_theme_constant_override("outline_size", 6)
	_lock_cost = UiFactory.label(self, "", Vector2(0, FRAME_H - 26), Vector2(FRAME_W, 22), 16, Color(1, 1, 0.85))
	# Transparent button over the whole slot captures the unlock tap.
	_lock_button = Button.new()
	_lock_button.flat = true
	_lock_button.position = Vector2.ZERO
	_lock_button.size = Vector2(FRAME_W, FRAME_H)
	_lock_button.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_lock_button)
	_lock_button.pressed.connect(func() -> void: unlock_requested.emit(stack_index))


## Lights the first [param count] capacity dots (0..[constant
## BoardModel.STACK_CAPACITY]) to show how full the stack is.
func set_filled(count: int) -> void:
	for i in _dots.size():
		_dots[i].texture = load(UiFactory.UI_DIR + ("kenney/dot_full.png" if i < count else "kenney/dot_empty.png"))


## Global top-left position for a card occupying fill index [param slot] (0..2).
func slot_global_position(slot: int) -> Vector2:
	return to_global(Vector2(CARD_INSET_X, SLOT_TOP + slot * SLOT_DY))


## Brief flash when the stack clears and adopts a new target. Returns to the
## palette tint (not plain white) so a colorblind hue survives the clear.
func play_clear() -> void:
	var base: Color = _base_tint()
	var flash := base * 1.8
	flash.a = 1.0
	var tween := create_tween()
	tween.tween_property(_frame, "self_modulate", flash, 0.08)
	tween.tween_property(_frame, "self_modulate", base, 0.14)
	await tween.finished
