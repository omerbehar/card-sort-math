# Directory Structure

Actual layout of the CardSortMath repository. (This differs from the upstream
framework's generic `src/`-based layout — agents and rules are scoped to the
directories below.)

```text
/
├── CLAUDE.md                # Project configuration & conventions
├── project.godot            # Godot 4.6 project config
├── icon.svg                 # App icon
├── .claude/                 # Agents, skills, rules, docs (this framework)
├── .github/                 # CI workflows + Copilot review instructions
├── addons/
│   └── gdUnit4/             # Vendored test framework (v6.1.3)
├── core/                    # PURE game logic — node-free, deterministic, tested
│                            #   board_model, exposure, layouts, game_event
├── data/                    # Card/level Resource definitions (CardData, LevelConfig)
├── autoloads/               # Singletons: GameManager, LevelData (+ future services)
├── scenes/                  # View layer (replays core GameEvents)
│   ├── main/ card/ stack/ discard/ floor/
│   └── ui/                  # HUD / UI screens (scoped by ui-code rules)
├── assets/
│   └── ui/                  # Kenney skin + icons (assets/shaders/ for future shaders)
├── tests/                   # gdUnit4 suites (one per system)
├── tools/                   # Dev tooling (playthrough harness)
├── docs/                    # Design & technical docs (GAME_PLAN.md, architecture/, ADRs)
│   └── architecture/        # ADRs (created by /architecture-decision)
├── design/                  # Design artifacts emitted by skills (gdd/, quick-specs/, ...)
└── production/              # Sprint plans, milestones, releases (skill output)
```

## Path → rule scope mapping

| Directory | Rule applied |
|-----------|--------------|
| `core/`, `scenes/` | `gameplay-code.md` |
| `scenes/ui/` | `ui-code.md` |
| `autoloads/` | `engine-code.md` |
| `data/` | `data-files.md` |
| `tests/` | `test-standards.md` |
| `docs/`, `design/` | `design-docs.md` |
| `assets/shaders/` | `shader-code.md` |
| `tools/`, `prototypes/` | `prototype-code.md` |
