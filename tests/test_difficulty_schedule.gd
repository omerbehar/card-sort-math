extends GdUnitTestSuite
## Difficulty schedule tests (S2-003b, GDD level-generator Formula 6 + §Tuning
## Knobs, AC-21..26). The schedule is pure; tests construct the default
## [DifficultyScheduleData] and check the N -> knobs mapping directly.

var _data: DifficultyScheduleData


func before_test() -> void:
	_data = DifficultyScheduleData.new()


# --- AC-21: R_max(N) at pinned indices (onboarding plateau, both Gentle steps,
# first step inside each later segment, soft cap). ---
func test_r_max_curve_pinned_values() -> void:
	var ns: Array[int] = [1, 5, 6, 8, 13, 16, 28, 29, 52, 53, 84, 85, 200]
	var expected: Array[int] = [10, 10, 11, 12, 12, 13, 16, 16, 20, 20, 23, 23, 28]
	for i in range(ns.size()):
		assert_int(DifficultySchedule.r_max_for(ns[i], _data)) \
			.override_failure_message("R_max(%d) wrong" % ns[i]) \
			.is_equal(expected[i])


# --- AC-22: R_max non-decreasing over N=1..200. ---
func test_r_max_is_non_decreasing() -> void:
	var prev: int = DifficultySchedule.r_max_for(1, _data)
	for n in range(2, 201):
		var cur: int = DifficultySchedule.r_max_for(n, _data)
		assert_bool(cur >= prev) \
			.override_failure_message("R_max dropped at N=%d (%d -> %d)" % [n, prev, cur]) \
			.is_true()
		prev = cur


# --- AC-23: soft cap 30 over N=85..1000. ---
func test_r_max_respects_soft_cap() -> void:
	for n in range(85, 1001):
		assert_int(DifficultySchedule.r_max_for(n, _data)).is_less_equal(30)


# --- AC-24: per-level delta of R_max is in {0,1}. ---
func test_r_max_delta_is_zero_or_one() -> void:
	for n in range(1, 200):
		var delta: int = DifficultySchedule.r_max_for(n + 1, _data) - DifficultySchedule.r_max_for(n, _data)
		assert_bool(delta == 0 or delta == 1) \
			.override_failure_message("dR_max at N=%d is %d" % [n, delta]).is_true()


# --- AC-25: per-level delta of D is in {0,1}. ---
func test_d_delta_is_zero_or_one() -> void:
	for n in range(1, 200):
		var delta: int = DifficultySchedule.d_for(n + 1, _data) - DifficultySchedule.d_for(n, _data)
		assert_bool(delta == 0 or delta == 1) \
			.override_failure_message("dD at N=%d is %d" % [n, delta]).is_true()


# --- AC-26: strict per-level stagger — at most one of {R_max, D, layout_id,
# R_min, max_operand} changes between any consecutive levels. ---
func test_strict_per_level_stagger() -> void:
	for n in range(1, 200):
		var changed: int = 0
		if DifficultySchedule.r_max_for(n + 1, _data) != DifficultySchedule.r_max_for(n, _data):
			changed += 1
		if DifficultySchedule.d_for(n + 1, _data) != DifficultySchedule.d_for(n, _data):
			changed += 1
		if DifficultySchedule.layout_for(n + 1, _data) != DifficultySchedule.layout_for(n, _data):
			changed += 1
		if DifficultySchedule.r_min_for(n + 1, _data) != DifficultySchedule.r_min_for(n, _data):
			changed += 1
		if DifficultySchedule.max_operand_for(n + 1, _data) != DifficultySchedule.max_operand_for(n, _data):
			changed += 1
		assert_int(changed) \
			.override_failure_message("%d knobs changed between N=%d and N=%d" % [changed, n, n + 1]) \
			.is_less_equal(1)


# --- The D 4->5 step lands exactly at N=21 (off the N=29 band edge). ---
func test_d_step_is_pinned_to_level_21() -> void:
	assert_int(DifficultySchedule.d_for(20, _data)).is_equal(4)
	assert_int(DifficultySchedule.d_for(21, _data)).is_equal(5)


# --- Schedule produces solvable, in-band generated levels end to end. ---
func test_scheduled_params_generate_solvable_levels() -> void:
	for n in [1, 8, 13, 21, 29, 40, 53, 70, 85, 120]:
		var params := DifficultySchedule.params_for(n, _data, n)  # seed = n
		var result := LevelGenerator.generate(params)
		assert_object(result.config) \
			.override_failure_message("level %d generated null" % n).is_not_null()
		assert_bool(Solvability.is_solvable(result.config)) \
			.override_failure_message("level %d not solvable" % n).is_true()


# --- D never exceeds the queue length of any cycled late-game layout's L when
# clamped by the generator (sanity: scheduled D <= 5 so layout-1 (L=6) fits fully). ---
func test_scheduled_d_capped_at_five() -> void:
	for n in range(1, 300):
		assert_int(DifficultySchedule.d_for(n, _data)).is_less_equal(5)
