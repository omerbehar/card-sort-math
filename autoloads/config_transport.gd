class_name ConfigTransport
extends RefCounted
## Injectable transport for [JsonRemoteConfigSource] — abstracts the network fetch (S4-005).
##
## Splitting the transport from the parsing lets the remote-config source be unit-tested
## with zero network: a [StubConfigTransport] returns a canned JSON payload (or a simulated
## failure), while the real transport (deferred to M5 / a native HTTP layer) performs the
## actual request. This base class is a deliberate [b]no-op[/b]: [method fetch_raw] returns
## an empty string, which the source treats as "no remote available" → local fallback.
##
## Source: ADR-0014 §1 (uniform seam), design/gdd/deck-economy.md §Tuning Knobs
##         ("remote-config-loadable"); production/sprints/sprint-04.md S4-005.


## Returns the raw remote-config payload as a JSON string, or an empty string when no
## payload is available / the fetch failed. MUST be non-blocking-safe for the caller and
## MUST return [code]""[/code] (never [code]null[/code]) on any failure. The base
## implementation always returns [code]""[/code] (no transport wired).
func fetch_raw() -> String:
	return ""


## [b]Test double.[/b] Returns a canned [member payload] (or simulates a failed/empty fetch
## via [member should_fail]) so [JsonRemoteConfigSource] can be exercised deterministically
## without a network. The real transport (HTTPRequest-based) is a future subclass injected
## the same way.
class StubConfigTransport extends ConfigTransport:
	## The raw JSON string returned by [method fetch_raw].
	var payload: String = ""

	## When true, [method fetch_raw] returns [code]""[/code] regardless of [member payload],
	## simulating a network error / timeout.
	var should_fail: bool = false

	func fetch_raw() -> String:
		if should_fail:
			return ""
		return payload
