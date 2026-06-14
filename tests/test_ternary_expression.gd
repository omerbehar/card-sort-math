extends GdUnitTestSuite
## Tests for [TernaryExpression] — pure three-term evaluation/formatting helpers
## (GDD math-exercises, multi-term teaching worlds). Proves each grouping
## evaluates and renders correctly, that precedence resolves ×/÷ before +/−, and
## that illegal triples (negative mid-step, divide-by-zero, inexact division) are
## rejected with [constant TernaryExpression.INVALID].

const ADD := Operation.Type.ADD
const SUB := Operation.Type.SUBTRACT
const MUL := Operation.Type.MULTIPLY
const DIV := Operation.Type.DIVIDE
const G := TernaryExpression.Grouping


func test_left_grouping_evaluates_and_formats_left_to_right() -> void:
	# 3 + 7 − 4 = 6, printed without parentheses.
	assert_int(TernaryExpression.evaluate(3, 7, 4, ADD, SUB, G.LEFT)).is_equal(6)
	assert_str(TernaryExpression.format(3, 7, 4, ADD, SUB, G.LEFT)).is_equal("3 + 7 − 4")


func test_left_grouping_order_does_not_change_result() -> void:
	# The 21-25 lesson: 5 + 7 − 4 and 5 − 4 + 7 are the same value (both kept
	# non-negative at every step, so both are legal exercises).
	assert_int(TernaryExpression.evaluate(5, 7, 4, ADD, SUB, G.LEFT)).is_equal(8)
	assert_int(TernaryExpression.evaluate(5, 4, 7, SUB, ADD, G.LEFT)).is_equal(8)


func test_paren_left_matches_left_value_but_shows_parentheses() -> void:
	assert_int(TernaryExpression.evaluate(3, 7, 4, ADD, SUB, G.PAREN_LEFT)).is_equal(6)
	assert_str(TernaryExpression.format(3, 7, 4, ADD, SUB, G.PAREN_LEFT)).is_equal("(3 + 7) − 4")


func test_paren_right_changes_grouping() -> void:
	# 10 − (3 + 2) = 5, distinct from (10 − 3) + 2 = 9 — the parentheses lesson.
	assert_int(TernaryExpression.evaluate(10, 3, 2, SUB, ADD, G.PAREN_RIGHT)).is_equal(5)
	assert_str(TernaryExpression.format(10, 3, 2, SUB, ADD, G.PAREN_RIGHT)).is_equal("10 − (3 + 2)")
	assert_int(TernaryExpression.evaluate(10, 3, 2, SUB, ADD, G.PAREN_LEFT)).is_equal(9)


func test_precedence_evaluates_high_op_first_without_parentheses() -> void:
	# 2 + 3 × 4 = 14 (not 20), and it is printed bare to teach the order of operations.
	assert_int(TernaryExpression.evaluate(2, 3, 4, ADD, MUL, G.PRECEDENCE)).is_equal(14)
	assert_str(TernaryExpression.format(2, 3, 4, ADD, MUL, G.PRECEDENCE)).is_equal("2 + 3 × 4")


func test_precedence_with_leading_high_op_is_left_to_right() -> void:
	# 3 × 4 + 2 = 14: the high op is already first, so evaluation is left-to-right.
	assert_int(TernaryExpression.evaluate(3, 4, 2, MUL, ADD, G.PRECEDENCE)).is_equal(14)


func test_precedence_same_precedence_ops_left_to_right() -> void:
	# 8 ÷ 4 × 2 = 4 (left-to-right), not 8 ÷ 8 = 1.
	assert_int(TernaryExpression.evaluate(8, 4, 2, DIV, MUL, G.PRECEDENCE)).is_equal(4)


func test_negative_intermediate_is_rejected() -> void:
	# (3 − 7) … would go negative mid-step.
	assert_int(TernaryExpression.evaluate(3, 7, 1, SUB, ADD, G.LEFT)).is_equal(TernaryExpression.INVALID)
	assert_bool(TernaryExpression.is_valid(3, 7, 1, SUB, ADD, G.LEFT)).is_false()


func test_negative_final_is_rejected() -> void:
	# 2 + 3 − 9 = −4: legal mid-step, negative final.
	assert_int(TernaryExpression.evaluate(2, 3, 9, ADD, SUB, G.LEFT)).is_equal(TernaryExpression.INVALID)


func test_inexact_division_is_rejected() -> void:
	# 2 + 7 ÷ 2: 7 ÷ 2 is not a whole number.
	assert_int(TernaryExpression.evaluate(2, 7, 2, ADD, DIV, G.PRECEDENCE)).is_equal(TernaryExpression.INVALID)


func test_exact_division_is_accepted() -> void:
	# 2 + 8 ÷ 4 = 4.
	assert_int(TernaryExpression.evaluate(2, 8, 4, ADD, DIV, G.PRECEDENCE)).is_equal(4)


func test_divide_by_zero_intermediate_is_rejected() -> void:
	# a ÷ (b − c) with b == c divides by zero.
	assert_int(TernaryExpression.evaluate(6, 3, 3, DIV, SUB, G.PAREN_RIGHT)).is_equal(TernaryExpression.INVALID)


func test_effective_grouping_resolves_precedence() -> void:
	assert_int(TernaryExpression.effective_grouping(ADD, MUL, G.PRECEDENCE)).is_equal(G.PAREN_RIGHT)
	assert_int(TernaryExpression.effective_grouping(MUL, ADD, G.PRECEDENCE)).is_equal(G.PAREN_LEFT)
	# Non-precedence groupings pass through unchanged.
	assert_int(TernaryExpression.effective_grouping(ADD, SUB, G.PAREN_RIGHT)).is_equal(G.PAREN_RIGHT)
