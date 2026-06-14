class_name Operation
extends RefCounted
## The arithmetic operation printed on a [CardData] (GDD math-exercises).
##
## Pure, node-free helpers shared by [CardData] (display + result) and
## [OperandPicker] (operand selection). The sort engine never reads the
## operation — it routes solely by [member CardData.result] — so operations are a
## pure content concern layered on top of the result-only solvability invariant
## (ADR-0003). This is why subtraction, multiplication and division "worlds" need
## no change to the board model or solvability check.

## The four supported operations. Ordinals are stable and persisted: an authored
## card or a bare [code]CardData.new()[/code] defaults to [constant Type.ADD] (0).
enum Type {
	ADD,      ## a + b
	SUBTRACT, ## a − b
	MULTIPLY, ## a × b
	DIVIDE,   ## a ÷ b
}

## Every operation type, in display order. Seeds a mixed-operation world.
const ALL: Array[int] = [Type.ADD, Type.SUBTRACT, Type.MULTIPLY, Type.DIVIDE]

# The operator glyph printed between operands. Math glyphs (−, ×, ÷) per design.
const _GLYPHS: Dictionary = {
	Type.ADD: "+",
	Type.SUBTRACT: "−",
	Type.MULTIPLY: "×",
	Type.DIVIDE: "÷",
}


## The operator glyph for [param operation] (e.g. [code]"×"[/code]). Falls back to
## [code]"+"[/code] for an unknown value so a card never renders blank.
static func glyph(operation: int) -> String:
	return _GLYPHS.get(operation, "+")


## Whether [param operation] binds tighter than +/− under the order of operations
## — i.e. it is × or ÷. Used by [TernaryExpression] to resolve precedence and by
## the level generator to compose order-of-operations worlds.
static func is_high_precedence(operation: int) -> bool:
	return operation == Type.MULTIPLY or operation == Type.DIVIDE


## Applies [param operation] to [param a] and [param b]. Division is exact by
## construction (the generator only pairs evenly-divisible operands); a zero
## divisor returns 0 rather than crashing.
static func apply(a: int, b: int, operation: int) -> int:
	match operation:
		Type.SUBTRACT:
			return a - b
		Type.MULTIPLY:
			return a * b
		Type.DIVIDE:
			return a / b if b != 0 else 0
		_:
			return a + b


## Human-readable exercise for [param a] [param operation] [param b],
## e.g. [code]"12 ÷ 3"[/code].
static func format(a: int, b: int, operation: int) -> String:
	return "%d %s %d" % [a, glyph(operation), b]
