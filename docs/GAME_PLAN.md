# CardSortMath — Game Development Plan

> Living document. Status reflects the repository as of the current MVP
> (game core + gdUnit4 CI). Anything marked **[Built]** exists today;
> everything else is planned.

---

## 1. Vision & Positioning

**CardSortMath** is a mobile **sort-and-stack puzzle** with an educational
**mental-math** core. Each card on the floor shows an arithmetic exercise
(today: addition, e.g. `3 + 4`); the player must compute the result and tap the
card to route it onto a stack that collects that value. Fill a stack of three
matching results and it clears, cascading into discard pull-backs.

It sits at the intersection of two proven mobile genres:

- **Sort/tile-stack puzzlers** (Triple Tile, Tile Busters, Sort It / Goods Sort)
  — short sessions, satisfying clears, "one more level" pull.
- **Edu-math casual** (Math games, Brain-training) — repeat engagement framed
  as self-improvement; broad demographic, parent-friendly.

**Positioning statement:** *"A relaxing tile-sorting puzzle that quietly sharpens
your mental arithmetic — calm enough for a coffee break, smart enough to feel
good about."*

**Target audiences (primary → secondary):**
1. Adult casual puzzle players (25–55) who like "productive" relaxation.
2. Students / parents seeking light, non-patronizing math practice.
3. Brain-training / streak-keeper retention seekers.

**Design pillars:**
- **Calm, not frantic** — no hard timers in core mode; difficulty comes from
  planning and arithmetic, not reflex.
- **Always solvable, never unfair** — levels are solvable by construction
  (already enforced; see §3).
- **Math is the mechanic, not a quiz** — the arithmetic is load-bearing for the
  puzzle, so practice happens implicitly.

---

## 2. Current State **[Built]**

| Area | Status |
|------|--------|
| Core rules engine (`core/board_model.gd`) | Deterministic, node-free, event-driven |
| Exposure/coverage DAG (`core/exposure.gd`) | Cards become tappable as coverers are removed |
| Layouts (`core/layouts.gd`) | 3 hand-authored layout presets |
| Card model (`data/card_data.gd`) | Addition exercise → result |
| Level data + solvability invariant (`autoloads/level_data.gd`) | 3 authored levels, `is_solvable()` |
| Save/persistence (`autoloads/save_service.gd`, `core/save_data.gd`) | Versioned `user://` JSON, schema migration, `age_band` (ADR-0005) |
| Settings (`autoloads/settings_service.gd`, `data/settings.gd`) | Sound/music/haptics/reduced-motion model, persisted (UI = S1-011, pending) |
| Audio (`autoloads/audio_service.gd`) | Event SFX + calm music bed (Kenney CC0); honors mute |
| Juice (`autoloads/juice_service.gd`) | Haptics + particle burst + scale punch; gated by reduced-motion |
| Autoloads | `SaveService`, `SettingsService`, `AudioService`, `JuiceService`, `GameManager`, `LevelData` |
| View layer (`scenes/`) | main, card, stack, discard_row, floor_area, hud, ui_factory |
| Skin | Kenney UI assets (licensed); Kenney CC0 audio (`assets/audio/`) |
| Tests | 13 gdUnit4 suites, 74 cases |
| CI | GitHub Actions runs gdUnit4 headless on push/PR |
| Tooling | `tools/playthrough.gd` automated playthrough |

**Engine/target:** Godot 4.6, Mobile renderer, portrait (390×844), touch input.

**Built since MVP (Milestone M1, Sprint 1 Must-Haves):** persistence, settings
model, audio, and juice all landed behind the model/view seam. See
`production/milestones/m1-review.md`.

**Gaps before "shippable v1":** no meta/progression, no economy, no monetization,
no settings UI or onboarding/tutorial yet (S1-010/S1-011, in progress), no
analytics, no store presence.

---

## 3. Core Gameplay Loop **[Built — rules]**

1. Cards are dealt onto a layered floor. A card is **exposed** (tappable) only
   once every card covering it is removed.
2. Four **stacks** each show a **target result**; capacity 3.
3. Tapping an exposed card computes its result and routes it to a matching open
   stack. No match → it goes to one of **5 discard slots**.
4. A full stack **clears**, draws the **next target** from the level's queue, and
   **pulls back** matching cards from discard — which can chain (cascade).
5. **Win:** floor emptied. **Lose:** discard fills with no legal move.

**Solvability invariant (already enforced & unit-tested):** for every result,
`card_count == 3 × (occurrences of that result in the target queue)`. This
guarantees every authored level is winnable and is the backbone for all future
procedural/generated content.

**Math progression hooks (planned):** the operation is currently fixed to
addition in `CardData`. Generalize to an operation type so later "worlds" can
introduce subtraction, multiplication, division, mixed, and negatives — without
touching the sort engine (the engine only cares about `result`).

---

## 4. Feature Roadmap (Phased)

### Phase 0 — Foundation (current → v0.1) **[partially built]**
- [x] Core rules + tests + CI
- [ ] **Save/load** (player profile, progress, settings) — Godot `user://` JSON or
      `ConfigFile`, with schema versioning.
- [ ] **Tutorial / first-time UX** — guided first level, gesture coaching.
- [ ] **Audio** — SFX (tap, route, clear, win/lose) + calm music bed; mute toggle.
- [ ] **Juice** — tween polish, particles on clear, haptics, screen-shake-lite.
- [ ] **Settings** — sound, haptics, language, accessibility, reset progress.

### Phase 1 — Game Feel & Content (v0.2–v0.5)
- [ ] **Procedural level generator** built on the solvability invariant, with
      difficulty knobs: layout depth, # of distinct results, queue rotations,
      operand magnitude, operation type.
- [ ] **Operation worlds**: Addition → Subtraction → Multiplication → Division →
      Mixed. Each world = themed skin + new number ranges.
- [ ] **Difficulty curve & pacing** model (target win-rate per cohort).
- [ ] **Star/score rating** per level (efficiency: fewer discards = more stars).
- [ ] **Undo** (single step) and **board reshuffle/hint** as economy sinks (§7).

### Phase 2 — Meta & Retention (v0.6–v0.9)
- [ ] **Map / world progression** screen.
- [ ] **Daily challenge** (seeded deterministic level → leaderboard-friendly).
- [ ] **Streaks & daily rewards**.
- [ ] **Player level / XP**, cosmetic unlocks (card backs, themes, table felt).
- [ ] **Achievements** (math milestones: "100 multiplications cleared").
- [ ] **Stats dashboard** ("you solved 1,240 sums — accuracy 96%") — leans into
      the edu value prop and is great UA creative.

### Phase 3 — Monetization & Live Ops (v1.0)
- [ ] IAP, ads, remove-ads, currency, offers (§§7–9).
- [ ] Remote config + A/B testing.
- [ ] Analytics + crash reporting.
- [ ] LiveOps calendar: events, limited-time worlds, sales.

### Phase 4 — Growth (post-launch)
- [ ] Leaderboards / async social (daily challenge ranks, friends).
- [ ] Cloud save (platform Game Services).
- [ ] Localization expansion.
- [ ] Seasonal/event content cadence.

---

## 5. Content & Level Design

- **Authoring → generation:** keep hand-authored layouts as the art-directed
  "set pieces"; use the generator for volume and daily challenges. All generated
  levels must pass `is_solvable()` before shipping/serving.
- **Difficulty dimensions:** floor depth (coverage layers), distinct results,
  queue length & rotation reuse, discard pressure (how often no-match forces
  discard), operand size, operation complexity.
- **Target launch content:** ~120–200 levels across 4–5 worlds, plus an infinite
  daily-challenge generator. (Sort-genre players consume levels fast — generation
  is what makes the catalog sustainable.)
- **Pacing:** front-load easy wins (first 10 levels ~90%+ win rate), introduce
  discard pressure ~level 8, first operation switch ~world 2.

---

## 6. Progression & Meta Systems

- **World map** with gated worlds (unlock by stars or level completion).
- **Star economy:** 1–3 stars/level on efficiency; stars unlock worlds & cosmetics.
- **XP & player level:** steady dopamine independent of star skill ceiling.
- **Daily challenge:** one seeded level/day, shareable result card (UA loop).
- **Collections/cosmetics:** card skins, table themes, clear-effect VFX — the
  primary *non-pay-to-win* spend sink.

---

## 7. Economy & Currencies

Two-currency model (industry standard, keeps soft/hard sinks separate):

| Currency | Earned via | Spent on |
|----------|-----------|----------|
| **Coins** (soft) | Level wins, dailies, rewarded ads | Hints, undo, reshuffle, extra discard slot, cosmetics |
| **Gems** (hard) | IAP, sparse rewards, milestone gifts | Premium cosmetics, currency conversion, skip-wait, bundles |

**Power-ups / boosters (consumable sinks — also rescue moments where ads attach):**
- **Hint** — highlights a productive next tap.
- **Undo** — revert last tap (great rewarded-ad attach point).
- **Reshuffle / extra discard slot** — soft-fail rescue when discard is full.

**Design rule:** boosters must **never** trivialize the math (no "auto-solve"
that removes the arithmetic) — that would gut the core value prop and edu framing.

---

## 8. Monetization — In-App Purchases

**Model:** free-to-play, hybrid (IAP + ads), with a strong **Remove Ads** anchor
because the calm/edu audience converts well on a one-time ad-removal.

**IAP catalog:**
1. **Remove Ads** ($2.99–$4.99 one-time) — removes interstitials/banners; keeps
   *optional* rewarded ads available. Highest-converting SKU for this genre/tone.
2. **Currency packs** — tiered gem/coin bundles ($0.99 → $49.99) with
   increasing value-per-dollar.
3. **Starter / value bundles** — first-time discounted pack (remove-ads + gems +
   cosmetic) shown after ~session 2–3.
4. **Cosmetic packs / season pass** — themes, card skins; optional paid track on
   seasonal events.
5. **Booster bundles** — consumable packs for players who'd rather buy than grind.

**Pricing & merchandising:** localized price points, anchored bundles, time-boxed
offers via remote config; one tasteful, non-nagging offer surface per session.

---

## 9. Advertising

> ⚠️ **Audience caveat drives everything here — see §10.** If we market to or
> knowingly attract **children**, ad networks and targeting are heavily
> restricted (COPPA/GDPR-K). The plan below assumes a **general-audience (13+)**
> positioning with an age gate; if we pivot to a kids product, ads shrink to
> contextual-only / kid-safe networks or we go ad-free + paid/subscription.

**Ad formats (general-audience plan):**
- **Rewarded video** — the workhorse and most player-friendly: free hints,
  undo, extra discard slot, coin doublers, "continue" on a near-loss, daily
  reward boosts. Opt-in only.
- **Interstitial** — between levels, **frequency-capped** (e.g. every 3–4 levels,
  min 60–90s apart, never mid-puzzle). Calm audiences churn on aggressive ads —
  cap conservatively.
- **Banner** — optional, only on non-gameplay screens (map/menu); arguably skip
  banners entirely to protect the premium calm feel.
- **No** rewarded/interstitial during active arithmetic.

**Mediation & networks:** use a mediation layer (e.g. AdMob mediation / LevelPlay)
across Google AdMob + 1–2 demand partners. Implement via a Godot Android/iOS
plugin or GDExtension wrapper; abstract behind an internal `AdService` interface
so networks are swappable and the core game never depends on a vendor SDK.

**Privacy/consent:** integrate a **CMP** for GDPR/UMP consent and ATT prompt on
iOS; respect "limited ads" when consent is denied. Remove-Ads IAP must disable
all non-rewarded ads immediately and persist across reinstalls (receipt restore).

---

## 10. Compliance & Privacy (do not skip)

Because the game is **math/education-flavored**, store algorithms and regulators
may treat it as appealing to children.

> **DECISION (2026-06-08): General audience (13+), neutral age gate, COPPA
> "mixed-audience" handling.** See [ADR-0005](architecture/ADR-0005-audience-positioning-13plus-age-gated.md).
> Adults (13+) get the full ad/IAP/analytics experience; any user who declares
> under 13 gets child-safe restrictions (no ad ID, contextual-only/no ads, data
> minimization, parental-gated IAP). The label is backed by substance: neutral
> art direction, 13+ store rating, **no marketing to children**. §§8–9 (ads/IAP)
> and §11 (analytics) assume this posture.

**Implementation seam:** a `ComplianceService` (behind the ADR-0001 model/view
seam) owns `age_band` (persisted via SaveService) + consent state; `AdService`,
`Analytics`, and `IAPService` must query it — never assume. Neutral date-style
gate on first launch; collect no personal data before it resolves.

**Resilience rule:** design the economy to survive on **Remove-Ads + IAP alone**
— ad revenue is upside, not load-bearing — so a future tightening or
reclassification doesn't sink the business.

**Always:** clear Privacy Policy + ToS, CMP/UMP consent + iOS ATT, data-safety
form (Play) / privacy nutrition labels (App Store), DSAR handling, and a
documented data inventory. Keep PII collection at zero where possible (no login
required for core loop). **Legal review of the "child-directed" determination is
required before launch.**

---

## 11. Analytics & KPIs

**Instrument from Phase 0** behind an `Analytics` interface (vendor-agnostic;
candidates: GameAnalytics, Firebase, or a self-hosted sink). Event taxonomy:
session start/end, level start/win/fail (+ reason), discard pressure, booster
use, ad impression/reward, IAP funnel, tutorial step completion, math accuracy.

**North-star & guardrail KPIs:**
- **Engagement:** D1/D7/D30 retention, sessions/day, session length, levels/session.
- **Difficulty health:** per-level win rate, attempts-to-clear, quit points.
- **Monetization:** ARPDAU, conversion %, ad ARPDAU, rewarded opt-in rate,
  Remove-Ads attach rate, LTV.
- **Edu signal (differentiator):** math accuracy & speed trend per user — also
  fuels marketing claims and a "progress" UI.

---

## 12. Technical Architecture & Platform

**Strengths to preserve:** the model/view split is excellent — `BoardModel` is
pure, deterministic, and fully testable, emitting `GameEvent`s the view replays.
Keep all new systems behind that seam.

**New systems (each behind a clean interface/autoload):**
- `SaveService` — versioned persistence (`user://`), migration-safe.
- `Economy` / `Wallet` — currencies, transactions, server-authoritative-ready API.
- `AdService` / `IAPService` / `Analytics` / `RemoteConfig` — thin platform
  wrappers (Android/iOS plugins or GDExtension), each mockable for tests & editor.
- `LevelGenerator` — produces solvable configs; reuses `LevelData.is_solvable`.
- `Localization` — Godot CSV/PO translations.

**Platform:** Android first (cheaper UA, faster iteration), iOS fast-follow.
Godot export pipelines + signing automated in CI later. Consider GDExtension for
native ad/IAP SDKs.

**Testing/CI:** extend the gdUnit4 suite to cover generator solvability, economy
math, and save migrations. Keep CI green as the merge gate (already in place).

---

## 13. Art, Audio, UX

- **Art direction:** clean, warm, tactile cards; readable numerals at small sizes
  (accessibility-critical). Replace placeholder Kenney skin with bespoke set for
  v1; keep Kenney for prototyping.
- **Audio:** soft, satisfying tap/clear SFX; unobtrusive ambient music; distinct
  win sting. Audio is a huge share of "juice" ROI.
- **UX/accessibility:** colorblind-safe stack differentiation (shape + color, not
  color alone), dyslexia-friendly font option, large-text mode, left/right-hand
  layouts, reduced-motion toggle.
- **Localization:** numerals/operators are near-universal; UI strings localized.
  Prioritize EN, ES, PT-BR, DE, FR, then JP/KR + RU/TR for UA reach.

---

## 14. QA & Release

- **Automated:** gdUnit4 unit/integration (engine, generator, economy) in CI.
- **Manual:** device matrix (low-end Android key), soak/perf on mobile renderer,
  store-compliance checklist (privacy forms, age rating, IAP review).
- **Release rings:** internal → closed beta (Play testing track / TestFlight) →
  staged rollout (5%→100%) gated on crash-free % and retention.
- **Crash/ANR:** integrate crash reporting (Phase 3) with alerting.

---

## 15. Milestones & Indicative Timeline

> Order matters more than exact dates; assumes a small team.

| Milestone | Scope | Rough effort |
|-----------|-------|--------------|
| **M1 — Playable core+** | Save, tutorial, audio, juice, settings | 3–4 wks |
| **M2 — Content engine** | Level generator, operation worlds, scoring/stars | 4–6 wks |
| **M3 — Meta** | Map, daily challenge, streaks, XP, achievements, stats | 4–6 wks |
| **M4 — Monetize** | IAP, ads + mediation, currency, remote config, CMP | 4–6 wks |
| **M5 — Instrument** | Analytics, crash reporting, A/B framework | 2–3 wks |
| **M6 — Soft launch** | 1–2 geos, tune retention/monetization, fix funnel | 4–8 wks |
| **M7 — Global launch** | Store optimization (ASO), UA ramp, LiveOps cadence | ongoing |

---

## 16. Key Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| **Kids-audience classification** restricts ads/targeting | Decide positioning early (§10); design economy to survive on Remove-Ads/IAP if ad ARPU is capped |
| Math framing narrows mass-market appeal | Lead with "relaxing puzzle," math as quiet benefit; A/B the store creative |
| Sort-genre players exhaust content | Procedural generator + daily challenge from day one |
| Native ad/IAP SDKs on Godot are fiddly | Abstract behind interfaces; spike the plugin early (M4 de-risk in M1) |
| Aggressive ads churn the calm audience | Conservative interstitial caps; lean on rewarded + Remove-Ads |
| Difficulty mis-tuned | Instrument win-rate per level; tune via remote config without app updates |

---

## 17. Immediate Next Steps (actionable now)

1. **Decide audience positioning (Path A vs B, §10)** — gates the entire
   monetization design. *This is a product call needed before M4.*
2. Implement **SaveService** + **settings** (Phase 0) — unblocks everything meta.
3. Add **audio + juice + tutorial** — biggest perceived-quality jump for least code.
4. Build the **level generator** on the existing solvability invariant.
5. Stand up the **service interfaces** (`Ad/IAP/Analytics/RemoteConfig`) as mocked
   stubs so gameplay can integrate against them before real SDKs land.

---

*This plan is intentionally engine-agnostic at the systems level and leans on the
already-strong, testable core. The single most consequential decision is §10
(audience), because it determines whether monetization is ad-led or IAP/paid-led.*
