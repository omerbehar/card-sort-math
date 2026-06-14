extends GdUnitTestSuite
## Tests for [OperandPicker] — operation-aware operand splitting (GDD
## level-generator Formula 3/4, GDD math-exercises). Proves that for every
## operation the picked pair (a) applies back to the requested result, (b) stays
## within [1, max_operand], and (c) cycles deterministically over its window.

const MAX_OPERAND := 10


# For [param op], every result the picker accepts must yield an in-bounds pair
# whose operation evaluates back to the result, for several round-robin indices.
func _assert_picks_are_correct(op: int) -> void:
	for result in range(1, 30):
		if not OperandPicker.has_valid_pair(result, MAX_OPERAND, op):
			continue
		for index in range(0, 12):
			var pair := OperandPicker.pick(result, index, MAX_OPERAND, op)
			assert_int(Operation.apply(pair.x, pair.y, op)) \
				.override_failure_message("op %d, result %d, index %d -> (%d,%d)"
					% [op, result, index, pair.x, pair.y]).is_equal(result)
			assert_bool(pair.x >= 1 and pair.x <= MAX_OPERAND).is_true()
			assert_bool(pair.y >= 1 and pair.y <= MAX_OPERAND).is_true()


func test_addition_picks_are_correct_and_in_bounds() -> void:
	_assert_picks_are_correct(Operation.Type.ADD)


func test_subtraction_picks_are_correct_and_in_bounds() -> void:
	_assert_picks_are_correct(Operation.Type.SUBTRACT)


func test_multiplication_picks_are_correct_and_in_bounds() -> void:
	_assert_picks_are_correct(Operation.Type.MULTIPLY)


func test_division_picks_are_correct_and_in_bounds() -> void:
	_assert_picks_are_correct(Operation.Type.DIVIDE)


func test_addition_default_matches_legacy_split() -> void:
	# Authored path: max_operand = result - 1 reproduces the legacy split exactly.
	assert_vector(OperandPicker.pick(7, 0, 6)).is_equal(Vector2i(1, 6))
	assert_vector(OperandPicker.pick(7, 1, 6)).is_equal(Vector2i(2, 5))
	assert_vector(OperandPicker.pick(7, 2, 6)).is_equal(Vector2i(3, 4))


func test_has_valid_pair_subtraction_rejects_result_at_or_above_max() -> void:
	# a − b = result needs b >= 1 with a = b + result <= max_operand.
	assert_bool(OperandPicker.has_valid_pair(5, 10, Operation.Type.SUBTRACT)).is_true()
	assert_bool(OperandPicker.has_valid_pair(10, 10, Operation.Type.SUBTRACT)).is_false()


func test_has_valid_pair_multiplication_rejects_unfactorable_result() -> void:
	# 11 is prime and > max_operand 8, so it has no in-bounds factor pair.
	assert_bool(OperandPicker.has_valid_pair(12, 8, Operation.Type.MULTIPLY)).is_true()
	assert_bool(OperandPicker.has_valid_pair(11, 8, Operation.Type.MULTIPLY)).is_false()


func test_has_valid_pair_division_rejects_result_above_max() -> void:
	assert_bool(OperandPicker.has_valid_pair(8, 8, Operation.Type.DIVIDE)).is_true()
	assert_bool(OperandPicker.has_valid_pair(9, 8, Operation.Type.DIVIDE)).is_false()


func test_multiplication_prefers_nontrivial_factors() -> void:
	# 12 with max 8: prefer 2×6 / 3×4 over the trivial 1×12 (which is also illegal here).
	var pair := OperandPicker.pick(12, 0, 8, Operation.Type.MULTIPLY)
	assert_bool(pair.x >= 2 and pair.y >= 2) \
		.override_failure_message("got trivial pair (%d,%d)" % [pair.x, pair.y]).is_true()


func test_division_prefers_nontrivial_divisor_when_possible() -> void:
	# result 2, max 10: divisor window [2,5] -> never "n ÷ 1".
	var pair := OperandPicker.pick(2, 0, 10, Operation.Type.DIVIDE)
	assert_int(pair.y).is_greater_equal(2)


func test_valid_operations_filters_allowed_to_those_with_pairs() -> void:
	# result 5, max 6: + (1+4..), − (b in [1]), × (1×5), ÷ (5÷1) all valid.
	var ops := OperandPicker.valid_operations(5, 6, Operation.ALL)
	assert_array(ops).contains([Operation.Type.ADD, Operation.Type.SUBTRACT])
	# result 7, max 6: addition only (7 > max for −/÷, prime 7 > max for ×).
	var only_add := OperandPicker.valid_operations(7, 6, Operation.ALL)
	assert_array(only_add).contains_exactly([Operation.Type.ADD])


func test_pick_is_deterministic() -> void:
	for op: int in Operation.ALL:
		if OperandPicker.has_valid_pair(8, MAX_OPERAND, op):
			assert_vector(OperandPicker.pick(8, 3, MAX_OPERAND, op)) \
				.is_equal(OperandPicker.pick(8, 3, MAX_OPERAND, op))
