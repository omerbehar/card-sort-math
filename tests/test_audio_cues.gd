extends GdUnitTestSuite
## Tests for the [AudioCues] event/UI -> path mapping (S1-004).


func test_every_event_kind_with_a_cue_resolves_to_an_existing_file() -> void:
	for kind: int in AudioCues.EVENT_CUES:
		var path: String = AudioCues.event_cue_path(kind)
		assert_str(path).is_not_empty()
		assert_bool(ResourceLoader.exists(path)) \
			.override_failure_message("Missing audio file: %s" % path) \
			.is_true()


func test_all_ui_cues_resolve_to_existing_files() -> void:
	for name: String in AudioCues.UI_CUES:
		var path: String = AudioCues.ui_cue_path(name)
		assert_bool(ResourceLoader.exists(path)) \
			.override_failure_message("Missing UI audio file: %s" % path) \
			.is_true()


func test_event_cue_path_for_unknown_kind_is_empty() -> void:
	# 999 is not a valid GameEvent.Kind
	assert_str(AudioCues.event_cue_path(999)).is_empty()


func test_ui_cue_path_for_unknown_name_is_empty() -> void:
	assert_str(AudioCues.ui_cue_path("nonexistent")).is_empty()


func test_distinct_events_map_to_distinct_cues() -> void:
	# Win and lose must not share a cue (feedback must be distinguishable).
	var win: String = AudioCues.event_cue_path(GameEvent.Kind.WIN)
	var lose: String = AudioCues.event_cue_path(GameEvent.Kind.LOSE)
	assert_str(win).is_not_equal(lose)


func test_music_path_exists() -> void:
	assert_bool(ResourceLoader.exists(AudioCues.MUSIC_PATH)) \
		.override_failure_message("Missing music: %s" % AudioCues.MUSIC_PATH) \
		.is_true()
