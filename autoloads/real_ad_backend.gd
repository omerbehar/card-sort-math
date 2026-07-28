class_name RealAdBackend
extends AdBackend
## Native ad-SDK backend (real-ads plan §3) — the production subclass of [AdBackend] that drives
## an AdMob (or compatible) GDExtension plugin. Injected into [AdService] on Android/iOS builds
## where the plugin is present; on every other target (desktop, headless, CI) [AdService] keeps
## the no-op base [AdBackend], so the gdUnit4 suite never touches native code (risk M4-R3).
##
## [b]Safety contract — this class must never hang or crash the game.[/b] Every presentation path
## resolves the async signal ([signal AdBackend.interstitial_finished] /
## [signal AdBackend.rewarded_finished]) exactly once:
## [br]• plugin missing / not [method is_active] → resolve immediately with no-fill / not-completed;
## [br]• plugin present but a show throws or the SDK reports an error → resolve no-fill;
## [br]• a real ad shows → resolve when the SDK's dismiss/reward callback fires.
## [AdService]'s [code]await[/code] therefore always completes, so a broken or absent SDK simply
## degrades to "no ad" — the same behaviour as the base backend — rather than freezing the win flow.
##
## [b]This is SCAFFOLDING.[/b] The concrete plugin singleton name, method names, and signal names
## below are marked [b]VERIFY[/b]: they follow the common community AdMob plugin shape but MUST be
## confirmed against the exact plugin you install (see docs/architecture/real-ads-setup-guide.md).
## Until the plugin is installed and these are confirmed, [method is_active] returns false and this
## backend behaves identically to the no-op base — safe to ship, shows no ads yet.
##
## Source: docs/architecture/real-ads-integration-plan.md §3; ADR-0014 §1 (uniform seam).

## VERIFY: the Engine singleton name registered by the installed AdMob plugin. Community builds
## commonly register "AdMob" / "MobileAds" / "PoingGodotAdMob" — confirm against your plugin's docs.
const SINGLETON_NAME := "AdMob"

## The per-platform ad-unit IDs (test IDs by default — see [AdUnitConfig]).
var _config: AdUnitConfig = null

## The resolved plugin singleton, or null when absent. When null this backend is inert.
var _plugin: Object = null

## "Android" / "iOS" / "" — drives which ad-unit ID [AdUnitConfig] hands back.
var _platform: String = ""

# Exactly-once guards so a duplicated SDK callback can never double-resolve one await.
var _interstitial_pending: bool = false
var _rewarded_pending: bool = false


## Constructs the backend around an [AdUnitConfig] (test IDs when none is supplied) and resolves
## the plugin singleton if the running platform exposes it. Never raises — a missing plugin just
## leaves [method is_active] false.
func _init(config: AdUnitConfig = null) -> void:
	_config = config if config != null else AdUnitConfig.new()
	_platform = OS.get_name()
	_resolve_plugin()


# Resolves the plugin singleton on supported platforms only. VERIFY the singleton name + that the
# plugin is enabled in the export before trusting a non-null result.
func _resolve_plugin() -> void:
	if _platform != "Android" and _platform != "iOS":
		return  # desktop / headless / web — no native ad SDK; stay inert (base-backend behaviour)
	if not Engine.has_singleton(SINGLETON_NAME):
		push_warning("RealAdBackend: '%s' singleton not found — is the AdMob plugin installed and "
			% SINGLETON_NAME + "enabled in the export? Falling back to no-ad behaviour.")
		return
	_plugin = Engine.get_singleton(SINGLETON_NAME)
	# VERIFY: initialize + consent must already be handled by AdConsentBridge before first show.


## True only when a native ad plugin is present and this backend can actually request ads. When
## false, every show resolves as no-fill / not-completed — [AdService] treats that as "no ad".
func is_active() -> bool:
	return _plugin != null


# ---------------------------------------------------------------------------
# Interstitial
# ---------------------------------------------------------------------------

## Preloads an interstitial through the SDK so [method show_interstitial] resolves without a
## network round-trip. No-op when inert. VERIFY the load method name + that a "loaded" signal
## flips readiness.
func preload_interstitial(_ad_type: int) -> void:
	if not is_active():
		return
	# VERIFY plugin API, e.g.:
	#   _plugin.load_interstitial(_config.interstitial_unit_id(_platform))
	pass


## True when a preloaded interstitial is ready. VERIFY the readiness query. Defaults false so the
## service never assumes fill it does not have.
func has_interstitial_ready(_ad_type: int) -> bool:
	if not is_active():
		return false
	# VERIFY, e.g.: return _plugin.is_interstitial_loaded()
	return false


## Presents an interstitial, resolving [signal AdBackend.interstitial_finished] exactly once. If
## inert or the SDK call fails, resolves [constant InterstitialResult.NO_FILL] immediately so the
## caller's await never stalls.
func show_interstitial(ad_type: int) -> void:
	if not is_active():
		interstitial_finished.emit.call_deferred(InterstitialResult.NO_FILL)
		return
	_interstitial_pending = true
	var unit_id := _config.interstitial_unit_id(_platform)
	# VERIFY: connect the SDK's dismiss/failed callbacks to _on_interstitial_closed / _on_interstitial_failed
	# (one-shot), then request the show. Wrapped so any plugin-call error resolves as no-fill rather
	# than propagating and freezing the win flow.
	#   _connect_interstitial_signals()
	#   _plugin.show_interstitial(unit_id, ad_type == AdService.AdType.PERSONALIZED)
	# Until the plugin methods are wired, fail closed (no ad shown):
	push_warning("RealAdBackend.show_interstitial: plugin wiring not yet completed for unit '%s' "
		% unit_id + "— see real-ads-setup-guide.md. Reporting no-fill.")
	_finish_interstitial(InterstitialResult.NO_FILL)


# Called by the SDK's "dismissed" callback (VERIFY signal name). Resolves as SHOWN.
func _on_interstitial_closed() -> void:
	_finish_interstitial(InterstitialResult.SHOWN)


# Called by the SDK's "failed to show / no fill" callback (VERIFY). Resolves as NO_FILL.
func _on_interstitial_failed(_error: Variant = null) -> void:
	_finish_interstitial(InterstitialResult.NO_FILL)


# Emits the interstitial outcome exactly once (guards against duplicate SDK callbacks).
func _finish_interstitial(result: int) -> void:
	if not _interstitial_pending:
		return
	_interstitial_pending = false
	interstitial_finished.emit.call_deferred(result)


# ---------------------------------------------------------------------------
# Rewarded
# ---------------------------------------------------------------------------

## Preloads a rewarded ad. No-op when inert. VERIFY the load method name.
func preload_rewarded() -> void:
	if not is_active():
		return
	# VERIFY, e.g.: _plugin.load_rewarded(_config.rewarded_unit_id(_platform))
	pass


## True when a preloaded rewarded ad is ready. VERIFY. Defaults false.
func has_rewarded_ready() -> bool:
	if not is_active():
		return false
	# VERIFY, e.g.: return _plugin.is_rewarded_loaded()
	return false


## Presents a rewarded ad, resolving [signal AdBackend.rewarded_finished] exactly once. Resolves
## [code]false[/code] (not completed) immediately when inert or on any SDK error, so no reward is
## granted without a verified completed view.
func show_rewarded() -> void:
	if not is_active():
		rewarded_finished.emit.call_deferred(false)
		return
	_rewarded_pending = true
	var unit_id := _config.rewarded_unit_id(_platform)
	# VERIFY: connect the SDK's "user_earned_reward" and "dismissed/failed" callbacks to
	# _on_rewarded_earned / _on_rewarded_dismissed (one-shot), then request the show.
	#   _connect_rewarded_signals()
	#   _plugin.show_rewarded(unit_id)
	# Until wired, fail closed (grant nothing):
	push_warning("RealAdBackend.show_rewarded: plugin wiring not yet completed for unit '%s' "
		% unit_id + "— see real-ads-setup-guide.md. Reporting not-completed.")
	_finish_rewarded(false)


# Called by the SDK's "user earned reward" callback (VERIFY). Marks the view completed.
func _on_rewarded_earned(_reward: Variant = null) -> void:
	_finish_rewarded(true)


# Called by the SDK's "dismissed without reward / failed" callback (VERIFY). No reward.
func _on_rewarded_dismissed() -> void:
	_finish_rewarded(false)


# Emits the rewarded outcome exactly once (guards against duplicate SDK callbacks). Note: the
# reward threshold is the SDK's — only _on_rewarded_earned passes true; a plain dismiss is false.
func _finish_rewarded(completed: bool) -> void:
	if not _rewarded_pending:
		return
	_rewarded_pending = false
	rewarded_finished.emit.call_deferred(completed)
