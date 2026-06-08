extends GdUnitTestSuite
## Tests for [Exposure] — the pure coverage/exposure logic.


# Two overlapping cards on different layers: the higher covers the lower.
func _two_overlapping() -> Array:
	return [
		{pos = Vector2(0, 0), layer = 0},
		{pos = Vector2(10, 10), layer = 1},
	]


func test_higher_card_covers_overlapping_lower_card() -> void:
	var covered_by := Exposure.compute_covered_by(_two_overlapping())
	assert_array(covered_by[0]).contains_exactly([1])
	assert_array(covered_by[1]).is_empty()


func test_non_overlapping_cards_do_not_cover() -> void:
	var placements := [
		{pos = Vector2(0, 0), layer = 0},
		{pos = Vector2(500, 500), layer = 1},
	]
	var covered_by := Exposure.compute_covered_by(placements)
	assert_array(covered_by[0]).is_empty()
	assert_array(covered_by[1]).is_empty()


func test_same_layer_never_covers() -> void:
	var placements := [
		{pos = Vector2(0, 0), layer = 1},
		{pos = Vector2(10, 10), layer = 1},
	]
	var covered_by := Exposure.compute_covered_by(placements)
	assert_array(covered_by[0]).is_empty()
	assert_array(covered_by[1]).is_empty()


func test_card_exposed_only_after_all_coverers_removed() -> void:
	var covered_by := Exposure.compute_covered_by(_two_overlapping())
	var removed: Dictionary = {}
	assert_bool(Exposure.is_exposed(0, removed, covered_by)).is_false()
	assert_bool(Exposure.is_exposed(1, removed, covered_by)).is_true()

	removed[1] = true
	assert_bool(Exposure.is_exposed(0, removed, covered_by)).is_true()


func test_exposed_cards_lists_uncovered_only() -> void:
	var covered_by := Exposure.compute_covered_by(_two_overlapping())
	assert_array(Exposure.exposed_cards({}, covered_by)).contains_exactly([1])
