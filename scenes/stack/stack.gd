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

# Kenney coloured slot per stack index (mirrors the reference: red, amber, green,
# blue).
const _SLOT_FILES: Array[String] = [
	"kenney/slot_red.png",
	"kenney/slot_yellow.png",
	"kenney/slot_green.png",
	"kenney/slot_blue.png",
]

var stack_index: int = -1
var target: int = -1

var _frame: NinePatchRect
var _label: Label
var _dots: Array[Sprite2D] = []


func setup(index: int, target_value: int) -> void:
	stack_index = index
	_build_visuals()
	set_target(target_value)


func _build_visuals() -> void:
	var slot_file: String = _SLOT_FILES[stack_index % _SLOT_FILES.size()]
	_frame = UiFactory.nine_patch(self, slot_file, Vector2.ZERO, Vector2(FRAME_W, FRAME_H), 16)

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
	# Empty (no active target) stacks dim slightly.
	var active: bool = target >= 0
	if _frame != null:
		_frame.self_modulate.a = 1.0 if active else 0.5
	# A (re)targeted stack starts empty.
	set_filled(0)


## Lights the first [param count] capacity dots (0..[constant
## BoardModel.STACK_CAPACITY]) to show how full the stack is.
func set_filled(count: int) -> void:
	for i in _dots.size():
		_dots[i].texture = load(UiFactory.UI_DIR + ("kenney/dot_full.png" if i < count else "kenney/dot_empty.png"))


## Global top-left position for a card occupying fill index [param slot] (0..2).
func slot_global_position(slot: int) -> Vector2:
	return to_global(Vector2(CARD_INSET_X, SLOT_TOP + slot * SLOT_DY))


## Brief flash when the stack clears and adopts a new target.
func play_clear() -> void:
	var tween := create_tween()
	tween.tween_property(_frame, "self_modulate", Color(1.8, 1.8, 1.8), 0.08)
	tween.tween_property(_frame, "self_modulate", Color.WHITE, 0.14)
	await tween.finished
