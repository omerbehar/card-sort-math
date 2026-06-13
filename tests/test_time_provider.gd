extends GdUnitTestSuite
## Tests for [TimeProvider], [FixedTimeProvider], and [ReshuffleSeed.mix] —
## S3-003 (Deck Economy: injectable TimeProvider seam + reshuffle seed helper).
##
## Coverage:
##   - FixedTimeProvider.unix_seconds() returns the injected value (not a real clock).
##   - Default TimeProvider.unix_seconds() returns a plausible positive integer (smoke).
##   - utc_day_key(): two timestamps in the same UTC day share a key.
##   - utc_day_key(): one second across an 86_400 boundary produces different keys.
##   - utc_day_key(): a fixed clock at 86_400 * N yields key exactly N.
##   - ReshuffleSeed.mix(): reproducible — same inputs always produce the same output.
##   - ReshuffleSeed.mix(): per-count difference (AC-R04).
##   - ReshuffleSeed.mix(): cross-session difference (AC-R08).
##   - ReshuffleSeed.mix(): result is non-negative and within the 63-bit ceiling.
##
## All tests are deterministic: no random seeds, no real-time assertions, no I/O.
## Source: design/gdd/deck-economy.md Formula 6, AC-R04/R08; ADR-0009.


# ---------------------------------------------------------------------------
# FixedTimeProvider — injected value round-trips
# ---------------------------------------------------------------------------

func test_fixed_time_provider_unix_seconds_returns_injected_value() -> void:
	# Arrange
	var clock := FixedTimeProvider.new()
	clock.now_seconds = 1_718_000_000
	# Act / Assert
	assert_int(clock.unix_seconds()).is_equal(1_718_000_000)


func test_fixed_time_provider_unix_seconds_reflects_updated_value() -> void:
	# Arrange
	var clock := FixedTimeProvider.new()
	clock.now_seconds = 100
	# Act — update the fixed value
	clock.now_seconds = 200
	# Assert
	assert_int(clock.unix_seconds()).is_equal(200)


# ---------------------------------------------------------------------------
# Default TimeProvider — smoke (not pinned to wall clock)
# ---------------------------------------------------------------------------

func test_default_time_provider_unix_seconds_returns_positive_int() -> void:
	# Smoke: the default provider wraps the real engine clock; we only assert it
	# is a plausible Unix timestamp (> 0). We intentionally do NOT pin the exact
	# value — that would make CI depend on the runner's wall clock.
	var clock := TimeProvider.new()
	assert_int(clock.unix_seconds()).is_greater(0)


# ---------------------------------------------------------------------------
# utc_day_key — day boundary arithmetic
# ---------------------------------------------------------------------------

func test_utc_day_key_two_timestamps_in_same_day_share_key() -> void:
	# Arrange: two times within the same UTC day (day 19884 = 2024-06-10)
	var clock := FixedTimeProvider.new()
	clock.now_seconds = 86_400 * 19884           # exactly midnight UTC day 19884
	var key_start: int = clock.utc_day_key()
	clock.now_seconds = 86_400 * 19884 + 86_399  # one second before the next midnight
	var key_end: int = clock.utc_day_key()
	# Assert
	assert_int(key_start).is_equal(key_end)


func test_utc_day_key_one_second_across_boundary_yields_different_keys() -> void:
	# Arrange: last second of day N and first second of day N+1
	var clock := FixedTimeProvider.new()
	var day_n: int = 19884
	clock.now_seconds = 86_400 * day_n + 86_399   # 23:59:59 UTC day N
	var key_before: int = clock.utc_day_key()
	clock.now_seconds = 86_400 * (day_n + 1)       # 00:00:00 UTC day N+1
	var key_after: int = clock.utc_day_key()
	# Assert
	assert_int(key_after).is_equal(key_before + 1)


func test_utc_day_key_epoch_multiple_n_yields_key_n() -> void:
	# Arrange: a fixed clock at exactly 86_400 * N seconds
	var clock := FixedTimeProvider.new()
	var n: int = 5000
	clock.now_seconds = 86_400 * n
	# Act / Assert — integer floor division must yield N exactly
	assert_int(clock.utc_day_key()).is_equal(n)


# ---------------------------------------------------------------------------
# ReshuffleSeed.mix — determinism properties (AC-R04, AC-R08)
# ---------------------------------------------------------------------------

func test_mix_reproducible_same_inputs_same_output() -> void:
	# AC-R04 (part 1): calling mix with identical inputs always returns the same
	# value — no hidden state or random component.
	var result_a: int = ReshuffleSeed.mix(42, 1_718_000_000, 1)
	var result_b: int = ReshuffleSeed.mix(42, 1_718_000_000, 1)
	assert_int(result_a).is_equal(result_b)


func test_mix_per_count_difference_consecutive_reshuffles_differ(
		) -> void:
	# AC-R04: two consecutive reshuffles on the same level (same session) must
	# produce different seeds so the layout actually changes.
	var seed_1: int = ReshuffleSeed.mix(42, 1_718_000_000, 1)
	var seed_2: int = ReshuffleSeed.mix(42, 1_718_000_000, 2)
	assert_int(seed_1).is_not_equal(seed_2)


func test_mix_cross_session_different_timestamp_yields_different_seed() -> void:
	# AC-R08: two sessions starting one second apart produce different seeds,
	# preventing a cross-session layout replay.
	var t: int = 1_718_000_000
	var seed_t0: int = ReshuffleSeed.mix(42, t, 1)
	var seed_t1: int = ReshuffleSeed.mix(42, t + 1, 1)
	assert_int(seed_t0).is_not_equal(seed_t1)


func test_mix_result_is_non_negative() -> void:
	# The & 0x7FFFFFFFFFFFFFFF mask must strip the sign bit; result is always >= 0.
	var seed: int = ReshuffleSeed.mix(42, 1_718_000_000, 1)
	assert_int(seed).is_greater_equal(0)


func test_mix_result_within_63_bit_ceiling() -> void:
	# Result must fit in a non-negative 63-bit integer so it is safe to assign
	# directly to rng.seed (ADR-0007 §2 / ADR-0009).
	var seed: int = ReshuffleSeed.mix(42, 1_718_000_000, 1)
	assert_int(seed).is_less_equal(0x7FFFFFFFFFFFFFFF)
