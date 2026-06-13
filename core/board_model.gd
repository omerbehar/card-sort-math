class_name BoardModel
extends RefCounted
## Pure game state + rules for one level. No [Node], no scene tree.
##
## [method tap_card] is the single entry point: it mutates state instantly and
## returns an ordered [code]Array[GameEvent][/code] describing routing, stack
## fills/clears, discard pull-backs and the full cascade. The view replays the
## events as animations. Because the model is deterministic and node-free it is
## fully unit-testable (see [code]tests/test_board_model.gd[/code]).

const STACK_COUNT: int = 4
const STACK_CAPACITY: int = 3
const DISCARD_SLOTS: int = 5
const NO_TARGET: int = -1
## Max permutations the Reshuffle booster tries to satisfy the routable-card
## guarantee (Core Rule 10 / AC-R09) before falling back to the last layout.
const RESHUFFLE_TRIES: int = 32

# --- immutable level data ---
var _result_of: Array[int] = []        # card_id -> printed result
var _covered_by: Dictionary = {}       # card_id -> Array[int] of coverers
var _target_queue: Array[int] = []

# --- mutable state ---
var _removed: Dictionary = {}          # card_id -> true once off the floor
var _stack_targets: Array[int] = []    # per stack, NO_TARGET when inactive
var _stack_counts: Array[int] = []     # per stack, 0..STACK_CAPACITY
var _locked: Array[bool] = []          # per stack (prototype: locked-decks)
var _discard: Array[int] = []          # slot -> card_id, or -1 when empty
# Live discard capacity (ADR-0010). Initialised to DISCARD_SLOTS (the base/reset
# value) and grown one slot at a time by expand_discard() (Extra Discard Slot
# booster). All three live-discard loops iterate this field, not the constant, so
# the array and its capacity stay in lockstep. Resets to DISCARD_SLOTS every level
# because a fresh BoardModel is built per level (AC-E03).
var _active_discard_slots: int = DISCARD_SLOTS
var _draw_index: int = STACK_COUNT     # next unused target_queue entry
var _total_cards: int = 0
var _won: bool = false
var _lost: bool = false


## Low-level constructor. [param results] maps card_id -> result, [param
## covered_by] is the exposure graph (see [Exposure]), [param target_queue] is
## the ordered target list whose first [constant STACK_COUNT] entries seed the
## stacks. [param open_count] (prototype: locked-decks) is how many stacks start
## OPEN; the rest start locked with no target until [method unlock_stack] opens
## them. Defaults to [constant STACK_COUNT] so all existing callers/tests behave
## exactly as before.
func _init(results: Array[int], covered_by: Dictionary, target_queue: Array[int],
		open_count: int = STACK_COUNT) -> void:
	_result_of = results
	_covered_by = covered_by
	_target_queue = target_queue
	_total_cards = results.size()

	var open: int = clampi(open_count, 0, STACK_COUNT)
	_stack_targets = []
	_stack_counts = []
	_locked = []
	for i in STACK_COUNT:
		var is_open: bool = i < open
		_stack_targets.append(_target_queue[i] if (is_open and i < _target_queue.size()) else NO_TARGET)
		_stack_counts.append(0)
		_locked.append(not is_open)
	# Open stacks have consumed the first `open` queue entries; the next unlock
	# (or stack clear) draws from here.
	_draw_index = open

	_discard = []
	for _i in _active_discard_slots:   # base DISCARD_SLOTS at construction (ADR-0010)
		_discard.append(-1)


## Convenience constructor that derives the exposure graph from the level's
## layout preset. [param open_count] (prototype) is how many stacks start open.
static func from_config(config: LevelConfig, open_count: int = STACK_COUNT) -> BoardModel:
	var results: Array[int] = []
	for card: CardData in config.card_pool:
		results.append(card.result)
	var placements := Layouts.get_layout(config.layout_id)
	var covered_by := Exposure.compute_covered_by(placements)
	return BoardModel.new(results, covered_by, config.target_queue, open_count)


# --- queries ---

func result_of(card_id: int) -> int:
	return _result_of[card_id]

func stack_target(stack_index: int) -> int:
	return _stack_targets[stack_index]

func stack_count(stack_index: int) -> int:
	return _stack_counts[stack_index]

## Whether [param stack_index] is still locked (prototype: locked-decks).
func is_stack_locked(stack_index: int) -> bool:
	return _locked[stack_index]

func discard_card(slot: int) -> int:
	return _discard[slot]

## Current discard capacity (live, post-expansion). Used by the view layout and by
## the economy precondition for the Extra Discard Slot booster (ADR-0010).
func active_discard_slots() -> int:
	return _active_discard_slots

## Count of occupied discard slots. Drives the purchase-ahead precondition (EC-06):
## Extra Discard Slot is blocked when this equals [method active_discard_slots]
## (the row is full — buy earlier, no room to expand into now).
func occupied_discard_count() -> int:
	var n: int = 0
	for slot in _active_discard_slots:
		if _discard[slot] != -1:
			n += 1
	return n

## Appends one empty discard slot (Extra Discard Slot booster, Core Rule 11).
## [b]UNCAPPED by design[/b]: the [code]MAX_DISCARD_SLOTS[/code] policy is enforced by
## the caller ([WalletService]), keeping [BoardModel] free of economy config (ADR-0010).
## Per-level: a fresh BoardModel is built each level, so capacity resets to
## [constant DISCARD_SLOTS] naturally (AC-E03).
func expand_discard() -> void:
	_active_discard_slots += 1
	_discard.append(-1)

func is_card_removed(card_id: int) -> bool:
	return _removed.has(card_id)

func floor_count() -> int:
	return _total_cards - _removed.size()

func is_won() -> bool:
	return _won

func is_lost() -> bool:
	return _lost

func is_game_over() -> bool:
	return _won or _lost

func is_exposed(card_id: int) -> bool:
	return Exposure.is_exposed(card_id, _removed, _covered_by)

func exposed_cards() -> Array[int]:
	return Exposure.exposed_cards(_removed, _covered_by)


## Number of currently-unexposed cards that would become exposed if [param card_id]
## were removed now (i.e. cards for which card_id is the last remaining coverer).
## Used by the Hint booster's scoring (Formula 5 opens_new_cards). Read-only; pure.
func newly_exposed_count(card_id: int) -> int:
	if _removed.has(card_id):
		return 0
	var count: int = 0
	for other: int in _covered_by:
		if other == card_id or _removed.has(other):
			continue
		var coverers: Array = _covered_by[other]
		if not coverers.has(card_id):
			continue
		# `other` is covered by card_id and not removed -> not currently exposed.
		# It becomes exposed iff every OTHER coverer is already removed.
		var still_covered: bool = false
		for c: int in coverers:
			if c != card_id and not _removed.has(c):
				still_covered = true
				break
		if not still_covered:
			count += 1
	return count


## Resolves a tap on [param card_id]. Returns the ordered events to animate, or
## an empty array if the tap is a no-op (card already gone, not exposed, or the
## game is over).
func tap_card(card_id: int) -> Array[GameEvent]:
	if is_game_over():
		return []
	if _removed.has(card_id):
		return []
	if not is_exposed(card_id):
		return []
	return _resolve_play(card_id)


## Picker booster: plays a [b]covered[/b] card regardless of coverage — the only
## way to act on a card that is not yet exposed. Resolution is identical to a tap
## (route to a matching open stack, else discard, then cascade); only the exposure
## precondition is skipped. A no-op when the card is gone or the game is over.
## The economy layer ([method WalletService.use_picker]) gates this behind a spend.
## Source: design/gdd/deck-economy.md (Picker booster — replaces Hint).
func pick_card(card_id: int) -> Array[GameEvent]:
	if is_game_over():
		return []
	if _removed.has(card_id):
		return []
	return _resolve_play(card_id)


## Reshuffle booster (Core Rule 10 / Formula 6): re-permutes the coverage of the
## cards still on the floor. Preserves results, target queue, removed set, stacks,
## discard, and draw index (AC-R01/R02); solvability is preserved trivially since
## results and queue are untouched (AC-R03).
##
## [param placements] is the level's layout ([code]{pos, layer}[/code] per card_id —
## passed in because [code]core/[/code] never loads resources). [param rng] is a
## caller-seeded generator ([ReshuffleSeed.mix] → [code]rng.seed[/code]) so the
## permutation is deterministic and platform-stable (AC-R04/R08). The layout is
## re-rolled up to [constant RESHUFFLE_TRIES] times to guarantee at least one
## exposed card routes directly or opens coverage (AC-R09), so the board is never
## immediately stuck after a reshuffle.
##
## Returns the new placement→card assignment ([code]Array[int][/code], index =
## placement, value = card_id, [code]-1[/code] = empty/removed) so callers and
## tests can compare layouts across seeds.
func reshuffle(placements: Array, rng: RandomNumberGenerator) -> Array[int]:
	var occupied: Array[int] = []          # placement indices still holding a floor card
	for i in _result_of.size():
		if not _removed.has(i):
			occupied.append(i)
	var placement_cover: Dictionary = Exposure.compute_covered_by(placements)
	var applied: Array[int] = []
	for _attempt in RESHUFFLE_TRIES:
		var cards: Array[int] = occupied.duplicate()
		_shuffle_ints(cards, rng)
		var card_at: Dictionary = {}        # placement index -> card_id now there
		for k in occupied.size():
			card_at[occupied[k]] = cards[k]
		var new_cov: Dictionary = {}
		for i in _result_of.size():
			new_cov[i] = [] as Array[int]
		for p in occupied:
			var coverers: Array[int] = []
			for q in (placement_cover[p] as Array):
				if card_at.has(q):          # only occupied placements still cover
					coverers.append(card_at[q])
			new_cov[card_at[p]] = coverers
		_covered_by = new_cov
		applied = _assignment_array(card_at)
		if _has_routable_move():
			return applied
	return applied                          # fallback: last layout (best effort)


# Seeded Fisher–Yates in-place shuffle (gameplay-code rule: no global RNG in core/).
func _shuffle_ints(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# Builds a placement→card_id array (−1 where the placement is empty/removed).
func _assignment_array(card_at: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for p in _result_of.size():
		out.append(card_at.get(p, -1))
	return out


# True when at least one currently-exposed card can make a meaningful move: it
# routes to an open stack, or removing it would expose a covered card (AC-R09).
func _has_routable_move() -> bool:
	for cid in exposed_cards():
		if _find_open_stack(_result_of[cid]) != -1:
			return true
		if newly_exposed_count(cid) > 0:
			return true
	return false


# Shared play resolution for [method tap_card] (exposed) and [method pick_card]
# (covered): route the card to a matching open stack, else discard it (or LOSE if
# the discard is full), then run the cascade and the win check.
func _resolve_play(card_id: int) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	var result: int = _result_of[card_id]
	var stack_index: int = _find_open_stack(result)

	if stack_index != -1:
		_remove_from_floor(card_id)
		_stack_counts[stack_index] += 1
		events.append(GameEvent.route(card_id, stack_index))
	else:
		var slot: int = _first_empty_discard()
		if slot == -1:
			_lost = true
			events.append(GameEvent.lose())
			return events
		_remove_from_floor(card_id)
		_discard[slot] = card_id
		events.append(GameEvent.discard(card_id, slot))

	_resolve_cascade(events)

	if not _won and floor_count() == 0:
		_won = true
		events.append(GameEvent.win())
	return events


## Opens locked stack [param stack_index] (prototype: locked-decks): it draws the
## next queue target and pulls any matching cards back out of discard, possibly
## cascading. Returns the ordered events; a no-op (empty) when the stack is
## already open, out of range, or the game is over. Payment (coins/ad) is the
## caller's concern — the model only models the board.
func unlock_stack(stack_index: int) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	if stack_index < 0 or stack_index >= STACK_COUNT:
		return events
	if not _locked[stack_index] or is_game_over():
		return events

	_locked[stack_index] = false
	var new_target: int = _draw_next_target()
	_stack_targets[stack_index] = new_target
	events.append(GameEvent.unlock(stack_index, new_target))

	if new_target != NO_TARGET:
		_pull_matching(stack_index, new_target, events)
	_resolve_cascade(events)

	if not _won and floor_count() == 0:
		_won = true
		events.append(GameEvent.win())
	return events


# Repeatedly clears any full stack, draws its next target, and pulls matching
# cards out of discard — which may refill the stack and continue the chain.
func _resolve_cascade(events: Array[GameEvent]) -> void:
	while true:
		var stack_index: int = _find_full_stack()
		if stack_index == -1:
			return
		_stack_counts[stack_index] = 0
		var new_target: int = _draw_next_target()
		_stack_targets[stack_index] = new_target
		events.append(GameEvent.stack_cleared(stack_index, new_target))
		if new_target != NO_TARGET:
			_pull_matching(stack_index, new_target, events)


# Pulls cards whose result == target out of discard into the (just cleared)
# stack, up to its remaining capacity.
func _pull_matching(stack_index: int, target: int, events: Array[GameEvent]) -> void:
	for slot in _active_discard_slots:   # live capacity, not the base constant (ADR-0010)
		if _stack_counts[stack_index] >= STACK_CAPACITY:
			return
		var card_id: int = _discard[slot]
		if card_id == -1:
			continue
		if _result_of[card_id] != target:
			continue
		_discard[slot] = -1
		_stack_counts[stack_index] += 1
		events.append(GameEvent.pull(card_id, stack_index, slot))


func _find_open_stack(result: int) -> int:
	for i in STACK_COUNT:
		if _stack_targets[i] == result and _stack_counts[i] < STACK_CAPACITY:
			return i
	return -1


func _find_full_stack() -> int:
	for i in STACK_COUNT:
		if _stack_counts[i] >= STACK_CAPACITY:
			return i
	return -1


func _first_empty_discard() -> int:
	for slot in _active_discard_slots:   # live capacity, not the base constant (ADR-0010)
		if _discard[slot] == -1:
			return slot
	return -1


func _draw_next_target() -> int:
	if _draw_index >= _target_queue.size():
		return NO_TARGET
	var target: int = _target_queue[_draw_index]
	_draw_index += 1
	return target


func _remove_from_floor(card_id: int) -> void:
	_removed[card_id] = true
