extends Node
## Autoload: the single resolver for the live [EconomyConfig] (S3-011).
##
## Every system that needs tuning knobs (booster costs, earn rates, caps, the
## milestone tables) reads the config through this loader instead of calling
## [code]load()[/code] on the [code].tres[/code] directly. The loader resolves the
## config in priority order:
## [codeblock]
## 1. remote overrides (RemoteConfigSource.fetch_overrides())  — live-ops retune
## 2. local assets/data/economy_config.tres                    — bundled defaults
## 3. EconomyConfig.new() script defaults                      — last-resort guard
## [/codeblock]
## The local resource is always the base; remote values are layered on top, so a
## partial or empty remote payload still yields a complete, valid config. The
## base [RemoteConfigSource] is a no-op (returns [code]{}[/code]), so until M4
## wires a real backend the loader behaves exactly like a plain local load — the
## "remote unavailable → local fallback" guarantee (sprint AC) holds out of the box.
##
## The resolved config is a [method Resource.duplicate] of the bundled resource,
## so applying overrides never mutates the shared in-memory [code].tres[/code].
##
## [b]Wiring:[/b] [WalletService] reads [method get_config] in its [code]_ready[/code].
## Tests bypass the loader entirely via [code]WalletService.configure(..., config)[/code],
## or drive the loader directly via [method configure] + [method reload] with a
## stub [RemoteConfigSource] — no real clock, file, or network required.
##
## Source: design/gdd/deck-economy.md §Tuning Knobs, §Dependencies;
##         production/sprints/sprint-03.md S3-011.

## Default location of the bundled local config (the source of truth for defaults).
const DEFAULT_LOCAL_PATH: String = "res://assets/data/economy_config.tres"

# Injected local source. When non-null it wins over _local_path (test DI). The
# bundled .tres is loaded from _local_path otherwise.
var _local_override: EconomyConfig = null
var _local_path: String = DEFAULT_LOCAL_PATH

# Injected remote provider. Defaults to the no-op base (local fallback path).
var _remote: RemoteConfigSource = null

# Cached resolved config; resolved lazily on first get_config(), refreshable via reload().
var _resolved: EconomyConfig = null


func _ready() -> void:
	if _remote == null:
		_remote = RemoteConfigSource.new()


## Returns the resolved [EconomyConfig], resolving (and caching) it on first call.
## Resolution layers any remote overrides over the local base; see the class doc.
func get_config() -> EconomyConfig:
	if _resolved == null:
		_resolved = _resolve()
	return _resolved


## Injects the local base config and the remote source. Intended for tests and for
## M4 (which injects a real [RemoteConfigSource]). Pass [code]null[/code] for
## [param local] to keep loading the bundled [code].tres[/code]. Clears the cache;
## the next [method get_config] re-resolves.
func configure(local: EconomyConfig, remote: RemoteConfigSource) -> void:
	_local_override = local
	if remote != null:
		_remote = remote
	_resolved = null


## Forces a fresh resolution (e.g. after a remote refresh) and returns it.
func reload() -> EconomyConfig:
	_resolved = _resolve()
	return _resolved


# Resolves the effective config: duplicate the local base, then apply remote
# overrides on top. Never returns null.
func _resolve() -> EconomyConfig:
	var base := _load_local()
	var cfg := base.duplicate(true) as EconomyConfig
	_apply_overrides(cfg, _safe_fetch())
	return cfg


# Loads the local base config: an injected override if present, else the bundled
# .tres, else script defaults (defensive — a missing/malformed .tres never leaves
# the game without a usable config).
func _load_local() -> EconomyConfig:
	if _local_override != null:
		return _local_override
	var res: Resource = load(_local_path)
	if res is EconomyConfig:
		return res as EconomyConfig
	push_warning("EconomyConfigLoader: '%s' missing or not an EconomyConfig; using script defaults." % _local_path)
	return EconomyConfig.new()


# Fetches remote overrides defensively: a null source or a non-Dictionary return
# (e.g. a provider bug) degrades to no overrides, i.e. the local fallback.
func _safe_fetch() -> Dictionary:
	if _remote == null:
		return {}
	var overrides: Variant = _remote.fetch_overrides()
	return overrides if overrides is Dictionary else {}


# Applies each override onto cfg, skipping any key the config does not declare and
# any value whose type differs from the local knob. This forward/backward-compat
# guard means a newer or malformed server payload can never corrupt the client's
# config — it only ever applies recognised, type-matching knobs. Returns the count
# applied (handy for tests / future telemetry).
func _apply_overrides(cfg: EconomyConfig, overrides: Dictionary) -> int:
	var applied := 0
	for key in overrides:
		if not (key in cfg):
			push_warning("EconomyConfigLoader: ignoring unknown override key '%s'." % str(key))
			continue
		var current: Variant = cfg.get(key)
		var value: Variant = overrides[key]
		# JSON number literals always parse as float; coerce losslessly to the knob's
		# numeric type so a remote int knob isn't silently dropped as "type-mismatched"
		# (S4-005). Non-numeric mismatches (e.g. a String for an int) still fall through.
		value = _coerce_numeric(current, value)
		if typeof(current) != typeof(value):
			push_warning("EconomyConfigLoader: ignoring type-mismatched override '%s'." % str(key))
			continue
		cfg.set(key, value)
		applied += 1
	return applied


# Losslessly aligns a remote numeric value to the local knob's numeric type:
# a whole-number float onto an int knob, or an int onto a float knob. Anything else
# (a fractional float onto an int, or a non-numeric type) is returned unchanged so the
# type-mismatch guard still rejects it.
func _coerce_numeric(current: Variant, value: Variant) -> Variant:
	if typeof(current) == TYPE_INT and typeof(value) == TYPE_FLOAT and value == floorf(value):
		return int(value)
	if typeof(current) == TYPE_FLOAT and typeof(value) == TYPE_INT:
		return float(value)
	return value
