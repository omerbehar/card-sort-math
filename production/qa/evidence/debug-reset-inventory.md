# Debug "Reset Inventory" Button — Visual Evidence

- **Feature**: Settings (pause menu) debug button — resets coins to **1000** and
  every buff (Picker / Reshuffle / Extra Discard) to **3**.
- **Date**: 2026-06-14
- **Evidence**: `debug-reset-before.png`, `debug-reset-settings.png`,
  `debug-reset-after.png`
- **Gate level**: Advisory (UI) + Blocking (Logic/Integration — automated, below)

## How it was produced

Real Godot render (not a mockup) via the dev harness
`tools/screenshot_debug_reset.gd`:

```sh
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --rendering-method gl_compatibility -s res://tools/screenshot_debug_reset.gd
```

Headless can't render (dummy renderer), so this uses the OpenGL3 compatibility
backend under a virtual framebuffer (Mesa llvmpipe). The harness boots
`scenes/main/main.tscn`, drains the inventory to a depleted "before" state,
opens the pause menu, presses the **real** "Reset Inventory" button (driving the
`debug_reset_pressed → main._on_debug_reset → WalletService.debug_set_inventory`
path), then captures the refreshed HUD. **Note:** it writes to the real `user://`
save. Console confirms the end state: `coins=1000 picker=3 reshuffle=3 extra=3`.

## What it shows

1. **`debug-reset-before.png`** — HUD with a depleted inventory: coin badge reads
   **🪙 75**, and the bottom booster tray shows the empty "+" refill cue on all
   three buffs (dimmed/cool-grey tiles).
2. **`debug-reset-settings.png`** — pause menu open. The new **"Reset Inventory"**
   button sits beside **"Reset Tutorial"** in the row above Home / Continue
   (amber-tinted to mark it as a debug control). Behind it the HUD still shows the
   depleted "before" state.
3. **`debug-reset-after.png`** — after pressing the button: coin badge reads
   **🪙 1000**, and every booster tile shows the count **3** on a lit/affordable
   (warm-neutral) tile.

## Behaviour / wiring

- The button is **always shown** (every build, including release on device) per
  boss request, sharing the row with "Reset Tutorial". It is not gated behind
  `OS.is_debug_build()`. (`scenes/ui/pause_menu.gd`)
- `PauseMenu` owns no state — it emits `debug_reset_pressed`; `main.gd` handles it
  via `_on_debug_reset`, calling `WalletService.debug_set_inventory(1000, 3)`
  (constants `DEBUG_RESET_COINS` / `DEBUG_RESET_BOOSTERS`) and refreshing the coin
  HUD. Booster badges refresh off `WalletService.booster_stock_changed`.
- `WalletService.debug_set_inventory` clamps coins to the wallet cap, persists via
  `SaveService`, and emits `booster_stock_changed` per buff. It deliberately
  bypasses the earn/spend policy layer and emits **no** `economy_event`, so it
  never pollutes the live economy or its analytics.

## Automated coverage

- `tests/test_wallet_service.gd` (5 new unit tests, **BLOCKING**): sets coins +
  every buff, overwrites higher existing values, persists across reload, emits one
  `booster_stock_changed` per buff, and clamps coins to the wallet cap.
- `tests/integration/main_booster_flow_test.gd` (2 new integration tests,
  **BLOCKING**): pressing the real pause-menu button end-to-end resets coins +
  every buff and updates the coin HUD label; and the button is present in the
  pause menu (always shown, every build).
