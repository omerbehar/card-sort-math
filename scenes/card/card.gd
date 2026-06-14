class_name Card
extends Area2D
## Visual + input for one floor card. Built procedurally (no .tscn) so the card
## is just an [Area2D] with a panel, a label and a rectangular collision shape.
##
## The card is a dumb view: it renders its exercise, reports taps via [signal
## tapped], and exposes [method fly_to] for the controller to animate it. All
## routing decisions live in [BoardModel].

signal tapped(card_id: int)

const W: float = Layouts.CARD_W
const H: float = Layouts.CARD_H

var card_id: int = -1
var card_data: CardData

var _label: Label
var _showing_result: bool = false

# Exercise label font sizes: a roomy size for a binary "3 + 4", a smaller one for
# a three-term "(3 + 7) − 4" so the longer string fits the 72px card, and the big
# size for the bare result number once a card lands on a stack.
const _FONT_BINARY: int = 20
const _FONT_TERNARY: int = 13
const _FONT_RESULT: int = 30


func _ready() -> void:
	z_as_relative = false
	_build_visuals()
	input_pickable = false
	input_event.connect(_on_input_event)
	_apply_text()


func _build_visuals() -> void:
	UiFactory.nine_patch(self, "kenney/card.png", Vector2.ZERO, Vector2(W, H), 16)

	_label = Label.new()
	_label.size = Vector2(W, H)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", _FONT_BINARY)
	_label.add_theme_color_override("font_color", Color(0.10, 0.12, 0.20))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wrap a long three-term exercise onto a second line rather than clip it.
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(W, H)
	shape.shape = rect
	shape.position = Vector2(W * 0.5, H * 0.5)
	add_child(shape)


## Assigns the card's identity + exercise.
func setup(id: int, data: CardData) -> void:
	card_id = id
	card_data = data
	_apply_text()


func _apply_text() -> void:
	if _label == null or card_data == null:
		return
	if _showing_result:
		_label.text = str(card_data.result)
		return
	_label.text = card_data.exercise_text()
	# A three-term exercise needs the smaller font to fit the card width.
	var size: int = _FONT_TERNARY if card_data.term_count >= 3 else _FONT_BINARY
	_label.add_theme_font_size_override("font_size", size)


## Flips the card from its exercise to just the result number (used when the
## card lands on a stack, so the stack reads as a column of matching numbers).
func show_result() -> void:
	_showing_result = true
	if _label != null:
		_label.add_theme_font_size_override("font_size", _FONT_RESULT)
	_apply_text()


## Exposed cards are tappable and fully lit; covered cards are dimmed and inert.
func set_exposed(value: bool) -> void:
	input_pickable = value
	modulate = Color.WHITE if value else Color(0.6, 0.6, 0.66)


## A card that has left the floor (now in a stack or discard): never tappable,
## rendered at full colour.
func set_inert() -> void:
	input_pickable = false
	modulate = Color.WHITE


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not input_pickable:
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		tapped.emit(card_id)


## Tweens the card to [param target] (global, top-left) and awaits completion.
## [param target_scale] tweens the card's scale alongside the move — used to shrink
## a card into the smaller discard slots (S3-006) and restore it to full size when
## pulled back onto a stack. Defaults to full size (1.0).
func fly_to(target: Vector2, duration: float, target_scale: float = 1.0) -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target, duration)
	if not is_equal_approx(scale.x, target_scale):
		tween.tween_property(self, "scale", Vector2(target_scale, target_scale), duration)
	await tween.finished
