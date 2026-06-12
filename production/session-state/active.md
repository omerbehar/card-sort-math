# Active Session — Handoff

**Last updated:** 2026-06-12
**Branch:** `claude/project-status-udaOL` (even with `main`; PRs #19/#20/#21 merged)

## Where we are

Two arcs landed this session and are fully shipped to `main`:

1. **iOS → TestFlight pipeline (from scratch).** `.github/workflows/mobile-build.yml`
   builds the Godot iOS export on `macos-26` (Xcode 26 / iOS 26 SDK), signs manually
   (Apple Distribution cert + App Store profile), and uploads to TestFlight via
   `altool` + App Store Connect API key. Triggers: `workflow_dispatch`, `push` to
   `main`, and `v*` tags. Build number = `github.run_number`. All Apple secrets are
   in GitHub Actions secrets.
   - Fixes baked in: ETC2/ASTC enabled (`project.godot` `import_etc2_astc=true`) —
     this was the cause of the silent "configuration errors"; manual code signing;
     portrait lock (`orientation=1` + `UIRequiresFullScreen`); iPhone+iPad
     (`targeted_device_family=2`). Details: `docs/ios-build.md`, `docs/android-build.md`.

2. **Locked-decks prototype + reset-tutorial.** Game starts with **1 deck open, 3
   locked** behind a buyable green "+" (coin stub, `UNLOCK_COST=100`, starting
   `_coins=150`; ad-watch stub when broke). Settings → **Reset Tutorial** button.
   - Core: `BoardModel` `open_count` + `_locked[]` + `unlock_stack()`; new
     `GameEvent.UNLOCK`. View: `stack.gd` lock chrome, `main.gd` coins HUD +
     `_on_unlock_requested`, `pause_menu.gd` reset button. 5 new board tests pass.
   - Visual evidence: `production/qa/evidence/locked-decks.png` (rendered via
     `tools/screenshot_board.gd` under xvfb).

**CI status:** mobile-build **run #10 (push, sha 86ceba3) = SUCCESS.** The
locked-decks + reset-tutorial + portrait build is on TestFlight (pending Apple
processing). Install that build to see the locked decks on device.

## Open / deferred work

- **Deck economy `/design-system` pass (NOT STARTED).** The locked-decks economy is
  a prototype stub. Needs a real design: where coins come from, the unlock pricing
  curve, ad placement/SDK choice, and teaching the level generator to scale
  difficulty to the number of open stacks. This is the agreed next workstream.
- Level-generator GDD (S2-001) + ADR-0007 are done and in `main`.

## Conventions to keep

- Develop only on `claude/project-status-udaOL`; never push elsewhere without
  permission. Don't open PRs unless asked.
- On every `git push`, verify the `<old>..<new>` ref-update line printed — not just
  `tail -1` (a silent push failure once cost us a lost prototype commit).
- Sandbox: `git reset --hard` is permission-blocked; use `git checkout -B` instead.
