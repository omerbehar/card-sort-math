# Smoke Evidence — EconomyConfig remote-config-ready loader (S3-011)

- **Date**: 2026-06-15
- **Story**: S3-011 (Sprint 3, nice-to-have)
- **Type**: Config/Data infrastructure (Test Evidence table → "Smoke check pass", advisory gate)
- **Files**: `autoloads/economy_config_loader.gd`, `autoloads/remote_config_source.gd`,
  `autoloads/wallet_service.gd` (config source), `project.godot` (autoload registration)

## What changed (and what did NOT)

`WalletService` no longer `load()`s `economy_config.tres` directly; it asks the new
`EconomyConfigLoader` autoload for the resolved config. The loader layers remote
overrides over the local `.tres` base. **No behavioural/value change ships in this
story**: the bundled `RemoteConfigSource` base is a no-op (`fetch_overrides() -> {}`),
so resolution returns the same local defaults the game used before. A real remote
backend is deferred to M4; this story builds only the seam + fallback chain.

Because there is no view surface and no value change, there is nothing new to
screenshot. Evidence is the automated suite (the wiring) plus this smoke note.

## Smoke check

| Check | Result |
|---|---|
| Project imports clean with `EconomyConfigLoader` registered before `WalletService` | PASS |
| Loader unit suite `tests/test_economy_config_loader.gd` (12 cases: local fallback, remote-wins, partial override, unknown-key/type-mismatch robustness, non-mutation, cache, reload) | PASS |
| Full gdUnit4 suite incl. integration (`main_booster_flow_test`, which spends real config-driven booster costs through `WalletService`) | PASS — 596/596, exit 0 |

## Fallback behaviour verified (unit)

- No-op / empty remote → local `.tres` values used (the "remote unavailable" AC).
- Stub remote override → its value wins over the local base; other knobs untouched.
- Malformed payload (unknown key, wrong type) → ignored; config never corrupted.
- Resolution duplicates the base → the shared in-memory `.tres` is never mutated.

## Notes

- `WalletService._ready()` keeps a defensive direct-`load()` fallback if the
  `EconomyConfigLoader` autoload is somehow absent.
- Tests bypass the loader via `WalletService.configure(..., config)`, so no test
  depends on the autoload's resolution — the loader is covered by its own suite.
</content>
