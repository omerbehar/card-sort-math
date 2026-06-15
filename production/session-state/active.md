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
