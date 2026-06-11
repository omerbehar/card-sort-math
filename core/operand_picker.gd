class_name OperandPicker
extends RefCounted
## The single source of truth for splitting a result into a printed addition pair
## (GDD level-generator Formula 3). Pure and node-free.
##
## [method pick] is deterministic in [param index]: cards sharing a result cycle
## through the legal first-operand window so a board is not all "1 + 1". Both the
## generator (with the configured [code]max_operand[/code]) and the authored
## [LevelData] path call this — the authored path passes
## [code]max_operand = result - 1[/code], which reproduces the legacy
## [code]LevelData._split_operands[/code] output exactly, so that method can
## delegate here in a later story (S2-004) without changing authored levels.

## Returns [code](operand_a, operand_b)[/code] for [param result], where
## [code]operand_a + operand_b == result[/code] and both operands fall in
## [code][1, max_operand][/code] when [param result] > 1. The within-result
## [param index] selects which legal pair via round-robin over the window.
## Degenerate [param result] <= 1 returns [code](0, max(result, 0))[/code],
## matching the authored splitter's edge case.
static func pick(result: int, index: int, max_operand: int) -> Vector2i:
	if result <= 1:
		return Vector2i(0, maxi(result, 0))
	var a_min: int = maxi(1, result - max_operand)
	var a_max: int = mini(max_operand, result - 1)
	var span: int = a_max - a_min + 1
	# span >= 1 holds whenever the result passed the candidate filter
	# (has_valid_pair); guard anyway so a misuse never divides by zero.
	if span < 1:
		return Vector2i(1, result - 1)
	var a: int = a_min + (index % span)
	return Vector2i(a, result - a)


## Whether [param result] has at least one legal addition pair under
## [param max_operand] (GDD Formula 4). A result with no valid pair must be
## excluded from the candidate set.
static func has_valid_pair(result: int, max_operand: int) -> bool:
	return maxi(1, result - max_operand) <= mini(max_operand, result - 1)
