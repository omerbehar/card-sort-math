class_name DiscardRow
extends Node2D
## The discard row: one slot per active discard buffer entry, rendered as Kenney
## grey slots. View only — occupancy and capacity live in [BoardModel]. The slot
## count mirrors [method BoardModel.active_discard_slots] so the Extra Discard Slot
## booster (S3-006 / ADR-0010) is reflected when the buffer grows. Tints red as a
## warning when nearly full.
##
## Slots are sized once for the [b]maximum[/b] capacity (two Extra Discard purchases
## → 7 slots) so they fit across the portrait width with visible gaps between them.
## The size is fixed: adding a slot fills the next position rather than resizing the
## existing slots, so the row layout stays stable as the buffer grows.

## Base slot count — matches [constant BoardModel.DISCARD_SLOTS].
const SLOTS: int = 5
## Display budget: the row is sized to fit this many slots. Matches the economy
## default [code]EconomyConfig.max_discard_slots[/code] (5 base + two purchases).
const MAX_SLOTS: int = 7
## Max horizontal span the row may occupy (390px portrait, minus the row origin).
const MAX_ROW_W: float = 376.0
## Visible space between slots.
const SLOT_GAP: float = 10.0
## Slot width, sized so MAX_SLOTS slots + gaps fit within MAX_ROW_W (~45px at 7/10).
const SLOT_W: float = (MAX_ROW_W - (MAX_SLOTS - 1) * SLOT_GAP) / MAX_SLOTS
## Slot height, keeping the original 72×92 card aspect ratio.
const SLOT_H: float = SLOT_W * (92.0 / 72.0)

const _NORMAL_TINT: Color = Color(0.78, 0.80, 0.88)
const _WARNING_TINT: Color = Color(1.0, 0.55, 0.55)

var _slot_count: int = SLOTS
var _frames: Array[NinePatchRect] = []
var _warning: bool = false


func _ready() -> void:
	_build_visuals()


func _build_visuals() -> void:
	for frame in _frames:
		frame.queue_free()
	_frames.clear()
	var tint: Color = _WARNING_TINT if _warning else _NORMAL_TINT
	for i in _slot_count:
		var pos := Vector2(i * (SLOT_W + SLOT_GAP), 0)
		var frame := UiFactory.nine_patch(self, "kenney/slot_grey.png", pos, Vector2(SLOT_W, SLOT_H), 12, tint)
		_frames.append(frame)


## Sets the number of rendered slots to [param n] (mirrors the model's active
## discard capacity) and rebuilds the row. Slot size is fixed (budgeted for
## [constant MAX_SLOTS]); adding a slot fills the next position. (S3-006 / ADR-0010.)
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
	return to_global(Vector2(slot * (SLOT_W + SLOT_GAP), 0))


## Tints every slot red when the row is nearly full.
func set_warning(active: bool) -> void:
	_warning = active
	var tint: Color = _WARNING_TINT if active else _NORMAL_TINT
	for frame in _frames:
		frame.self_modulate = tint
