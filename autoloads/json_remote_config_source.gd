class_name JsonRemoteConfigSource
extends RemoteConfigSource
## A real [RemoteConfigSource] that fetches a JSON payload via an injected [ConfigTransport]
## and parses it into a flat override dictionary (S4-005).
##
## This is the M4 subclass the base [RemoteConfigSource] doc anticipates: it does the
## fetch + parse, while [EconomyConfigLoader] still owns the merge policy (remote-wins,
## per-key type validation, local fallback). Network access is isolated behind the
## [ConfigTransport] seam, so every test runs deterministically with no real request.
##
## [b]Contract (matches the base):[/b] returns a [Dictionary] of overrides, or an empty
## dictionary — never [code]null[/code] — on any failure (no payload, malformed JSON, or a
## non-object top-level value). Per-key type/unknown filtering is the loader's job, so this
## source returns the parsed object verbatim and never corrupts a valid local config.
##
## Usage:
## [codeblock]
## var transport := ConfigTransport.StubConfigTransport.new()
## transport.payload = '{"picker_cost_coins": 90}'
## var source := JsonRemoteConfigSource.new()
## source.configure(transport)
## EconomyConfigLoader.configure(null, source)  # remote layered over the local .tres
## [/codeblock]
##
## Source: ADR-0014 §1; production/sprints/sprint-04.md S4-005.

## Preloaded so the transport type resolves regardless of global-class-cache timing.
const ConfigTransportClass := preload("res://autoloads/config_transport.gd")

var _transport: ConfigTransportClass = null


## Injects the transport. Pass a [ConfigTransport] (or [ConfigTransport.StubConfigTransport]
## in tests). When never configured, [method fetch_overrides] uses a base no-op transport
## and therefore falls back to local config.
func configure(transport) -> void:
	_transport = transport


## Fetches the raw payload via the transport and parses it to an overrides dictionary.
## Returns [code]{}[/code] on an empty payload, malformed JSON, or a non-object top-level
## value — never [code]null[/code]. See the class contract.
func fetch_overrides() -> Dictionary:
	var transport = _transport if _transport != null else ConfigTransportClass.new()
	var raw: String = transport.fetch_raw()
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}
