extends Node
## Autoload: persistence of [SaveData] to disk.
##
## Thin I/O layer over the pure [SaveData] (de)serializer — loads on boot and
## saves on demand. The save path is injectable (see [method configure]) so tests
## can target a temp file. Per ADR-0001 all save/migration logic lives in
## [SaveData]; this class only touches the filesystem.
##
## Implements Sprint 1 story S1-001 (`production/sprints/sprint-01.md`).

## Emitted after a successful write.
signal saved
## Emitted after a load that found a valid file, or no file at all (first launch).
signal loaded
## Emitted after a load whose file EXISTED but was unreadable or invalid JSON.
## Distinct from [signal loaded] so consumers/telemetry can tell lost data from a
## genuine first launch (see design/gdd/save-service.md Edge Case 14).
signal load_failed

const DEFAULT_PATH: String = "user://save.json"

var data: SaveData = SaveData.new()
var _path: String = DEFAULT_PATH


func _ready() -> void:
	load_game()


## Overrides the save file path. Intended for tests; call before [method load_game].
func configure(path: String) -> void:
	_path = path


## Loads the save file into [member data], falling back to safe defaults when the
## file is missing or its contents are unreadable / corrupt.
##
## Emits [signal loaded] on success or first launch (no file). Emits [signal
## load_failed] when a file existed but could not be read or parsed — the data is
## lost and defaults are used, but the caller can tell this apart from a new player.
## The on-disk file is never clobbered by a failed load.
func load_game() -> void:
	if not FileAccess.file_exists(_path):
		data = SaveData.defaults()
		loaded.emit()
		return

	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		push_warning("SaveService: cannot open %s (err %d); using defaults" % [_path, FileAccess.get_open_error()])
		data = SaveData.defaults()
		load_failed.emit()
		return

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		data = SaveData.from_dict(parsed as Dictionary)
		loaded.emit()
	else:
		push_warning("SaveService: corrupt save at %s; using defaults" % _path)
		data = SaveData.defaults()
		load_failed.emit()


## Writes [member data] to disk as JSON using an atomic temp-then-rename so an
## interrupted write never corrupts the live save (see ADR-0001; GDD Edge Case 4).
## On any failure the call is a no-op and the previous save, if any, is left intact.
func save_game() -> void:
	var tmp_path: String = _path + ".tmp"

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot write %s (err %d)" % [tmp_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data.to_dict()))
	file.close()

	# Atomic swap: rename the fully-written temp over the live file. On POSIX
	# (Android/iOS/Linux) rename is atomic and overwrites the destination, so a
	# crash can only ever damage the temp file, never the prior save.
	var dir := DirAccess.open(_path.get_base_dir())
	if dir == null:
		push_error("SaveService: cannot open save dir for %s (err %d)" % [_path, DirAccess.get_open_error()])
		return
	var err: Error = dir.rename(tmp_path, _path)
	if err != OK:
		push_error("SaveService: cannot finalize save %s (err %d)" % [_path, err])
		return
	saved.emit()


## Sets the current level (clamped to >= 1) and persists.
func set_current_level(level: int) -> void:
	data.current_level = maxi(1, level)
	save_game()


## Records the audience band from the age gate (ADR-0005) and persists.
func set_age_band(band: SaveData.AgeBand) -> void:
	data.age_band = band
	save_game()


## Records player consent choices from the CMP flow (ADR-0013 §3) and persists.
##
## Writes all three consent flags atomically (one save), sets [member SaveData.consent_captured]
## to [code]true[/code], and persists. [ComplianceService] verdicts reflect the new state on
## the very next call — no restart required.
##
## Usage (future CMP/UMP UI adapter, not yet built — vendor SDK deferred to native-SDK sprint):
## [codeblock]
## SaveService.capture_consent(personalized_ads: true, analytics: false, iap: true)
## [/codeblock]
func capture_consent(personalized_ads: bool, analytics: bool, iap: bool) -> void:
	data.consent_personalized_ads = personalized_ads
	data.consent_analytics = analytics
	data.consent_iap = iap
	data.consent_captured = true
	save_game()


## Withdraws a specific consent field and persists (ADR-0013 §3, "withdrawal immediacy").
##
## The withdrawal flips the relevant field to [code]false[/code] (denied) and persists.
## Because [ComplianceService] reads the live [SaveData] on every [code]can_*[/code] call,
## the corresponding verdict flips to restricted immediately — no restart, no cache.
##
## [param field] must be one of [code]"personalized_ads"[/code], [code]"analytics"[/code],
## or [code]"iap"[/code]. An unknown field is ignored with a warning.
func withdraw_consent(field: String) -> void:
	match field:
		"personalized_ads":
			data.consent_personalized_ads = false
		"analytics":
			data.consent_analytics = false
		"iap":
			data.consent_iap = false
		_:
			push_warning("SaveService.withdraw_consent: unknown field '%s'" % field)
			return
	save_game()
