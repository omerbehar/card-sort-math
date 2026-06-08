class_name SaveData
extends RefCounted
## Pure, node-free player save state with (de)serialization and schema migration.
##
## Holds everything persisted between runs. [method to_dict] / [method from_dict]
## are the serialization seam; [SaveService] performs the actual file I/O. Keeping
## this class pure (no [Node], no file access) makes save / load / migration fully
## unit-testable (see [code]tests/test_save_data.gd[/code]) per ADR-0001.

## Bump when the persisted shape changes, and add a step to [method _migrate].
const CURRENT_SCHEMA_VERSION: int = 1

## Audience band from the neutral age gate (see ADR-0005). Drives ad / analytics /
## IAP behaviour via the future ComplianceService.
enum AgeBand { UNKNOWN, ADULT, CHILD }

var schema_version: int = CURRENT_SCHEMA_VERSION
var current_level: int = 1
var age_band: AgeBand = AgeBand.UNKNOWN
var settings: Dictionary = _default_settings()


## A fresh save with safe defaults.
static func defaults() -> SaveData:
	return SaveData.new()


## Serializes to a plain [Dictionary] suitable for JSON.
func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"current_level": current_level,
		"age_band": int(age_band),
		"settings": settings.duplicate(true),
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
	data.settings = _merge_settings(migrated.get("settings", {}))
	return data


# Upgrades a raw dict from [param from_version] to the current schema. Each step
# transforms version N into N+1; add a new `if version == N:` block per bump.
# Pre-versioned/unknown saves arrive as version 0 and flow through unchanged into
# the validation in [method from_dict].
static func _migrate(dict: Dictionary, from_version: int) -> Dictionary:
	var out: Dictionary = dict.duplicate(true)
	var version: int = from_version
	# Example (future): migrating v1 -> v2 would go here.
	# if version == 1:
	#     out["new_field"] = <default>
	#     version = 2
	return out


static func _default_settings() -> Dictionary:
	return {
		"sound": true,
		"music": true,
		"haptics": true,
		"reduced_motion": false,
	}


# Accepts an int or enum value; anything outside the known bands -> UNKNOWN.
static func _parse_age_band(value: Variant) -> AgeBand:
	match int(value):
		AgeBand.ADULT:
			return AgeBand.ADULT
		AgeBand.CHILD:
			return AgeBand.CHILD
		_:
			return AgeBand.UNKNOWN


# Starts from defaults and overlays only known, type-checked keys, so unknown or
# malformed entries in a save can never introduce stray/garbage settings.
static func _merge_settings(raw: Variant) -> Dictionary:
	var merged: Dictionary = _default_settings()
	if raw is Dictionary:
		for key: String in merged:
			if (raw as Dictionary).has(key):
				merged[key] = bool((raw as Dictionary)[key])
	return merged
