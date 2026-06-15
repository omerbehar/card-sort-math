extends GdUnitTestSuite
## Integration contract for the remote-config path (S4-005): the real
## [JsonRemoteConfigSource] + a stub [ConfigTransport] driving the real
## [EconomyConfigLoader] merge policy end-to-end (remote-wins, local-fallback,
## per-key type filtering). No real network; a fresh non-autoload loader per test.

const LOADER_SCRIPT := preload("res://autoloads/economy_config_loader.gd")
const SOURCE_SCRIPT := preload("res://autoloads/json_remote_config_source.gd")
const TRANSPORT := preload("res://autoloads/config_transport.gd")


func _local_base() -> EconomyConfig:
	var cfg := EconomyConfig.new()
	cfg.picker_cost_coins = 120
	cfg.reshuffle_cost_coins = 250
	return cfg


# Builds a loader wired to a JsonRemoteConfigSource fed the given JSON payload.
func _loader_with_payload(payload: String, fail: bool = false):
	var transport = TRANSPORT.StubConfigTransport.new()
	transport.payload = payload
	transport.should_fail = fail
	var source = SOURCE_SCRIPT.new()
	source.configure(transport)
	var loader = auto_free(LOADER_SCRIPT.new())
	loader.configure(_local_base(), source)
	return loader


func test_remote_json_int_override_wins_over_local() -> void:
	# JSON gives float 90.0; the loader coerces it onto the int knob (S4-005).
	var loader = _loader_with_payload('{"picker_cost_coins": 90}')
	assert_int(loader.get_config().picker_cost_coins).is_equal(90)


func test_partial_override_leaves_other_knobs_local() -> void:
	var loader = _loader_with_payload('{"picker_cost_coins": 90}')
	var cfg: EconomyConfig = loader.get_config()
	assert_int(cfg.picker_cost_coins).is_equal(90)    # remote
	assert_int(cfg.reshuffle_cost_coins).is_equal(250)  # local kept


func test_failed_fetch_falls_back_to_local_defaults() -> void:
	var loader = _loader_with_payload('{"picker_cost_coins": 90}', true)
	var cfg: EconomyConfig = loader.get_config()
	assert_int(cfg.picker_cost_coins).is_equal(120)   # local
	assert_int(cfg.reshuffle_cost_coins).is_equal(250)


func test_type_mismatch_key_ignored_local_kept() -> void:
	# String for an int knob → not numerically coercible → ignored; local kept.
	var loader = _loader_with_payload('{"picker_cost_coins": "free", "reshuffle_cost_coins": 200}')
	var cfg: EconomyConfig = loader.get_config()
	assert_int(cfg.picker_cost_coins).is_equal(120)   # mismatch ignored
	assert_int(cfg.reshuffle_cost_coins).is_equal(200)  # valid remote applied


func test_malformed_payload_never_corrupts_config() -> void:
	var loader = _loader_with_payload('{garbage')
	var cfg: EconomyConfig = loader.get_config()
	assert_int(cfg.picker_cost_coins).is_equal(120)
	assert_int(cfg.reshuffle_cost_coins).is_equal(250)
