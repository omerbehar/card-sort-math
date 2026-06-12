# Deck Economy — Review Log

## Review — 2026-06-12 — Verdict: NEEDS REVISION → revised & accepted (APPROVED)
Scope signal: L → XL (revision itself M; implementation L–XL)
Specialists: game-designer, systems-designer, economy-designer, qa-lead, godot-gdscript-specialist, ux-designer, creative-director (synthesis)
Blocking items: 11 | Recommended: 6

Summary: Strong, thorough GDD whose vision (two-currency model, four-faucet design,
no-arithmetic-solving constraint, calm-toolbox positioning) is sound, but it was not
implementable as written. Six independent specialists converged on five root issues:
(1) the Player Fantasy's load-bearing "efficiency bonus" for no-spend clears was never
mechanized; (2) a three-way economy event-name schism left ~19 ACs unverifiable against a
nonexistent enum; (3) the ~750/day income headline was never reconciled with the 500/day cap,
and gem→coin conversion bypassed the cap; (4) three boosters were specified against
`BoardModel`/`ComplianceService` APIs that don't exist (`replay_to()`/`tap_history`,
`can_show_ads()`/`can_show_iap()`); (5) the GDD owed several spend-trust UX decisions.

Resolution (all 11 blockers addressed in-session):
- Efficiency bonus mechanized: Formula 1b `CLEAN_CLEAR_BONUS=20` + knob + AC-EFF01–03.
- Canonical `EconomyEvent` type introduced (separate from board `GameEvent`); references corrected.
- `DAILY_COINS_CAP` scope declared ad-earn-only; income model recomputed; conversion on its own cap.
- Streak reset softened to a day-3 floor (`STREAK_RESET_FLOOR`); contradiction fixed; average 37→39.
- Hint ceiling corrected 585→405 (GDD + registry); weight-interaction + card_id notes added.
- Rollback uses pre-spend snapshot (EC-09) + AC-W05b near-MAX regression.
- Undo respecified as replay-from-initial coordinator; EC-16/AC-U07 Undo-after-Reshuffle.
- ComplianceService gate corrected to `not is_restricted()` throughout.
- Extra Discard Slot reframed purchase-ahead-only (single mechanism, 3-loop refactor noted); EC-06/AC-E05 rewritten.
- Reshuffle routable-card guarantee (EC-05 "spend-and-stuck" designed out); `reshuffle()` not `generate()`.
- SaveData v1→v2 migration spelled out.
- UX contracts fixed: spend-confirm ≥250, distinguishable feedback, bottom HUD tray, ad CTA hierarchy + cap-gate.
- Premium Bundle labeled an intentional anchor SKU.

Design decisions by author: efficiency bonus = coin bonus; Extra Discard = proactive-only;
streak = day-3 floor; Reshuffle = guarantee a routable card.

Prior verdict resolved: First review.
Disposition: Revisions accepted; marked Approved without a fresh-context re-review (author's call).
Note: No `design/gdd/systems-index.md` exists in this repo, so no systems-index status update was made.

## Scope change — 2026-06-12 — Undo booster removed (author decision, pre-implementation)

Trigger: while scoping ADRs for implementation (the "decide before implementation" Open
Questions), the author elected to **cut the Undo booster entirely** rather than build the
replay-from-initial coordinator it required. The booster set drops from four to **three**:
**Hint, Reshuffle, Extra Discard Slot**.

Rationale:
- Undo was the only booster requiring net-new cross-system machinery — a per-level session
  coordinator owning `tap_history`, a `LevelConfig` reference, and an O(N) replay of every prior
  tap against a freshly reconstructed `BoardModel` — for a quality-of-life feature. Cutting it
  removes the heaviest, highest-risk slice of the economy (the replay coordinator + its tap-capture
  coupling) with no impact on the core faucet/sink economy or the no-arithmetic-solving pillar.
- The remaining boosters act on board *arrangement* (Hint = routing highlight; Reshuffle = layout;
  Extra Discard = buffer capacity); none needs an event log or replay seam, so `BoardModel` keeps
  its stateless-return model unchanged.

Ripple applied this session (full removal + this log note, per author):
- **GDD body**: Overview + Player Fantasy ("all three boosters"); Core Rule 7 (four→three);
  Core Rule 9 **tombstoned** (kept as a number so `Core Rule N` cross-refs stay valid); Core Rules
  4/8/12 Undo clauses struck; clean-clear forfeit list (Rule 13); States table (`undos_used` +
  `tap_history` rows removed); Interactions + Dependencies `BoardModel` rows; Visual/Audio
  ("Undo activation" bullet); UI Requirements (tray 4→3 buttons, 176pt→132pt, spend-confirm copy,
  failure-feedback copy).
- **Spend rates**: Rule 19 (Undo 180 coins) + Rule 20 (Undo 5 gems) removed; Formula 2
  time-to-afford table Undo row removed; Formula 1b example reworded.
- **Edge cases**: EC-02/03/04/16 struck (tombstoned); EC-09 rollback example moved Undo(180)→Reshuffle(250).
- **Acceptance Criteria**: AC-U01–U07 withdrawn; AC-R06 (tap_history/Undo) removed; AC-E02
  (Undo+Extra-Discard interaction) removed; AC-W05b 180→250; AC-I01/I02 integration retargeted
  Undo-replay → Reshuffle; AC-B01 "four"→"three".
- **Tuning Knobs**: `UNDO_COST_COINS`, `UNDO_COST_GEMS` rows removed.
- **IAP catalog**: Booster 5-Pack copy "5× Undo"→"5× Reshuffle".
- **Open Questions**: "Undo implementation risk" withdrawn; `EconomyEvent` / `TimeProvider` /
  Extra-Discard entries marked RESOLVED in ADR-0008 / ADR-0009 / ADR-0010 respectively.
- **Registry** (`design/registry/entities.yaml`): `UNDO_COST_COINS` + `UNDO_COST_GEMS` removed
  (tombstone comments left in place).

Note: the injectable `TimeProvider` seam **survives** the Undo cut — it is still required for
Reshuffle determinism (Formula 6 `level_start_timestamp`, AC-R04/R08) and daily caps/streaks.
It is ratified independently in ADR-0009.
