# Real-ads scaffolding (RealAdBackend + consent bridge + config) · QA Evidence

**Type:** Backend scaffolding / architecture · **Spec:** `docs/architecture/real-ads-integration-plan.md` §3–§5
**Status:** full suite green (backend seam — no UI surface, no screenshot). Human wiring steps in
`docs/architecture/real-ads-setup-guide.md`.

## What shipped

The safe, inert scaffolding that lets a real AdMob plugin drop into the async `AdBackend` seam with
no further architecture work — and ships today without showing or breaking anything:

- **`data/ad_unit_config.gd`** (`AdUnitConfig`) — data-driven per-platform ad-unit IDs; Google
  **test** IDs by default, production IDs only when `use_test_ad_units = false` in a release build.
- **`autoloads/real_ad_backend.gd`** (`RealAdBackend extends AdBackend`) — wraps the native plugin
  singleton; **inert** (`is_active() == false`) with no plugin, so every `show_*` resolves its async
  signal exactly once (no-fill / not-completed). Exactly-once `_finish_*` guards against duplicate
  SDK callbacks. All plugin calls are `VERIFY`-marked for the human to wire.
- **`autoloads/ad_consent_bridge.gd`** (`AdConsentBridge`) — UMP/ATT → consent, **fail-closed**
  (records no personalized-ads consent, returns false) until wired. Routes through the new narrow
  `SaveService.capture_ad_personalization_consent` chokepoint — never touches consent fields
  directly (single-reader invariant, ADR-0013 Criterion 6, preserved).
- **`autoloads/ad_service.gd`** `_resolve_backend()` — picks `RealAdBackend` on Android/iOS **only
  when the plugin is active**, else the no-op base `AdBackend`. CI/desktop always get the base
  backend, so the native SDK is never loaded headlessly (risk M4-R3).
- **`autoloads/save_service.gd`** — `capture_ad_personalization_consent(bool)`: writes only the
  ad-personalization flag, leaving analytics/IAP to the in-app CMP sheet (S6).

## Automated evidence (BLOCKING — green)

New unit suites pin the load-bearing safety guarantees (all run headlessly on CI where no plugin
exists):

- `tests/unit/ads/ad_unit_config_test.gd` (4) — test-ID default; test-mode ignores authored prod IDs;
  production-mode routes per platform; non-iOS falls to the Android branch.
- `tests/unit/ads/real_ad_backend_test.gd` (3) — inert without a plugin; interstitial resolves
  `NO_FILL`; rewarded resolves not-completed — i.e. **never hangs the win flow**.
- `tests/unit/ads/ad_consent_bridge_test.gd` (2) — fails closed (records `false`, returns false)
  with no CMP; returns false and does not crash when the sink lacks the method.
- `tests/unit/save/consent_migration_test.gd` `test_consent_fields_read_only_by_permitted_files` —
  still green: the bridge introduces **no** new direct consent-field reader.

Full suite: **845 test cases, 0 failures** (was 836; +9).

## Notes / follow-ups

- `RealAdBackend`'s plugin calls and `AdConsentBridge`'s UMP/ATT calls are intentionally stubbed and
  `VERIFY`-marked — they are wired by the human against the chosen plugin's docs (setup guide Steps
  2–3). Until then behaviour is identical to the no-op base backend.
- No screenshot: this is a non-visual backend seam. First on-device visual verification (a real test
  ad rendering) is setup-guide Step 6, which requires a physical device + AdMob account.
