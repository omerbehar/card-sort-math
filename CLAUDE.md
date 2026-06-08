# CardSortMath

A Godot 4.6 mobile **sort-and-stack puzzle** with a mental-math core: cards show
arithmetic exercises (e.g. `3 + 4`); the player computes the result and taps to
route cards onto stacks that collect matching values. Full vision, roadmap, and
monetization plan: **[`docs/GAME_PLAN.md`](docs/GAME_PLAN.md)**.

## Technology Stack

- **Engine**: Godot 4.6 (Mobile renderer, portrait, touch)
- **Language**: GDScript (statically typed)
- **Testing**: gdUnit4 (vendored in `addons/gdUnit4/`), run in CI on every PR
- **Version Control**: Git, feature branches → PR into `main`

## Architecture — the load-bearing rule

**Model/View split is mandatory.** `core/` is pure, deterministic, node-free game
logic that emits `GameEvent`s; the view layer (`scenes/`) replays them as
animations. This is why the game is fully unit-testable. Keep every new system
(generator, economy, save, services) behind this seam.

All authored/generated levels must satisfy the **solvability invariant**
(`LevelData.is_solvable`): for every result, `card_count == 3 × occurrences in
the target queue`.

## Project Structure

@.claude/docs/directory-structure.md

## Technical Preferences

@.claude/docs/technical-preferences.md

## Coordination Rules

@.claude/docs/coordination-rules.md

## Coding Standards

@.claude/docs/coding-standards.md

## Agent / Skill Framework

This repo uses a Godot-focused subset of the
[Claude Code Game Studios](https://github.com/donchitos/claude-code-game-studios)
framework (MIT). Specialist **agents** live in `.claude/agents/`, workflow
**skills** (slash commands) in `.claude/skills/`, and path-scoped **rules** in
`.claude/rules/`. See `.claude/ATTRIBUTION.md` for exactly what was imported and
adapted. No hooks were imported from that framework; the only hook is our own
`SessionStart` hook (`.claude/hooks/session-start.sh`), which installs Godot 4.6
so the gdUnit4 suite can run in Claude Code on the web sessions.

Skills write design artifacts to `design/` and production artifacts to
`production/`.

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.** Prefer:
Question → Options → Decision → Draft → Approval. Confirm before large multi-file
changes; commit/push only when asked.

## Build & Test

- Open in Godot 4.6; main scene is `scenes/main/main.tscn`.
- Tests: the gdUnit4 suite under `tests/` (CI: `.github/workflows/tests.yml`).
