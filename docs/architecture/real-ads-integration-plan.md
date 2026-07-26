# Real Ads Integration Plan

## Status
Draft — planning deliverable, not an ADR. Written to inform the ADR(s) and stories that will
formally accept the native ad SDK integration (the "native-SDK sprint" repeatedly deferred by
ADR-0013 §4 and ADR-0014 §6). No code changes accompany this document.

## Scope note on engine version
`docs/engine-reference/godot/VERSION.md` does not exist in this repo. The engine version used
below (**Godot 4.6**) is taken from `CLAUDE.md` and `project.godot`, per project convention. Given
GDExtension binaries are **not ABI-stable across minor Godot versions**, recommend creating
`docs/engine-reference/godot/VERSION.md` (+ a breaking-changes/deprecated-APIs log) before the
native-SDK sprint starts, so the plugin compatibility work in this plan has a fixed target to
verify against and a paper trail if the project's Godot version moves.

## Grounding — what already exists
- `autoloads/ad_backend.gd`: `AdBackend` (RefCounted seam) with **synchronous** methods
  `show_interstitial(ad_type: int) -> int` (`InterstitialResult.SHOWN`/`NO_FILL`) and
  `show_rewarded() -> bool`. Base class is a no-op (always `NO_FILL`/`false`); `MockAdBackend`
  is the configurable test double. The docstring already states real SDKs are async — this plan
  is the resolution of that stated gap.
- `autoloads/ad_service.gd`: the autoload consumers call. Owns the **triple gate** (puzzle-active
  → entitlement suppression → frequency cap, then `resolve_ad_type()` for compliance × consent
  targeting), the frequency cap (`maybe_show_interstitial`, driven by `TimeProvider` +
  `EconomyConfig.interstitial_every_n_levels` / `interstitial_min_seconds`), and rewarded earn
  (`show_rewarded()` → `WalletService._earn_rewarded_ad(_config.coins_rewarded_ad)`). Backend is
  injected via `configure()`; `_ready()` defaults to `AdBackendClass.new()` (the no-op base).
- `autoloads/compliance_service.gd`: sole reader of `SaveData.age_band` and the consent fields
  (v6 schema, ADR-0013). `can_show_targeted_ads()` = `is_adult() AND consent_personalized_ads`;
  fails safe to contextual/restrictive on any gap.
- Call sites: `scenes/main/main.gd` `_on_win_advance()` → `notify_level_completed()` →
  `maybe_show_interstitial()` → on `SHOWN`, `_present_interstitial()` instantiates the
  **`InterstitialMock`** full-screen node and advances once its `closed` signal fires.
  `scenes/ui/rewarded_prompt.gd` `_on_watch()` calls `_ad.show_rewarded()` synchronously and reads
  the credited `int` immediately.
- `.github/workflows/mobile-build.yml`: iOS-only pipeline (macOS runner) — Godot generates the
  Xcode project, an unsigned Simulator compile runs every push, and a signed IPA + TestFlight
  upload run when Apple secrets are present. The Android job was removed; the Android export
  preset still exists in `export_presets.cfg`.
- `data/economy_config.gd` (`EconomyConfig` Resource): the tuning-knob pattern this project uses
  — script-default-as-source-of-truth, `.tres` as an override sheet. Ad-unit IDs should follow an
  analogous but **separate** resource (see §5) — they are platform/store config, not economy
  tuning.
- `tests/integration/ads/rewarded_earn_test.gd` (+ the interstitial/rewarded UI suites): drive the
  real `AdService`/`WalletService`/`EntitlementService`/`ComplianceService` stack against
  `MockAdBackend` via `scene_runner(scenes/main/main.tscn)`. These must keep passing headlessly
  after the async refactor.

---

## 1. Recommended plugin / network

**Recommendation: integrate Google AdMob directly (no mediation layer) for the first ship.**

CardSortMath is a calm, 13+ math puzzle leaning on **rewarded** (opt-in earn-in) plus a **capped**
interstitial (every 3–4 levels, ≥60–90s apart, suppressed by Remove-Ads) — a low ad-request-volume,
low-aggression posture. That profile does not need a mediation waterfall's marginal eCPM lift to
be viable, and mediation roughly doubles the integration surface (a second SDK, a second consent
wiring path, a second set of platform build steps) for a benefit that only matters at scale.

| Option | Pros | Cons |
|---|---|---|
| **AdMob direct** (recommended) | Single SDK; Google's UMP CMP is the same SDK family (simpler consent wiring, §4); best-documented Godot plugin path (`poing-studios/godot-admob-plugin` — Android GDExtension "v2" plugin + iOS framework); smallest build-pipeline footprint | Single-network fill ceiling; no cross-network eCPM optimization |
| **Mediation (AppLovin MAX / LevelPlay)** | Higher fill/eCPM at scale via multiple networks; industry-standard for revenue-optimizing titles | Bigger integration (mediation SDK + AdMob-as-a-network adapter, or LevelPlay's own waterfall); doubles the consent/UMP-equivalent wiring; doubles VERIFY surface for Godot 4.6 compatibility; not justified pre-launch with no fill data yet |

**VERIFY (Godot 4.6 compatibility — plugin landscape, not certain from training data):**
- `poing-studios/godot-admob-plugin` current release's stated Godot version support — confirm it
  covers **4.6** specifically (Android "v2" GDExtension plugin model + the iOS integration), not
  just 4.2–4.4. Plugin ecosystems for Godot's Android v2 plugin system have moved fast across 4.x
  minors; do not assume forward compatibility.
- Whether the plugin's iOS side is a genuine GDExtension or a bundled precompiled `.framework`/
  `.xcframework` with a separate glue layer — this changes how it's declared in
  `export_presets.cfg` and whether Xcode-side dependency resolution (CocoaPods/SPM) is required.
- Whether the plugin bundles Google's UMP SDK, or whether UMP must be added as a second
  dependency.
- Recency/maintenance signal: last-release date and open issues referencing Godot 4.6 — treat as
  a go/no-go gate before Phase 2 (§8), not an assumption to build against blind.
- Fallback if the plugin lags 4.6 support: AppLovin's own Godot plugin (which mediates AdMob) is
  the documented alternative path — but this reintroduces the mediation trade-off above, so only
  fall back to it if AdMob-direct's plugin is confirmed stale for 4.6.

---

## 2. The sync → async contract evolution

This is the core technical work, and it must happen **before** any native plugin lands, so the
plugin only ever slots into an already-async seam (mirrors the `RemoteConfigSource` /
`configure()` precedent this project already uses).

### Why the current contract can't survive contact with a real SDK
Real ad SDKs are inherently **load → (wait for fill) → show → (wait for user to dismiss/complete)
→ callback**, each hop asynchronous and event-driven. `show_interstitial(ad_type) -> int` and
`show_rewarded() -> bool` currently promise an immediate, deterministic return — a contract only a
mock can honor. A `RealAdBackend` cannot return "shown" synchronously; it must report the outcome
through a signal once the SDK's callback fires (which could be seconds later, or after the user
watches a 30-second rewarded video).

### Proposed shape
Keep the **gates synchronous** (puzzle-active, entitlement, frequency cap, compliance/consent
resolution — none of this needs the network) and make **only the backend call** async:

- `AdBackend` (base) gains:
  - `func preload_interstitial(ad_type: int) -> void` — fire-and-forget load request.
  - `func has_interstitial_ready(ad_type: int) -> bool` — sync query of a locally-cached "loaded"
    flag (no network call — just a boolean the backend already knows).
  - `func show_interstitial(ad_type: int) -> void` — presents an already-loaded ad; **no return
    value**. Result now arrives via signal.
  - `signal interstitial_result(outcome: int)` — emits `InterstitialResult.SHOWN` or `NO_FILL`
    once the SDK's dismiss/fail callback fires.
  - Mirrored `preload_rewarded()` / `has_rewarded_ready()` / `show_rewarded()` (void) /
    `signal rewarded_result(completed: bool)`.
- `AdService` becomes the `await` boundary so **callers keep a simple call shape**:
  - `func maybe_show_interstitial() -> int` becomes an async function (Godot 4's `await` on a
    normal `func`, no special declaration needed): it runs the existing sync gates unchanged, then
    `_backend.show_interstitial(ad_type)` followed by `await _backend.interstitial_result`, and
    returns the resolved `InterstitialOutcome` exactly as it does today. Every existing gate/outcome
    test still exercises pure sync logic; only the final leaf becomes an awaited signal.
  - `func show_rewarded() -> int` similarly: unchanged `is_rewarded_available()` gate, then
    `_backend.show_rewarded()` + `await _backend.rewarded_result`, then the existing
    `WalletService._earn_rewarded_ad()` call and `rewarded_earned` emission.
  - **Preload-ahead**: `AdService.notify_level_started()` (or a new hook right after
    `notify_level_completed()`) should also kick `_backend.preload_interstitial(...)` proactively,
    so that by the time the frequency-cap gate opens, an ad is very likely already loaded and
    `show_interstitial()` resolves near-instantly instead of surfacing load latency mid-transition.
    Same idea for rewarded: preload as soon as `is_rewarded_available()` starts returning true
    (e.g. when the result screen is about to reveal the offer), not at tap time.

### Exact call sites that change
| Call site | Current | Change |
|---|---|---|
| `AdService.show_rewarded()` | `func show_rewarded() -> int` synchronous | Same signature, body now does `await _backend.rewarded_result` before returning — callers must `await` |
| `AdService.maybe_show_interstitial()` | synchronous | Same signature, body awaits `_backend.interstitial_result` — callers must `await` |
| `scenes/main/main.gd` `_on_win_advance()` | synchronous, calls `maybe_show_interstitial()` directly | becomes `func _on_win_advance() -> void:` using `await ad.maybe_show_interstitial()`; the `SHOWN` branch's `_present_interstitial()` call collapses for the **real** backend (see below) but is retained for the **mock/dev** backend |
| `scenes/main/main.gd` `_present_interstitial()` | instantiates `InterstitialMock`, awaits its `closed` signal | **Mock/dev path only.** A real interstitial IS the full-screen ad (the native SDK owns its own overlay outside the Godot viewport) — there is nothing for `main.gd` to draw. Gate this function on the injected backend type (`_ad._backend is MockAdBackend` or an explicit `AdService.is_using_mock_presentation()` query) so a real backend's `await ad.maybe_show_interstitial()` already blocks until the native ad is dismissed, then goes straight to `_advance_to_next()` |
| `scenes/ui/rewarded_prompt.gd` `_on_watch()` | `var credited: int = _ad.show_rewarded()` | `var credited: int = await _ad.show_rewarded()`; button-disable-before-await already happens (`_watch_btn.disabled = true` before the call), so no UI double-tap risk during the wait |

### What stays intact
- **Model/view seam (ADR-0001)**: `AdService` remains the only place game/economy state is
  touched; `main.gd`/`RewardedPrompt` remain thin views that `await` a service call and react to
  its return value — no new game state creeps into UI.
- **Triple gate** (compliance × consent × entitlement) and the frequency cap: entirely unchanged,
  still synchronous, still run before any backend call, still fully unit-testable against
  `MockAdBackend` with zero timing dependency.
- **`InterstitialMock`** stops being "the interstitial" and becomes explicitly dev/mock-only
  scaffolding — worth a docstring update at that point noting the real backend never uses it.

---

## 3. `RealAdBackend` design (skeleton signatures only)

```gdscript
# autoloads/real_ad_backend.gd  (skeleton — NOT implemented by this plan)
class_name RealAdBackend
extends AdBackend
## Wraps the vendor SDK's Godot plugin singleton. Constructed with the platform's ad-unit
## IDs (data-driven, §5 — never hardcoded). VERIFY exact plugin autoload/class name and
## constructor shape against the chosen plugin's own docs for the pinned Godot 4.6 build.

func _init(_ad_unit_ids: Dictionary) -> void:
    pass  # connect to the vendor plugin's load/show/reward signals here

func preload_interstitial(ad_type: int) -> void:
    pass  # -> plugin.load_interstitial(unit_id_for(ad_type), request_config_for(ad_type))

func has_interstitial_ready(ad_type: int) -> bool:
    return false  # local cached flag, set true by the plugin's "loaded" callback

func show_interstitial(ad_type: int) -> void:
    pass  # -> plugin.show_interstitial(); result surfaces via interstitial_result (base signal)

func preload_rewarded() -> void:
    pass

func has_rewarded_ready() -> bool:
    return false

func show_rewarded() -> void:
    pass  # result surfaces via rewarded_result (base signal)

# Internal: connected once in _init() to the plugin's own signals, translated into ours.
func _on_plugin_interstitial_loaded() -> void: pass
func _on_plugin_interstitial_failed_to_load(_error) -> void: pass          # -> interstitial_result(NO_FILL)
func _on_plugin_interstitial_dismissed() -> void: pass                     # -> interstitial_result(SHOWN)
func _on_plugin_interstitial_failed_to_show(_error) -> void: pass          # -> interstitial_result(NO_FILL)
func _on_plugin_rewarded_user_earned_reward(_amount, _type) -> void: pass  # sets an internal "earned" flag
func _on_plugin_rewarded_dismissed() -> void: pass                         # -> rewarded_result(<earned flag>)
func _on_plugin_rewarded_failed_to_show(_error) -> void: pass              # -> rewarded_result(false)
```

**VERIFY**: the plugin signal names above (`interstitial_ad_loaded`,
`rewarded_ad_user_earned_reward`, etc.) are the *shape* AdMob-style SDKs use, not confirmed exact
names/argument order for the specific Godot plugin — confirm against its README/source before
implementation. Note the reward mapping is two-step (earn signal, then dismiss signal) because
AdMob's own callback model separates "user earned the reward" from "ad closed" — a user can
technically earn and then the SDK still fires dismissed; our `rewarded_result` should only resolve
on dismiss, using the earned-flag captured in between.

### Platform-gated injection
```gdscript
# autoloads/ad_service.gd _ready() — extended, not replaced
func _ready() -> void:
    ...
    if _backend == null:
        if OS.get_name() in ["Android", "iOS"] and _real_ads_available():
            _backend = RealAdBackendClass.new(_ad_unit_config.for_platform(OS.get_name()))
        else:
            _backend = AdBackendClass.new()  # unchanged no-op base; tests inject MockAdBackend
```
`OS.get_name()` naturally excludes CI (Linux runner) and the editor/desktop dev loop — no separate
CI-detection flag is needed for the common case. `_real_ads_available()` is a placeholder for an
additional kill-switch (e.g. a remote-config flag or a debug build check) recommended so a bad
plugin build can be disabled without a code change — see Decisions Needed.

---

## 4. Consent / ATT

Two independent SDK-level prompts feed our **existing** consent model (ADR-0013); neither replaces
`ComplianceService` as the chokepoint:

- **Google UMP (User Messaging Platform)**: on qualifying regions (EEA/UK and similar), requests a
  consent-info update from Google's servers and, if required, renders Google's own CMP form. Its
  *result* (personalized-ads consent granted/denied) must be written into
  `SaveData.consent_personalized_ads` via the existing `SaveService` setter (ADR-0013 §1) — i.e. a
  thin **UMP → SaveService bridge**, not a new consent-storage path. `ComplianceService` remains
  the sole reader; nothing about its `can_show_targeted_ads()` contract changes.
- **iOS ATT (App Tracking Transparency)**: the system permission prompt gating IDFA access,
  required since iOS 14.5 for any app that tracks across apps/websites using device identifiers.
  Its result should similarly map into `consent_personalized_ads` (or a dedicated
  `consent_advertising_id` field if the two need to diverge — VERIFY whether Apple's and Google's
  definitions of "tracking" cleanly line up with our single field, or whether the v6 schema needs a
  distinct ATT-specific flag before this ships).

### Why the consent-UI sprint gates personalized ads specifically
`ComplianceService.can_show_targeted_ads()` is already `is_adult() AND consent_personalized_ads`,
and `consent_personalized_ads` defaults to **denied** for every player until a real capture flow
sets it (ADR-0013 — conservative, protected-field default). Without a first-run consent UI, that
field can never become `true`, so **every** ad request resolves `CONTEXTUAL` by construction —
which is exactly the safe, correct behavior, but it means personalized ads are structurally
unreachable until that UI exists. **Contextual/non-personalized ads can ship without it** — the
existing gate already produces the right verdict today with zero new UI.

**VERIFY**: current Google AdMob policy on whether a UMP consent message is still required in EEA
even when only requesting **non-personalized** ads (policy in this area has shifted over time;
do not assume the pre-cutoff rule still holds). If UMP integration turns out to be required
regardless of personalization, the "contextual ships without consent UI" simplification above
does not hold for EEA users and the consent-UI sprint becomes a hard prerequisite for **any** real
ad, not just personalized ones.

### Sequencing implication
Recommend treating "first-run consent UI (or equivalent UMP wiring)" as its own scoped sprint
**before** Phase 2 of the rollout (§8), even though it's technically decoupled from the
async-contract refactor — legal/policy risk here is higher-stakes than the engineering risk, and
should not be an afterthought bolted onto the native-plugin spike.

---

## 5. Ad-unit config

Following the project rule (no hardcoded gameplay/tuning values) and the IAP-catalog precedent
already planned in ADR-0014 (§6, "catalog drives from config, never hardcoded SKUs"), recommend a
**dedicated resource**, not an extension of `EconomyConfig` — ad-unit IDs are platform/store
config, not economy tuning, and mixing them would blur `EconomyConfig`'s single responsibility.

```gdscript
# data/ad_unit_config.gd (proposed — not implemented by this plan)
class_name AdUnitConfig
extends Resource
## Platform ad-unit IDs for AdService's RealAdBackend. Mirrors EconomyConfig's
## script-default-as-source-of-truth pattern. Never hardcode an ad-unit ID in GDScript.

@export var use_test_ad_units: bool = true  # true in every dev/debug build; false only in
                                             # signed release exports (see Decisions Needed)

@export_group("Android")
@export var android_interstitial_unit_id: String = ""   # production ID; test ID used when use_test_ad_units
@export var android_rewarded_unit_id: String = ""

@export_group("iOS")
@export var ios_interstitial_unit_id: String = ""
@export var ios_rewarded_unit_id: String = ""

func interstitial_unit_id(platform: String) -> String: ...
func rewarded_unit_id(platform: String) -> String: ...
```

Instance lives at `assets/data/ad_unit_config.tres`, loaded the same way `EconomyConfigLoader`
resolves `economy_config.tres` today. Google's official test ad-unit ID constants (VERIFY exact
current values against AdMob docs — they are stable per-format but must be confirmed, not
guessed) should be the compiled-in defaults so a fresh checkout never accidentally serves live ads
in dev.

Ad-unit IDs are not secret (visible in a decompiled APK/IPA regardless), so committing production
IDs to the `.tres` is acceptable from a security standpoint — but recommend still gating them
behind `use_test_ad_units` so no development build (editor, debug export, CI) ever requests a
production ad unit and pollutes real impression/fill metrics.

---

## 6. Build / store / CI

### iOS
- `GADApplicationIdentifier` must be present in the exported `Info.plist` (the AdMob App ID, a
  separate value from the ad-unit IDs). **VERIFY** how the chosen plugin injects this into
  Godot's export — likely one of: (a) a companion export plugin hooking `_export_begin`/plist
  patch, (b) a manual custom `Info.plist` addition Godot 4.6's iOS export preset supports directly
  (check `export_presets.cfg`'s current iOS section for a plist-additions field), or (c) a
  post-export script step added to `mobile-build.yml`.
- SKAdNetwork identifiers (Google's ad-network ID plus any mediated networks') must be added to
  `Info.plist`'s `SKAdNetworkItems` array for install attribution. **VERIFY** the current
  Google-provided SKAdNetwork ID list — this changes as Google's ad tech stack evolves.
- `NSUserTrackingUsageDescription` is required if ATT is invoked (§4) — a plain string, easy to
  add, but must exist before the first build that calls the ATT API or the app is rejected at
  App Store review / crashes on the API call (platform behavior, not a Godot detail).
- `mobile-build.yml`'s existing unsigned Simulator compile step should still succeed once the
  plugin is linked, **provided** the plugin's framework is either vendored in-repo or resolvable
  without network access during `godot --headless --export-release` / the subsequent `xcodebuild`.
  **VERIFY**: does the plugin require CocoaPods or Swift Package Manager resolution at build time?
  If so, the CI job needs an added `pod install` / SPM resolve step — the current job has none.

### Android
- `AndroidManifest.xml` needs the `com.google.android.gms.ads.APPLICATION_ID` `<meta-data>` tag
  (the AdMob App ID). Godot's Android export can inject manifest entries via the export preset's
  custom permissions/manifest fields, or the plugin may inject it automatically as part of its
  Android v2 plugin package — **VERIFY** which applies for the chosen plugin.
- Requires **"Use Gradle Build"** enabled in the Android export preset (custom GDExtension Android
  plugins generally require the Gradle build path, not the prebuilt APK path) — **VERIFY** the
  current `export_presets.cfg` Android section's Gradle-build flag state and whether it's already
  on.
- The plugin's `.aar`/Gradle dependency (and the Google Play Services Ads Gradle dependency it
  pulls in) must be registered in the export preset's Android Plugins list.
- **CI**: the Android job was removed from `mobile-build.yml`. Recommend restoring a
  **build-only** Android job mirroring the iOS pattern (unsigned APK/AAB compile as a smoke test,
  no signing/upload required) specifically to catch Gradle+plugin export breakage early, once the
  plugin is added — this is a `devops-engineer` coordination item, not something to defer silently.

### Keeping gdUnit4 CI green
The platform-gated injection in `AdService._ready()` (§3) already ensures gdUnit4 (running on a
Linux CI runner) and the editor/desktop dev loop never construct `RealAdBackend` — `OS.get_name()`
never returns `"Android"`/`"iOS"` there. No CI configuration change is needed to keep the mock as
the CI backend; this falls out of the existing platform check, same as today's implicit exclusion.
The **only** CI risk is the native export step itself failing to compile once the plugin is linked
(covered above) — that is a build-pipeline concern, not a gdUnit4 test concern, and should not be
allowed to block the unrelated gdUnit4 job (keep them as separate CI jobs, as they already are).

---

## 7. Testability & verification

**Stays unit/integration-testable headlessly (unchanged in spirit, updated for async):**
- Every triple-gate branch (puzzle-active, entitlement suppression, frequency cap, compliance ×
  consent targeting) — none of this touches the backend and none of it changes with the async
  refactor.
- Rewarded earn → `WalletService` crediting, and its abandonment path (`rewarded_completes =
  false`) — `tests/integration/ads/rewarded_earn_test.gd` needs its two `show_rewarded()` calls
  updated to `await`, and `MockAdBackend` should emit its result via a signal (even if only a
  `call_deferred` immediately after, to genuinely exercise the `await` path rather than silently
  returning) so a caller that forgets to `await` fails loudly rather than "working" by accident on
  a synchronous coincidence.
- Interstitial frequency-cap determinism via the injected `TimeProvider` — unaffected.
- The new preload-ahead behavior (`preload_interstitial`/`has_interstitial_ready`) is itself pure
  local state against the mock and fully testable (e.g. "preload called after level N completions,
  before the cap opens").

**Can ONLY be verified on a real device/signed build — this environment cannot exercise these:**
- Actual ad fill from Google's ad servers (network round-trip, real inventory).
- The real UMP consent form rendering and its region-detection behavior (EEA simulation).
- The iOS ATT system prompt appearing and its OS-level authorization result.
- SKAdNetwork attribution actually firing on an install.
- The native full-screen ad's real rendering/dismiss UX and timing.
- Gradle/Xcode build success with the plugin's binary actually linked (CI can smoke-test the
  *export step*, but full behavioral correctness needs a signed install on a device or emulator
  with Google Play Services).
- Fill rate / eCPM data in the AdMob console (there is no way to generate real traffic here).

Be explicit with the team: **this Claude Code environment has no Android/iOS device, no emulator
with Google Play Services, and no network path to ad-serving infrastructure.** Every item in the
list above requires a human on real hardware (or at minimum a cloud device farm) — no amount of
additional planning or code review from this environment substitutes for that device-verification
step (§8 Phase 3).

---

## 8. Phased rollout + risks

| Phase | Work | Effort | Risk | Notes |
|---|---|---|---|---|
| **0 — Consent-UI sprint** | First-run age-gate + consent screen wiring toggles to `SaveData` consent fields via `SaveService` setters (per ADR-0013); decide UMP-now vs UMP-later (§4) | M (UX + GDScript) | Low technical / **Medium legal** | Prerequisite for personalized ads; contextual ads may ship without it *if* the EEA-non-personalized VERIFY item in §4 resolves favorably |
| **1 — Async contract refactor + `RealAdBackend` skeleton** | Evolve `AdBackend`/`AdService` to the signal/await shape (§2); update all 3 call sites; update `MockAdBackend` to emit async-style; update existing tests; land the **stub** `RealAdBackend` (not wired to any SDK) behind the platform gate | M | Medium — touches 3 call sites + the ad/rewarded test suites, but zero native dependency, fully containable in current CI | Do this **before** touching a real plugin — de-risks the plugin spike from also being an architecture migration |
| **2 — Single-platform spike (Android, test ad units)** | Pull in the chosen plugin for Android only; wire `RealAdBackend`'s stubs to its real signals; `export_presets.cfg` Gradle-build + plugin registration; Google test ad-unit IDs only; restore an Android CI build-smoke job | L | **High** — the biggest unknown is plugin/Godot 4.6 ABI + Gradle-plugin compatibility (all the §1/§6 VERIFY items land here) | Go/no-go gate: confirm the plugin's stated 4.6 support before starting |
| **3 — Device verification** | Install the built APK on a real Android device/emulator with Play Services; confirm test ads render, UMP form appears where expected, rewarded callback credits the wallet end-to-end | — | N/A (human/device task) | **Cannot be performed from this environment** — flag this explicitly to the team, not a step Claude Code can complete |
| **4 — iOS integration** | Repeat 2/3 for iOS: framework linking, `Info.plist` (`GADApplicationIdentifier` + SKAdNetwork), ATT prompt, verify via the existing `mobile-build.yml` TestFlight path | L | High (separate VERIFY surface from Android — different plugin packaging model) | Leverage the existing signed-IPA + TestFlight pipeline already in place |
| **5 — Production ad units + soft-launch monitoring** | Flip `AdUnitConfig.use_test_ad_units` off in release builds; monitor fill/eCPM in the AdMob console; frequency cap + triple gate remain the safety net against ad fatigue | S | Low (config-only swap, assuming Phases 2–4 are solid) | Data-driven swap only — no code change |
| **6 — Mediation evaluation (optional, later)** | Only if AdMob-direct fill/eCPM proves insufficient with real data: evaluate AppLovin MAX/LevelPlay layering AdMob as one network | L | Medium | Revisit-if-justified, not default-do |

---

## Decisions needed from the team
1. **AdMob direct vs. mediation from day one** — this plan recommends AdMob direct; confirm.
2. **Can contextual/non-personalized ads ship before the full consent-UI/UMP sprint?** — legal
   call, gated on the EEA-non-personalized-still-needs-UMP VERIFY item (§4).
3. **In-house consent screen vs. integrating Google's UMP CMP UI (or both, phased)?**
4. **Where do production ad-unit IDs live and how are they injected at build time** — committed
   `.tres` (this plan's default recommendation, since they're not secret) vs. a CI-secret-injected
   override mirroring the iOS signing-secret pattern already in `mobile-build.yml`?
5. **Does `age_band` HMAC-signing (ADR-0013 §4, risk M4-R2, currently OPEN-DEFERRED) need to land
   before real ads ship?** The deferral was accepted on the basis that the mock services move no
   real revenue/PII off-device — that basis disappears the moment `ComplianceService`'s verdict
   gates a **real** ad SDK making real network requests. Recommend re-litigating M4-R2's target
   sprint against this plan's Phase 2, not leaving it at "some future native sprint."
6. **When to restore the Android CI job** (currently removed) — recommend at the start of Phase 2,
   scoped to devops-engineer coordination.
7. **Who owns the Google Play Console / App Store Connect AdMob app registration** and the
   creation of production ad units (a human/business-account task, not something this plan or
   Claude Code can perform).
8. **A kill-switch for the real backend** beyond the platform check (§3's `_real_ads_available()`
   placeholder) — e.g. a remote-config flag to force-fallback to the mock/no-op backend in
   production if the plugin misbehaves post-launch. Worth deciding now vs. retrofitting under
   incident pressure later.

## VERIFY before implementation
- [ ] `poing-studios/godot-admob-plugin` (or chosen alternative) states explicit support for
      **Godot 4.6** — Android v2 GDExtension plugin model + iOS integration. Do not assume
      forward compatibility from 4.2–4.4-era docs.
- [ ] Exact plugin signal/method names for the interstitial and rewarded load→show→callback flow
      (this plan's §3 names are illustrative, not confirmed).
- [ ] Whether the plugin bundles Google's UMP SDK or requires it as a separate dependency.
- [ ] Current Google AdMob policy: does a UMP consent message remain required in EEA even for
      **non-personalized** ad requests? (Gates whether Phase 0 is a hard prerequisite for any real
      ad, not just personalized ones.)
- [ ] Whether the iOS ATT prompt is legally/technically required if the app only ever requests
      non-personalized ads and never touches IDFA.
- [ ] How `GADApplicationIdentifier` and `SKAdNetworkItems` get into Godot 4.6's exported
      `Info.plist` (export-plugin plist patch vs. a native export-preset field vs. a CI
      post-export script).
- [ ] Current Google-provided SKAdNetwork ID list (changes over time).
- [ ] Current Godot 4.6 Android export preset defaults: is "Use Gradle Build" already on, and what
      does the Android Plugins registration mechanism look like today.
- [ ] Whether the plugin's export step needs network-dependent dependency resolution (CocoaPods/
      SPM for iOS, extra Gradle repos for Android) that the current `mobile-build.yml` runner
      doesn't yet perform.
- [ ] Current Google-provided test ad-unit ID constants for each ad format (interstitial,
      rewarded) — confirm against AdMob docs, don't hardcode from memory.
- [ ] Confirm whether ATT's "tracking" definition and AdMob's "personalized ads" consent cleanly
      map to the single `consent_personalized_ads` field, or whether the v6 schema needs a
      distinct field before ATT wiring lands.
