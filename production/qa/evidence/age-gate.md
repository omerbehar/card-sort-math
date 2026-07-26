# S6-001 — First-Run Neutral Age Gate · QA Evidence

**Story:** S6-001 (Sprint 6 — Compliance UI) · **Type:** Logic + UI/Integration
**Spec:** ADR-0005 (audience positioning, 13+ neutral gate) · ADR-0013 (consent model)
**Status:** unit + integration suites green + screenshot captured.

## What shipped

The first-run **neutral age gate** — the piece Sprint 5 deferred and the real-ads plan
gates on. It wires the already-shipped `ComplianceService` / `SaveData` v6 model to real UI:

- `scenes/ui/age_gate.gd` (`AgeGate extends PopupBase`) — a **non-leading** birth-year entry
  ("When were you born?", a `−/+` year stepper), **not** a leading "are you 13+?" prompt
  (ADR-0005 §Decision.1). Undismissable (no backdrop dismiss / close-X) — the player must
  answer before playing. A thin view (ADR-0001): it emits `age_submitted(birth_year)`; the
  controller owns the policy mapping + persistence.
- `ComplianceService.age_band_for_birth_year(birth_year, current_year)` — a **pure, static,
  unit-tested** policy: `ADULT` when age ≥ `ADULT_MIN_AGE` (13), else `CHILD`; never
  `UNKNOWN`. The legal threshold is a named constant (ADR-0005/COPPA), not a tuning knob.
- `main.gd` presents the gate on first launch (`age_band == UNKNOWN`) over the board, its
  opaque backdrop blocking play until answered (gate before personal-data collection). On
  submit → `ComplianceService.age_band_for_birth_year(...)` → `SaveService.set_age_band(band)`
  (persists + flips every compliance verdict live) → the gate dismisses.

13+ → `ADULT` (full experience path); under-13 → `CHILD` (child-safe restrictions already
enforced by `ComplianceService`). A returning player (band already declared) sees no gate.

## Automated evidence (BLOCKING — green)

**Unit** (`tests/unit/compliance/age_band_policy_test.gd`) — the pure threshold policy:
- exactly 13 → ADULT; 12 → CHILD (boundary); clear adult/child cases; born-this-year → CHILD;
  never returns UNKNOWN.

**Integration** (`tests/integration/compliance/age_gate_test.gd`, real `main.tscn` + autoloads):

| Test | Asserts |
|---|---|
| `test_first_run_presents_the_age_gate` | first run (UNKNOWN) → gate is up |
| `test_returning_player_sees_no_gate` | band already set → no gate |
| `test_submitting_adult_year_sets_adult_and_dismisses` | adult year → `age_band = ADULT`, `is_adult()` true, gate dismissed |
| `test_submitting_child_year_sets_child_band` | under-13 year → `age_band = CHILD`, `is_restricted()` true |

Full suite: **812 test cases, 0 failures** (802 baseline + 10 new). The existing main-scene
suites were unaffected (they drive the board via direct calls, which the gate's backdrop
doesn't intercept); the age-gate suite forces `UNKNOWN` and restores a known band after each
test so nothing leaks.

## Screenshot evidence (ADVISORY)

Rendered at 390×844 portrait via
`xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tools/screenshot_age_gate.gd`.

| File | Shows |
|---|---|
| `age-gate.png` | The neutral gate over the dimmed board — "Before you play / When were you born?", the `−/+` year stepper, the "asked once" note, and Continue. |

## Notes / follow-ups

- **Birth-year granularity**: a year-difference gate (not full date of birth) — a reasonable
  neutral first cut; DOB-precision is a follow-up if legal wants exact-day accuracy.
- **Consent capture (S6-002)** is the next story — after the age gate, a 13+ player should be
  offered the personalized-ads/analytics/IAP consent sheet (`SaveService.capture_consent`),
  which is what actually flips `can_show_targeted_ads()` etc. true.
- **`age_band` tamper-signing (M4-R2, ADR-0013 §4)** remains OPEN-DEFERRED — a prerequisite
  before a real ad/analytics SDK ships (see the real-ads plan, decision #5).
