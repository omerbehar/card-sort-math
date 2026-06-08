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
