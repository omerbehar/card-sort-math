# S6-006 (M4-R2) — Compliance Save Tamper-Signing · QA Evidence

**Story:** S6-006 / risk **M4-R2** (Sprint 6 — Compliance UI) · **Type:** Logic + Integration (security)
**Spec:** ADR-0013 §4 · ADR-0005 · `docs/architecture/real-ads-integration-plan.md` decision #5
**Status:** unit + integration suites green (no UI surface — no screenshot).

## What shipped

Closes the OPEN-DEFERRED **M4-R2** risk: the plain-JSON save let anyone edit `age_band` or the
consent / Remove-Ads flags to unlock targeted ads, IAP, or bypass child-safe mode. That's the
tamper bar ADR-0013 §4 requires closed before a real Ad/Analytics SDK trusts these fields.

- `core/save_integrity.gd` (`SaveIntegrity`) — pure, deterministic HMAC-SHA256 over a canonical
  string of the **protected fields** (`age_band`, the four consent flags, `consent_version`,
  `remove_ads_owned`), keyed by a compiled-in app secret. Type-normalized canonicalization so a
  JSON round-trip (ints→floats) signs identically at save- and verify-time.
- `SaveService.save_game()` signs the payload; `load_game()` **verifies** and, on a bad or
  missing signature, **fails closed** — drops the protected keys so `SaveData.from_dict()`
  applies conservative defaults (UNKNOWN age, all consent denied, Remove-Ads not owned) and
  fires `integrity_failed`. Non-protected progress (level, wallet, boosters) is preserved.
- `ComplianceService`'s M4-R2 note updated: RESOLVED.

**Documented limitation:** a client-side secret is extractable from the binary — this raises
save-editing well above plain-text tampering but is not server-grade anti-cheat. A legacy
unsigned save is treated as untrusted (re-gates), which is safe since no real entitlements have
shipped (mock-first).

## Automated evidence (BLOCKING — green)

**Unit** (`tests/unit/save/save_integrity_test.gd`): sign/verify roundtrip; deterministic;
tampering `age_band` / a consent flag / `remove_ads_owned` fails verify; a missing signature
fails; changing a non-protected field keeps the signature valid.

**Integration** (`tests/integration/save/save_integrity_load_test.gd`): a signed save
round-trips the protected fields; an unsigned "hacked" save (adult + Remove-Ads owned) resets
those fields on load while keeping level/wallet and firing `integrity_failed`; a forged
signature is rejected.

Full suite: **834 test cases, 0 failures** (824 baseline + 10 new). Fixed two implementation
bugs found by the suite: a `sign()` name-collision with GDScript's built-in, and int/float
canonicalization across the JSON round-trip. Added `save_integrity.gd` to the two "sole-reader"
architecture-test allowlists (it references the protected field names to sign them).

## Notes / follow-ups

- **Real parental gate** (replace the S6-004 stub) and **server-authoritative** validation of
  purchases/consent remain follow-ups beyond this client-side tamper bar.
