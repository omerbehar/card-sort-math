class_name Exposure
extends RefCounted
## Pure floor-exposure logic, derived from layout placements only.
##
## A card is "covered" by another card that sits on a strictly higher layer and
## whose rectangle overlaps it. A card is exposed (tappable) once every card
## covering it has been removed. Because coverage only ever points from a higher
## layer to a lower one, the relation is a DAG: removing cards top-down always
## eventually exposes everything, so every card is reachable.

## Builds the coverage graph for [param placements] (an ordered list of
## [code]{pos: Vector2, layer: int}[/code], index = card id).
##
## Returns a [Dictionary] mapping each card id to an [code]Array[int][/code] of
## the ids that cover it.
static func compute_covered_by(placements: Array, card_w: float = Layouts.CARD_W, card_h: float = Layouts.CARD_H) -> Dictionary:
	var covered_by: Dictionary = {}
	for i in placements.size():
		covered_by[i] = [] as Array[int]

	for lower in placements.size():
		var lower_rect := _rect_of(placements[lower], card_w, card_h)
		var lower_layer: int = placements[lower].layer
		for higher in placements.size():
			if higher == lower:
				continue
			if int(placements[higher].layer) <= lower_layer:
				continue
			if lower_rect.intersects(_rect_of(placements[higher], card_w, card_h)):
				(covered_by[lower] as Array[int]).append(higher)
	return covered_by


## True when every card covering [param card_id] is in [param removed].
static func is_exposed(card_id: int, removed: Dictionary, covered_by: Dictionary) -> bool:
	if removed.has(card_id):
		return false
	for coverer: int in covered_by.get(card_id, [] as Array[int]):
		if not removed.has(coverer):
			return false
	return true


## All not-yet-removed card ids that are currently exposed.
static func exposed_cards(removed: Dictionary, covered_by: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for card_id: int in covered_by:
		if is_exposed(card_id, removed, covered_by):
			out.append(card_id)
	return out


static func _rect_of(placement: Dictionary, card_w: float, card_h: float) -> Rect2:
	return Rect2(placement.pos, Vector2(card_w, card_h))
