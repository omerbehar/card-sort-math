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
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.10, 0.12, 0.20))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if _label != null and card_data != null:
		_label.text = str(card_data.result) if _showing_result else card_data.exercise_text()


## Flips the card from its exercise to just the result number (used when the
## card lands on a stack, so the stack reads as a column of matching numbers).
func show_result() -> void:
	_showing_result = true
	if _label != null:
		_label.add_theme_font_size_override("font_size", 30)
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
