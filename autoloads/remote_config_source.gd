class_name RemoteConfigSource
extends RefCounted
## Injectable seam for a remote economy-config provider (S3-011).
##
## [EconomyConfigLoader] asks an instance of this class for a flat dictionary of
## knob overrides ([code]{ "picker_cost_coins": 90, ... }[/code]) and layers them
## over the bundled local [EconomyConfig]. This base class is a deliberate
## [b]no-op[/b]: [method fetch_overrides] returns an empty dictionary, so the
## loader falls back to the local [code].tres[/code] defaults. That is exactly the
## "remote unavailable" production behaviour the sprint AC requires — the game
## ships with this default and always has a valid config.
##
## [b]Why a seam, not a real provider:[/b] the actual backend (Firebase Remote
## Config / a custom endpoint) and its network/SDK dependency are deferred to M4
## (Monetize). M4 subclasses this — overriding [method fetch_overrides] to do the
## fetch + parse — and injects it via [method EconomyConfigLoader.configure], with
## zero changes to the loader or to [WalletService]. Tests inject a stub subclass
## to prove the remote-wins-when-present / local-wins-when-absent contract
## deterministically (no network).
##
## Source: design/gdd/deck-economy.md §Tuning Knobs ("remote-config-loadable"),
##         §Dependencies; production/sprints/sprint-03.md S3-011.


## Returns a flat dictionary of [EconomyConfig] knob overrides keyed by the
## [code]@export[/code] property name, or an empty dictionary when no remote
## config is available. Keys the local config does not declare, and values whose
## type does not match the local knob, are ignored by the loader (forward- and
## backward-compatible: a newer server payload never corrupts an older client).
##
## The base implementation returns [code]{}[/code] — override it in M4 with the
## real fetch. Implementations MUST be non-blocking-safe for the caller and MUST
## return [code]{}[/code] (never [code]null[/code]) on any failure.
func fetch_overrides() -> Dictionary:
	return {}
