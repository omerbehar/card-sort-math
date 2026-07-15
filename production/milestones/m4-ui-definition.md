# Sprint 5 — Monetization UI (M4 Monetize, view half)

> **Status:** Draft plan (awaiting approval) · **Milestone:** M4 Monetize (this is the
> UI half; the service core shipped in Sprint 4 / PR #39) · **Design:**
> `design/ux/monetization-ui.md`.

## Goal

Ship the player-facing **commerce + ad presentation** surfaces that consume the M4
service seams — wallet display, shop, rewarded-ad prompt, interstitial + Remove-Ads
offer — as thin, tested views (ADR-0001 model/view). Calm, non-nagging tone; one offer
per session; no ads mid-puzzle. **Mock-first**: no native SDK; the existing mock backends
back every surface.

## In scope

The four MVP surfaces from the UX spec, plus the data + wiring they require:

1. **Catalog display metadata** — the offer cards need names/prices the resource lacks.
2. **Wallet display** — gems in the HUD alongside coins.
3. **Shop screen** — catalog → purchase / restore, with pending/success/fail states.
4. **Rewarded-ad prompt** — availability-gated opt-in attach points.
5. **Interstitial + Remove-Ads offer** — boundary presentation (mock) + one/session anchor.
6. **Analytics funnel wiring** — emit the funnel events the seam already exposes.

## Explicitly deferred (not this sprint)

| Deferred | To |
|---|---|
| **Age-gate / CMP consent UI** | Own dedicated **compliance-UI sprint** (blocks live IAP/personalized ads) |
| Native Ad/IAP SDK plugins | Device-tested sprint |
| Real localized pricing (store SDK) | With the native sprint (mock `$X.XX` until then) |
| Cosmetic / season-pass store, banner ads | Live-ops / later monetization sprint |

## Proposed stories

| ID | Story | Type | Prio | Est (d) |
|----|-------|------|------|---------|
| **S5-000** | Kickoff: this UX spec + `/ux-review` sign-off + catalog display-metadata quick-design | Docs | must | 0.5 |
| **S5-001** | Extend `IAPCatalogEntryResource` with display metadata (`display_name`, `grant_summary`/`icon`, loc key) + update `iap_catalog.tres` + validation | Logic/Data | must | 1.0 |
| **S5-002** | Wallet display: gems pill in `hud.gd`, live `economy_event` binding, reduced-motion-aware count-up | UI/Integration | must | 1.0 |
| **S5-003** | Shop screen: render catalog, purchase flow (pending/success/fail), restore-purchases, Remove-Ads "Owned" state | UI/Integration | must | 2.5 |
| **S5-004** | Rewarded-ad prompt component: availability-gated, wired at result screen + booster/near-loss attach points | UI/Integration | must | 1.5 |
| **S5-005** | Interstitial mock presentation: `Main` boundary wiring (`notify_level_completed` + `maybe_show_interstitial`) + mock full-screen | Integration | must | 1.0 |
| **S5-006** | Remove-Ads offer surface: one-per-session dismissible anchor → deep-links Shop | UI | should | 1.0 |
| **S5-007** | Analytics funnel wiring: emit `track_iap_purchase` / `track_ad_impression` / `track_ad_reward` from the flows | Integration | should | 0.5 |
| **S5-008** | Accessibility + reduced-motion pass; screenshot evidence for all surfaces | Visual/UI | should | 1.0 |

**Must-have ≈ 7.5d · Should-have ≈ 2.5d.** Sequence: S5-001 → S5-002 → (S5-003 / S5-004 /
S5-005 parallelizable) → S5-006 / S5-007 → S5-008. S5-006/007/008 are the cut-first queue.

## Validation requirements (per CLAUDE.md — both mandatory for UI work)

- **Integration tests** driving `scenes/main/main.tscn` + autoloads (gdUnit4 `scene_runner`):
  each surface's model↔view↔service wiring proven end-to-end (purchase grants, rewarded
  credits, interstitial gating, wallet binding). Consent mocked **granted** in tests.
- **Screenshots** via an `xvfb-run` dev harness under `tools/`, saved with an evidence doc
  to `production/qa/evidence/` — proving each surface renders at 390×844 portrait.
- Unit tests for any `core/`/`data/` logic (S5-001 catalog metadata + price formatting).
- A `/qa-plan` pass generates the per-story test matrix before dev.

## Key dependencies & risks

| Item | Note |
|---|---|
| **Consent-UI prerequisite (soft block)** | Shop "purchases available" + personalized-ad type are consent-gated. Built + tested against **mock consent granted**; live gating already enforced by `ComplianceService`. The consent-UI sprint must precede store launch. |
| **Catalog display-metadata coupling** | S5-003 depends on S5-001; sequence first. |
| **Art fidelity** | Reuse Kenney skin + existing popup patterns for MVP (fast); net-new art → `art-director` follow-up. Decide at S5-000. |
| **Localization** | Copy + price strings should route a string table; flagged, non-blocking for the mock sprint. |
| **Entitlement chokepoint** | Shop/offers read `should_suppress_interstitials()`, never `remove_ads_owned` (ADR-0014 §3). |

## Definition of Done (sprint)

- All must-have stories' acceptance criteria (UX spec §8) verified via integration test +
  screenshot evidence.
- Full gdUnit4 suite green (baseline 773 → no regressions).
- No new `_process` hot-path allocations; all service reads are signal-driven.
- Calm-tone guardrails held: ≤1 offer/session, no mid-puzzle ads, opt-in rewarded only.

## On approval, I will

1. Run `/ux-review` on `design/ux/monetization-ui.md` (APPROVED gate).
2. Generate `production/sprint-status.yaml` (sprint 5) + a `/qa-plan` test matrix.
3. Begin S5-001 (catalog metadata) → S5-002 (wallet) as the foundation.
