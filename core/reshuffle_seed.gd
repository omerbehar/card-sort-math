class_name ReshuffleSeed
extends RefCounted
## Pure static helper that derives a deterministic reshuffle seed from three
## integer inputs via an explicit integer mix. Used by the Reshuffle booster
## path (S3-009, Formula 6) ahead of that story so its determinism is locked in
## early and property-tested independently.
##
## [b]Why not [code]hash()[/code]:[/b] GDScript [code]hash()[/code] is
## implementation-defined and [b]not stable across platforms or Godot versions[/b]
## — ADR-0007 §2 bans it for any value fed to [code]rng.seed[/code] because it
## would break cross-device reshuffle reproducibility (daily-challenge identity,
## shareable seeds, AC-R04/R08). This helper uses only pure 64-bit integer
## arithmetic; Godot [code]int[/code] overflow wraps deterministically, so the
## result is platform- and version-stable everywhere.
##
## The [param level_start_timestamp] argument is obtained from
## [method TimeProvider.unix_seconds] — never from
## [code]Time.get_unix_time_from_system()[/code] directly (ADR-0009 seam).
##
## Source: design/gdd/deck-economy.md Formula 6; ADR-0009
## §"Reshuffle seed derivation — explicit integer mix".


## Knuth/Fibonacci multiplicative constant (first mix step).
## Pinned by ADR-0009; must not be changed without a new ADR and
## re-running the property tests in [code]test_time_provider.gd[/code].
const MIX_A: int = 0x9E3779B1   # 2654435761

## Second mix constant.
## Pinned by ADR-0009.
const MIX_B: int = 0x85EBCA77   # 2246822519

## Third mix constant.
## Pinned by ADR-0009.
const MIX_C: int = 0xC2B2AE3D   # 3266489917


## Returns a non-negative 63-bit integer suitable for use as [code]rng.seed[/code].
##
## The result changes for [b]any[/b] difference in [param level_start_timestamp]
## (cross-session anti-replay, AC-R08) or in [param reshuffle_count]
## (consecutive reshuffles produce different layouts, AC-R04). Cross-level
## collisions are harmless: a different card set still satisfies the solvability
## invariant, and at worst the player sees a déjà-vu layout.
##
## Caller is responsible for sourcing [param level_start_timestamp] via an
## injected [TimeProvider] instance captured once at level entry, so the same
## timestamp is reused across all reshuffles of that level (Formula 6 stability).
##
## [param level_id]: stable [code]LevelConfig.level_id[/code] for this level.
## [param level_start_timestamp]: Unix epoch seconds from [TimeProvider.unix_seconds].
## [param reshuffle_count]: 1-based count of reshuffles used on this level so far.
static func mix(level_id: int, level_start_timestamp: int, reshuffle_count: int) -> int:
	var s: int = level_id * MIX_A
	s = (s ^ level_start_timestamp) * MIX_B
	s = (s ^ reshuffle_count) * MIX_C
	s ^= (s >> 16)
	return s & 0x7FFFFFFFFFFFFFFF   # non-negative 63-bit; passed straight to rng.seed
