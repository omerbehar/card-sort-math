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
	for _i in DISCARD_SLOTS:
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
	for slot in DISCARD_SLOTS:
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
	for slot in DISCARD_SLOTS:
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
