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
## Emitted after a load attempt (whether the file existed or defaults were used).
signal loaded

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
func load_game() -> void:
	if not FileAccess.file_exists(_path):
		data = SaveData.defaults()
		loaded.emit()
		return

	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		push_warning("SaveService: cannot open %s (err %d); using defaults" % [_path, FileAccess.get_open_error()])
		data = SaveData.defaults()
		loaded.emit()
		return

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		data = SaveData.from_dict(parsed as Dictionary)
	else:
		push_warning("SaveService: corrupt save at %s; using defaults" % _path)
		data = SaveData.defaults()
	loaded.emit()


## Writes [member data] to disk as JSON. On open failure the call is a no-op
## (the previous save, if any, is left intact).
func save_game() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot write %s (err %d)" % [_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data.to_dict()))
	file.close()
	saved.emit()


## Sets the current level (clamped to >= 1) and persists.
func set_current_level(level: int) -> void:
	data.current_level = maxi(1, level)
	save_game()


## Records the audience band from the age gate (ADR-0005) and persists.
func set_age_band(band: SaveData.AgeBand) -> void:
	data.age_band = band
	save_game()
