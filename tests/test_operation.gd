extends GdUnitTestSuite
## Tests for [Operation] — the pure operator/result/display helpers (GDD
## math-exercises). Glyphs, result computation and formatting per operation.


func test_glyph_per_operation() -> void:
	assert_str(Operation.glyph(Operation.Type.ADD)).is_equal("+")
	assert_str(Operation.glyph(Operation.Type.SUBTRACT)).is_equal("−")
	assert_str(Operation.glyph(Operation.Type.MULTIPLY)).is_equal("×")
	assert_str(Operation.glyph(Operation.Type.DIVIDE)).is_equal("÷")


func test_glyph_unknown_falls_back_to_plus() -> void:
	assert_str(Operation.glyph(999)).is_equal("+")


func test_apply_computes_each_operation() -> void:
	assert_int(Operation.apply(3, 4, Operation.Type.ADD)).is_equal(7)
	assert_int(Operation.apply(7, 3, Operation.Type.SUBTRACT)).is_equal(4)
	assert_int(Operation.apply(2, 5, Operation.Type.MULTIPLY)).is_equal(10)
	assert_int(Operation.apply(12, 3, Operation.Type.DIVIDE)).is_equal(4)


func test_apply_divide_by_zero_returns_zero() -> void:
	# Guard: division never crashes even on a misused zero divisor.
	assert_int(Operation.apply(5, 0, Operation.Type.DIVIDE)).is_equal(0)


func test_format_renders_operands_and_glyph() -> void:
	assert_str(Operation.format(12, 3, Operation.Type.DIVIDE)).is_equal("12 ÷ 3")
	assert_str(Operation.format(6, 2, Operation.Type.SUBTRACT)).is_equal("6 − 2")


func test_all_lists_the_four_operations() -> void:
	assert_array(Operation.ALL).contains_exactly([
		Operation.Type.ADD,
		Operation.Type.SUBTRACT,
		Operation.Type.MULTIPLY,
		Operation.Type.DIVIDE,
	])
