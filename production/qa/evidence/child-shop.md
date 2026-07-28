# S6-004 — Child-Safe Mode (parental-gated shop) · QA Evidence

**Story:** S6-004 (Sprint 6 — Compliance UI) · **Type:** UI/Integration
**Spec:** `design/ux/compliance-ui.md` §3.4 · ADR-0005 · AC-3
**Status:** integration suite green + screenshot captured.

## What shipped

Child-safe treatment in the shop for an under-13 (restricted) player:

- `ShopScreen` now resolves `ComplianceService` (`configure(..., compliance)` / autoload
  default) and exposes `_is_child_restricted()` (`ComplianceService.is_restricted()`).
- When restricted, the shop shows a calm **"🔒 A grown-up can make purchases"** banner atop
  the offers, and a Buy tap surfaces **"Ask a grown-up to buy this"** — `IAPService` is
  **never driven** and the wallet is untouched (the compliance gate would fail-closed anyway;
  this replaces a generic failure with a child-appropriate cue — a **parental-gate stub**).
- Consent is never solicited from a child (S6-002 only presents the sheet for an ADULT), and
  ads are contextual-only by construction (`can_show_targeted_ads()` false for a child).

This complements the model-layer gating already shipped (`can_process_iap()` =
`is_adult() AND consent_iap`, false for a child) — S6-004 is the *view* that makes it calm.

## Automated evidence (BLOCKING — green)

`tests/integration/compliance/child_safe_test.gd`:

| Test | Asserts |
|---|---|
| `test_child_buy_is_parental_gated_and_never_purchases` | **AC-3** — restricted Buy → parental cue, `IAPService.purchase` not called |
| `test_restricted_player_is_flagged_child_safe` | `_is_child_restricted()` true for a restricted compliance |
| `test_real_child_shop_purchase_is_parental_gated_wallet_untouched` | real CHILD band → parental gate, wallet unchanged |

Full suite: **823 test cases, 0 failures** (820 baseline + 3 new). Fixed a latent
test-ordering dependency: `shop_screen_test._boot` now declares `ADULT` (its cases test an
adult, not a child).

## Screenshot evidence (ADVISORY)

Rendered at 390×844 via `tools/screenshot_child_shop.gd` (opengl3 harness).

| File | Shows |
|---|---|
| `child-shop.png` | The shop for a declared CHILD — the "🔒 A grown-up can make purchases" banner above the offer cards. |

## Notes / follow-ups

- **Real parental gate** (a genuine age-verification challenge) is a follow-up; this sprint
  ships the calm stub affordance.
- **Adult-who-declined-IAP-consent** still sees the generic "didn't go through" toast; pointing
  that case to Settings → Privacy (now that S6-003 exists) is a small follow-up.
