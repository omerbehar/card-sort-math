# S6-005 — Retire Mock-Consent Scaffolding · QA Evidence

**Story:** S6-005 (Sprint 6 — Compliance UI) · **Type:** Integration / test hygiene
**Spec:** `design/ux/compliance-ui.md` · ADR-0013
**Status:** integration suite green (no UI surface — no screenshot).

## What shipped

Now that the real capture flows exist (age gate S6-001, consent sheet S6-002), the
monetization suite establishes audience + consent through the **real `SaveService` setter
APIs** — the same ones the UI calls — instead of poking protected fields, and a new
end-to-end test proves the whole flow drives the compliance verdicts with **no** raw writes.

- `tests/integration/analytics/monetization_funnel_ui_test.gd`: swapped
  `save.data.age_band = …` / `save.data.consent_analytics = …` for
  `SaveService.set_age_band(…)` + `SaveService.capture_consent(…)`, and the mid-session
  revocation for `SaveService.withdraw_consent("analytics")`.
- New `tests/integration/compliance/consent_flow_e2e_test.gd`: boots a genuine first run
  (`UNKNOWN`, nothing captured), drives the **age gate → consent sheet → Save** entirely
  through the UI, and asserts `can_show_targeted_ads()` / `can_collect_personal_data()` /
  `can_process_iap()` all flip permissive — with zero direct consent-field assignments.

**Intentionally left as-is:** the compliance-model suites (`consent_gate_test`,
`ad_gate_matrix_test`, `funnel_consent_test`) still set raw fields directly — that is the
point of those tests (they exercise the gate matrix / conjunction across specific
grant/deny/withdraw combinations, which the all-or-nothing `capture_consent` can't express).

## Automated evidence (BLOCKING — green)

| Test | Asserts |
|---|---|
| `consent_flow_e2e_test::test_first_run_ui_grants_consent_and_flips_all_verdicts` | **AC-5** — UI-only consent capture flips all three verdicts permissive |
| `monetization_funnel_ui_test::*` (converted) | funnel emission gated on consent, now set via the real APIs |

Full suite: **824 test cases, 0 failures** (823 baseline + 1 new; funnel suite converted).

## Notes / follow-ups

- The compliance-gate/model suites keep granular raw-field control by design (documented
  above) — they are not "scaffolding to enable a flow."
