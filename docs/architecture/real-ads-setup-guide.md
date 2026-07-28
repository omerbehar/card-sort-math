# Real Ads — Human Setup Runbook

**Audience:** you (the human), not an agent. This is the step-by-step list of things only a
person with the AdMob/Apple/Google accounts and a physical device can do, to take the code from
"safe no-op scaffolding" to "a real ad shows on my phone."

**Companion docs:**
- `docs/architecture/real-ads-integration-plan.md` — the architecture decision (the *why*).
- This file — the checklist (the *how* + *who does what*).

---

## TL;DR — where we are

The code seam is done and shipping safely **today**:

| Piece | File | State |
|---|---|---|
| Async ad contract | `autoloads/ad_backend.gd` | ✅ done, tested |
| Platform backend gate | `autoloads/ad_service.gd` `_resolve_backend()` | ✅ done, tested |
| Real backend skeleton | `autoloads/real_ad_backend.gd` | ⚠️ **inert** until plugin wired (VERIFY marks) |
| Consent bridge skeleton | `autoloads/ad_consent_bridge.gd` | ⚠️ **fail-closed** until plugin wired |
| Ad-unit IDs (data-driven) | `data/ad_unit_config.gd` | ✅ done — Google **test** IDs by default |

Because `RealAdBackend.is_active()` returns `false` with no plugin, the game currently behaves
exactly like the no-op base backend: **no ad shows, nothing crashes, nothing hangs, all 845
tests stay green.** Every step below is what *you* do to flip it on. The agent cannot do these —
they need your accounts, secrets, and a real device (see "Why the agent can't do these" at the end).

---

## Step 1 — Create the AdMob account & ad units  *(you · ~30 min · one-time)*

1. Sign up at <https://admob.google.com> with the Google account that will own the app's revenue.
2. Add your app twice — once as **Android**, once as **iOS** (you can do this before the app is on
   the stores; pick "app not listed yet").
3. Note each app's **AdMob App ID** — format `ca-app-pub-XXXXXXXX~YYYYYYY` (tilde `~`).
4. Under each app create **two ad units**: one **Interstitial**, one **Rewarded**.
   Note each unit's ID — format `ca-app-pub-XXXXXXXX/ZZZZZZZ` (slash `/`). That's **4 unit IDs**
   total (Android interstitial, Android rewarded, iOS interstitial, iOS rewarded).
5. **Do not** put production IDs anywhere yet — keep using Google's built-in test IDs (already the
   default in `data/ad_unit_config.gd`) until you've verified real test ads render on-device
   (Step 6). Requesting a *production* unit from a debug build risks an AdMob policy strike.

---

## Step 2 — Install the AdMob Godot plugin  *(you · ~45 min · one-time, VERIFY-heavy)*

The engine is **Godot 4.6**. Native ad SDKs are GDExtension/Godot-Android/iOS plugins — pick one
that publishes a build compatible with 4.6. (See integration-plan §1 for the recommendation and
alternatives.)

1. Choose the plugin and read *its* README — the exact singleton name, method names, and signal
   names are what the `VERIFY` comments in `real_ad_backend.gd` / `ad_consent_bridge.gd` refer to.
2. Install per the plugin's instructions:
   - **Android:** enable the plugin under Project → Export → Android → Plugins, and set
     **`gradle_build/use_gradle_build=true`** in `export_presets.cfg` (currently `false` — AdMob
     needs the Gradle build to pull the Play Services dependency).
   - **iOS:** add the plugin's `.a`/framework + the `.gdip` under the iOS export.
3. Put the **AdMob App ID** (the `~` one from Step 1) where the plugin wants it — usually
   `AndroidManifest` meta-data + iOS `Info.plist` `GADApplicationIdentifier`. The plugin README
   says exactly where. (This is the App ID, *not* the ad-unit IDs.)
4. **Wire the VERIFY blocks.** Open `autoloads/real_ad_backend.gd` and replace each `VERIFY` /
   `# _plugin.…` placeholder with the plugin's real calls:
   - `SINGLETON_NAME` → the plugin's actual `Engine.has_singleton(...)` name.
   - `preload_interstitial` / `has_interstitial_ready` / the `show_interstitial` body → the plugin's
     load / is-loaded / show calls, and connect its **dismissed** signal to `_on_interstitial_closed`
     and its **failed** signal to `_on_interstitial_failed` (one-shot).
   - Same for the rewarded methods → `_on_rewarded_earned` (the plugin's *user-earned-reward*
     callback) and `_on_rewarded_dismissed`.
   - Keep the `_finish_interstitial` / `_finish_rewarded` exactly-once guards — they protect against
     duplicate SDK callbacks double-resolving one `await`.
5. Do the same for `autoloads/ad_consent_bridge.gd` — wire the UMP form calls and (iOS) the ATT
   prompt into `request_consent()`, replacing the fail-closed placeholders.

> After this step `RealAdBackend.is_active()` returns `true` on-device, so `AdService`'s
> `_resolve_backend()` will start using it automatically — no other code changes needed.

---

## Step 3 — Register the autoloads  *(you · 5 min)*

`RealAdBackend` and `AdConsentBridge` are **not** autoloads yet — `AdService` constructs the
backend directly, and the consent bridge is invoked from the boot/age-gate flow. Decide the wiring:

- **Backend:** nothing to register — `AdService._resolve_backend()` already `new()`s it. ✅
- **Consent bridge:** call it once at app start **after** the age gate resolves and **before** the
  first interstitial. Wire `await AdConsentBridge.new().request_consent()` into `main.gd`'s existing
  age-gate/consent flow (see `_present_consent_sheet`), or add it as an autoload if you prefer a
  singleton. VERIFY the ordering against `ConsentSheet` (S6) so the two don't reset each other.

---

## Step 4 — Author the production ad-unit config  *(you · 10 min · when ready to earn)*

Only after test ads verify on-device (Step 6):

1. Create `assets/data/ad_unit_config.tres` from `data/ad_unit_config.gd` (in the Godot editor:
   right-click → New Resource → `AdUnitConfig`).
2. Paste your 4 production unit IDs from Step 1 into `android_interstitial`, `android_rewarded`,
   `ios_interstitial`, `ios_rewarded`.
3. Leave `use_test_ad_units = true` for now. **Flip it to `false` only in the signed release build**
   — never in the editor/debug/CI (that's the one switch between test and real ads).
   `AdService._load_ad_unit_config()` loads this `.tres` automatically if present; if absent it
   falls back to test ads, so a missing file can never accidentally serve production ads.

---

## Step 5 — Build settings & CI  *(you · 20 min)*

- **iOS** (`export_presets.cfg` preset.0): add the AdMob SDK per plugin docs; add the
  `GADApplicationIdentifier` and `SKAdNetworkItems` to `Info.plist` (AdMob publishes the SKAdNetwork
  list); if you use IDFA/ATT, add `NSUserTrackingUsageDescription`. The existing
  `.github/workflows/mobile-build.yml` (signed IPA → TestFlight on push to `main`) keeps working;
  the plugin just needs to be committed so CI's export picks it up.
- **Android** (`export_presets.cfg` preset.1): set `gradle_build/use_gradle_build=true` and enable
  the plugin (Step 2). There is no Android CI lane yet — add one only when you want Play uploads.
- **CI stays green:** the gdUnit4 job runs headless on Linux, where `_resolve_backend()` returns the
  base no-op backend and `RealAdBackend` is never touched. Do **not** register the native plugin as a
  *desktop* dependency — keep it export-platform-only so `tests.yml` never tries to load native code.

---

## Step 6 — Verify a real (test) ad on a device  *(you · 30 min · the actual "see an ad" moment)*

1. Register your device as an **AdMob test device** (AdMob console → Settings → Test devices; add the
   device's advertising ID). This lets you safely see *live* test ads without policy risk.
2. Build a debug APK/IPA with the plugin enabled and `use_test_ad_units = true`.
3. Play to a win → the interstitial attach point (`main._on_win_advance`) fires
   `AdService.maybe_show_interstitial()`; a Google **test** interstitial should appear.
4. Open the rewarded prompt (result screen "watch for +N coins") → a test rewarded ad; complete it →
   coins credit through `WalletService` (the daily/compliance cap still applies).
5. If nothing shows: check `adb logcat` / Xcode console for the `RealAdBackend` `push_warning`s — they
   name exactly which VERIFY block is still unwired or which unit ID returned no fill.

Once test ads render here, flip `use_test_ad_units = false` in the **release** export (Step 4) and
ship. That is the point where real, paying ads appear to players.

---

## Order of operations (quick map)

```
Step 1 (AdMob account + 4 unit IDs)
   └─ Step 2 (install plugin + wire VERIFY blocks)  ← turns RealAdBackend "active"
        └─ Step 3 (invoke consent bridge in boot flow)
             └─ Step 6 (device test with TEST ids)   ← first real ad you see
                  └─ Step 4 + Step 5 (author prod .tres, flip use_test=false in release)
                       └─ ship → players see paying ads
```

---

## Why the agent can't do these

Every step above needs something outside the repo and this environment:

- **Accounts & legal ownership** — the AdMob/Google/Apple accounts, the payout bank details, and
  accepting the AdMob program policies are yours to own; revenue and policy liability attach to a
  human/company identity.
- **Real secrets** — production ad-unit IDs and the plugin's native SDK keys are credentials; they
  don't belong in agent-authored commits (and the model identifier must never leak into the repo).
- **A physical device + advertising ID** — headless Linux CI cannot render or verify a native ad;
  "does an ad actually appear" is only answerable on real hardware you hold.
- **Vendor-specific truth** — the exact plugin singleton/method/signal names (the `VERIFY` marks)
  must be read from the plugin you choose; guessing them risks silent breakage, so they're left for
  you to confirm against its docs.

What the agent *did* do: build the whole async seam, the platform gate, the data-driven config, the
fail-closed safety guarantees, and the tests — so that when you complete the steps above, real ads
drop in with **no further code architecture work**, just wiring named calls.
