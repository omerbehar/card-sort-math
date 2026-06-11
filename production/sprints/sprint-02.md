# Sprint 2 — M2 Content Engine (kickoff)

> Indicative: 2026-06-11 → 2026-06-24 (2 weeks). Goal-driven, not date-driven.
> Review mode: **full**. Producer gate PR-SPRINT: CONCERNS → adjustments adopted
> (generator split, scoring moved to Nice-to-Have, ADR re-plan checkpoint).

## Sprint Goal

Replace the fixed 3-layout MVP with an **endless, difficulty-scaled procedural
level generator** that satisfies the solvability invariant **by construction**
(ADR-0003), wired into the level flow so play continues indefinitely.

## Capacity

- **Total days**: 10 (1 dev, 2 weeks) · **Buffer (20%)**: 2 · **Available**: 8
- Committed (Must-Have) ≈ **6.5 days** → ~1.5 days genuine slack before the buffer
  (per the producer gate: protect the keystone, keep everything else optional).

## Tasks

### Must Have (Critical Path — the generator)
| ID | Task | Owner | Days | Deps | Acceptance Criteria |
|----|------|-------|------|------|--------------------|
| S2-001 | **Level-generator GDD** (`/design-system level-generator`): difficulty knobs (operand magnitude, # distinct results, stack/queue config, operation), seeding, and how solvability is guaranteed | game-designer + systems-designer | 1.5 | ADR-0003 | 8-section GDD, design-reviewed (full mode) |
| S2-002 | **Generator ADR** (`/architecture-decision`): construction algorithm, solvability guarantee, determinism/seed strategy. **Re-plan checkpoint:** on landing, re-estimate S2-003; if backtracking/rejection-sampling is required, formally drop the Nice-to-Have scoring stories that day | technical-director + systems-designer | 0.5 | S2-001 | ADR accepted; S2-003 estimate confirmed |
| S2-003a | **Generator core — by construction** (`core/`): build the target queue, emit exactly 3× cards per result, deterministic shuffle → solvable `LevelConfig` from a seed | gameplay-programmer + gdscript-specialist | 2 | S2-002 | **Property test:** `LevelData.is_solvable` holds for N (≥100) seeds; deterministic per seed; node-free (ADR-0001) |
| S2-003b | **Generator core — difficulty + determinism**: wire the GDD's difficulty knobs; seed-stability under knob changes | gameplay-programmer | 1.5 | S2-003a | Tests: knobs change output as specified; same seed+knobs → identical level; solvability still holds |
| S2-004 | **Wire generator into level flow**: `LevelData`/`GameManager` generate levels by index beyond the authored ones | gameplay-programmer | 1 | S2-003a | Integration test: level N is generated, solvable, playable end-to-end |

> **Partial-landing safety:** S2-003a + S2-004 alone is a shippable, tested generator
> even if S2-003b slips. Construction-first makes the invariant structural, not sampled.

### Should Have
*(None — single keystone this sprint. Scoring is held as the first Nice-to-Have to
pull in if the generator lands clean; see the producer gate rationale.)*

### Nice to Have (cut first / pull in only with slack)
| ID | Task | Owner | Days | Deps | Acceptance Criteria |
|----|------|-------|------|------|--------------------|
| S2-010 | **Scoring/stars quick-design** (`/quick-design`): efficiency = fewer discards → 1–3 stars; tunable thresholds; M3 star-economy hook noted | systems-designer | 0.5 | — | Quick Design Spec + formula |
| S2-011 | **Efficiency score** (`core/`, lands deferred **S1-021**): pure function discards→score/stars, unit-tested | systems-designer | 0.5 | S2-010 | Boundary-tested; deterministic; node-free |
| S2-012 | **Wire stars into `ResultScreen`**: populate the reserved `StarRatingPlaceholder` on WIN | ui-programmer | 1 | S2-011 | Interaction test: WIN shows correct star count for a given discard count |
| S2-020 | **Subtraction operation world**: `CardData` subtraction + themed skin (first new operation) | game-designer + gameplay-programmer | 2 | S2-003a | Subtraction levels generate + solve; world skin applied |
| S2-021 | **Carryover QA sign-offs** (M1 advisory): juice/audio device feel, 60 FPS, tutorial visual ACs (AC15–17), settings feel | qa-lead | 1 | — | Evidence in `production/qa/evidence/` |

## Carryover from Sprint 1
| Task | Reason | New home |
|------|--------|----------|
| S1-021 efficiency score | Deferred to M2 with the star economy | → S2-011 |
| Device/visual QA sign-offs | M1 advisory close-out items | → S2-021 (flag: homeless if never scheduled) |
| Pop-up visual-language decision | Art-direction call (Kenney vs flat) | tracked — art/creative-director, not a sprint story |
| "All levels complete" terminal state | Pre-existing last-level-WIN gap | **Resolved by design** — the generator makes levels endless, removing the last-level loop |

## Risks
See `production/risk-register/m2-risks.md`. Headline:
| Risk | Prob | Impact | Mitigation |
|------|------|--------|------------|
| Generator can't guarantee solvability for all knob combos | Low (with by-construction) | High | Construction-first (3× per result) makes it structural; property test over ≥100 seeds |
| S2-002 ADR reveals backtracking is needed → S2-003 overruns | Med | Med | ADR re-plan checkpoint (day ~2) drops scoring that day |
| Difficulty curve feels wrong | Med | Med | Knobs are data; defer curve calibration to a later sprint/playtest |

## Definition of Done
- [ ] All Must-Have complete & passing ACs
- [ ] QA plan exists (`production/qa/qa-plan-sprint-2.md`) — run `/qa-plan sprint`
- [ ] Generator has a GDD **and** ADR
- [ ] Solvability property test green (≥100 seeds); generator deterministic
- [ ] Generator wired + integration-tested end-to-end
- [ ] Code reviewed & merged; no S1/S2 bugs
- [ ] `/team-qa sprint` sign-off: APPROVED or APPROVED WITH CONDITIONS

## Notes
- Sequence: **S2-001 → S2-002 → S2-003a → S2-003b → S2-004** (single critical chain;
  no parallelism for one dev). Honour the day-2 ADR checkpoint.
- Scope check: run `/scope-check` if stories are added beyond this list.
