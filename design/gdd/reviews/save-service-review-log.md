# Review Log — Save & Settings (`save-service.md`)

## Review — 2026-06-09 — Verdict: NEEDS REVISION → Revised & Accepted (Approved)
Scope signal: L
Specialists: systems-designer, godot-specialist, security-engineer, qa-lead, creative-director (senior synthesis)
Blocking items: 6 | Recommended: ~12
Summary: First review of the reverse-documented Save & Settings GDD. Strong base
(8/8 sections, bidirectional deps, AC citations name real tests), but two
affirmative claims the shipped code does not honour: Edge Case 4 promised
data-safety the non-atomic write cannot deliver (mid-write kill → progress
reset), and the compliance section documented a convention where ADR-0005
mandates an enforced `ComplianceService` chokepoint (UNKNOWN=CHILD leak risk).
Three independent reviewer convergences (downgrade idempotency, write-failure,
compliance chokepoint) marked the genuine defects.

Blocking items resolved in-session:
1. Atomic write — EC4 corrected; temp+rename mandated as spec; current code flagged as scheduled follow-up.
2. ComplianceService chokepoint — sole `age_band` reader; AG-08 reframed to test the real verdict.
3. Migration idempotency — downgrade hazard + invariant documented; consent fields barred from missing-key-default.
4. load_failed signal — corrupt/unreadable save distinguished from first launch (EC14).
5. current_level upper bound — assigned to GameManager-on-use.
6. GDD accuracy — test count 22→29; tutorial_seen marked planned + SD-11 loosened; AG-03 mis-citation fixed + AG-03b; EC2/EC4 test strategy (FileAccess DI seam).

Decisions recorded (user adjudication of two ADR-0005 severity disagreements):
- age_band tamper-resistance: accept plain-JSON at M1; HMAC/signature REQUIRED pre-AdService.
- Retention/erasure: save-file deletion = full erasure at M1; full design scheduled pre-AdService.

Outcome: User accepted revisions and marked the GDD Approved without a separate
re-review. Three P0 code follow-ups remain tracked (not blocking the GDD):
atomic write, ComplianceService chokepoint, load_failed signal — plus the new
BLOCKING tests (SD-10/11/12, SV-06..14, SS-06..09, AG-02/03/03b/05/06/07/08).

Prior verdict resolved: First review.
