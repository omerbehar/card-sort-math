class_name PopupBase
extends Control
## Base chassis for modal pop-ups (ADR-0006).
##
## Owns the common modal BEHAVIOUR — a full-screen backdrop + input capture, an
## open/close animation (reduced-motion gated), and a uniform lifecycle — so each
## pop-up subclass only supplies its CONTENT (into [method body]) and its own
## domain signals. The visual skin of the panel is the subclass's job; this base is
## skin-agnostic (the game's pop-up art language is an open question — see ADR-0006).
##
## View only (ADR-0001): pop-ups emit intent signals and own no game state.
##
## Usage:
## [codeblock]
## class_name MyPopup
## extends PopupBase
## signal confirmed
## func _ready() -> void:
##     super()                       # builds backdrop + body
##     UiFactory.label(body(), "Are you sure?", ...)
##     # ... build a confirm button that does: confirmed.emit(); close()
##     play_open()
## [/codeblock]

## Emitted after the close animation, immediately before the node is freed.
signal closed
## Emitted when the backdrop is tapped (only when [member dismiss_on_backdrop]).
## Subclasses connect this to their own dismiss (e.g. resume).
signal backdrop_pressed

const _OPEN_T: float = 0.16
const _CLOSE_T: float = 0.12

## Backdrop colour (dim). Override before the node enters the tree.
@export var backdrop_color: Color = Color(0.04, 0.05, 0.09, 0.88)
## When true, [method close] unpauses the scene tree (the pop-up paused it).
@export var pauses_tree: bool = false
## When true, tapping the backdrop emits [signal backdrop_pressed] (tap-outside).
@export var dismiss_on_backdrop: bool = false

var _body: Control = null
var _closing: bool = false


func _ready() -> void:
	# Always responsive: animate + accept input even if the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# A flat Button serves as the backdrop: it always absorbs taps (modal), and when
	# dismiss_on_backdrop is set, a tap emits backdrop_pressed (tap-outside-to-close).
	var backdrop := Button.new()
	backdrop.name = "Backdrop"
	backdrop.flat = true
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = backdrop_color
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(dim)
	if dismiss_on_backdrop:
		backdrop.pressed.connect(func() -> void: backdrop_pressed.emit())
	add_child(backdrop)

	_body = Control.new()
	_body.name = "Body"
	_body.anchor_right = 1.0
	_body.anchor_bottom = 1.0
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)


## The content container. Subclasses build their panel + widgets into this.
func body() -> Control:
	return _body


## Plays the pop-in animation (scale + fade). No-op under reduced motion. Call
## after the subclass has built its content.
func play_open() -> void:
	if not _motion_ok():
		return
	modulate.a = 0.0
	_body.pivot_offset = _body.size * 0.5
	_body.scale = Vector2(0.94, 0.94)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, _OPEN_T)
	t.tween_property(_body, "scale", Vector2.ONE, _OPEN_T) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Dismisses the pop-up: fades out (unless reduced motion), unpauses the tree if it
## owned the pause, emits [signal closed], and frees itself. Idempotent.
func close() -> void:
	if _closing:
		return
	_closing = true
	if pauses_tree and get_tree() != null:
		get_tree().paused = false
	if _motion_ok():
		var t := create_tween()
		t.tween_property(self, "modulate:a", 0.0, _CLOSE_T)
		await t.finished
	closed.emit()
	queue_free()


func _motion_ok() -> bool:
	# Canonical motion seam, resolved via the tree path so dev harnesses that load
	# this script standalone still compile. Motion is allowed when unavailable.
	var juice := get_node_or_null(^"/root/JuiceService")
	return juice == null or juice.is_motion_enabled()
