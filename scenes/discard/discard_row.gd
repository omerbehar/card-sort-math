class_name DiscardRow
extends Node2D
## The discard row: one slot per active discard buffer entry, rendered as Kenney
## grey slots. View only — occupancy and capacity live in [BoardModel]. The slot
## count mirrors [method BoardModel.active_discard_slots] so the Extra Discard Slot
## booster (S3-006 / ADR-0010) is reflected when the buffer grows. Tints red as a
## warning when nearly full.

## Base slot count — matches [constant BoardModel.DISCARD_SLOTS]. The row starts here
## and grows via [method set_slot_count] when the Extra Discard Slot booster expands.
const SLOTS: int = 5
const SLOT_W: float = 72.0
const SLOT_H: float = 92.0
const SLOT_GAP: float = 4.0
## Max horizontal span the row may occupy (390px portrait, minus the row origin).
## When the slot count would overflow this, slot width shrinks to fit so every
## active slot stays on-screen.
const MAX_ROW_W: float = 376.0

const _NORMAL_TINT: Color = Color(0.78, 0.80, 0.88)
const _WARNING_TINT: Color = Color(1.0, 0.55, 0.55)

var _slot_count: int = SLOTS
var _slot_w: float = SLOT_W
var _frames: Array[NinePatchRect] = []
var _warning: bool = false


func _ready() -> void:
	_build_visuals()


# Width used per slot so [member _slot_count] slots fit within MAX_ROW_W. Stays at
# the full SLOT_W until the row would overflow (i.e. once expanded past the base 5).
func _compute_slot_w() -> float:
	var available: float = MAX_ROW_W - (_slot_count - 1) * SLOT_GAP
	return minf(SLOT_W, available / float(_slot_count))


func _build_visuals() -> void:
	for frame in _frames:
		frame.queue_free()
	_frames.clear()
	_slot_w = _compute_slot_w()
	var tint: Color = _WARNING_TINT if _warning else _NORMAL_TINT
	for i in _slot_count:
		var pos := Vector2(i * (_slot_w + SLOT_GAP), 0)
		var frame := UiFactory.nine_patch(self, "kenney/slot_grey.png", pos, Vector2(_slot_w, SLOT_H), 16, tint)
		_frames.append(frame)


## Sets the number of rendered slots to [param n] (mirrors the model's active
## discard capacity) and rebuilds the row, re-fitting slot width so every slot stays
## on-screen. Used when the Extra Discard Slot booster grows the buffer (ADR-0010).
func set_slot_count(n: int) -> void:
	if n == _slot_count:
		return
	_slot_count = maxi(1, n)
	_build_visuals()


## Current rendered slot count.
func slot_count() -> int:
	return _slot_count


## Global top-left position of discard [param slot].
func slot_global_position(slot: int) -> Vector2:
	return to_global(Vector2(slot * (_slot_w + SLOT_GAP), 0))


## Tints every slot red when the row is nearly full.
func set_warning(active: bool) -> void:
	_warning = active
	var tint: Color = _WARNING_TINT if active else _NORMAL_TINT
	for frame in _frames:
		frame.self_modulate = tint
