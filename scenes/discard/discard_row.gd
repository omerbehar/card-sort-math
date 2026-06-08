class_name DiscardRow
extends Node2D
## The discard row: five slots for cards with no matching stack, rendered as
## Kenney grey slots. View only — occupancy lives in [BoardModel]. Tints red as a
## warning when nearly full.

const SLOTS: int = 5
const SLOT_W: float = 72.0
const SLOT_H: float = 92.0
const SLOT_GAP: float = 4.0

const _NORMAL_TINT: Color = Color(0.78, 0.80, 0.88)
const _WARNING_TINT: Color = Color(1.0, 0.55, 0.55)

var _frames: Array[NinePatchRect] = []


func _ready() -> void:
	_build_visuals()


func _build_visuals() -> void:
	for i in SLOTS:
		var pos := Vector2(i * (SLOT_W + SLOT_GAP), 0)
		var frame := UiFactory.nine_patch(self, "kenney/slot_grey.png", pos, Vector2(SLOT_W, SLOT_H), 16, _NORMAL_TINT)
		_frames.append(frame)


## Global top-left position of discard [param slot].
func slot_global_position(slot: int) -> Vector2:
	return to_global(Vector2(slot * (SLOT_W + SLOT_GAP), 0))


## Tints every slot red when the row is nearly full.
func set_warning(active: bool) -> void:
	var tint: Color = _WARNING_TINT if active else _NORMAL_TINT
	for frame in _frames:
		frame.self_modulate = tint
