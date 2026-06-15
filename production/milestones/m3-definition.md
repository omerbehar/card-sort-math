# Milestone Definition: M3 — Meta (Deck Economy Core)

> Back-filled 2026-06-15 to close the process gap flagged in the M3 milestone
> review (PR-MILESTONE condition #1). M3 was executed via Sprint 3 before this
> definition existed; this document records the milestone's intended scope,
> success criteria, and boundaries as the acceptance baseline.

## Relationship to GAME_PLAN

GAME_PLAN §15 lists **M3 — Meta** (map, daily challenge, streaks, XP,
achievements, stats) and places *monetization* (IAP, ads, CMP) under **M4 —
Monetize**. The Deck Economy is the **Meta/Retention foundation** for M3: the
currency/wallet/booster *core* the meta systems and (later) monetization bolt
onto. This milestone deliberately builds only that core — the player-facing meta
screens (map, daily challenge, streak UI, shop) and all monetization surfaces are
their own scoped work. So M3 is delivered in slices; the Deck Economy core
(Sprint 3) is the first and the load-bearing one.

## Goal

Stand up a **pure, tested, data-driven wallet transaction core** behind the
mandatory model/view seam — two currencies; atomic spend/earn with snapshot
rollback; compliance gating; daily caps; gem→coin conversion; the consumable
boosters; and the earn math — so later UI, IAP/ad services, analytics, and the
remaining meta systems can attach without touching transaction logic.

## In Scope (Deck Economy core slice — Sprint 3)

- `EconomyEvent` channel + economy enums (disjoint from board `GameEvent`).
- `TimeProvider` injectable clock seam (deterministic; UTC day key).
- `WalletData` + SaveData migration + `EconomyConfig` (all knobs data-driven).
- `WalletService` transaction core: atomic spend/earn, pre-spend snapshot
  rollback, DI via `configure()`, per-level economy-state reset.
- Compliance gating + daily caps + gem→coin conversion.
- Consumable boosters: Picker (replaced Hint), Reshuffle, Extra Discard Slot.
- Earn triggers (level-win + clean-clear bonus) and streak/milestone earn math.
- `EconomyConfig` remote-config-ready loader with local fallback.

## Out of Scope (deferred — explicitly, not dropped)

| Deferred | Home |
|----------|------|
| Booster tray HUD, wallet display, post-level earn summary, shop screen | Later M3 UI sprint (needs `/ux-design`) |
| IAP Service, Ad Service + mediation, CMP | M4 — Monetize |
| Analytics `EconomyEvent` subscription, A/B framework | M5 — Instrument |
| Daily-challenge coin faucet, login-streak *trigger* | When the daily-challenge system is built |
| Stars-weighted earn (40/55/75) | Carryover S2-011; flat `COINS_WIN_FLAT_FALLBACK` used until it lands |
| Map / XP / achievements / stats meta screens | Later M3 meta slices |

## Success Criteria (acceptance baseline)

1. Wallet core: spend/earn atomic with snapshot rollback; daily caps; gem→coin
   conversion; compliance gating — all unit-tested.
2. SaveData migration tested; no hardcoded tuning (all costs/caps/earn from
   `EconomyConfig`).
3. Model/view split and the solvability invariant remain intact.
4. At least one booster proven end-to-end through an integration test driving the
   real scene tree + autoloads.
5. Full gdUnit4 suite green in CI.

## Dependencies

- **Upstream**: SaveService (persistence), ComplianceService (`is_restricted()`),
  the level generator + board/recoverability suites (M2) — all present.
- **Downstream (this milestone enables)**: M3 meta-economy UI; M4 IAP/Ad/CMP
  (earn call-ins); M5 analytics (`EconomyEvent` subscription).
- **Cross-milestone carryover**: S2-011 stars/efficiency score — until it lands,
  earn uses the documented flat fallback.

## Ratifying ADRs

- **ADR-0008** — `EconomyEvent` type.
- **ADR-0009** — injectable `TimeProvider` seam + explicit-int reshuffle seed.
- **ADR-0010** — Extra Discard Slot `BoardModel` change.
- _Pending_: an ADR recording the 2026-06-13 Hint→Picker design change.

## Sprints

- **Sprint 3** (`production/sprints/sprint-03.md`) — Deck Economy core. Status:
  **complete** (12/12 stories). Review: `production/milestones/m3-review.md`.

## Status

**Deck Economy core slice: COMPLETE** (2026-06-15). Remaining M3 meta slices
(UI, map, daily challenge, XP, achievements, stats) are not yet scheduled.
