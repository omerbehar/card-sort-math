extends GdUnitTestSuite
## Property tests for the hand-authored [Layouts] presets.
##
## The load-bearing invariant: within a single layer, cards must NOT overlap each
## other (only cross-layer coverage may overlap — that is the exposure mechanic,
## see [Exposure]). A same-layer overlap is a pure visual bug: the cards render on
## top of each other but neither covers the other (`test_same_layer_never_covers`).

const CARD_W := Layouts.CARD_W
const CARD_H := Layouts.CARD_H


# Two card rects overlap iff they overlap on BOTH axes (axis-aligned, equal size).
func _overlaps(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) < CARD_W and absf(a.y - b.y) < CARD_H


func test_no_two_cards_in_the_same_layer_overlap() -> void:
	for layout_id in Layouts.SLOT_COUNTS.size():
		var placements := Layouts.get_layout(layout_id)
		for i in placements.size():
			for j in range(i + 1, placements.size()):
				if int(placements[i].layer) != int(placements[j].layer):
					continue
				var pi: Vector2 = placements[i].pos
				var pj: Vector2 = placements[j].pos
				assert_bool(_overlaps(pi, pj)) \
					.override_failure_message(
						"layout %d: same-layer cards overlap — slot %d %s and slot %d %s"
						% [layout_id, i, str(pi), j, str(pj)]) \
					.is_false()


func test_placement_counts_match_slot_counts() -> void:
	for layout_id in Layouts.SLOT_COUNTS.size():
		assert_int(Layouts.get_layout(layout_id).size()).is_equal(Layouts.SLOT_COUNTS[layout_id])
