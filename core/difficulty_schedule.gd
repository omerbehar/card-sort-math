class_name DifficultySchedule
extends RefCounted
## Pure, node-free mapping from a 1-based level index N to [GeneratorParams]
## (GDD level-generator §Tuning Knobs, ADR-0007). The generator never sees N —
## this is the only place it is interpreted. Reads a [DifficultyScheduleData]
## (a [Resource]/[RefCounted]) passed in by the caller; it never calls
## [code]load()[/code], so the model/view + core-purity seams hold.

## Builds the difficulty knobs for level [param n] (1-based) from [param data].
## [param seed], [param world_id] and [param level_index] are provenance the
## caller supplies (S2-004 wiring); the schedule sets only the difficulty knobs.
static func params_for(
		n: int,
		data: DifficultyScheduleData,
		seed: int = 0,
		world_id: int = 0,
		level_index: int = 0) -> GeneratorParams:
	var p := GeneratorParams.new()
	p.layout_id = layout_for(n, data)
	p.result_max = r_max_for(n, data)
	p.distinct_results = d_for(n, data)
	p.result_min = r_min_for(n, data)
	p.max_operand = max_operand_for(n, data)
	p.allow_queue_repeats = data.allow_queue_repeats
	p.min_recovery_margin = data.min_recovery_margin
	p.seed = seed
	p.world_id = world_id
	p.level_index = level_index
	return p


## The result ceiling R_max(N) — piecewise base + floor((N - anchor)/step_every),
## capped, monotonic non-decreasing (GDD Formula 6).
static func r_max_for(n: int, data: DifficultyScheduleData) -> int:
	for i in range(data.rmax_seg_max_level.size()):
		if n <= data.rmax_seg_max_level[i]:
			var step_every: int = data.rmax_seg_step_every[i]
			if step_every <= 0:
				return data.rmax_seg_base[i]
			var steps: int = (n - data.rmax_seg_anchor[i]) / step_every  # int floor (n>=anchor)
			return mini(data.rmax_seg_base[i] + steps, data.rmax_seg_cap[i])
	# Past the last segment boundary: clamp to the final segment's value.
	var last: int = data.rmax_seg_base.size() - 1
	return mini(data.rmax_seg_base[last]
		+ (n - data.rmax_seg_anchor[last]) / maxi(1, data.rmax_seg_step_every[last]),
		data.rmax_seg_cap[last])


## Distinct results D(N) — base plus one step per crossed step level.
static func d_for(n: int, data: DifficultyScheduleData) -> int:
	return data.d_base + _steps_crossed(n, data.d_step_levels)


## Result floor R_min(N).
static func r_min_for(n: int, data: DifficultyScheduleData) -> int:
	return data.rmin_base + _steps_crossed(n, data.rmin_step_levels)


## Per-operand magnitude cap max_operand(N) — the last step value reached.
static func max_operand_for(n: int, data: DifficultyScheduleData) -> int:
	var value: int = data.maxop_base
	for i in range(data.maxop_step_levels.size()):
		if n >= data.maxop_step_levels[i]:
			value = data.maxop_step_values[i]
	return value


## Layout id — fixed per early band, then a held cycle for variety.
static func layout_for(n: int, data: DifficultyScheduleData) -> int:
	for i in range(data.layout_band_max_level.size()):
		if n <= data.layout_band_max_level[i]:
			return data.layout_band_value[i]
	var hold: int = maxi(1, data.layout_cycle_hold)
	var block: int = (n - data.layout_cycle_start) / hold
	return data.layout_cycle[block % data.layout_cycle.size()]


# Number of step levels in [param levels] that are <= [param n].
static func _steps_crossed(n: int, levels: Array[int]) -> int:
	var count: int = 0
	for level: int in levels:
		if n >= level:
			count += 1
	return count
