class_name TernaryExpression
extends RefCounted
## A three-term arithmetic expression printed on a [CardData] (GDD math-exercises,
## multi-term teaching worlds). Pure, node-free helpers layered on top of the
## binary [Operation] helpers.
##
## A ternary card reads [code]a op1 b op2 c[/code] with a [enum Grouping] that
## decides BOTH how it evaluates and how it renders:
## [codeblock]
## LEFT        3 + 7 − 4        evaluate left-to-right (no parentheses shown)
## PAREN_LEFT  (3 + 7) − 4      parentheses around the left pair
## PAREN_RIGHT 3 + (7 − 4)      parentheses around the right pair
## PRECEDENCE  2 + 3 × 4        no parentheses; ×/÷ bind tighter than +/− (order of operations)
## [/codeblock]
## Like [Operation], the sort engine never reads any of this — it routes solely by
## [member CardData.result] (ADR-0003) — so multi-term expressions need no change
## to the board model or the solvability invariant. Every value is kept
## non-negative and every division exact by construction: [method evaluate]
## returns [constant INVALID] for any triple that would go negative mid-step or
## divide inexactly, and the level generator only deals triples it accepts.

## How the three terms are grouped/evaluated and displayed. Ordinals are stable
## and persisted on [member CardData.grouping]; a bare card defaults to [constant
## Grouping.LEFT] (0).
enum Grouping {
	LEFT,        ## a op1 b op2 c — evaluate left-to-right, no parentheses shown
	PAREN_LEFT,  ## (a op1 b) op2 c — parentheses around the left pair
	PAREN_RIGHT, ## a op1 (b op2 c) — parentheses around the right pair
	PRECEDENCE,  ## a op1 b op2 c — order of operations, no parentheses (×/÷ first)
}

## Sentinel returned by [method evaluate] for a triple that cannot be displayed to
## a young learner: a negative intermediate/final value, a division by zero, or an
## inexact division. Distinct from every legal result (results are >= 0).
const INVALID: int = -1


## Resolves [param grouping] to the concrete left/right grouping actually used to
## evaluate and parenthesise. [constant Grouping.PRECEDENCE] becomes
## [constant Grouping.PAREN_RIGHT] only when a low-precedence op1 (+/−) is followed
## by a high-precedence op2 (×/÷) — e.g. [code]2 + 3 × 4[/code] computes the
## product first; every other case is left-to-right.
static func effective_grouping(op1: int, op2: int, grouping: int) -> int:
	if grouping == Grouping.PRECEDENCE:
		if not Operation.is_high_precedence(op1) and Operation.is_high_precedence(op2):
			return Grouping.PAREN_RIGHT
		return Grouping.PAREN_LEFT
	return grouping


## Evaluates [code]a op1 b op2 c[/code] under [param grouping], or returns
## [constant INVALID] when any step would be negative, divide by zero, or divide
## inexactly. Division is integer and exact by construction.
static func evaluate(a: int, b: int, c: int, op1: int, op2: int, grouping: int) -> int:
	if effective_grouping(op1, op2, grouping) == Grouping.PAREN_RIGHT:
		var inner: int = _apply_checked(b, c, op2)
		if inner == INVALID:
			return INVALID
		return _apply_checked(a, inner, op1)
	var left: int = _apply_checked(a, b, op1)
	if left == INVALID:
		return INVALID
	return _apply_checked(left, c, op2)


## Whether [code]a op1 b op2 c[/code] is a legal (non-negative, exactly-divisible)
## expression under [param grouping].
static func is_valid(a: int, b: int, c: int, op1: int, op2: int, grouping: int) -> bool:
	return evaluate(a, b, c, op1, op2, grouping) != INVALID


## Human-readable exercise, e.g. [code]"3 + 7 − 4"[/code], [code]"(3 + 7) − 4"[/code]
## or [code]"2 + 3 × 4"[/code]. [constant Grouping.PRECEDENCE] renders WITHOUT
## parentheses on purpose — reading the order of operations is the lesson.
static func format(a: int, b: int, c: int, op1: int, op2: int, grouping: int) -> String:
	var g1: String = Operation.glyph(op1)
	var g2: String = Operation.glyph(op2)
	match grouping:
		Grouping.PAREN_LEFT:
			return "(%d %s %d) %s %d" % [a, g1, b, g2, c]
		Grouping.PAREN_RIGHT:
			return "%d %s (%d %s %d)" % [a, g1, b, g2, c]
		_:
			return "%d %s %d %s %d" % [a, g1, b, g2, c]


# One binary step, guarding the kid-friendly invariants: subtraction must not go
# negative; division must be by a non-zero divisor and exact. Returns INVALID (-1)
# on any violation — safe because every legal result here is >= 0.
static func _apply_checked(x: int, y: int, operation: int) -> int:
	match operation:
		Operation.Type.SUBTRACT:
			return x - y if x >= y else INVALID
		Operation.Type.MULTIPLY:
			return x * y
		Operation.Type.DIVIDE:
			return int(x / y) if (y != 0 and x % y == 0) else INVALID
		_:
			return x + y
