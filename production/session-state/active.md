# Active Design Session

Task: deck-economy GDD — COMPLETE
Status: Designed (2026-06-12); all 8 required sections + Visual/Audio, UI Requirements, Open Questions written; CD-GDD-ALIGN CONCERNS (accepted); pending independent /design-review (fresh session)
File: design/gdd/deck-economy.md
Registry: design/registry/entities.yaml created (18 constants, 3 formulas, 3 data types)
Systems index: updated with Deck Economy row + dependency graph
Next: /design-review design/gdd/deck-economy.md (fresh session) → then scoring/stars GDD (S2-011)

<!-- QA-PLAN: 2026-06-12 | System: sprint-3 (Deck Economy core) | Plan written: production/qa/qa-plan-sprint-3-2026-06-12.md -->

## Session Extract — /dev-story 2026-06-12
- Story: S3-001 — EconomyEvent + economy enums (ADR-0008)
- Files changed: core/economy_enums.gd, core/economy_event.gd, tests/test_economy_event.gd
- Test written: tests/test_economy_event.gd (47 functions; full suite 259/259 green, exit 0)
- Blockers: None
- Next: /code-review then /story-done S3-001 → then S3-003 (TimeProvider)

## Session Extract — /dev-story 2026-06-12 (S3-003)
- Story: S3-003 — TimeProvider seam + explicit-int reshuffle mix() (ADR-0009)
- Files changed: core/time_provider.gd, core/reshuffle_seed.gd, tests/fixed_time_provider.gd, tests/test_time_provider.gd
- Test written: tests/test_time_provider.gd (11 functions); full suite 270/270 green, exit 0
- Verified: no hash() / no stray Time.* calls (sole clock call site = time_provider.gd:33)
- Blockers: None
- Next: S3-002 (WalletData + SaveData v1→v2 migration + EconomyConfig)

## Session Extract — /dev-story 2026-06-12 (S3-002)
- Story: S3-002 — WalletData + SaveData v1→v2 migration + EconomyConfig
- Files: core/wallet_data.gd (new), core/save_data.gd (v2 bump + migration), data/economy_config.gd (new), assets/data/economy_config.tres (new), tests/test_wallet_data.gd + test_economy_config.gd (new), tests/test_save_data.gd (extended)
- Test: full suite 348/348 green, exit 0 (was 270; +78)
- Notes: stale class-cache caused a transient "WalletData not declared" parse error — fixed by `godot --import` (CI's gdUnit4-action imports automatically). Hardened WalletData.from_dict null-safety to match its "never crashes" contract.
- Next: S3-004 (WalletService transaction core)

## Session Extract — /dev-story 2026-06-12 (S3-004)
- Story: S3-004 — WalletService transaction core (autoload)
- Files: autoloads/wallet_service.gd (new), tests/test_wallet_service.gd (new, 19 tests), project.godot (autoload registered)
- Test: full suite 367/367 green, exit 0 (was 348; +19). AC-W05b near-cap snapshot rollback verified.
- Notes: implemented directly by orchestrator — the gameplay-programmer agent stalled on a write-permission prompt without producing files and its context couldn't be resumed (SendMessage unavailable). EC-09 "board mutation raises" modeled as on_committed Callable returning false (GDScript has no exceptions). Fixed the agent's planned bug: GameManager autoload guard uses get_node_or_null("/root/GameManager"), NOT Engine.has_singleton.
- Next: S3-007 (Hint booster) — first booster on the use_booster/spend seam

## Session Extract — /dev-story 2026-06-12 (S3-007)
- Story: S3-007 — Hint booster (hint_score Formula 5 + WalletService.use_hint)
- Files: core/hint_score.gd (new), core/board_model.gd (+newly_exposed_count query), autoloads/wallet_service.gd (+use_hint/_hint_in_progress/notify_hint_consumed), tests/test_hint_score.gd (new, 14), tests/test_wallet_service.gd + test_board_model.gd (extended)
- Test: full suite 388/388 green, exit 0 (was 367; +21)
- Notes: gdscript-specialist agent left ONE failing test (test fixture bug — gave card 1 result 9 which DOES route since the queue seeds stack target 9; impl was correct). Fixed fixture (result 9→5). AC-M01a verified: HINT_RESULT carries card_id only.
- Next: S3-005 (compliance gating + daily caps + gem→coin) — LAST Must-Have

## Session Extract — /dev-story 2026-06-12 (S3-005)
- Story: S3-005 — compliance gating + daily caps + gem→coin conversion
- Files: core/save_data.gd (v2→v3: daily_key/ad_coins_today/ads_watched_today/gems_converted_today + migration), autoloads/wallet_service.gd (earn() source-router + _earn_raw/_earn_rewarded_ad/convert_gems_to_coins/initiate_iap/is_ad_earn_available/_roll_day_if_needed), tests/test_save_data.gd (+v3 migration tests), tests/test_wallet_service.gd (+14 S3-005 AC tests)
- Test: full suite 410/410 green, exit 0 (was 388; +22)
- Notes: gameplay-programmer agent was truncated mid-test-writing — it finished the SaveData v3 + migration tests + ALL WalletService impl, but did NOT add the WalletService S3-005 behavior tests. I added the 14 missing AC tests (C01/C02/C03, CH01/CH02, CL01, GC01/GC02/GC03, EC-13/14, rollover, count cap, is_ad_earn_available). Impl verified correct. AC-CL03/M02 advisory gate passes (no direct age_band/CardData.result reads).
- ALL 6 MUST-HAVES DONE. Should-Have: S3-006 (Extra Discard), S3-008 (earn triggers). Nice: S3-009/010/011.

<!-- QA-PLAN: 2026-06-15 | System: sprint-4 (M4 Monetize service core) | Plan written: production/qa/qa-plan-sprint-4-2026-06-15.md -->

## Session Extract — /dev-story 2026-06-15 (S4-000)
- Story: S4-000 (Sprint 4 kickoff docs) — Config/Data (Docs), DONE
- Files created: docs/architecture/ADR-0012-hint-to-picker-booster.md, ADR-0013-consent-cmp-model.md, ADR-0014-monetization-service-seam.md, production/milestones/m4-definition.md, production/risk-register/m4-risks.md; updated docs/architecture/README.md (ADR index 0011-0014), sprint-status.yaml (S4-000 done)
- Test written: None — Config/Data (Docs) story
- Blockers: None. ADR-0013/0014 now unblock the code stories.
- Next: S4-001 (consent/CMP model + SaveData v5->v6 migration) — /dev-story; governing ADR-0013 now exists

## Session Extract — /dev-story 2026-06-15 (S4-001)
- Story: S4-001 consent/CMP model + SaveData v5->v6 migration — Integration(+Logic), implemented (status in-progress pending /code-review + /story-done)
- Files changed: core/save_data.gd (v6 + 5 consent fields), autoloads/compliance_service.gd (consent x age_band verdicts + can_process_iap, sole reader), autoloads/save_service.gd (capture/withdrawal setters), tests/test_compliance_service.gd + tests/test_save_data.gd (updated for stricter verdicts)
- Tests written: tests/unit/save/consent_migration_test.gd (34), tests/integration/compliance/consent_gate_test.gd (26). Suite 596 -> 657 green.
- Single-reader grep gate: PASS (consent fields read only by ComplianceService/SaveService).
- Blockers: None.
- Next: /code-review then /story-done for S4-001; then S4-003 (extends the SAME v6 migration with the entitlement field — M4-R4 collision rule).

## Session Extract — story-done 2026-06-15 (S4-001)
- S4-001 CLOSED (status: done, 2026-06-15). All 4 sprint-04 acceptance criteria + 6 ADR-0013 validation criteria covered by tests; 7 code-review findings fixed. Suite 663 green.
- Note: no /story-done skill in this project — closed out manually (criteria check + status update).
- Next ready: S4-003 (Remove-Ads EntitlementService) per the sequence S4-000→S4-001→S4-003→S4-002→S4-004a. S4-003 extends the SAME v6 migration with the entitlement field (now a one-line unconditional add after review fix #1).

## Session Extract — /dev-story 2026-06-15 (S4-003)
- Story: S4-003 Remove-Ads EntitlementService — Integration(+Logic), implemented (status in-progress pending /code-review)
- Files: autoloads/entitlement_service.gd (new), autoloads/entitlement_backend.gd (new, mock receipt seam), core/save_data.gd (remove_ads_owned on shared v6 step), project.godot (autoload registered)
- Tests: tests/unit/entitlement/entitlement_service_test.gd, tests/integration/entitlement/remove_ads_gate_test.gd. Suite 663 -> 690 green.
- Note: implementing agent got cut off twice mid-fix; orchestrator finished the test fixes (local _MockBackend extends-by-path test double + `=` instead of `:=` to dodge Variant-inference-as-error) and verified the suite directly.
- Single v6 migration block confirmed (1 actual `if version == 5:`). M4-R4 respected.
- Next: /code-review then story-done for S4-003. Then S4-002 (IAPService → calls EntitlementService.grant_remove_ads() on Remove-Ads SKU).

## Session Extract — code-review + close 2026-06-15 (S4-003)
- S4-003 code-review: 7 findings, ALL fixed by orchestrator directly (agents kept getting cut off). #1 restore() return semantics (real bug), #2 real scene_runner integration test (CLAUDE.md mandate), #3 use production MockEntitlementBackend, #4 chokepoint grep test, #5+#7 typed _backend/configure, #6 assert write actually failed.
- Suite 690 -> 692 green. S4-003 CLOSED (status: done, 2026-06-15).
- Next ready: S4-002 (IAPService → calls EntitlementService.grant_remove_ads() on Remove-Ads SKU). Sequence: S4-002 → S4-004a → S4-004b → S4-007 (+ S4-005, S4-006).

## Session Extract — /dev-story 2026-06-15 (S4-002)
- Story: S4-002 IAPService — Integration(+Logic), implemented (status in-progress pending /code-review)
- Decision: IAPService owns flow; credits via WalletService.earn(EarnSource.IAP), Remove-Ads via EntitlementService.grant_remove_ads(); gates on can_process_iap(); initiate_iap() got the consent backstop (defense-in-depth).
- Files: autoloads/iap_service.gd (new), autoloads/iap_backend.gd (new), autoloads/wallet_service.gd (initiate_iap consent gate), project.godot (autoload). Tests: tests/unit/iap/iap_service_test.gd (12), tests/integration/iap/iap_grant_test.gd (3), + StubCompliance.can_process_iap() in both wallet tests + a consent-backstop regression test.
- Agent cut off before writing ANY tests (empty dirs) AND before verifying; orchestrator wrote all IAP tests, fixed the StubCompliance regression, and verified. Suite 692 -> 708 green.
- Catalog is a placeholder in iap_service.gd pending S4-006 (the real .tres). Note for code-review: header docstring line ~6 still says currency routes 'through initiate_iap' but code uses earn() — stale comment.
- Next: /code-review then close S4-002. Remaining: S4-004a/b, S4-005, S4-006, S4-007.

## S4-002 /code-review — applied 2026-06-15 (713 green)
- #1 cap: IAP currency now credits via WalletService.grant_iap_currency() (uncapped) per boss decision — real money bypasses earn() clamp.
- #2 null-wallet / #4 null-compliance: purchase() now fails CLOSED (no false SUCCESS, no fail-open gate).
- #3 restore over-count: grant_remove_ads() returns bool (newly-granted); restore() counts via return → preserves remove_ads_owned single-reader chokepoint (the is_remove_ads_owned() approach tripped entitlement_service_test.gd:347 guard, reverted).
- #5 docstrings fixed; #6 dead State.SUCCESS/FAILED writes removed.
- DEFERRED (intentional, not bugs): #7 WalletService.initiate_iap() retains the consent backstop though IAPService bypasses it (defense-in-depth for the deferred monetization UI / future direct callers; docstrings no longer overclaim it as the grant path). #8 State enum omits RESTORED — restore() is a separate non-blocking flow with its own restore_completed signal; revisit if restore must participate in PENDING mutual-exclusion. Both worth an ADR-0014 amendment note when S4-006 lands.
- Next: S4-004a (AdService) — rewarded earn-in + interstitial freq cap (TimeProvider) + triple gate (can_show_ads + entitlement suppression).

## S4-004a AdService — done 2026-06-15 (731 green)
- AdService autoload + AdBackend seam (mock). Rewarded → WalletService._earn_rewarded_ad (config amount, chokepoint owns caps/compliance). Interstitial freq cap: every_n_levels AND min_seconds via injected TimeProvider; suppressed by Remove-Ads entitlement; no mid-puzzle. Added EconomyConfig.interstitial_every_n_levels(3)+interstitial_min_seconds(90).
- 14 unit (tests/unit/ads) + 4 integration (tests/integration/ads). Implemented directly by orchestrator (agent-cutoff pattern) + full-suite verified.
- S4-004b (NEXT, should-have): audience x consent personalized-vs-contextual cross-gating matrix. configure() will ADD compliance param; AdService currently injects wallet/entitlement/time/config/backend (no compliance yet — kept DI surface honest).
- FOLLOW-UP (test hygiene, pre-existing S4-003, not blocking): tests/unit/entitlement/entitlement_service_test.gd and tests/integration/entitlement/remove_ads_gate_test.gd construct SaveService.new() WITHOUT configure(path) and call grant_remove_ads()/restore(), persisting remove_ads_owned:true to the REAL user://save.json. Harmless to current suite (no test reads real boot entitlement state) but a landmine for future boot-reading integration tests — my AdService boot test avoids it by asserting only the in-memory no-mid-puzzle gate. Recommend configuring temp paths in those tests.

## S4-004b AdService triple gate — done 2026-06-15 (740 green)
- configure() adds ComplianceService; resolve_ad_type() → PERSONALIZED only for ADULT+personalized consent (can_show_targeted_ads), else CONTEXTUAL (incl UNKNOWN/CHILD/denied). AdBackend.show_interstitial(ad_type); interstitial_shown(ad_type). Rewarded gate unchanged.
- +3 unit (ad-type) + 6 matrix integration (tests/integration/ads/ad_gate_matrix_test.gd).
- FOLLOW-UP RESOLVED: the S4-003 save-hygiene bug (entitlement tests persisting remove_ads_owned to real user://save.json) is fixed — both entitlement test files now use temp paths + after_test cleanup. Verified save.json stays clean.
- M4 service core now complete: S4-001..S4-004b done. Remaining: S4-005 (real RemoteConfigSource subclass), S4-006 (IAP catalog .tres + replace placeholder), S4-007 (Analytics seam).
