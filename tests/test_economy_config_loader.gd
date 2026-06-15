extends GdUnitTestSuite
## Unit tests for [EconomyConfigLoader] — remote-config-ready resolver (S3-011).
##
## Coverage:
##   - Local fallback: a no-op (or absent) remote source yields the local defaults.
##   - Remote override: a stub source's values win over the local base.
##   - Partial override: only the supplied knobs change; the rest stay local.
##   - Robustness: unknown keys, type-mismatched values, and a non-Dictionary
##     return are all ignored (a malformed payload never corrupts the config).
##   - Non-mutation: resolving never mutates the injected local base resource.
##   - Caching / reload: get_config() caches; reload() re-resolves.
##
## A fresh, non-autoload loader instance is built per test so the global autoload
## is never mutated. All inputs are injected — no real .tres, clock, or network.
##
## Source: design/gdd/deck-economy.md §Tuning Knobs; sprint-03 S3-011.

const LoaderScript := preload("res://autoloads/economy_config_loader.gd")


# A deterministic remote source stub returning a fixed override dictionary.
class StubRemoteSource extends RemoteConfigSource:
	var overrides: Dictionary = {}
	func fetch_overrides() -> Dictionary:
		return overrides


func _local_base() -> EconomyConfig:
	# A known local base distinct from script defaults where useful.
	var cfg := EconomyConfig.new()
	cfg.picker_cost_coins = 120
	cfg.reshuffle_cost_coins = 250
	return cfg


func _make_loader(local: EconomyConfig, remote: RemoteConfigSource) -> Node:
	var loader: Node = LoaderScript.new()
	loader.configure(local, remote)
	return loader


# ---------------------------------------------------------------------------
# Local fallback (no remote overrides)
# ---------------------------------------------------------------------------

func test_no_op_remote_yields_local_values() -> void:
	var loader := _make_loader(_local_base(), RemoteConfigSource.new())
	var cfg: EconomyConfig = loader.get_config()
	assert_int(cfg.picker_cost_coins).is_equal(120)
	assert_int(cfg.reshuffle_cost_coins).is_equal(250)
	loader.free()


func test_empty_override_yields_local_values() -> void:
	var loader := _make_loader(_local_base(), StubRemoteSource.new())  # overrides default {}
	assert_int(loader.get_config().picker_cost_coins).is_equal(120)
	loader.free()


# ---------------------------------------------------------------------------
# Remote overrides win
# ---------------------------------------------------------------------------

func test_remote_override_wins_over_local() -> void:
	var remote := StubRemoteSource.new()
	remote.overrides = {"picker_cost_coins": 90}
	var loader := _make_loader(_local_base(), remote)
	assert_int(loader.get_config().picker_cost_coins).is_equal(90)
	loader.free()


func test_partial_override_leaves_other_knobs_local() -> void:
	var remote := StubRemoteSource.new()
	remote.overrides = {"picker_cost_coins": 90}
	var loader := _make_loader(_local_base(), remote)
	var cfg: EconomyConfig = loader.get_config()
	assert_int(cfg.picker_cost_coins).is_equal(90)   # overridden
	assert_int(cfg.reshuffle_cost_coins).is_equal(250)  # untouched local value
	loader.free()


func test_remote_override_can_set_dictionary_knob() -> void:
	var remote := StubRemoteSource.new()
	remote.overrides = {"milestone_coin_gifts": {5: 999}}
	var loader := _make_loader(_local_base(), remote)
	assert_int(int(loader.get_config().milestone_coin_gifts.get(5, -1))).is_equal(999)
	loader.free()


# ---------------------------------------------------------------------------
# Robustness against malformed payloads
# ---------------------------------------------------------------------------

func test_unknown_key_is_ignored() -> void:
	var remote := StubRemoteSource.new()
	remote.overrides = {"not_a_real_knob": 42, "picker_cost_coins": 80}
	var loader := _make_loader(_local_base(), remote)
	# The good key still applies; the unknown one is dropped (no crash).
	assert_int(loader.get_config().picker_cost_coins).is_equal(80)
	loader.free()


func test_type_mismatched_value_is_ignored() -> void:
	var remote := StubRemoteSource.new()
	remote.overrides = {"picker_cost_coins": "free"}  # String, knob is int
	var loader := _make_loader(_local_base(), remote)
	assert_int(loader.get_config().picker_cost_coins).is_equal(120)  # local kept
	loader.free()


# ---------------------------------------------------------------------------
# Non-mutation + caching
# ---------------------------------------------------------------------------

func test_resolution_does_not_mutate_local_base() -> void:
	var base := _local_base()
	var remote := StubRemoteSource.new()
	remote.overrides = {"picker_cost_coins": 1}
	var loader := _make_loader(base, remote)
	var cfg: EconomyConfig = loader.get_config()
	assert_int(cfg.picker_cost_coins).is_equal(1)     # resolved copy changed
	assert_int(base.picker_cost_coins).is_equal(120)  # injected base untouched
	loader.free()


func test_get_config_is_cached() -> void:
	var loader := _make_loader(_local_base(), RemoteConfigSource.new())
	var a: EconomyConfig = loader.get_config()
	var b: EconomyConfig = loader.get_config()
	assert_bool(a == b).is_true()  # same cached instance
	loader.free()


func test_reload_picks_up_changed_remote_values() -> void:
	var remote := StubRemoteSource.new()
	remote.overrides = {"picker_cost_coins": 100}
	var loader := _make_loader(_local_base(), remote)
	assert_int(loader.get_config().picker_cost_coins).is_equal(100)
	# Simulate a live remote retune, then reload.
	remote.overrides = {"picker_cost_coins": 60}
	assert_int(loader.reload().picker_cost_coins).is_equal(60)
	loader.free()


# ---------------------------------------------------------------------------
# Base RemoteConfigSource contract
# ---------------------------------------------------------------------------

func test_base_remote_source_is_no_op() -> void:
	assert_int(RemoteConfigSource.new().fetch_overrides().size()).is_equal(0)
