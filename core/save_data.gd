class_name SaveData
extends RefCounted
## Pure, node-free player save state with (de)serialization and schema migration.
##
## Holds everything persisted between runs. [method to_dict] / [method from_dict]
## are the serialization seam; [SaveService] performs the actual file I/O. Keeping
## this class pure (no [Node], no file access) makes save / load / migration fully
## unit-testable (see [code]tests/test_save_data.gd[/code]) per ADR-0001.
##
## Persisted fields: [member schema_version], [member current_level],
## [member age_band], [member settings], [member tutorial_seen],
## [member wallet_coins], [member wallet_gems].

## Bump when the persisted shape changes, and add a step to [method _migrate].
const CURRENT_SCHEMA_VERSION: int = 2

## Audience band from the neutral age gate (see ADR-0005). Drives ad / analytics /
## IAP behaviour via the future ComplianceService.
enum AgeBand { UNKNOWN, ADULT, CHILD }

var schema_version: int = CURRENT_SCHEMA_VERSION
var current_level: int = 1
var age_band: AgeBand = AgeBand.UNKNOWN
var settings: Settings = Settings.new()
## Whether the player has already seen the first-time tutorial coach.
## Defaults to [code]false[/code]. Set to [code]true[/code] on first ROUTE (or
## safety-valve / LOSE) while coaching (see [code]design/gdd/first-time-tutorial.md[/code]
## §3 R6). Missing-key-defaulted in [method from_dict]; no schema bump required —
## old saves correctly default to [code]false[/code] (they have not seen the tutorial).
var tutorial_seen: bool = false

## Coin balance (soft currency). Persisted from [WalletData.coins].
## Added in schema v2 (S3-002 / design/gdd/deck-economy.md §Core Rule 3).
## Clamped to >= 0 in [method from_dict]; upper cap applied by WalletService (S3-004).
var wallet_coins: int = 0

## Gem balance (hard currency). Persisted from [WalletData.gems].
## Added in schema v2 (S3-002 / design/gdd/deck-economy.md §Core Rule 3).
## Clamped to >= 0 in [method from_dict]; upper cap applied by WalletService (S3-004).
var wallet_gems: int = 0


## A fresh save with safe defaults.
static func defaults() -> SaveData:
	return SaveData.new()


## Serializes to a plain [Dictionary] suitable for JSON.
func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"current_level": current_level,
		"age_band": int(age_band),
		"settings": settings.to_dict(),
		"tutorial_seen": tutorial_seen,
		"wallet_coins": wallet_coins,
		"wallet_gems": wallet_gems,
	}


## Builds a [SaveData] from a parsed dictionary, migrating older schema versions
## and validating / clamping every field. Corrupt or missing fields fall back to
## safe defaults rather than failing — a bad save never crashes the game.
static func from_dict(dict: Dictionary) -> SaveData:
	var from_version: int = int(dict.get("schema_version", 0))
	var migrated: Dictionary = _migrate(dict, from_version)

	var data := SaveData.new()
	data.schema_version = CURRENT_SCHEMA_VERSION
	data.current_level = maxi(1, int(migrated.get("current_level", 1)))
	data.age_band = _parse_age_band(migrated.get("age_band", AgeBand.UNKNOWN))
	data.settings = Settings.from_dict(migrated.get("settings", {}))
	data.tutorial_seen = bool(migrated.get("tutorial_seen", false))
	data.wallet_coins = maxi(0, _safe_int(migrated.get("wallet_coins", 0)))
	data.wallet_gems = maxi(0, _safe_int(migrated.get("wallet_gems", 0)))
	return data


# Upgrades a raw dict from [param from_version] to the current schema. Each step
# transforms version N into N+1; add a new `if version == N:` block per bump.
# Pre-versioned/unknown saves arrive as version 0 and flow through unchanged into
# the validation in [method from_dict].
static func _migrate(dict: Dictionary, from_version: int) -> Dictionary:
	var out: Dictionary = dict.duplicate(true)
	var version: int = from_version
	# v1 → v2: wallet fields introduced (S3-002, design/gdd/deck-economy.md §Dependencies Save Service).
	if version == 1:
		out["wallet_coins"] = 0
		out["wallet_gems"] = 0
		version = 2
	return out


# Coerces a Variant to int, treating null and non-numeric values as 0.
# Required because int(null) raises in GDScript — a save with an explicit JSON null
# for a numeric field must not crash (mirrors the null-guard in _parse_age_band).
static func _safe_int(value: Variant) -> int:
	if value == null:
		return 0
	if value is int or value is float:
		return int(value)
	return 0


# Accepts an int / float / enum value; null, non-numeric, or out-of-range -> UNKNOWN.
# Guards the numeric coercion: int(null) and int("x") raise in GDScript, so a save
# with an explicit JSON null age_band must be rejected before coercion (a bad save
# never crashes — see GDD Edge Case 7 / AC AG-06).
static func _parse_age_band(value: Variant) -> AgeBand:
	if not (value is int or value is float):
		return AgeBand.UNKNOWN
	match int(value):
		AgeBand.ADULT:
			return AgeBand.ADULT
		AgeBand.CHILD:
			return AgeBand.CHILD
		_:
			return AgeBand.UNKNOWN
