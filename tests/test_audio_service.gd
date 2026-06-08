extends GdUnitTestSuite
## Tests for [AudioService] settings gating + cue preloading (S1-004).
##
## Audio output ("feel") is verified manually; these cover the deterministic
## logic: that playback is gated by Settings and that cues/music preload. The
## service is given an injected SettingsService backed by a temp-file save.

const AUDIO_SCRIPT := preload("res://autoloads/audio_service.gd")
const SETTINGS_SCRIPT := preload("res://autoloads/settings_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const TEST_PATH := "user://test_audio_service.json"


func before_test() -> void:
	_remove_test_file()


func after_test() -> void:
	_remove_test_file()


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(TEST_PATH.get_file())


# Builds a SettingsService backed by a fresh temp-file save.
func _make_settings():
	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(TEST_PATH)
	save.load_game()
	var settings = auto_free(SETTINGS_SCRIPT.new())
	settings.configure(save)
	return settings


func _make_audio(settings):
	var audio = auto_free(AUDIO_SCRIPT.new())
	audio.configure(settings)
	return audio


func test_sfx_enabled_reflects_sound_setting() -> void:
	var settings = _make_settings()
	var audio = _make_audio(settings)
	assert_bool(audio.is_sfx_enabled()).is_true()
	settings.set_value("sound", false)
	assert_bool(audio.is_sfx_enabled()).is_false()


func test_music_enabled_reflects_music_setting() -> void:
	var settings = _make_settings()
	var audio = _make_audio(settings)
	assert_bool(audio.is_music_enabled()).is_true()
	settings.set_value("music", false)
	assert_bool(audio.is_music_enabled()).is_false()


func test_event_streams_are_preloaded() -> void:
	var audio = _make_audio(_make_settings())
	assert_object(audio.event_stream(GameEvent.Kind.ROUTE)).is_not_null()
	assert_object(audio.event_stream(GameEvent.Kind.LOSE)).is_not_null()


func test_unknown_event_kind_has_no_stream() -> void:
	var audio = _make_audio(_make_settings())
	assert_object(audio.event_stream(999)).is_null()


func test_play_event_with_sound_off_is_a_noop() -> void:
	# Arrange: sound disabled
	var settings = _make_settings()
	settings.set_value("sound", false)
	var audio = _make_audio(settings)
	# Act: should not raise and should not start playback
	audio.play_event(GameEvent.route(0, 0))
	# Assert: nothing is playing
	assert_bool(_any_sfx_playing(audio)).is_false()


func _any_sfx_playing(audio) -> bool:
	for player: AudioStreamPlayer in audio._sfx_players:
		if player.playing:
			return true
	return false
