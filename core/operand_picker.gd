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


## Whether [param result] has at least one legal operand pair under
## [param operation] within [param max_operand] (GDD Formula 4). A result with no
## valid pair for the world's operation(s) must be excluded from the candidate set.
static func has_valid_pair(result: int, max_operand: int, operation: int = Operation.Type.ADD) -> bool:
	match operation:
		Operation.Type.SUBTRACT:
			# a − b = result, a = b + result, b >= 1, a <= max_operand.
			return result >= 1 and max_operand - result >= 1
		Operation.Type.MULTIPLY:
			return not _multiply_factors(result, max_operand).is_empty()
		Operation.Type.DIVIDE:
			# a ÷ b = result, a = result * b, b >= 1, a <= max_operand.
			return result >= 1 and int(max_operand / result) >= 1
		_:
			return maxi(1, result - max_operand) <= mini(max_operand, result - 1)


## The subset of [param allowed] operations that can produce [param result]
## within [param max_operand]. Empty means [param result] is not a candidate for
## this world (used by the generator to filter results, and per card to pick which
## operation to print).
static func valid_operations(result: int, max_operand: int, allowed: Array[int]) -> Array[int]:
	var ops: Array[int] = []
	for op: int in allowed:
		if has_valid_pair(result, max_operand, op):
			ops.append(op)
	return ops


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


# a × b = result. Cycles the precomputed factor list (smaller factor first).
static func _pick_multiply(result: int, index: int, max_operand: int) -> Vector2i:
	var factors: Array[int] = _multiply_factors(result, max_operand)
	if factors.is_empty():
		return Vector2i(1, maxi(result, 0))  # misuse fallback
	var a: int = factors[index % factors.size()]
	return Vector2i(a, result / a)


# Smaller operands a (a <= result/a) with a × (result/a) == result and both in
# [1, max_operand]. Returns the non-trivial factors (a >= 2) when any exist, so a
# board is not all "1 × n"; falls back to the trivial [1] for primes / no other
# factorisation. Empty when result has no pair under max_operand at all.
static func _multiply_factors(result: int, max_operand: int) -> Array[int]:
	if result < 1:
		return []
	var all: Array[int] = []
	var nontrivial: Array[int] = []
	var a: int = 1
	while a <= max_operand and a * a <= result:
		if result % a == 0 and int(result / a) <= max_operand:
			all.append(a)
			if a >= 2:
				nontrivial.append(a)
		a += 1
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
