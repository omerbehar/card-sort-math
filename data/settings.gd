class_name Settings
extends RefCounted
## Typed, node-free player settings model.
##
## Pure data: serializes to / from a plain [Dictionary] and is persisted as part
## of [SaveData]. The app and UI read and mutate settings through
## [SettingsService], which wraps the instance held by the save. Keeping this
## typed (rather than a raw dictionary) gives callers compile-time keys and a
## single source of truth for defaults.

var sound: bool = true
var music: bool = true
var haptics: bool = true
var reduced_motion: bool = false
var colorblind: bool = false

## Ordered list of the persisted keys — the canonical settings schema.
const KEYS: Array[String] = ["sound", "music", "haptics", "reduced_motion", "colorblind"]


## A fresh settings object with safe defaults.
static func defaults() -> Settings:
	return Settings.new()


## Serializes to a plain [Dictionary] suitable for JSON.
func to_dict() -> Dictionary:
	return {
		"sound": sound,
		"music": music,
		"haptics": haptics,
		"reduced_motion": reduced_motion,
		"colorblind": colorblind,
	}


## Builds a [Settings] from a parsed value. Non-dictionaries and missing/garbage
## keys fall back to defaults, so a corrupt save never yields invalid settings.
static func from_dict(raw: Variant) -> Settings:
	var s := Settings.new()
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		s.sound = _read_bool(d, "sound", s.sound)
		s.music = _read_bool(d, "music", s.music)
		s.haptics = _read_bool(d, "haptics", s.haptics)
		s.reduced_motion = _read_bool(d, "reduced_motion", s.reduced_motion)
		s.colorblind = _read_bool(d, "colorblind", s.colorblind)
	return s


## Reads a single boolean by key. Returns the default for unknown keys.
func get_value(key: String) -> bool:
	match key:
		"sound": return sound
		"music": return music
		"haptics": return haptics
		"reduced_motion": return reduced_motion
		"colorblind": return colorblind
		_:
			push_warning("Settings: unknown key '%s'" % key)
			return false


## Sets a single boolean by key. Unknown keys are ignored (with a warning) and
## return [code]false[/code]; a successful set returns [code]true[/code].
func set_value(key: String, value: bool) -> bool:
	match key:
		"sound": sound = value
		"music": music = value
		"haptics": haptics = value
		"reduced_motion": reduced_motion = value
		"colorblind": colorblind = value
		_:
			push_warning("Settings: cannot set unknown key '%s'" % key)
			return false
	return true


static func _read_bool(d: Dictionary, key: String, fallback: bool) -> bool:
	return bool(d[key]) if d.has(key) else fallback
