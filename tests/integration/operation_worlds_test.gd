extends GdUnitTestSuite
## Integration tests — drive the REAL Main scene (full node tree + autoloads) to
## prove the operation worlds wire end to end: starting a level in a subtraction /
## multiplication / division / mixed world builds a board whose card view labels
## render the right operator glyph, and that such a board is still playable
## (a tap routes/discards through the live model↔view seam).
##
## Headless/CI-safe: cards and signals run in the live tree, no display needed.
## Source: design/gdd/math-exercises.md (operations); ADR-0001 (model/view seam),
## ADR-0007 (operation worlds / generated levels).

const MAIN := "res://scenes/main/main.tscn"


# Loads Main, suppresses the tutorial coach, and settles a few frames.
func _boot() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


# Starts level [param n] and returns the live Main controller.
func _start(runner: Variant, n: int) -> Variant:
	var main = runner.scene()
	main.start_level(n)
	await runner.simulate_frames(5)
	return main


# Asserts every floor card in the live scene prints [param glyph] on its label
# (proving model.operation -> CardData.exercise_text -> Card._label end to end).
func _assert_floor_glyph(main: Variant, glyph: String) -> void:
	var cards: Dictionary = main._floor._cards
	assert_int(cards.size()).is_greater(0)
	for card in cards.values():
		assert_str(card._label.text) \
			.override_failure_message("card label '%s' missing glyph '%s'" % [card._label.text, glyph]) \
			.contains(glyph)


func test_subtraction_world_renders_minus_glyph_in_scene() -> void:
	var runner = await _boot()
	var main = await _start(runner, 8)        # world 1 = subtraction
	_assert_floor_glyph(main, "−")


func test_multiplication_world_renders_times_glyph_in_scene() -> void:
	var runner = await _boot()
	var main = await _start(runner, 13)       # world 2 = multiplication
	_assert_floor_glyph(main, "×")


func test_division_world_renders_divide_glyph_in_scene() -> void:
	var runner = await _boot()
	var main = await _start(runner, 18)       # world 3 = division
	_assert_floor_glyph(main, "÷")


func test_operation_world_board_is_playable_in_scene() -> void:
	# A subtraction-world board still routes/discards a tap through the real seam.
	var runner = await _boot()
	var main = await _start(runner, 8)
	var model = main._model
	var exposed: Array[int] = model.exposed_cards()
	assert_bool(exposed.is_empty()).is_false()
	var cid: int = exposed[0]
	main._on_card_tapped(cid)
	await runner.simulate_frames(30)          # let the fly animation finish
	assert_bool(model.is_card_removed(cid)).is_true()


func test_mixed_world_renders_multiple_glyphs_in_scene() -> void:
	var runner = await _boot()
	var main = await _start(runner, 25)       # mixed world
	var cards: Dictionary = main._floor._cards
	var glyphs_seen: Dictionary = {}
	for card in cards.values():
		glyphs_seen[Operation.glyph(card.card_data.operation)] = true
	assert_int(glyphs_seen.size()).is_greater(1)
