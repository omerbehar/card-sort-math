class_name CardData
extends Resource
## A single arithmetic exercise printed on a floor card (GDD math-exercises).
##
## [member result] is [member operand_a] [member operation] [member operand_b]
## (e.g. 12 ÷ 3 = 4). The layout fields describe where the card sits in a
## hand-authored floor layout: [member layout_layer] is its stacking depth
## (0 = bottom) and [member layout_slot] is its index within that layout preset.
## The sort engine routes only by [member result]; [member operation] is a
## content concern (ADR-0003), so adding operations never touches the board model.

@export var operand_a: int = 0
@export var operand_b: int = 0
@export var result: int = 0
## Which arithmetic operation this card prints; see [enum Operation.Type].
@export var operation: int = Operation.Type.ADD
@export var layout_layer: int = 0
@export var layout_slot: int = 0


## Builds a [CardData] from two operands, computing
## [member result] = a [param operation] b. [param operation] defaults to
## [constant Operation.Type.ADD], so existing callers and authored cards are
## unchanged.
static func create(a: int, b: int, layer: int, slot: int, operation: int = Operation.Type.ADD) -> CardData:
	var card := CardData.new()
	card.operand_a = a
	card.operand_b = b
	card.operation = operation
	card.result = Operation.apply(a, b, operation)
	card.layout_layer = layer
	card.layout_slot = slot
	return card


## Human-readable exercise, e.g. "3 + 4" or "12 ÷ 3".
func exercise_text() -> String:
	return Operation.format(operand_a, operand_b, operation)
