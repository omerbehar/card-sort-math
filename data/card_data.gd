class_name CardData
extends Resource
## An addition exercise printed on a single floor card.
##
## [member result] is always [member operand_a] + [member operand_b]. The
## layout fields describe where the card sits in a hand-authored floor layout:
## [member layout_layer] is its stacking depth (0 = bottom) and
## [member layout_slot] is its index within that layout preset.

@export var operand_a: int = 0
@export var operand_b: int = 0
@export var result: int = 0
@export var layout_layer: int = 0
@export var layout_slot: int = 0


## Builds a [CardData] from two operands, computing [member result] = a + b.
static func create(a: int, b: int, layer: int, slot: int) -> CardData:
	var card := CardData.new()
	card.operand_a = a
	card.operand_b = b
	card.result = a + b
	card.layout_layer = layer
	card.layout_slot = slot
	return card


## Human-readable exercise, e.g. "3 + 4".
func exercise_text() -> String:
	return "%d + %d" % [operand_a, operand_b]
