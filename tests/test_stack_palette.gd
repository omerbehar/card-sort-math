extends GdUnitTestSuite
## Tests for [StackPalette] — the pure default vs colorblind stack skin mapping
## that backs the colorblind accessibility mode (S1-011).

const NEUTRAL := "kenney/slot_grey.png"


func test_default_palette_uses_coloured_slots_at_white_tint() -> void:
	# Default skin keeps the four pre-coloured Kenney slots, untinted.
	assert_str(StackPalette.slot_file(0, false)).is_equal("kenney/slot_red.png")
	assert_str(StackPalette.slot_file(1, false)).is_equal("kenney/slot_yellow.png")
	assert_str(StackPalette.slot_file(2, false)).is_equal("kenney/slot_green.png")
	assert_str(StackPalette.slot_file(3, false)).is_equal("kenney/slot_blue.png")
	assert_object(StackPalette.tint(0, false)).is_equal(Color.WHITE)
	assert_object(StackPalette.tint(3, false)).is_equal(Color.WHITE)


func test_colorblind_palette_tints_a_neutral_slot() -> void:
	# Colorblind skin swaps to one grey slot, distinguished by tint alone.
	for i in 4:
		assert_str(StackPalette.slot_file(i, true)).is_equal(NEUTRAL)
	# Okabe-Ito anchors: blue (index 0) and bluish-green (index 2) are not the
	# red/green confusion pair the default palette uses.
	assert_object(StackPalette.tint(0, true)).is_equal(Color(0.0, 0.447, 0.698))
	assert_object(StackPalette.tint(2, true)).is_equal(Color(0.0, 0.620, 0.451))


func test_colorblind_tints_are_mutually_distinct() -> void:
	var seen: Array[Color] = []
	for i in 4:
		var c: Color = StackPalette.tint(i, true)
		assert_bool(seen.has(c)).is_false()
		seen.append(c)


func test_index_wraps_for_both_palettes() -> void:
	assert_str(StackPalette.slot_file(4, false)).is_equal(StackPalette.slot_file(0, false))
	assert_object(StackPalette.tint(4, true)).is_equal(StackPalette.tint(0, true))
