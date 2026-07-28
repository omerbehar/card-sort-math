# Async `AdBackend` contract (real-ads plan Phase 1) · QA Evidence

**Type:** Refactor / architecture · **Spec:** `docs/architecture/real-ads-integration-plan.md` §2
**Status:** full suite green (backend refactor — no UI surface, no screenshot).

## What shipped

Evolves the ad presentation seam from **synchronous** to **async**, so a real ad SDK
(load → fill → show → dismiss/reward callback) can drop in as an `AdBackend` subclass with no
change to the service's gating logic. The mock stays the CI/desktop backend.

- `AdBackend`: `show_interstitial(ad_type)` / `show_rewarded()` now return **void** and report
  their outcome via new **deferred** signals `interstitial_finished(outcome)` /
  `rewarded_finished(completed)`. Added `preload_*` / `has_*_ready` no-op stubs for a real
  backend to implement. `MockAdBackend` keeps its config vars (`interstitial_result`,
  `rewarded_completes`) and emits them deferred (so an `await` set up right after the call
  catches them).
- `AdService.maybe_show_interstitial()` / `show_rewarded()` keep their **synchronous gates**
  (triple gate + frequency cap — unchanged, fully unit-testable) and now `await` the backend
  result signal before returning the same `InterstitialOutcome` / credited-coins value.
- Callers `await`: `main.gd._on_win_advance` (`await ad.maybe_show_interstitial()`),
  `RewardedPrompt._on_watch` (`await _ad.show_rewarded()`). `InterstitialMock` remains the
  dev/mock presentation; a real backend owns its own overlay (noted inline).

Model/view seam (ADR-0001) and the triple gate are untouched — only the leaf backend call
became awaited.

## Automated evidence (BLOCKING — green)

The existing ad suites were updated to `await` the now-async calls and **all pass headlessly** —
confirming the deferred-signal `await` works in pure unit tests (no scene tree needed):

- `tests/unit/ads/ad_service_test.gd` (17) — gate/cap/targeting + SHOWN/NO_FILL + rewarded
  credit/abandon/cap paths, all via `await`.
- `tests/integration/ads/ad_gate_matrix_test.gd`, `rewarded_earn_test.gd` — the triple-gate
  matrix + end-to-end rewarded earn through the real `WalletService`.
- `tests/integration/interstitial/…`, `rewarded/…` — the UI flows (`main._on_win_advance`,
  `RewardedPrompt`) drive the async service. `RewardedPrompt`'s fake returns a plain int, which
  `await` passes through unchanged — no fake churn.

Full suite: **836 test cases, 0 failures**.

## Notes / follow-ups

- **Preload-ahead** (`preload_interstitial` on the level boundary) is stubbed but not yet wired
  in `AdService` — a latency optimization for a real SDK; follow-up.
- This is Phase 1 of the real-ads plan. Phases 2+ (the actual `RealAdBackend` against a native
  plugin, consent/UMP/ATT, device verification) require infrastructure not available in this
  environment and remain the native-SDK sprint's work.
