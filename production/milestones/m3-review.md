# Milestone Review: M3 — Deck Economy Core

> **Review mode: Full** — PR-MILESTONE producer gate verdict: **ON TRACK**.

## Overview

| Field | Value |
|-------|-------|
| **Milestone** | M3 — Deck Economy Core |
| **Scope** | Wallet transaction core, compliance/caps/conversion, boosters, earn math, remote-config loader |
| **Window** | 2026-06-12 → 2026-06-25 (indicative; goal-driven, not date-driven) |
| **Current date** | 2026-06-15 |
| **Days remaining** | 10 |
| **Sprint in scope** | Sprint 3 |
| **Tests green** | 596 / 596 (exit 0), incl. real-scene integration |

---

## Feature Completeness

### Fully Complete

| Feature | Acceptance Criteria | Test Status |
|---------|---------------------|-------------|
| `EconomyEvent` + economy enums (S3-001) | 10 canonical kinds; leaf type | ✅ unit |
| `TimeProvider` seam + explicit-int reshuffle mix (S3-003) | deterministic clock; UTC day key; no stray `Time.*` | ✅ unit |
| `WalletData` + SaveData migration + `EconomyConfig` (S3-002) | v1→v2 migration; data-driven knobs | ✅ unit |
| `WalletService` transaction core (S3-004) | atomic spend/earn, snapshot rollback, DI, per-level reset | ✅ unit + integration |
| Compliance gating + daily caps + gem→coin (S3-005) | restriction gate, ad/convert caps, conversion | ✅ unit |
| Extra Discard Slot booster (S3-006) | mutable slots, MAX cap, purchase-ahead | ✅ unit |
| Earn triggers: level-win + clean-clear bonus (S3-008) | flat fallback until S2-011 | ✅ unit |
| Reshuffle booster (S3-009) | coverage re-permute, solvability holds | ✅ unit |
| Picker booster (S3-012, replaced Hint) | pick covered card, no answer reveal | ✅ unit + integration |
| Streak + milestone earn math (S3-010) | Rule 16–18, TimeProvider-driven | ✅ unit |
| EconomyConfig remote-config loader (S3-011) | remote-over-local, fallback, robustness | ✅ unit + smoke |

**12 of 12 stories DONE (100%).**

### Partially Complete

*None.*

### Not Started (deferred by design — not dropped)

| Feature | Priority | Can Cut? | Impact of Cutting |
|---------|----------|----------|-------------------|
| Booster tray HUD / wallet display / shop | M3-UI sprint | Deferred | Needs `/ux-design`; economy non-visible until then |
| IAP & Ad services | M4 | Deferred | No SDK dependency this milestone |
| Analytics `EconomyEvent` subscription | M5 | Deferred | Instrumentation milestone |
| Daily-challenge faucet + login-streak trigger | When daily-challenge lands | Deferred | Streak *math* built; trigger system unbuilt |
| Stars-weighted earn (40/55/75) | Carryover (S2-011) | Deferred | Flat `COINS_WIN_FLAT_FALLBACK` in use |

---

## Quality Metrics

- **Open S1 Bugs**: 0 (no bug tracker; none reported against delivered features)
- **Open S2 Bugs**: 0 · **Open S3 Bugs**: 0
- **Test suite**: 596/596 passing, exit 0, incl. real-scene integration (`tests/integration/main_booster_flow_test.gd`)
- **Performance**: N/A — pure model/service layer, no per-frame hot paths added

## Code Health

- **TODO**: 0 in own code · **FIXME**: 0 · **HACK**: 0 (the 6 found are all in vendored `addons/gdUnit4/`)
- **Technical debt**: `COINS_WIN_FLAT_FALLBACK` is an intentional, producer-flagged bridge until S2-011 ships (`data/economy_config.gd:37-39`, `autoloads/wallet_service.gd`)

## Risk Assessment

| Risk | Status | Impact if Realized | Mitigation Status |
|------|--------|--------------------|-------------------|
| No M3 milestone-definition file (process gap) | Closing | Med | Definition file back-filled (`m3-definition.md`); gate future milestones on a definition before sprint planning |
| S2-011 stars carryover (2 sprints) → economy tuned on placeholder | Open | Med | Flat fallback documented + flagged; sequence S2-011 early in M4/M5 |
| Economy not player-visible (by design) | Accepted | Low | UI is a separate UX-spec'd sprint; fully unit/integration covered |
| Pulled-in scope adds maintenance surface for M4 | Open | Low | Account for Reshuffle/Picker/streak/loader upkeep in M4 capacity |

## Velocity Analysis

- **Planned vs Completed**: 8 committed (6 Must + 2 Should) → 8 delivered, **plus 4 pulled-in** = 12 total, 100%
- **Trend**: Improving — over-delivered within the window, ahead of the indicative end date
- **Adjusted estimate for remaining work**: 0 days — scope complete with 10 days of window unused

## Scope Recommendations

### Protect (Must ship with milestone)
- Wallet transaction core + compliance/caps/conversion — the foundation everything bolts onto. ✅ shipped.

### At Risk (May need to cut or simplify)
- Nothing in M3. Watch the **S2-011 stars dependency** — it bleeds into M4 economy balancing.

### Cut Candidates (Can defer)
- None — zero remaining scope. The milestone *expanded* (4 extra stories) rather than crept; additions landed complete and tested. M4 inherits more surface to maintain than the original M3 plan implied.

---

## Go/No-Go Assessment

**Recommendation: GO** (milestone complete)

**Producer verdict (PR-MILESTONE gate, full mode): ON TRACK.** Independently verified — wallet/economy core files, the real-scene integration test, 0 own-code debt markers, the QA plan + populated evidence directory, and the documented/flagged S2-011 fallback all confirmed in-repo.

**Conditions to clear before/at M4 kickoff (not blocking M3 close):**
1. Back-fill the missing M3 milestone-definition file. — **Done** (`m3-definition.md`).
2. Confirm the Hint→Picker (2026-06-13) design-change paper trail includes an ADR/decision record of *why*, since the GDD originally specified Hint as the keystone booster.
3. Carry the S2-011 stars dependency into the M4 risk register as an open, owned line item.

**Rationale**: M3 met its goal in full — a pure, tested, data-driven economy core behind the model/view seam — with 100% completion, zero blocked work, clean code health, and a green integration suite, comfortably ahead of the indicative date. Deferrals are all explicit and milestone-appropriate. The only outstanding items are process hygiene and a known cross-milestone carryover, none of which compromise the milestone.

## Action Items

| # | Action | Owner | Deadline |
|---|--------|-------|----------|
| 1 | Create M3 milestone-definition + close-review files | producer | M4 kickoff — **definition done** |
| 2 | Record Hint→Picker decision as an ADR (`/architecture-decision`) | technical-director | M4 kickoff |
| 3 | Add S2-011 stars dependency to M4 risk register | producer | M4 kickoff |
| 4 | Schedule `/ux-design` for booster tray HUD / wallet / shop before M4 assumes a UI surface | ux-designer | Pre-M4 |
| 5 | Account for pulled-in booster/loader maintenance in M4 capacity | producer | M4 planning |

---

## Next Steps

- Run `/gate-check` if M3→M4 is a formal development-phase boundary.
- Run `/sprint-plan` to draft Sprint 4 (M4 Monetize) using the scope recommendations above.

_Reviewed 2026-06-15. Producer gate (PR-MILESTONE, full mode): ON TRACK._
