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
## Which arithmetic operation this card prints; see [enum Operation.Type]. For a
## three-term card ([member term_count] == 3) this is the FIRST operator (op1).
@export var operation: int = Operation.Type.ADD
@export var layout_layer: int = 0
@export var layout_slot: int = 0

## How many terms (operands) this card prints: 2 for a binary card
## [code]a ∘ b[/code], 3 for a multi-term card [code]a ∘ b ∘ c[/code] (the
## teaching worlds). Defaults to 2 so existing/authored cards are unchanged.
@export var term_count: int = 2
## Third operand; only meaningful when [member term_count] == 3.
@export var operand_c: int = 0
## The SECOND operator (op2), between b and c; only meaningful when
## [member term_count] == 3. See [enum Operation.Type].
@export var operation2: int = Operation.Type.ADD
## How a three-term card is grouped/displayed; see [enum TernaryExpression.Grouping].
## Only meaningful when [member term_count] == 3.
@export var grouping: int = TernaryExpression.Grouping.LEFT


## Builds a binary [CardData] from two operands, computing
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


## Builds a three-term [CardData] [code]a op1 b op2 c[/code] under [param grouping],
## computing [member result] via [TernaryExpression] (asserts the triple is legal —
## the generator only ever passes accepted triples).
static func create_ternary(
		a: int, b: int, c: int, op1: int, op2: int, grouping: int, layer: int, slot: int) -> CardData:
	var card := CardData.new()
	card.term_count = 3
	card.operand_a = a
	card.operand_b = b
	card.operand_c = c
	card.operation = op1
	card.operation2 = op2
	card.grouping = grouping
	card.result = TernaryExpression.evaluate(a, b, c, op1, op2, grouping)
	assert(card.result != TernaryExpression.INVALID,
		"create_ternary got an illegal triple: %d %d %d (ops %d,%d g%d)" % [a, b, c, op1, op2, grouping])
	card.layout_layer = layer
	card.layout_slot = slot
	return card


## Human-readable exercise, e.g. "3 + 4", "12 ÷ 3", "3 + 7 − 4" or "(3 + 7) − 4".
func exercise_text() -> String:
	if term_count >= 3:
		return TernaryExpression.format(operand_a, operand_b, operand_c, operation, operation2, grouping)
	return Operation.format(operand_a, operand_b, operation)
