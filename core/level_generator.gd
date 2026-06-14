class_name LevelGenerator
extends RefCounted
## Procedurally builds a solvable [LevelConfig] by construction (GDD
## level-generator, ADR-0007). Pure and node-free: a single seeded
## [RandomNumberGenerator] is the only randomness, consumed in a fixed step
## order, so the same [GeneratorParams] always yields a field-identical level.
##
## Solvability (ADR-0003) is structural, never sampled: the target queue is built
## first, then exactly [code]3 x queue_count(R)[/code] cards are dealt for each
## result R. When [member GeneratorParams.min_recovery_margin] > 0, a constructed
## board is also checked for "fair to play" recoverability (GDD Core Rule 10) and
## deterministically re-seeded on failure. Usage:
## [codeblock]
## var params := GeneratorParams.create(0, 4, 3, 12, 6, 42)
## var result := LevelGenerator.generate(params)
## if not result.is_error():
##     BoardModel.from_config(result.config)
## [/codeblock]

## Cards per stack clear — the queue-to-pool multiplier (ADR-0003).
const STACK_CAPACITY: int = 3

## Prime offset that deterministically re-seeds each recoverability attempt.
const RESEED_STRIDE: int = 7919


## Generates a solvable [LevelConfig] from [param params]. On incoherent params
## the returned [GeneratorResult] has a [code]null[/code] config and a warning.
## [param recovery_fn] (optional) is an injected
## [code]func(config, margin) -> bool[/code] recoverability predicate — defaults
## to [RecoverabilitySimulator]; injectable so the re-seed/fallback path is
## deterministically testable (AC-34).
static func generate(params: GeneratorParams, recovery_fn: Callable = Callable()) -> GeneratorResult:
	var result := GeneratorResult.new()
	var margin: int = params.min_recovery_margin
	var attempts: int = 1 if margin <= 0 else maxi(1, params.recovery_attempt_cap)
	var fallback: LevelConfig = null
	var fallback_warnings: Array[String] = []

	for attempt in range(attempts):
		var effective_seed: int = params.seed + attempt * RESEED_STRIDE
		var built := _build_level(params, effective_seed)
		var config: LevelConfig = built.config

		if config == null:
			# Hard error (bad params / empty pool) — seed-independent, fail fast.
			result.warnings = built.warnings
			return result

		if margin <= 0:
			result.warnings = built.warnings
			result.config = config
			return result

		if fallback == null:
			fallback = config
			fallback_warnings = built.warnings

		var recoverable: bool = (
			recovery_fn.call(config, margin) if recovery_fn.is_valid()
			else RecoverabilitySimulator.is_recoverable(config, margin))
		if recoverable:
			result.warnings = built.warnings
			result.config = config
			return result

	# Cap exhausted — keep the first solvable candidate (GDD Rule 10 fallback).
	result.warnings = fallback_warnings
	result.warn("recoverability cap (%d attempts) exhausted; using fallback level" % attempts)
	result.config = fallback
	return result


# Builds one solvable level from [param effective_seed]. Returns
# { config: LevelConfig or null, warnings: Array[String] }.
static func _build_level(params: GeneratorParams, effective_seed: int) -> Dictionary:
	var warnings: Array[String] = []

	# INIT — validate params before any allocation (GDD Core Rule 4 guard, Edge Cases).
	if params.layout_id < 0 or params.layout_id >= Layouts.SLOT_COUNTS.size():
		push_error("LevelGenerator: layout_id %d out of range" % params.layout_id)
		warnings.append("layout_id %d out of range [0, %d)" % [params.layout_id, Layouts.SLOT_COUNTS.size()])
		return {config = null, warnings = warnings}
	if params.max_operand < 1:
		push_error("LevelGenerator: max_operand must be >= 1 (got %d)" % params.max_operand)
		warnings.append("max_operand %d < 1" % params.max_operand)
		return {config = null, warnings = warnings}
	if params.distinct_results < 1:
		push_error("LevelGenerator: distinct_results must be >= 1")
		warnings.append("distinct_results %d < 1" % params.distinct_results)
		return {config = null, warnings = warnings}

	var rng := RandomNumberGenerator.new()
	rng.seed = effective_seed

	var slot_count: int = Layouts.SLOT_COUNTS[params.layout_id]
	var queue_length: int = slot_count / STACK_CAPACITY

	# PICK_RESULTS — candidates are results offering at least min_operand_options
	# distinct displayed pairs under at least one of the world's allowed operations
	# (variety floor: no result whose cards would all read identically).
	var candidates: Array[int] = []
	for r in range(params.result_min, params.result_max + 1):
		if _result_has_content(r, params):
			candidates.append(r)
	# Empty-pool guard MUST precede the clamp: clampi(D, 1, 0) returns 1, which
	# would otherwise draw from an empty set (GDD Edge Cases / Formula 5).
	if candidates.is_empty():
		push_error("LevelGenerator: no valid result in [%d, %d] under max_operand %d"
			% [params.result_min, params.result_max, params.max_operand])
		warnings.append("empty candidate pool")
		return {config = null, warnings = warnings}

	var distinct: int = clampi(params.distinct_results, 1, mini(queue_length, candidates.size()))
	if distinct < params.distinct_results:
		warnings.append("distinct_results clamped from %d to %d" % [params.distinct_results, distinct])

	_shuffle_int(candidates, rng)
	var chosen: Array[int] = candidates.slice(0, distinct)

	# BUILD_QUEUE — one of each chosen result, then seeded repeats fill to length L.
	var allow_repeats: bool = params.allow_queue_repeats
	if not allow_repeats and distinct < queue_length:
		allow_repeats = true
		warnings.append("allow_queue_repeats promoted to true (distinct %d < queue length %d)"
			% [distinct, queue_length])

	var queue: Array[int] = chosen.duplicate()
	while queue.size() < queue_length:
		queue.append(chosen[rng.randi_range(0, chosen.size() - 1)])
	# ORDER_QUEUE — spread equal targets apart so the starting decks differ and no
	# two identical targets sit back-to-back in the draw order (no two-of-a-kind in
	# a row). Falls back to a plain seeded shuffle when spacing is disabled.
	if params.space_targets:
		_arrange_spaced(queue, rng)
	else:
		_shuffle_int(queue, rng)

	# BUILD_POOL — exactly 3*k cards per result (the solvability identity).
	var queue_counts: Dictionary = {}
	for target: int in queue:
		queue_counts[target] = int(queue_counts.get(target, 0)) + 1

	var placements := Layouts.get_layout(params.layout_id)
	# ASSIGN_SLOTS — a seeded slot permutation; card order is canonicalised below.
	var slot_order: Array[int] = []
	for s in range(slot_count):
		slot_order.append(s)
	_shuffle_int(slot_order, rng)

	var pool: Array[CardData] = []
	var next_slot_index: int = 0
	for result_value: int in queue_counts:
		var card_count: int = STACK_CAPACITY * int(queue_counts[result_value])
		if params.term_count >= 3:
			_deal_ternary(pool, result_value, card_count, params, placements, slot_order, next_slot_index, rng)
			next_slot_index += card_count
			continue
		# Operations this result can be printed with (non-empty: it passed the
		# candidate filter). A single-operation world skips the RNG draw entirely,
		# so addition levels stay byte-identical to the pre-operations generator.
		var ops: Array[int] = OperandPicker.valid_operations(
			result_value, params.max_operand, params.allowed_operations, params.min_operand_options)
		for i in range(card_count):
			var slot: int = slot_order[next_slot_index]
			next_slot_index += 1
			var layer: int = placements[slot].layer
			var op: int = ops[0] if ops.size() == 1 else ops[rng.randi_range(0, ops.size() - 1)]
			var operands := OperandPicker.pick(result_value, i, params.max_operand, op)
			pool.append(CardData.create(operands.x, operands.y, layer, slot, op))

	# Canonical ordering (determinism-critical, AC-08): pool order is a pure
	# function of slot assignment, never of result draw order.
	pool.sort_custom(func(a: CardData, b: CardData) -> bool: return a.layout_slot < b.layout_slot)

	# ASSEMBLE — fresh arrays (no aliasing of working buffers). Provenance stamps
	# the BASE seed so re-running generate(params) reproduces the same final level.
	var config := LevelConfig.new()
	config.level_id = LevelConfig.GENERATED_ID
	config.layout_id = params.layout_id
	config.target_queue = queue.duplicate()
	config.card_pool = pool
	config.seed = params.seed
	config.world_id = params.world_id
	config.level_index = params.level_index

	# VALIDATE — debug self-check; by construction it cannot fail.
	assert(Solvability.is_solvable(config), "LevelGenerator produced an unsolvable level (construction bug)")

	return {config = config, warnings = warnings}


# Whether [param r] can seed enough variety to be a candidate result: a binary
# world needs an allowed operation with >= min_operand_options pairs; a three-term
# world needs >= min_operand_options distinct rendered exercises across its specs.
static func _result_has_content(r: int, params: GeneratorParams) -> bool:
	if params.term_count >= 3:
		return OperandPicker.triple_renderings(
			r, params.max_operand, params.expression_specs).size() >= params.min_operand_options
	return not OperandPicker.valid_operations(
		r, params.max_operand, params.allowed_operations, params.min_operand_options).is_empty()


# Deals [param card_count] three-term cards for [param result_value] into
# [param pool], starting at [code]slot_order[start_index][/code]. Cycles a
# deterministically shuffled list of distinct rendered exercises (size >=
# min_operand_options by the candidate filter), so equal-result cards read
# differently and the level stays reproducible for a given seed.
static func _deal_ternary(pool: Array[CardData], result_value: int, card_count: int,
		params: GeneratorParams, placements: Array, slot_order: Array[int],
		start_index: int, rng: RandomNumberGenerator) -> void:
	var renderings: Array = OperandPicker.triple_renderings(
		result_value, params.max_operand, params.expression_specs)
	var order: Array[int] = []
	for k in range(renderings.size()):
		order.append(k)
	_shuffle_int(order, rng)
	for i in range(card_count):
		var slot: int = slot_order[start_index + i]
		var layer: int = placements[slot].layer
		var rd: Dictionary = renderings[order[i % order.size()]]
		pool.append(CardData.create_ternary(
			rd["a"], rd["b"], rd["c"], rd["op1"], rd["op2"], rd["grouping"], layer, slot))


## Reorders [param arr] in place so equal values are spread apart (no two adjacent
## entries equal whenever the multiset allows it — i.e. when no value's count
## exceeds [code]ceil(n/2)[/code]). Greedy: at each step place the value with the
## most remaining copies that differs from the one just placed, breaking ties with
## a seeded draw so variety is preserved and the result stays reproducible. Only
## when counts force it (the previous value is all that remains) is a repeat placed.
##
## Used for the target queue so the starting decks never share a number and the
## draw order has no back-to-back duplicates. Determinism: key order follows first
## appearance in [param arr] and every tie-break draws from [param rng], so the same
## seed reproduces the same arrangement.
static func _arrange_spaced(arr: Array[int], rng: RandomNumberGenerator) -> void:
	var counts: Dictionary = {}
	var order: Array[int] = []  # distinct values in first-appearance order (stable)
	for v: int in arr:
		if not counts.has(v):
			order.append(v)
		counts[v] = int(counts.get(v, 0)) + 1

	var out: Array[int] = []
	var have_last: bool = false
	var last: int = 0
	while out.size() < arr.size():
		var best: int = -1
		var picks: Array[int] = []
		for v: int in order:
			var c: int = int(counts[v])
			if c <= 0 or (have_last and v == last):
				continue
			if c > best:
				best = c
				picks = [v]
			elif c == best:
				picks.append(v)
		if picks.is_empty():
			# Forced repeat: only the just-placed value is left (count > n/2).
			for v: int in order:
				if int(counts[v]) > 0:
					picks = [v]
					break
		var pick: int = picks[0] if picks.size() == 1 else picks[rng.randi_range(0, picks.size() - 1)]
		out.append(pick)
		counts[pick] = int(counts[pick]) - 1
		have_last = true
		last = pick

	arr.clear()
	arr.append_array(out)


## In-place seeded Fisher-Yates over [param arr]. The ONLY shuffle the generator
## uses — [code]Array.shuffle()[/code] is banned in [code]core/[/code] because it
## draws from the global RNG and breaks determinism (see gameplay-code rules).
static func _shuffle_int(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
