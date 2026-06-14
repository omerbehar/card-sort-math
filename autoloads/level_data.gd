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

# Operation worlds + generated-level seeding (ADR-0007). The first four
# WORLD_SIZE-level bands each teach one binary operation (+, −, ×, ÷); the bands
# above teach multi-term expressions:
#   1-5  + | 6-10 − | 11-15 × | 16-20 ÷        (binary, one op each)
#   21-25  three-term add/sub, left-to-right     (WORLD_TRI_ADDSUB)
#   26-30  three-term add/sub WITH parentheses   (WORLD_TRI_PARENS)
#   31-40  three-term ×/÷ mixed with +/−, order of operations (WORLD_TRI_ORDER)
#   41+    all three multi-term styles mixed     (MIXED_WORLD_ID)
# seed = world_for_level(n) * WORLD_STRIDE + n, so every world's seed space is
# disjoint and the same index always rebuilds the same level. WORLD_ID (0 =
# addition) is retained for back-compatible references.
const WORLD_ID: int = 0
const WORLD_STRIDE: int = 1_000_000
const WORLD_SIZE: int = 5
# Stable world ids (carried onto generated levels as provenance).
const WORLD_ADD: int = 0
const WORLD_SUB: int = 1
const WORLD_MUL: int = 2
const WORLD_DIV: int = 3
const WORLD_TRI_ADDSUB: int = 4   # 21-25: a ± b ± c, left-to-right
const WORLD_TRI_PARENS: int = 5   # 26-30: parentheses that can change grouping
const WORLD_TRI_ORDER: int = 6    # 31-40: ×/÷ with +/−, order of operations
const MIXED_WORLD_ID: int = 7     # 41+: all multi-term styles mixed
# The first 1-based level of each multi-term band (binary bands use WORLD_SIZE).
const TRI_ADDSUB_START: int = 21
const TRI_PARENS_START: int = 26
const TRI_ORDER_START: int = 31
const MIXED_START: int = 41

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
# The two operators the add/sub teaching worlds mix (21-30).
const _ADD_SUB: Array[int] = [Operation.Type.ADD, Operation.Type.SUBTRACT]
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


## The teaching world for 1-based [param n] (see the world-id constants):
## 0 = +, 1 = −, 2 = ×, 3 = ÷ for the four binary bands (1-20), then the
## three-term bands — add/sub (21-25), parentheses (26-30), order of operations
## (31-40) — and finally the mixed world (41+).
func world_for_level(n: int) -> int:
	var lvl: int = maxi(n, 1)
	if lvl < TRI_ADDSUB_START:
		return mini((lvl - 1) / WORLD_SIZE, WORLD_DIV)
	if lvl < TRI_PARENS_START:
		return WORLD_TRI_ADDSUB
	if lvl < TRI_ORDER_START:
		return WORLD_TRI_PARENS
	if lvl < MIXED_START:
		return WORLD_TRI_ORDER
	return MIXED_WORLD_ID


## Whether 1-based [param n] is a three-term (multi-operand) teaching level.
func is_multi_term_level(n: int) -> bool:
	return world_for_level(n) >= WORLD_TRI_ADDSUB


## The base operations involved at 1-based [param n]: the single op for a binary
## world, [+, −] for the add/sub teaching worlds, or all four where ×/÷ appear.
## (Three-term grouping is described by [method expression_specs_for_level].)
func operations_for_level(n: int) -> Array[int]:
	var world: int = world_for_level(n)
	match world:
		WORLD_TRI_ADDSUB, WORLD_TRI_PARENS:
			return _ADD_SUB.duplicate()
		WORLD_TRI_ORDER, MIXED_WORLD_ID:
			return Operation.ALL.duplicate()
		_:
			return [_WORLD_OPERATIONS[world]] as Array[int]


## The three-term expression specs (each a Vector3i (op1, op2, grouping); see
## [enum TernaryExpression.Grouping]) a generated level at 1-based [param n] may
## print, or empty for the binary worlds. The generator draws each card's
## spec + operands from those that produce its result.
func expression_specs_for_level(n: int) -> Array[Vector3i]:
	var specs: Array[Vector3i] = []
	match world_for_level(n):
		WORLD_TRI_ADDSUB:
			# a ± b ± c, left-to-right — teaches that 3 + 7 − 4 reads as 3 − 4 + 7.
			for op1: int in _ADD_SUB:
				for op2: int in _ADD_SUB:
					specs.append(Vector3i(op1, op2, TernaryExpression.Grouping.LEFT))
		WORLD_TRI_PARENS:
			# Parentheses that can genuinely change the grouping (e.g. a − (b + c)).
			for op1: int in _ADD_SUB:
				for op2: int in _ADD_SUB:
					specs.append(Vector3i(op1, op2, TernaryExpression.Grouping.PAREN_LEFT))
					specs.append(Vector3i(op1, op2, TernaryExpression.Grouping.PAREN_RIGHT))
		WORLD_TRI_ORDER:
			specs = _order_of_operations_specs()
		MIXED_WORLD_ID:
			specs = expression_specs_for_world(WORLD_TRI_ADDSUB)
			specs.append_array(expression_specs_for_world(WORLD_TRI_PARENS))
			specs.append_array(_order_of_operations_specs())
	return specs


## The expression specs for an explicit [param world] id (used to compose the
## mixed world). See [method expression_specs_for_level].
func expression_specs_for_world(world: int) -> Array[Vector3i]:
	return expression_specs_for_level(_first_level_of_world(world))


# Specs for the order-of-operations world: every operator pair where at least one
# side is ×/÷ (so precedence actually matters), displayed without parentheses.
func _order_of_operations_specs() -> Array[Vector3i]:
	var specs: Array[Vector3i] = []
	for op1: int in Operation.ALL:
		for op2: int in Operation.ALL:
			if Operation.is_high_precedence(op1) or Operation.is_high_precedence(op2):
				specs.append(Vector3i(op1, op2, TernaryExpression.Grouping.PRECEDENCE))
	return specs


# A representative 1-based level for [param world], so the spec/op helpers can be
# queried by world id as well as by level.
func _first_level_of_world(world: int) -> int:
	match world:
		WORLD_TRI_ADDSUB:
			return TRI_ADDSUB_START
		WORLD_TRI_PARENS:
			return TRI_PARENS_START
		WORLD_TRI_ORDER:
			return TRI_ORDER_START
		MIXED_WORLD_ID:
			return MIXED_START
		_:
			return world * WORLD_SIZE + 1


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
		WORLD_SUB:  # a − b = result needs b in [1, max−result]; ≥3 ⇒ result ≤ max−3.
			params.max_operand = maxi(params.max_operand, 12)
			params.result_min = 2
			params.result_max = mini(params.result_max, params.max_operand - OPERAND_OPTIONS_MIN)
		WORLD_MUL:  # only composites with 3+ factor pairs qualify (12,16,18,20,24…).
			params.max_operand = maxi(params.max_operand, 12)
			params.result_min = 8
			params.result_max = maxi(params.result_max, 24)
		WORLD_DIV:  # a ÷ b = result needs b in [2, max/result]; ≥3 ⇒ small quotients.
			params.max_operand = maxi(params.max_operand, 20)
			params.result_min = 2
			params.result_max = 5
		WORLD_TRI_ADDSUB, WORLD_TRI_PARENS:
			# Small single-digit operands so the lesson is the ordering/parentheses
			# idea, not large sums; results span enough values for variety.
			params.max_operand = clampi(params.max_operand, 5, 9)
			params.result_min = 2
			params.result_max = clampi(params.result_max, 12, 18)
		WORLD_TRI_ORDER, MIXED_WORLD_ID:
			# Room for ×/÷ products while keeping operands single-digit.
			params.max_operand = clampi(params.max_operand, 6, 9)
			params.result_min = 4
			params.result_max = maxi(params.result_max, 36)
		_:  # addition (WORLD_ADD): the schedule's range already offers enough.
			pass


func _build_generated_level(n: int) -> LevelConfig:
	var world: int = world_for_level(n)
	var seed: int = world * WORLD_STRIDE + n
	var params := DifficultySchedule.params_for(n, _get_schedule(), seed, world, n)
	# Every result must offer >= OPERAND_OPTIONS_MIN distinct exercises so equal-result
	# cards vary (e.g. a prime like 7 is never a multiply result — it'd be all "1 × 7").
	params.min_operand_options = OPERAND_OPTIONS_MIN
	# The schedule sets only difficulty knobs; the operation(s)/expression shape are a
	# world concern decided here (ADR-0007), keeping DifficultySchedule op-agnostic.
	if is_multi_term_level(n):
		params.term_count = 3
		params.expression_specs = expression_specs_for_level(n)
	else:
		params.allowed_operations = operations_for_level(n)
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

