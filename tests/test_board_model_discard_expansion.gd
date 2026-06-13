extends GdUnitTestSuite
## Tests for the Extra Discard Slot BoardModel change (ADR-0010 / S3-006).
##
## Verifies the mutable _active_discard_slots: expand_discard() appends one empty
## slot (uncapped — the cap lives in WalletService), the live-discard loops
## (_first_empty_discard, _pull_matching) honour the expanded length, and the
## new queries report correctly. All boards are pure BoardModel instances.
## Source: design/gdd/deck-economy.md Core Rule 11, AC-E01; ADR-0010.


## Builds a fully-exposed board (no coverage) from results + target queue.
func _open(results: Array[int], queue: Array[int]) -> BoardModel:
	var covered_by: Dictionary = {}
	for i in results.size():
		covered_by[i] = [] as Array[int]
	return BoardModel.new(results, covered_by, queue)


# --- queries + expand_discard (AC-E01) ---

func test_active_discard_slots_defaults_to_base_constant() -> void:
	var board := _open([99], [1, 2, 3, 4])
	assert_int(board.active_discard_slots()).is_equal(BoardModel.DISCARD_SLOTS)   # 5


func test_expand_discard_appends_one_empty_slot() -> void:
	# AC-E01: 5 → 6; the new slot is empty (-1).
	var board := _open([99], [1, 2, 3, 4])
	board.expand_discard()
	assert_int(board.active_discard_slots()).is_equal(6)
	assert_int(board.discard_card(5)).is_equal(-1)   # new slot empty


func test_expand_discard_is_uncapped_can_reach_seven() -> void:
	# BoardModel itself imposes no cap (MAX_DISCARD_SLOTS is enforced by WalletService).
	var board := _open([99], [1, 2, 3, 4])
	board.expand_discard()
	board.expand_discard()
	assert_int(board.active_discard_slots()).is_equal(7)
	assert_int(board.discard_card(6)).is_equal(-1)


func test_occupied_discard_count_reflects_filled_slots() -> void:
	# 3 result-99 cards discard (no stack targets 99) → occupied == 3, capacity 5.
	var board := _open([99, 99, 99], [1, 2, 3, 4])
	board.tap_card(0)
	board.tap_card(1)
	assert_int(board.occupied_discard_count()).is_equal(2)
	board.tap_card(2)
	assert_int(board.occupied_discard_count()).is_equal(3)
	assert_int(board.active_discard_slots()).is_equal(5)


# --- _first_empty_discard honours the expanded length ---

func test_discard_into_expanded_slot_after_base_is_full() -> void:
	# Fill all 5 base slots, expand, then a 6th discard must land in the new slot 5
	# (proving _first_empty_discard scans the expanded length, not the constant).
	# A 7th card (result 99) stays on the floor so the board does not win.
	var board := _open([99, 99, 99, 99, 99, 99], [1, 2, 3, 4])
	for i in 5:
		board.tap_card(i)                       # fill discard slots 0..4
	assert_int(board.occupied_discard_count()).is_equal(5)
	board.expand_discard()                       # 5 → 6
	board.tap_card(5)                            # 6th discard → new slot 5
	assert_int(board.discard_card(5)).is_equal(5)
	assert_bool(board.is_lost()).is_false()      # not a LOSE — there was room


# --- _pull_matching honours the expanded length ---

func test_pull_matching_scans_expanded_slot() -> void:
	# Prove _pull_matching iterates the expanded length: only the card in the
	# appended slot 5 matches the cleared stack's new target, so it must be pulled.
	#
	# Layout: stacks seed [1,2,3,4]; queue's 5th entry (7) is drawn when a stack clears.
	#   cards 0-2: result 1  → route into stack 0, filling + clearing it
	#   cards 3-7: result 9  → discard into base slots 0-4 (non-matching filler)
	#   card  8:   result 7  → discarded into the EXPANDED slot 5
	#   card  9:   result 99 → stays on the floor (prevents an early win)
	var results: Array[int] = [1, 1, 1, 9, 9, 9, 9, 9, 7, 99]
	var board := _open(results, [1, 2, 3, 4, 7])
	# Fill the 5 base discard slots with the non-matching result-9 cards.
	for i in range(3, 8):
		board.tap_card(i)
	assert_int(board.occupied_discard_count()).is_equal(5)
	# Expand and discard the result-7 card into the new slot 5.
	board.expand_discard()
	board.tap_card(8)
	assert_int(board.discard_card(5)).is_equal(8)
	# Route three result-1 cards → stack 0 fills, clears, draws target 7, and
	# _pull_matching pulls the result-7 card out of the expanded slot 5.
	board.tap_card(0)
	board.tap_card(1)
	board.tap_card(2)
	assert_int(board.discard_card(5)).is_equal(-1)     # pulled from the expanded slot
	assert_int(board.stack_count(0)).is_equal(1)       # into the cleared stack
	assert_bool(board.is_lost()).is_false()


# --- inert at base: existing behaviour unchanged when never expanded ---

func test_sixth_discard_without_expansion_still_loses() -> void:
	# Regression guard: with no expansion, a 6th discard with all 5 slots full is a
	# LOSE exactly as before (the change is inert at 5 slots).
	var board := _open([99, 99, 99, 99, 99, 99], [1, 2, 3, 4])
	for i in 5:
		board.tap_card(i)                       # slots 0..4 full
	board.tap_card(5)                            # nowhere to go → LOSE
	assert_bool(board.is_lost()).is_true()
