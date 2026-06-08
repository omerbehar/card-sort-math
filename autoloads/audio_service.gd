extends Node
## Autoload (view/presentation layer): plays SFX for [GameEvent]s and a looping
## music bed, gated by [Settings] via [SettingsService].
##
## Depends on core's [GameEvent] value object (allowed direction: view -> core);
## the pure model never depends on audio. Cue selection lives in the testable
## [AudioCues]; this class owns the [AudioStreamPlayer]s and playback only.
##
## The settings service is injectable (see [method configure]) so the gating
## logic is unit-testable. Implements Sprint 1 story S1-004.

const SFX_POOL_SIZE: int = 6

# SettingsService; resolves to the autoload at runtime, injectable in tests.
var _settings = null

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0
var _music_player: AudioStreamPlayer = null
var _event_streams: Dictionary = {}   # GameEvent.Kind -> AudioStream
var _ui_streams: Dictionary = {}      # UI cue name -> AudioStream
var _music_stream: AudioStream = null
var _initialized: bool = false


func _ready() -> void:
	if _settings == null:
		_settings = SettingsService
	_init_audio()
	_connect_settings()
	refresh_music()


## Injects the settings service and initializes audio. Intended for tests; normal
## play uses the [code]SettingsService[/code] autoload automatically.
func configure(settings: Object) -> void:
	_settings = settings
	_init_audio()
	_connect_settings()


## Plays the SFX cue for a resolved [GameEvent], if sound is enabled. Kinds with
## no mapped cue (all kinds are mapped today; defensive for future ones) are
## simply skipped.
func play_event(event: GameEvent) -> void:
	if not is_sfx_enabled():
		return
	if _event_streams.has(event.kind):
		_play_stream(_event_streams[event.kind])


## Plays a named UI cue (see [constant AudioCues.UI_CUES]) if sound is enabled.
func play_ui(cue: String) -> void:
	if not is_sfx_enabled():
		return
	if _ui_streams.has(cue):
		_play_stream(_ui_streams[cue])


## Starts / stops the music bed to match the current music setting.
func refresh_music() -> void:
	if _music_player == null:
		return
	if is_music_enabled() and _music_stream != null:
		if not _music_player.playing:
			_music_player.play()
	else:
		_music_player.stop()


func is_sfx_enabled() -> bool:
	return _settings != null and _settings.get_value("sound")


func is_music_enabled() -> bool:
	return _settings != null and _settings.get_value("music")


## The preloaded stream for a [GameEvent] kind, or null. Exposed for tests.
func event_stream(kind: int) -> AudioStream:
	return _event_streams.get(kind, null)


func _init_audio() -> void:
	if _initialized:
		return
	_initialized = true

	for _i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)

	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)

	for kind: int in AudioCues.EVENT_CUES:
		var path: String = AudioCues.event_cue_path(kind)
		if ResourceLoader.exists(path):
			_event_streams[kind] = load(path)

	# Preload UI cues too, so a button press never blocks on disk I/O.
	for cue: String in AudioCues.UI_CUES:
		var ui_path: String = AudioCues.ui_cue_path(cue)
		if ResourceLoader.exists(ui_path):
			_ui_streams[cue] = load(ui_path)

	if ResourceLoader.exists(AudioCues.MUSIC_PATH):
		# Looping is set in the .import (loop=true) — no runtime fixup needed.
		_music_stream = load(AudioCues.MUSIC_PATH)
		_music_player.stream = _music_stream


func _connect_settings() -> void:
	if _settings != null and not _settings.changed.is_connected(_on_setting_changed):
		_settings.changed.connect(_on_setting_changed)


# Round-robin across the SFX pool so overlapping cues don't cut each other off.
func _play_stream(stream: AudioStream) -> void:
	if _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	player.stream = stream
	player.play()


func _on_setting_changed(key: String, _value: bool) -> void:
	# Sound toggles take effect on the next SFX via is_sfx_enabled(); only music
	# needs an immediate start/stop.
	if key == "music":
		refresh_music()
