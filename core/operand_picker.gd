class_name OperandPicker
extends RefCounted
## The single source of truth for splitting a [param result] into the printed
## operand pair for a given [enum Operation.Type] (GDD level-generator Formula 3,
## GDD math-exercises). Pure and node-free.
##
## [method pick] is deterministic in [param index]: cards sharing a result and
## operation cycle through the legal operand window so a board is not all
## "1 + 1". Both the generator (with the configured [code]max_operand[/code]) and
## the authored [LevelData] path call this. For addition the authored path passes
## [code]max_operand = result - 1[/code], reproducing the legacy
## [code]LevelData._split_operands[/code] output exactly.

## Returns [code](operand_a, operand_b)[/code] for [param result] under
## [param operation], where applying the operation to the pair yields
## [param result] and both operands fall in [code][1, max_operand][/code].
## [param index] selects which legal pair via round-robin over the window.
## Callers must only pass a [param result] that [method has_valid_pair] accepts;
## a misuse degrades to a clamped best-effort pair rather than crashing.
static func pick(result: int, index: int, max_operand: int, operation: int = Operation.Type.ADD) -> Vector2i:
	match operation:
		Operation.Type.SUBTRACT:
			return _pick_subtract(result, index, max_operand)
		Operation.Type.MULTIPLY:
			return _pick_multiply(result, index, max_operand)
		Operation.Type.DIVIDE:
			return _pick_divide(result, index, max_operand)
		_:
			return _pick_add(result, index, max_operand)


## How many distinct displayed operand pairs [method pick] will cycle for
## [param result] under [param operation] within [param max_operand] — i.e. the
## variety the player sees across equal-result cards. Used to require a minimum
## variety so a prime like 7 (only "1 × 7") is never used as a multiply result.
static func option_count(result: int, max_operand: int, operation: int = Operation.Type.ADD) -> int:
	match operation:
		Operation.Type.SUBTRACT:
			# b in [1, max_operand - result].
			return maxi(0, max_operand - result) if result >= 1 else 0
		Operation.Type.MULTIPLY:
			return _multiply_options(result, max_operand).size()
		Operation.Type.DIVIDE:
			if result < 1:
				return 0
			var b_max: int = int(max_operand / result)
			if b_max < 1:
				return 0
			var b_min: int = 2 if b_max >= 2 else 1
			return b_max - b_min + 1
		_:
			# a in [max(1, r-max), min(max, r-1)] — empty (0) for r <= 1, where the
			# only "pair" is the degenerate (0, r) with an out-of-bounds operand.
			return maxi(0, mini(max_operand, result - 1) - maxi(1, result - max_operand) + 1)


## Whether [param result] has at least one legal operand pair under
## [param operation] within [param max_operand] (GDD Formula 4).
static func has_valid_pair(result: int, max_operand: int, operation: int = Operation.Type.ADD) -> bool:
	return option_count(result, max_operand, operation) >= 1


## The subset of [param allowed] operations that can produce [param result] with at
## least [param min_options] distinct displayed pairs within [param max_operand].
## Empty means [param result] is not a candidate for this world (used by the
## generator to filter results, and per card to pick which operation to print).
## [param min_options] defaults to 1 (any legal pair); the generator passes the
## variety floor (see [member GeneratorParams.min_operand_options]).
static func valid_operations(result: int, max_operand: int, allowed: Array[int], min_options: int = 1) -> Array[int]:
	var ops: Array[int] = []
	for op: int in allowed:
		if option_count(result, max_operand, op) >= min_options:
			ops.append(op)
	return ops


# --- ternary (three-term) picking ------------------------------------------

## Every in-bounds, non-negative, exactly-divisible [code](a, b, c)[/code] triple
## (as [Vector3i]) that evaluates to [param result] under the ternary spec
## ([param op1], [param op2], [param grouping]); see [TernaryExpression]. Operands
## range over [code][1, max_operand][/code] and are enumerated a→b→c ascending, so
## the list is deterministic. The cube of [param max_operand] is tiny at gameplay
## sizes (<= 9), and this runs once per level build, never per frame.
static func triple_options(result: int, max_operand: int, op1: int, op2: int, grouping: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if result < 0:
		return out
	for a in range(1, max_operand + 1):
		for b in range(1, max_operand + 1):
			for c in range(1, max_operand + 1):
				if TernaryExpression.evaluate(a, b, c, op1, op2, grouping) == result:
					out.append(Vector3i(a, b, c))
	return out


## The distinct DISPLAYED three-term exercises for [param result] across
## [param specs] (each a [Vector3i] [code](op1, op2, grouping)[/code]), as an
## [code]Array[Dictionary][/code] with keys [code]a, b, c, op1, op2, grouping[/code].
## Deduped by rendered text (so e.g. a LEFT and a PRECEDENCE "3 + 4 + 5" count
## once) and ordered deterministically (spec order, then a→b→c). The generator
## uses its size for the variety floor and deals cards from it. Empty when no spec
## yields a legal triple for [param result].
static func triple_renderings(result: int, max_operand: int, specs: Array[Vector3i]) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for spec: Vector3i in specs:
		for t: Vector3i in triple_options(result, max_operand, spec.x, spec.y, spec.z):
			var text: String = TernaryExpression.format(t.x, t.y, t.z, spec.x, spec.y, spec.z)
			if seen.has(text):
				continue
			seen[text] = true
			out.append({a = t.x, b = t.y, c = t.z, op1 = spec.x, op2 = spec.y, grouping = spec.z})
	return out


# --- per-operation pickers -------------------------------------------------

# a + b = result. Window over operand_a in [max(1, r-max), min(max, r-1)].
# Unchanged from the original addition-only picker (regression-guarded by AC-28).
static func _pick_add(result: int, index: int, max_operand: int) -> Vector2i:
	if result <= 1:
		return Vector2i(0, maxi(result, 0))
	var a_min: int = maxi(1, result - max_operand)
	var a_max: int = mini(max_operand, result - 1)
	var span: int = a_max - a_min + 1
	# span >= 1 holds whenever the result passed has_valid_pair; guard anyway so a
	# misuse never divides by zero, clamping the fallback into [1, max_operand].
	if span < 1:
		var a_fallback: int = clampi(result - max_operand, 1, max_operand)
		return Vector2i(a_fallback, result - a_fallback)
	var a: int = a_min + (index % span)
	return Vector2i(a, result - a)


# a − b = result, with a = b + result. Window over the subtrahend b in
# [1, max_operand - result] so both operands stay in [1, max_operand].
static func _pick_subtract(result: int, index: int, max_operand: int) -> Vector2i:
	var b_max: int = max_operand - result
	if b_max < 1:
		return Vector2i(result + 1, 1)  # misuse fallback (has_valid_pair rejects this)
	var b: int = 1 + (index % b_max)
	return Vector2i(result + b, b)


# a × b = result. Cycles the full ordered factor list (both orientations), so e.g.
# 12 shows 2×6, 6×2, 3×4, 4×3 — more variety than one orientation.
static func _pick_multiply(result: int, index: int, max_operand: int) -> Vector2i:
	var options: Array[int] = _multiply_options(result, max_operand)
	if options.is_empty():
		return Vector2i(1, maxi(result, 0))  # misuse fallback
	var a: int = options[index % options.size()]
	return Vector2i(a, result / a)


# Every operand a in [1, max_operand] with result % a == 0 and result/a in
# [1, max_operand] — both orientations (a=2,b=6 and a=6,b=2 are distinct displayed
# pairs). Returns the non-trivial options (a >= 2 AND result/a >= 2) when any exist,
# so a board is not all "1 × n"; falls back to the trivial options for primes / no
# other factorisation. Empty when result has no pair under max_operand at all.
static func _multiply_options(result: int, max_operand: int) -> Array[int]:
	if result < 1:
		return []
	var all: Array[int] = []
	var nontrivial: Array[int] = []
	for a in range(1, max_operand + 1):
		if result % a == 0 and int(result / a) <= max_operand:
			all.append(a)
			if a >= 2 and int(result / a) >= 2:
				nontrivial.append(a)
	return nontrivial if not nontrivial.is_empty() else all


# a ÷ b = result, with a = result * b. Window over the divisor b in
# [1, max_operand / result] so the dividend a stays <= max_operand; prefers b >= 2
# so the board is not all "n ÷ 1" when there is room.
static func _pick_divide(result: int, index: int, max_operand: int) -> Vector2i:
	if result < 1:
		return Vector2i(maxi(result, 0), 1)  # misuse fallback
	var b_max: int = int(max_operand / result)
	if b_max < 1:
		return Vector2i(result, 1)  # misuse fallback (has_valid_pair rejects this)
	var b_min: int = 2 if b_max >= 2 else 1
	var span: int = b_max - b_min + 1
	var b: int = b_min + (index % span)
	return Vector2i(result * b, b)
