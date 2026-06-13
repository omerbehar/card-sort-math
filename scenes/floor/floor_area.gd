class_name FloorArea
extends Node2D
## Container + spawner for all floor cards. Owns the [Card] nodes (which keep
## living here even after they fly into a stack or discard — only their position
## and z-index change). Applies exposure state from the [BoardModel], which is
## the single source of truth for which cards are tappable.

signal card_tapped(card_id: int)

const MOVING_Z: int = 100

var _cards: Dictionary = {}  # card_id -> Card


## Spawns one [Card] per entry in [member LevelConfig.card_pool], positioned and
## z-ordered by the level's layout preset.
func spawn(config: LevelConfig) -> void:
	clear()
	var placements := Layouts.get_layout(config.layout_id)
	for card_data: CardData in config.card_pool:
		var card := Card.new()
		add_child(card)
		card.setup(card_data.layout_slot, card_data)
		card.position = placements[card_data.layout_slot].pos
		card.z_index = placements[card_data.layout_slot].layer
		card.tapped.connect(_on_card_tapped)
		_cards[card_data.layout_slot] = card


func clear() -> void:
	for card: Card in _cards.values():
		card.queue_free()
	_cards.clear()


func get_card(card_id: int) -> Card:
	return _cards.get(card_id)


## Lifts a card above the floor pile while it animates into a stack/discard.
func lift(card_id: int, extra_z: int = 0) -> void:
	var card: Card = _cards.get(card_id)
	if card != null:
		card.z_index = MOVING_Z + extra_z
		card.set_inert()


func remove_card(card_id: int) -> void:
	var card: Card = _cards.get(card_id)
	if card != null:
		card.queue_free()
		_cards.erase(card_id)


## Re-applies tappable/dim state to every surviving card from the model.
func refresh_exposure(model: BoardModel) -> void:
	for card_id: int in _cards:
		var card: Card = _cards[card_id]
		if model.is_card_removed(card_id):
			card.set_inert()
		else:
			card.set_exposed(model.is_exposed(card_id))


## Picker mode (S3-012): makes every surviving card tappable — including covered
## ones — so the player can choose a lower-layer card to play. The controller calls
## [method refresh_exposure] afterwards to return to normal tappability.
func set_pickable_all(model: BoardModel) -> void:
	for card_id: int in _cards:
		if not model.is_card_removed(card_id):
			(_cards[card_id] as Card).input_pickable = true


## Repositions [param card_id] to a placement (used by the Reshuffle re-layout).
## Tweens over [param duration]s (instant when 0).
func place_card_at(card_id: int, pos: Vector2, layer: int, duration: float) -> void:
	var card: Card = _cards.get(card_id)
	if card == null:
		return
	card.z_index = layer
	if duration <= 0.0:
		card.position = pos
		return
	var tween := card.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(card, "position", pos, duration)


func _on_card_tapped(card_id: int) -> void:
	card_tapped.emit(card_id)
