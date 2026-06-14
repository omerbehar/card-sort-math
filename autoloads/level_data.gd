extends Node
## Autoload: authored level definitions + generated-level dispatch (ADR-0007).
##
## Holds persistent, level-design data only (no scene-tree references). Levels
## 1..[method level_count] are hand-authored; every level beyond is produced by
## the pure [LevelGenerator], seeded so the same index always yields the same
## level. This autoload is the ONLY layer that [code]load()[/code]s the difficulty
## schedule resource — it hands the data to the pure [DifficultySchedule], keeping
## [code]core/[/code] node-free and resource-free (ADR-0001).

const STACK_COUNT: int = 4
const STACK_CAPACITY: int = 3

# Operation worlds + generated-level seeding (ADR-0007). Each WORLD_SIZE-level
# band advances one operation (+, −, ×, ÷); levels past the four single-operation
# bands mix all four. seed = world_for_level(n) * WORLD_STRIDE + n, so every
# world's seed space is disjoint and the same index always rebuilds the same
# level. WORLD_ID (0 = addition) is retained for back-compatible references.
const WORLD_ID: int = 0
const WORLD_STRIDE: int = 1_000_000
const WORLD_SIZE: int = 5
const MIXED_WORLD_ID: int = 4

# Variety floor: every result in a generated level must offer at least this many
# distinct displayed operand pairs, so equal-result cards aren't all the same
# exercise (a prime like 7 is excluded from a multiply world — only "1 × 7").
# Matches STACK_CAPACITY: each result is dealt in groups of 3, so 3 options lets
# the first group read all-different.
const OPERAND_OPTIONS_MIN: int = 3
# World id -> the single operation it prints (see [enum Operation.Type]). The
# mixed world (MIXED_WORLD_ID) is handled separately in [method operations_for_level].
const _WORLD_OPERATIONS: Array[int] = [
	Operation.Type.ADD,
	Operation.Type.SUBTRACT,
	Operation.Type.MULTIPLY,
	Operation.Type.DIVIDE,
]
const _SCHEDULE_PATH: String = "res://assets/data/difficulty_schedule.tres"

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
var _schedule: DifficultyScheduleData = null


## Total number of authored levels.
func level_count() -> int:
	return _LEVEL_LAYOUTS.size()


## Returns the [LevelConfig] for 1-based [param n]: an authored level for
## [code]n <= level_count()[/code], otherwise a deterministically generated one
## (ADR-0007). Only the (bounded) authored levels are cached; generated levels are
## rebuilt on demand — they are deterministic and cheap, and caching them would
## grow unbounded over an endless session.
func get_level(n: int) -> LevelConfig:
	var key: int = maxi(n, 1)
	if key > level_count():
		return _build_generated_level(key)
	if _cache.has(key):
		return _cache[key]
	var config := _build_authored_level(key - 1)
	_cache[key] = config
	return config


## The operation world for 1-based [param n]: 0 = +, 1 = −, 2 = ×, 3 = ÷ for the
## first four [constant WORLD_SIZE]-level bands, then [constant MIXED_WORLD_ID]
## (all four mixed) from level 21 onward.
func world_for_level(n: int) -> int:
	return mini((maxi(n, 1) - 1) / WORLD_SIZE, MIXED_WORLD_ID)


## The operations a generated level at 1-based [param n] may print: one operation
## per single-operation world, or all four in the mixed world. The generator
## picks each card's operation from those valid for its result.
func operations_for_level(n: int) -> Array[int]:
	var world: int = world_for_level(n)
	if world == MIXED_WORLD_ID:
		return Operation.ALL.duplicate()
	return [_WORLD_OPERATIONS[world]] as Array[int]


## Returns the next stack target drawn from [param queue] at [param draw_index],
## or -1 when the queue is exhausted (a cleared stack then goes empty).
func next_target(queue: Array[int], draw_index: int) -> int:
	if draw_index < 0 or draw_index >= queue.size():
		return -1
	return queue[draw_index]


## A level is solvable when every card result appears in the target queue and the
## card count for each result equals 3 x (its occurrences in the queue). Delegates
## to the pure [Solvability] check (the same rule the generator self-checks with).
func is_solvable(config: LevelConfig) -> bool:
	return Solvability.is_solvable(config)


func _build_authored_level(index: int) -> LevelConfig:
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
		# Single shared operand splitter (OperandPicker); max_operand = result-1
		# reproduces the legacy authored split exactly (regression-guarded by AC-28).
		var operands := OperandPicker.pick(result, slot, result - 1)
		pool.append(CardData.create(operands.x, operands.y, layer, slot))
	config.card_pool = pool
	return config


# Widens a single-operation world's number range so enough results clear the
# OPERAND_OPTIONS_MIN variety floor (the shared schedule is tuned for addition,
# where small operands already give many options; ×/÷/− need bigger operands or a
# narrower result band to offer 3+ ways). Addition and the mixed world keep the
# schedule's range (addition options are plentiful; mixed qualifies via addition).
func _apply_world_number_range(params: GeneratorParams, world: int) -> void:
	match world:
		1:  # subtraction: a − b = result needs b in [1, max−result]; ≥3 ⇒ result ≤ max−3.
			params.max_operand = maxi(params.max_operand, 12)
			params.result_min = 2
			params.result_max = mini(params.result_max, params.max_operand - OPERAND_OPTIONS_MIN)
		2:  # multiplication: only composites with 3+ factor pairs qualify (12,16,18,20,24…).
			params.max_operand = maxi(params.max_operand, 12)
			params.result_min = 8
			params.result_max = maxi(params.result_max, 24)
		3:  # division: a ÷ b = result needs b in [2, max/result]; ≥3 ⇒ small quotients.
			params.max_operand = maxi(params.max_operand, 20)
			params.result_min = 2
			params.result_max = 5
		_:  # addition (0) and mixed (4): the schedule's range already offers enough.
			pass


func _build_generated_level(n: int) -> LevelConfig:
	var world: int = world_for_level(n)
	var seed: int = world * WORLD_STRIDE + n
	var params := DifficultySchedule.params_for(n, _get_schedule(), seed, world, n)
	# The schedule sets only difficulty knobs; the operation(s) are a world concern
	# decided here (ADR-0007), keeping DifficultySchedule operation-agnostic.
	params.allowed_operations = operations_for_level(n)
	# Every result must offer >= OPERAND_OPTIONS_MIN distinct exercises so equal-result
	# cards vary (e.g. a prime like 7 is never a multiply result — it'd be all "1 × 7").
	params.min_operand_options = OPERAND_OPTIONS_MIN
	_apply_world_number_range(params, world)
	var result := LevelGenerator.generate(params)
	if result.config == null:
		# Graceful degradation (engine-code rule): the schedule should never
		# produce incoherent params, but never hand the game a null level.
		push_error("LevelData: generator failed for level %d; falling back to last authored level" % n)
		return _build_authored_level(level_count() - 1)
	return result.config


# Lazily loads the difficulty schedule resource (this is the only loader, ADR-0007).
# Falls back to the resource defaults if the file is missing.
func _get_schedule() -> DifficultyScheduleData:
	if _schedule == null:
		var loaded := load(_SCHEDULE_PATH)
		if loaded is DifficultyScheduleData:
			_schedule = loaded
		else:
			push_warning("LevelData: schedule resource missing at %s; using defaults" % _SCHEDULE_PATH)
			_schedule = DifficultyScheduleData.new()
	return _schedule

