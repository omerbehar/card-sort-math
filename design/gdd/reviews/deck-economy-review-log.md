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
