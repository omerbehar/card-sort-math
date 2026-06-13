# Sprint 3 — M3 Meta: Deck Economy core

> Indicative: 2026-06-12 → 2026-06-25 (2 weeks). Goal-driven, not date-driven.
> Review mode: **full**. Producer gate PR-SPRINT: **CONCERNS → adjustments adopted**
> (S3-004/S3-006 re-estimated to 2.0d; Hint promoted to the Must-Have keystone booster and
> Extra Discard demoted to Should-Have; per-level-reset + `configure()` DI ACs added to S3-004;
> TimeProvider reordered before WalletData; `COINS_WIN_FLAT_FALLBACK` knob added; ADR-0010 amended
> for the `recoverability_simulator.gd` reads the producer caught).
> Implements `design/gdd/deck-economy.md` (Undo cut — three boosters: Hint, Reshuffle, Extra Discard).
> Ratified by **ADR-0008** (EconomyEvent), **ADR-0009** (TimeProvider + explicit-int reshuffle seed),
> **ADR-0010** (Extra Discard BoardModel change).

## Sprint Goal

Stand up the **pure, tested wallet transaction core** (two currencies, atomic spend/earn with
snapshot rollback, compliance gating, daily caps, gem→coin conversion) behind the model/view seam,
plus the **first booster (Hint)** end-to-end — the M3 economy foundation that later UI, IAP/ad
services, and the remaining boosters bolt onto. UI is intentionally out of scope (needs `/ux-design`).

## Capacity

- **Total days**: 10 (1 dev, 2 weeks) · **Buffer (20%)**: 2 · **Available**: 8
- Committed (Must-Have) ≈ **7.0 days** → ~1 day slack before the buffer (per the producer gate:
  protect the wallet core, keep boosters beyond Hint optional).

## Tasks

### Must Have (Critical Path — wallet core + Hint, the lower-risk keystone booster)
| ID | Task | Owner | Days | Deps | Acceptance Criteria |
|----|------|-------|------|------|--------------------|
| S3-001 | **`EconomyEvent` + economy enums** (`core/economy_event.gd`; `Currency`/`EarnSource`/`BoosterType`/`reason`): typed `RefCounted` + `Kind`, static factories, `hint_result()` = card_id only (ADR-0008) | gdscript-specialist | 0.5 | ADR-0008 | Unit test: `Kind` = exactly the 10 canonical names; `hint_result()` sets only `card_id` (AC-M01a) |
| S3-003 | **`TimeProvider` seam** (`core/time_provider.gd` + `tests/` `FixedTimeProvider`) — incl. the explicit-integer reshuffle-seed `mix()` helper, NEVER `hash()` (ADR-0009) | gdscript-specialist | 0.5 | ADR-0009 | Tests: fixed clock deterministic; `utc_day_key()` UTC rollover; `mix(level,ts,count)` reproducible + differs per count/ts; no `Time.*` call outside the default provider |
| S3-002 | **`WalletData` + SaveData v1→v2 migration + `EconomyConfig` resource** (`core/wallet_data.gd`; `core/save_data.gd` bump; `assets/data/economy_config.tres`) — config **holds every knob** S3-004/005 read (costs, caps, `COINS_WIN_FLAT_FALLBACK`) | gameplay-programmer | 1.0 | S3-001 | Migration test: v1 save → coins=0/gems=0; `from_dict` defaults missing keys; `_migrate` v1→v2 step; config loads all knobs |
| S3-004 | **`WalletService` transaction core** (autoload): atomic `spend()`/`earn()` w/ pre-spend **snapshot** rollback (EC-09, NOT `earn()`), `EconomyEvent` signal, 0-amount guards, MAX_BALANCE clamp, `SaveService` persist; **`configure()` DI** (Save/Compliance/Time/Config); **per-level economy-state reset** on GameManager level-start/end | gameplay-programmer | 2.0 | S3-002, S3-003 | AC-W01–W08, AC-W05/W05b (near-cap snapshot rollback), AC-B01/B02; **DI wired via `configure()` (no singletons)**; **per-level `reshuffle_count`/`boosters_used_this_level`/`extra_discard_active` cleared on level boundary (own test)** |
| S3-007 | **Hint booster** (`core/` `hint_score` Formula 5, pure; `WalletService.use_booster(HINT)` → `HINT_RESULT`; in-progress double-tap guard) | gameplay-programmer | 1.5 | S3-004 | AC-H01–H05, AC-M01a (no result/operands in payload), EC-08; tie-break lowest `card_id` deterministic |
| S3-005 | **Compliance gating + daily caps + gem→coin conversion** (`WalletService` + `DailyCapTracker` via `TimeProvider.utc_day_key()`): `not is_restricted()` ad/IAP gate; rewarded-ad + gem-convert caps; child-mode play-earn ungated; `convert_gems_to_coins()` | gameplay-programmer | 1.5 | S3-004, S3-003 | AC-C01–03, AC-CL01–03, AC-CH01/02, AC-GC01–03, EC-10–14 |

> **Sequence (single chain, 1 dev):** S3-001 → S3-003 → S3-002 → S3-004 → S3-007 → S3-005.
> **Partial-landing safety:** S3-001→S3-005 minus S3-007 is still a complete, tested wallet core
> (currencies, transactions, compliance, caps, conversion). S3-007 Hint proves the wallet→booster→
> event seam with a pure, low-risk booster *before* any core board state is touched.

### Should Have (pull in with slack)
| ID | Task | Owner | Days | Deps | Acceptance Criteria |
|----|------|-------|------|------|--------------------|
| S3-006 | **Extra Discard Slot booster** (`BoardModel` mutable `_active_discard_slots` + `expand_discard()`, ADR-0010: refactor the **3 instance loops**, leave the **3 `recoverability_simulator.gd` reads** at base + comment; `WalletService.use_booster(EXTRA_DISCARD)` precondition + `MAX_DISCARD_SLOTS` cap) | gdscript-specialist + gameplay-programmer | 2.0 | S3-004, **ADR-0010 (amended)** | **Board suite + generator/recoverability suite green (inert at 5)**; `DISCARD_SLOTS` grep = exactly 6 sites; AC-E01–E06; purchase-ahead-only (EC-06/07) |
| S3-008 | **Earn triggers: level-win coins + clean-clear bonus** wired to `GameManager` win (Formula 1/1b; **flat fallback** `COINS_WIN_FLAT_FALLBACK` until stars S2-011 lands — GDD Open Q) | gameplay-programmer | 1.0 | S3-004 | AC-EFF01–03, AC-EF01/02; `boosters_used_this_level == 0` gates bonus; no hardcoded earn value |

### Nice to Have (cut first / pull in only with slack)
| ID | Task | Owner | Days | Deps | Acceptance Criteria |
|----|------|-------|------|------|--------------------|
| S3-009 | **Reshuffle booster** (new `LevelGenerator.reshuffle(config, seed)` helper: re-permute slots only via ADR-0007 §8 Fisher–Yates, explicit-int seed ADR-0009, routable-card guarantee; `WalletService.use_booster(RESHUFFLE)`) | gameplay-programmer | 2.0 | S3-004, S3-003, ADR-0007/0009 | AC-R01–R09, AC-I01/I02; card set + queue preserved; `is_solvable` holds |
| S3-010 | **Streak + milestone earn math** (`core/`, `TimeProvider`-driven; day-3 reset floor). *Daily-challenge faucet deferred — system not built* | systems-designer | 1.0 | S3-004, S3-003 | AC-EF03/04/05/06 (streak/milestone only); deterministic |
| S3-011 | **`EconomyConfig` remote-config-ready loader** + local `.tres` fallback | tools-programmer | 0.5 | S3-002 | All costs/caps drive from config; falls back to local resource if remote unavailable |

## Deferred beyond this sprint (explicit — not silently dropped)
| Deferred | Why | Home |
|----------|-----|------|
| Booster tray HUD, wallet display, post-level earn summary, shop screen | Need `/ux-design` specs (GDD UX flag, Pre-Production) | Later M3 UI sprint |
| IAP Service, Ad Service (earn call-ins) | M4 Monetize; GDD marks them planned | M4 |
| Analytics `EconomyEvent` subscription | M5 Instrument | M5 |
| Daily-challenge coin faucet, login-streak *trigger* | Daily-challenge system is unbuilt M3 meta | When daily-challenge lands |
| Stars-weighted earn (40/55/75) | Scoring/stars S2-011 not done; flat fallback used | When S2-011 lands |

## Carryover from Sprint 2
| Task | Reason | New home |
|------|--------|----------|
| S2-011 efficiency score / stars | Was Nice-to-Have in Sprint 2, not completed | Economy uses `COINS_WIN_FLAT_FALLBACK` until it lands |

## Risks
| Risk | Prob | Impact | Mitigation |
|------|------|--------|------------|
| ADR-0010 refactor regresses the board / recoverability suites | Low | High | Inert at 5 slots; grep = exactly 6 sites; re-run **both** suites (S3-006 AC) |
| `WalletService` AC surface large → S3-004/005 overrun | Med | Med | S3-004 re-estimated to 2.0d; transaction core split from policy/caps (S3-005); partial-landing safety |
| Economy not player-visible this sprint (UI deferred) | High (planned) | Low | Model-first discipline; UI is a separate UX-spec'd sprint; everything unit-tested |
| Reshuffle needs a new generator helper | Med | Med | Nice-to-Have; `reshuffle()` reuses ADR-0007 §8 Fisher–Yates; cut first |
| Snapshot-rollback (EC-09) subtlety → clamp bug near MAX | Med | High | AC-W05b is the explicit near-cap regression test; direct assignment, never `earn()` |

## Dependencies on External Factors
- None. All three ADRs are Accepted; ComplianceService (`is_restricted()`) and the board/generator
  suites already exist. IAP/Ad/Analytics services are deferred, so no SDK dependency this sprint.

## Definition of Done for this Sprint
- [ ] All Must-Have tasks completed & passing ACs
- [ ] QA plan exists (`production/qa/qa-plan-sprint-3.md`) — run `/qa-plan sprint`
- [ ] Wallet core: spend/earn atomic + snapshot rollback; caps; conversion; compliance — all unit-tested
- [ ] Board suite **and** generator/recoverability suite green after the ADR-0010 refactor (if S3-006 lands)
- [ ] SaveData v1→v2 migration tested
- [ ] No hardcoded tuning — all costs/caps/earn from `EconomyConfig`
- [ ] Code reviewed & merged; no S1 or S2 bugs in delivered features
- [ ] Design docs updated for any deviations
- [ ] `/team-qa sprint` sign-off: APPROVED or APPROVED WITH CONDITIONS

## Notes
- **Scope check:** if stories are added beyond this list, run `/scope-check deck-economy`.
- Honour the keystone shape: wallet core is the non-negotiable foundation; Hint is the one
  Must-Have booster; Extra Discard / Reshuffle / earn-triggers are the pull-in queue.
