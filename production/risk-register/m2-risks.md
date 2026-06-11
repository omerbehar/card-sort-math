# Risk Register — M2 Content Engine

> Stood up Sprint 2 (2026-06-10) per the PR-SPRINT producer gate. M2's central risk
> is a single algorithmic keystone (the level generator), so risks are tracked here.

| # | Risk | Prob | Impact | Owner | Mitigation | Status |
|---|------|------|--------|-------|-----------|--------|
| M2-R1 | Generator cannot guarantee the solvability invariant for all difficulty-knob combinations | Low* | High | gameplay-programmer | *Low only with the by-construction approach (build target queue → emit exactly 3× cards per result → deterministic shuffle), which makes the invariant structural rather than sampled. Property test over ≥100 seeds (S2-003a). | Open |
| M2-R2 | S2-002 ADR reveals the chosen algorithm needs backtracking / rejection sampling → S2-003 estimate (3d) overruns | Med | Med | technical-director | Day-2 ADR re-plan checkpoint: re-estimate S2-003 on ADR landing; if backtracking is required, drop the Nice-to-Have scoring stories that day rather than discovering the overrun on day 7. | Open |
| M2-R3 | Determinism and solvability interact badly (RNG state under rejection sampling breaks seed reproducibility) | Med | Med | gameplay-programmer | Construction-first avoids rejection sampling; seed-stability test (S2-003b) asserts same seed+knobs → identical level. | Open |
| M2-R4 | Difficulty curve feels wrong / untunable once generating | Med | Med | game-designer | Knobs are data-driven; defer curve calibration to a later sprint + playtest; not a Sprint 2 commitment. | Open |
| M2-R5 | M1 advisory QA sign-offs (juice/audio device feel, 60 FPS, tutorial visual ACs) never get scheduled and become "homeless" | Med | Low | qa-lead | Parked as S2-021 (Nice-to-Have). If it slips again, escalate to a dedicated polish slot before the Production→Polish gate. | Open |
| M2-R6 | Zero-slack sprint: committed scope (6.5d) leaves only ~1.5d before the 20% buffer | Med | Med | producer | Single keystone committed; scoring optional; buffer protected. Re-plan at the day-2 checkpoint. | Open |

\* Probability is conditional on the by-construction design being adopted in S2-002.

## Review cadence
Re-check at the **day-2 ADR checkpoint** (S2-002) and at sprint mid-point
(`/sprint-status`). Close risks as their mitigating stories land.
