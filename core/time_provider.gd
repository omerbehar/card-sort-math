class_name TimeProvider
extends RefCounted
## Injectable clock seam. Every economy and level system that needs "now" reads
## time through an instance of this class rather than calling the engine clock
## directly.
##
## [b]Determinism contract (extends ADR-0007 to time):[/b] this default
## implementation is the [b]ONLY[/b] code in the project permitted to call
## [method Time.get_unix_time_from_system]. No [code]core/[/code], economy, or
## level code may call [code]Time.get_unix_time_from_system()[/code],
## [code]Time.get_datetime_dict_from_system()[/code], [code]OS[/code]-clock APIs,
## or [code]Time.get_ticks_*()[/code] directly. Tests inject a
## [FixedTimeProvider] stub so every time-dependent assertion is deterministic and
## headless-safe (no real clock, no timezone). Production wires
## [code]TimeProvider.new()[/code] via the same [code]configure()[/code] injection
## pattern used by [code]SaveService[/code] and [code]ComplianceService[/code].
##
## Source: design/gdd/deck-economy.md Formula 6/8, Rules 14–16, AC-R04/R08,
##         AC-EF04, Open Questions; ADR-0009 (Key Interfaces).


## Returns the current Unix epoch time in whole seconds.
##
## This is the [b]sole authorised call site[/b] for
## [method Time.get_unix_time_from_system] in the project. All other code that
## needs the current time must read it through an injected [TimeProvider]
## instance — never by calling the engine clock directly.
##
## Used as [code]level_start_timestamp[/code] in Formula 6
## ([method ReshuffleSeed.mix]) and as the raw basis for
## [method utc_day_key].
func unix_seconds() -> int:
	return int(Time.get_unix_time_from_system())


## Returns an integer key identifying the current UTC calendar day (days since
## the Unix epoch, i.e. [code]unix_seconds() / 86_400[/code]).
##
## Every calendar-day-keyed economy decision routes through this method —
## including: the rewarded-ad coin cap reset (Formula 8, Rule 15), the
## daily-challenge reset (Rule 14), the login-streak missed-day / rollover
## transitions (Rule 16), the [code]first_win_today[/code] flag (Formula 1),
## and the gem-to-coin daily cap ([code]DAILY_GEM_CONVERT_CAP[/code], Rule 21).
## Centralising all "what day is it" logic here means a single injected
## [FixedTimeProvider] drives the entire daily-reset surface deterministically
## in tests (AC-EF04).
##
## Uses UTC throughout (integer floor division on epoch seconds), matching the
## GDD's "midnight UTC" reset specification (Rules 14–16).
func utc_day_key() -> int:
	return unix_seconds() / 86_400
