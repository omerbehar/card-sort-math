# Architecture Decision Records

Records of the load-bearing technical decisions for CardSortMath. Each ADR is
immutable once Accepted; to change a decision, write a new ADR that supersedes it.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](ADR-0001-model-view-separation.md) | Model/View separation (pure `core/`) | Accepted |
| [0002](ADR-0002-event-sourced-view-replay.md) | Event-sourced view replay (`GameEvent`) | Accepted |
| [0003](ADR-0003-solvability-invariant.md) | Solvability invariant for all levels | Accepted |
| [0004](ADR-0004-gdscript-static-typing-and-gdunit4.md) | GDScript (typed) + gdUnit4 in CI | Accepted |

Create new ADRs with `/architecture-decision`. Template:
`.claude/docs/templates/architecture-decision-record.md`.
