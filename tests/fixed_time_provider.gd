class_name FixedTimeProvider
extends TimeProvider
## Deterministic [TimeProvider] stub for unit tests.
##
## Inject an instance of this class wherever a [TimeProvider] is required in
## tests; set [member now_seconds] to drive both [method unix_seconds] and,
## transitively, [method utc_day_key]. A single field controls the entire
## daily-reset surface, so tests can simulate day boundaries, streak
## transitions, and anti-replay scenarios without real-clock dependency.
##
## Used by: [code]test_time_provider.gd[/code] (S3-003); future stories
## S3-004 (daily-cap/streak) and S3-005+ will reuse the same fixture.
##
## Source: ADR-0009 §"Key Interfaces" (FixedTimeProvider design).
## Keep in [code]tests/[/code] — this is test-only infrastructure.


## The fixed Unix epoch seconds returned by [method unix_seconds].
## Default [code]0[/code] (1970-01-01T00:00:00Z, day key 0).
## Set this before calling any time-dependent code under test.
var now_seconds: int = 0


## Returns [member now_seconds] instead of the real engine clock.
## [method utc_day_key] is inherited and derives from this value automatically.
func unix_seconds() -> int:
	return now_seconds
