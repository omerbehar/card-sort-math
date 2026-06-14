extends GdUnitTestSuite
## Tests for [CardData].


func test_create_computes_result_as_sum() -> void:
	var card := CardData.create(3, 4, 1, 2)
	assert_int(card.operand_a).is_equal(3)
	assert_int(card.operand_b).is_equal(4)
	assert_int(card.result).is_equal(7)
	assert_int(card.layout_layer).is_equal(1)
	assert_int(card.layout_slot).is_equal(2)


func test_result_is_never_negative_for_positive_operands() -> void:
	for a in range(0, 10):
		for b in range(0, 10):
			var card := CardData.create(a, b, 0, 0)
			assert_int(card.result).is_greater_equal(0)


func test_exercise_text() -> void:
	assert_str(CardData.create(2, 5, 0, 0).exercise_text()).is_equal("2 + 5")


func test_create_defaults_to_addition() -> void:
	var card := CardData.create(2, 5, 0, 0)
	assert_int(card.operation).is_equal(Operation.Type.ADD)


func test_create_subtraction_computes_difference() -> void:
	var card := CardData.create(7, 3, 1, 2, Operation.Type.SUBTRACT)
	assert_int(card.result).is_equal(4)
	assert_int(card.operation).is_equal(Operation.Type.SUBTRACT)
	assert_str(card.exercise_text()).is_equal("7 − 3")


func test_create_multiplication_computes_product() -> void:
	var card := CardData.create(2, 5, 0, 0, Operation.Type.MULTIPLY)
	assert_int(card.result).is_equal(10)
	assert_str(card.exercise_text()).is_equal("2 × 5")


func test_create_division_computes_quotient() -> void:
	var card := CardData.create(12, 3, 0, 0, Operation.Type.DIVIDE)
	assert_int(card.result).is_equal(4)
	assert_str(card.exercise_text()).is_equal("12 ÷ 3")


func test_create_defaults_to_two_terms() -> void:
	assert_int(CardData.create(2, 5, 0, 0).term_count).is_equal(2)


func test_create_ternary_computes_result_and_text() -> void:
	# 3 + 7 − 4 = 6, left-to-right.
	var card := CardData.create_ternary(
		3, 7, 4, Operation.Type.ADD, Operation.Type.SUBTRACT, TernaryExpression.Grouping.LEFT, 1, 2)
	assert_int(card.term_count).is_equal(3)
	assert_int(card.operand_c).is_equal(4)
	assert_int(card.operation2).is_equal(Operation.Type.SUBTRACT)
	assert_int(card.result).is_equal(6)
	assert_str(card.exercise_text()).is_equal("3 + 7 − 4")
	assert_int(card.layout_layer).is_equal(1)
	assert_int(card.layout_slot).is_equal(2)


func test_create_ternary_respects_grouping_in_text_and_result() -> void:
	# 10 − (3 + 2) = 5.
	var card := CardData.create_ternary(
		10, 3, 2, Operation.Type.SUBTRACT, Operation.Type.ADD, TernaryExpression.Grouping.PAREN_RIGHT, 0, 0)
	assert_int(card.result).is_equal(5)
	assert_str(card.exercise_text()).is_equal("10 − (3 + 2)")


func test_create_ternary_precedence_text_has_no_parentheses() -> void:
	# 2 + 3 × 4 = 14, printed bare.
	var card := CardData.create_ternary(
		2, 3, 4, Operation.Type.ADD, Operation.Type.MULTIPLY, TernaryExpression.Grouping.PRECEDENCE, 0, 0)
	assert_int(card.result).is_equal(14)
	assert_str(card.exercise_text()).is_equal("2 + 3 × 4")
