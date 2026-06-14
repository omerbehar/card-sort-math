class_name DiscardRow
extends Node2D
## The discard row: one slot per active discard buffer entry, rendered as Kenney
## grey slots. View only — occupancy and capacity live in [BoardModel]. The slot
## count mirrors [method BoardModel.active_discard_slots] so the Extra Discard Slot
## booster (S3-006 / ADR-0010) is reflected when the buffer grows. Tints red as a
## warning when nearly full.
##
## [b]Layout (UX spec, S3-006):[/b] slots are a fixed small size budgeted so the
## maximum 7 (5 base + two Extra Discard purchases) fit across the 390px portrait
## with comfortable side margins, and the row is [b]horizontally centred[/b] for
## every count — slots are laid out from [code]-total_width/2[/code] and the node
## sits at screen-centre x (set by [code]Main.DISCARD_ORIGIN[/code]). Row widths:
## 5→248px, 6→300px, 7→352px (margins 71 / 45 / 19px per side).
##
## NOTE: slots are non-interactive today (cards auto-route). If they ever become
## tappable, each needs a ≥44px touch region (invisible padding) per WCAG/HIG —
## do not grow the visual slot to reach it.

## Base slot count — matches [constant BoardModel.DISCARD_SLOTS].
const SLOTS: int = 5
## Display budget: the row is sized to fit this many slots. Matches the economy
## default [code]EconomyConfig.max_discard_slots[/code] (5 base + two purchases).
const MAX_SLOTS: int = 7
## Visible space between slots.
const SLOT_GAP: float = 12.0
## Seconds the existing slots take to slide to their re-centred positions on a grow.
## Shared so the cards sitting in those slots (re-homed by Main) move in lockstep.
const GROW_SLIDE_SEC: float = 0.20
## Slot width — fixed; sized so MAX_SLOTS slots + gaps fit the portrait with margins.
const SLOT_W: float = 40.0
## Slot height, keeping the original 72×92 card aspect ratio (40 × 92/72 ≈ 51).
const SLOT_H: float = 51.0

const _NORMAL_TINT: Color = Color(0.78, 0.80, 0.88)
const _WARNING_TINT: Color = Color(1.0, 0.55, 0.55)

var _slot_count: int = SLOTS
var _start_x: float = 0.0          # local x of slot 0 (recomputed per count to centre the row)
var _frames: Array[NinePatchRect] = []
var _warning: bool = false


func _ready() -> void:
	_build_visuals()


# Local x of slot 0 so the whole row is centred on this node's origin (which Main
# positions at screen-centre). Pure function of the current slot count.
func _compute_start_x() -> float:
	var total_w: float = _slot_count * SLOT_W + (_slot_count - 1) * SLOT_GAP
	return -total_w / 2.0


func _build_visuals() -> void:
	for frame in _frames:
		frame.queue_free()
	_frames.clear()
	_start_x = _compute_start_x()
	var tint: Color = _WARNING_TINT if _warning else _NORMAL_TINT
	for i in _slot_count:
		var pos := Vector2(_start_x + i * (SLOT_W + SLOT_GAP), 0)
		var frame := UiFactory.nine_patch(self, "kenney/slot_grey.png", pos, Vector2(SLOT_W, SLOT_H), 12, tint)
		_frames.append(frame)


## Sets the number of rendered slots to [param n] (mirrors the model's active
## discard capacity). Slot size is fixed (budgeted for [constant MAX_SLOTS]); adding
## a slot re-centres the row. A grow is animated (existing slots slide to their new
## centred positions, the new slot fades in) unless reduced-motion is on, in which
## case it rebuilds instantly. (S3-006 / ADR-0010.)
func set_slot_count(n: int) -> void:
	if n == _slot_count:
		return
	var old_count: int = _slot_count
	_slot_count = maxi(1, n)
	if is_inside_tree() and _slot_count > old_count and old_count == _frames.size() \
			and not _reduced_motion():
		_animate_grow(old_count)
	else:
		_build_visuals()


# True when the player has enabled reduced motion (skip the slide/fade).
func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/SettingsService")
	return settings != null and bool(settings.get_value("reduced_motion"))


# Slides the existing frames to their new centred positions and fades the appended
# slot(s) in, so a mid-level Extra Discard purchase doesn't snap the row sideways.
func _animate_grow(old_count: int) -> void:
	_start_x = _compute_start_x()
	var tint: Color = _WARNING_TINT if _warning else _NORMAL_TINT
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i in old_count:
		tween.tween_property(_frames[i], "position",
				Vector2(_start_x + i * (SLOT_W + SLOT_GAP), 0), GROW_SLIDE_SEC)
	for i in range(old_count, _slot_count):
		var pos := Vector2(_start_x + i * (SLOT_W + SLOT_GAP), 0)
		var frame := UiFactory.nine_patch(self, "kenney/slot_grey.png", pos, Vector2(SLOT_W, SLOT_H), 12, tint)
		frame.self_modulate = Color(tint, 0.0)
		_frames.append(frame)
		tween.tween_property(frame, "self_modulate:a", tint.a, GROW_SLIDE_SEC).set_delay(0.06)


## Current rendered slot count.
func slot_count() -> int:
	return _slot_count


## Global top-left position of discard [param slot] (centred-row aware).
func slot_global_position(slot: int) -> Vector2:
	return to_global(Vector2(_start_x + slot * (SLOT_W + SLOT_GAP), 0))


## Tints every slot red when the row is nearly full.
func set_warning(active: bool) -> void:
	_warning = active
	var tint: Color = _WARNING_TINT if active else _NORMAL_TINT
	for frame in _frames:
		frame.self_modulate = tint
