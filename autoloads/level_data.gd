extends Node
## Autoload: authored level definitions + solvability checking.
##
## Holds persistent, level-design data only (no scene-tree references). Each
## level is built from a layout preset (see [Layouts]) plus a list of target
## results assigned per slot. A level is solvable by construction when the
## count of cards for every result equals 3 x (its occurrences in the level's
## target queue) — enforced by [method is_solvable] and unit-tested.

const STACK_COUNT: int = 4
const STACK_CAPACITY: int = 3

# Per-level: the result printed on each slot's card. Length must equal the
# layout's slot count. Counts must obey the 3xN solvability invariant.
const _LEVEL_RESULTS: Array = [
	# Level 1 — layout 0, 12 cards: 5,7,9,11 each x3 (no rotation).
	[5, 7, 9, 11, 5, 7, 9, 11, 5, 7, 9, 11],
	# Level 2 — layout 1, 18 cards: 6,8,10,12,14,16 each x3.
	# 14 & 16 are absent from the initial 4 stacks, so they exercise the
	# discard row + pull-back when stacks rotate them in.
	[6, 8, 10, 12, 14, 16, 6, 8, 10, 12, 14, 16, 6, 8, 10, 12, 14, 16],
	# Level 3 — layout 2, 15 cards: 7 x6, 9/11/13 x3. Target 7 repeats in the
	# queue (rotation re-shows it), demonstrating same-target combos.
	[7, 9, 11, 13, 7, 7, 9, 11, 13, 7, 7, 9, 11, 13, 7],
]

# Per-level ordered target queue. First STACK_COUNT entries are the starting
# stack targets; each stack clear draws the next entry.
const _LEVEL_QUEUES: Array = [
	[5, 7, 9, 11],
	[6, 8, 10, 12, 14, 16],
	[7, 9, 11, 13, 7],
]

const _LEVEL_LAYOUTS: Array[int] = [0, 1, 2]

var _cache: Dictionary = {}


## Total number of authored levels.
func level_count() -> int:
	return _LEVEL_LAYOUTS.size()


## Returns the [LevelConfig] for 1-based [param n] (clamped to the authored
## range). Configs are built once and cached.
func get_level(n: int) -> LevelConfig:
	var index: int = clampi(n - 1, 0, level_count() - 1)
	if _cache.has(index):
		return _cache[index]
	var config := _build_level(index)
	_cache[index] = config
	return config


## Returns the next stack target drawn from [param queue] at [param draw_index],
## or -1 when the queue is exhausted (a cleared stack then goes empty).
func next_target(queue: Array[int], draw_index: int) -> int:
	if draw_index < 0 or draw_index >= queue.size():
		return -1
	return queue[draw_index]


## A level is solvable when every card result appears in the target queue and
## the card count for each result equals 3 x (its occurrences in the queue).
func is_solvable(config: LevelConfig) -> bool:
	var queue_counts: Dictionary = {}
	for target: int in config.target_queue:
		queue_counts[target] = int(queue_counts.get(target, 0)) + 1

	var card_counts: Dictionary = {}
	for card: CardData in config.card_pool:
		card_counts[card.result] = int(card_counts.get(card.result, 0)) + 1

	if card_counts.size() != queue_counts.size():
		return false
	for result: int in card_counts:
		if not queue_counts.has(result):
			return false
		if int(card_counts[result]) != STACK_CAPACITY * int(queue_counts[result]):
			return false
	return true


func _build_level(index: int) -> LevelConfig:
	var config := LevelConfig.new()
	config.level_id = index + 1
	config.layout_id = _LEVEL_LAYOUTS[index]

	var queue: Array[int] = []
	queue.assign(_LEVEL_QUEUES[index])
	config.target_queue = queue

	var placements := Layouts.get_layout(config.layout_id)
	var results: Array = _LEVEL_RESULTS[index]
	assert(results.size() == placements.size(),
		"Level %d: result count %d != layout slot count %d" % [index + 1, results.size(), placements.size()])

	var pool: Array[CardData] = []
	for slot in results.size():
		var result: int = results[slot]
		var layer: int = placements[slot].layer
		var operands := _split_operands(result, slot)
		pool.append(CardData.create(operands.x, operands.y, layer, slot))
	config.card_pool = pool
	return config


# Picks two positive operands summing to [param result], varied by [param slot]
# so identical-result cards don't all read the same.
func _split_operands(result: int, slot: int) -> Vector2i:
	if result <= 1:
		return Vector2i(0, maxi(result, 0))
	var a: int = 1 + (slot % (result - 1))
	var b: int = result - a
	return Vector2i(a, b)
