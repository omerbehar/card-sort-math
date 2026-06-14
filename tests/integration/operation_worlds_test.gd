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


func test_two_decks_unlocked_by_default_in_scene() -> void:
	# Default unlock count is 2: stacks 0 and 1 start open, 2 and 3 start locked.
	var runner = await _boot()
	var main = await _start(runner, 1)
	var model = main._model
	assert_bool(model.is_stack_locked(0)).is_false()
	assert_bool(model.is_stack_locked(1)).is_false()
	assert_bool(model.is_stack_locked(2)).is_true()
	assert_bool(model.is_stack_locked(3)).is_true()


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


func test_three_term_addsub_world_renders_two_operator_expression() -> void:
	# Level 21-25: every floor card prints a three-term a ∘ b ∘ c exercise.
	var runner = await _boot()
	var main = await _start(runner, 23)       # three-term add/sub world
	var cards: Dictionary = main._floor._cards
	assert_int(cards.size()).is_greater(0)
	for card in cards.values():
		assert_int(card.card_data.term_count) \
			.override_failure_message("card '%s' is not three-term" % card._label.text).is_equal(3)
		# Two operators ⇒ five whitespace-separated tokens (e.g. "3 + 7 − 4").
		assert_int(card._label.text.split(" ", false).size()).is_greater_equal(5)


func test_parentheses_world_renders_a_parenthesised_card_in_scene() -> void:
	# Level 26-30: at least one floor card shows parentheses.
	var runner = await _boot()
	var main = await _start(runner, 28)
	var cards: Dictionary = main._floor._cards
	var saw_parens := false
	for card in cards.values():
		if card._label.text.contains("("):
			saw_parens = true
	assert_bool(saw_parens) \
		.override_failure_message("no parenthesised card rendered in the parentheses world").is_true()


func test_order_of_operations_world_renders_high_op_glyph_in_scene() -> void:
	# Level 31-40: a × or ÷ appears on the floor, with no parentheses printed.
	var runner = await _boot()
	var main = await _start(runner, 33)
	var cards: Dictionary = main._floor._cards
	var saw_high := false
	for card in cards.values():
		var text: String = card._label.text
		assert_str(text).not_contains("(")
		if text.contains("×") or text.contains("÷"):
			saw_high = true
	assert_bool(saw_high) \
		.override_failure_message("no ×/÷ card rendered in the order-of-operations world").is_true()
