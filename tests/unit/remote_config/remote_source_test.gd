extends GdUnitTestSuite
## Unit tests for [JsonRemoteConfigSource] — fetch + parse via an injected transport (S4-005).
##
## All inputs are injected ([ConfigTransport.StubConfigTransport]); no real network. Per-key
## type/unknown filtering is the loader's job (covered in the integration contract test) — here
## we verify the source's parse + fail-safe contract (always a Dictionary, never null).

const SOURCE_SCRIPT := preload("res://autoloads/json_remote_config_source.gd")
const TRANSPORT := preload("res://autoloads/config_transport.gd")


func _source(payload: String, fail: bool = false):
	var transport = TRANSPORT.StubConfigTransport.new()
	transport.payload = payload
	transport.should_fail = fail
	var src = SOURCE_SCRIPT.new()
	src.configure(transport)
	return src


func test_valid_json_object_parsed_into_overrides() -> void:
	var src = _source('{"picker_cost_coins": 90, "reshuffle_cost_coins": 200}')
	var overrides: Dictionary = src.fetch_overrides()
	assert_int(overrides.size()).is_equal(2)
	# JSON numbers parse as float — the loader coerces to the knob's type (tested there).
	assert_float(overrides["picker_cost_coins"]).is_equal(90.0)
	assert_float(overrides["reshuffle_cost_coins"]).is_equal(200.0)


func test_empty_payload_yields_empty_dict() -> void:
	var src = _source("")
	assert_int(src.fetch_overrides().size()).is_equal(0)


func test_failed_transport_yields_empty_dict() -> void:
	var src = _source('{"picker_cost_coins": 90}', true)  # transport simulates failure
	assert_int(src.fetch_overrides().size()).is_equal(0)


func test_malformed_json_yields_empty_dict_not_null() -> void:
	var src = _source('{not valid json')
	var overrides: Dictionary = src.fetch_overrides()
	assert_object(overrides).is_not_null()
	assert_int(overrides.size()).is_equal(0)


func test_non_object_top_level_json_yields_empty_dict() -> void:
	# A JSON array (or scalar) at the top level is not an overrides map → {}.
	assert_int(_source('[1, 2, 3]').fetch_overrides().size()).is_equal(0)
	assert_int(_source('42').fetch_overrides().size()).is_equal(0)


func test_unconfigured_source_falls_back_to_empty() -> void:
	# No transport injected → base no-op transport → no overrides (local fallback).
	var src = SOURCE_SCRIPT.new()
	assert_int(src.fetch_overrides().size()).is_equal(0)


func test_extra_unknown_keys_passed_through_verbatim() -> void:
	# The source does not filter; it returns the parsed object as-is (loader filters per key).
	var src = _source('{"picker_cost_coins": 90, "totally_unknown_key": 5}')
	var overrides: Dictionary = src.fetch_overrides()
	assert_bool(overrides.has("totally_unknown_key")).is_true()
