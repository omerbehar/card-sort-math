# Architecture Decision Records

Records of the load-bearing technical decisions for CardSortMath. Each ADR is
immutable once Accepted; to change a decision, write a new ADR that supersedes it.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](ADR-0001-model-view-separation.md) | Model/View separation (pure `core/`) | Accepted |
| [0002](ADR-0002-event-sourced-view-replay.md) | Event-sourced view replay (`GameEvent`) | Accepted |
| [0003](ADR-0003-solvability-invariant.md) | Solvability invariant for all levels | Accepted |
| [0004](ADR-0004-gdscript-static-typing-and-gdunit4.md) | GDScript (typed) + gdUnit4 in CI | Accepted |
| [0005](ADR-0005-audience-positioning-13plus-age-gated.md) | Audience: 13+ age-gated (mixed-audience) | Accepted |
| [0006](ADR-0006-popup-base-modal-chassis.md) | Popup base modal chassis | Accepted |
| [0007](ADR-0007-level-generator.md) | Level generator — construction, determinism, dispatch & recoverability | Accepted |
| [0008](ADR-0008-economy-event-type.md) | `EconomyEvent` — separate `core/` type from board `GameEvent` | Accepted |
| [0009](ADR-0009-time-provider-seam.md) | Injectable `TimeProvider` seam (deterministic reshuffle seeds + daily caps/streaks) | Accepted |
| [0010](ADR-0010-extra-discard-slot-board-change.md) | Extra Discard Slot — mutable `_active_discard_slots` + `expand_discard()` | Accepted |
| [0011](ADR-0011-arithmetic-operations-worlds.md) | Arithmetic operations & worlds | Accepted |
| [0012](ADR-0012-hint-to-picker-booster.md) | Hint → Picker booster (no-scoring; protects the math core) | Accepted |
| [0013](ADR-0013-consent-cmp-model.md) | Consent / CMP model — consent fields in `SaveData`, gated through `ComplianceService` (consent × age_band) | Accepted |
| [0014](ADR-0014-monetization-service-seam.md) | Monetization service seam — thin autoloads behind interfaces with injectable mock backends | Accepted |

Create new ADRs with `/architecture-decision`. Template:
`.claude/docs/templates/architecture-decision-record.md`.
