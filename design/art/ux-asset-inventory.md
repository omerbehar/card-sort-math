# UX Asset Inventory — CardSortMath

**Owner:** ux-designer
**Audience:** art-director, concept artists, UI artists
**Last updated:** 2026-06-13
**Viewport:** 390x844 portrait (base). `canvas_items` stretch with `expand` aspect — elements
anchored to screen edges must be designed with safe-area bleed. One-handed thumb reach governs
all interactive placement.

---

## How to read this document

- **Phase** — the milestone when the asset is first needed (P0 = built/in-progress now, P1–P4 = future).
- **Type** — Static (non-scaling image), 9-slice (stretchable panel), Icon (vector glyph), Animation (sprite sheet or particle), Procedural (code-drawn, no art file needed unless redesigned).
- **States** — Every distinct visual variant that requires a separate asset or tint pass. States marked "tint" mean the same source art is recolored in code; a separate export is NOT needed — but the base art must support the tint correctly (white or neutral base).
- **Touch target** — Minimum interactive area. Visual element may be smaller; invisible padding brings it to the minimum. Current code already implements this pattern (see `DiscardRow` note re: invisible padding).
- **Localization note** — Where text overlaps or sits adjacent to art, the longest expected string length across EN / ES / PT-BR / DE / FR is noted. Artists must not hard-bake text into art or leave insufficient clear space.

**Accessibility flags used below:**
- [A1] Must be distinguishable WITHOUT color alone (add shape, pattern, or luminance difference).
- [A2] Must have a reduced-motion static alternative (no looping animation).
- [A3] Text overlay — leave clear space for longest localized string (see per-element notes).
- [A4] Large-text mode — layout must reflow or scale without clipping; do not hard-crop text regions.
- [A5] Colorblind-safe — if color carries meaning, a parallel cue (shape/icon/label) must exist.
- [A6] No flashing content without a seizure-safe warning screen preceding it.

---

## Phase 0 / Milestone 1 — Core Gameplay (Built or In-Progress)

These assets replace existing Kenney CC0 placeholders for the v1 bespoke skin.
Everything here is needed before soft launch.

---

### Screen: Gameplay Board (main playing field)

The board occupies the full 390x844 canvas. The floor card pile sits centrally, stacks are
arranged in a row, the discard row sits between the floor and the booster tray, and the HUD
chrome wraps the top and bottom.

#### 1.1 Floor / Table Background

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Table felt / board background | Static (full-bleed) | Default only | Not interactive | Full 390x844 with safe bleed. Neutral warm surface. Must be legible behind floor cards and stacks. Phase 1 worlds introduce themed variants of this same asset. [A2] No motion in base; Phase 1 animated variant must have a static fallback. |

#### 1.2 Floor Cards

Cards are built procedurally in code (`card.gd`) using a 9-slice card panel, a Label for the
exercise text, and a collision shape. The card's visual state is driven by `set_exposed()` and
`set_inert()`.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Card face panel | 9-slice | **Default (exposed)** — full color, full alpha; **Covered (inert)** — 60% luminance / dimmed (currently via `modulate = Color(0.6, 0.6, 0.66)` — a tint, no separate asset needed if base is white-neutral); **Hover/focus** (mouse/editor) — optional subtle rim | Min 44x44 pt; actual card is ~72x92 pt (see `Layouts.CARD_W/H`) — already above minimum | 9-slice corners must survive scaling. Art must be white/neutral base so tint dimming reads correctly. The numeral label is placed by code — leave a clean interior clear zone. [A3] Exercise text e.g. "12 + 13" (5 chars EN) vs. potential future localized operator strings; clear interior zone of at least 60x40 pt. [A4] Font size is code-driven (20 pt exercise, 30 pt result); card art must not impose a maximum legible size. |
| Card exercise text (numeral + operator) | Procedural (Label) | Exposed / Covered | — | Not an art asset — driven by code. Numeral legibility at small sizes is CRITICAL (design pillar). Font choice is art-director decision; must be crisp at 20 pt on a mobile screen. |
| Card result number (post-route, on stack) | Procedural (Label) | Single state | — | Shown at 30 pt after `show_result()`. Same font as exercise; must read clearly against each stack color. |

**Accessibility notes for cards:**
- [A1] Covered vs. exposed must be distinguishable by luminance contrast, not only color shift.
- [A5] The card itself is color-neutral (white/cream). Stack color differentiation (not card color) carries the routing signal — see Stacks below.
- Dyslexia-friendly font option: the code currently uses the engine default font; a font swap hook must be designed so a dyslexia-friendly alternative (e.g. OpenDyslexic) can be dropped in without touching card art.

---

#### 1.3 Stack Slots (4 stacks)

Stacks are built in `stack.gd`. Each stack has a frame (9-slice), a centered target number
label, and three capacity-indicator dots at the bottom edge.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Stack frame / slot panel | 9-slice | **Active** (target assigned, full alpha); **Idle/empty** (no target, 50% alpha tint); **Clear flash** (brief bright pulse on stack clear — currently code-driven, no art asset needed but a bespoke clear-flash particle or flash texture is a Phase 1 polish opportunity); **Locked** (Phase 1 locked-deck feature — currently rendered as solid green tint via code, see §1.4) | Stack is not directly tappable in base gameplay — no touch target required on frame itself | Four variants needed: one per stack index for the DEFAULT palette. Base art should be white/neutral so Okabe-Ito tints (applied in code) render accurately under the colorblind palette. For the default palette, four pre-colored variants are used (currently Kenney slot_red / slot_yellow / slot_green / slot_blue — all to be replaced). [A1] [A5] See colorblind note below. |
| Stack capacity dots | Icon (small, x2) | **Empty dot** (slot unfilled); **Full dot** (slot filled) | Not interactive | Two icons: empty ring and filled circle. Currently 16x16 pt. Must be distinguishable by shape alone, not just fill color, for colorblind users. Dots should share the visual weight of the final v1 card skin. |
| Stack target number | Procedural (Label) | Visible (target assigned) / Hidden (no target) | — | White text, 34 pt, with dark outline. Not an art asset — code-driven. Must be legible against all four stack colors in both default and Okabe-Ito palettes. |

**Colorblind stack differentiation — CRITICAL accessibility requirement:**

The current default palette (red / yellow / green / blue) will fail for red-green colorblind
users. The colorblind palette (Okabe-Ito via `StackPalette`) applies a code tint over a
neutral grey slot. **For v1 bespoke art:**

- [A1] [A5] Each stack must carry a SHAPE differentiator in addition to color: distinct corner
  treatment, border pattern, or icon badge in the stack frame's corner. The shape cue must
  be visible in both the default and colorblind palette variants.
- The four Okabe-Ito tints used are: blue (#0072B2), orange (#E69F00), bluish-green (#009E73),
  vermillion (#D55E00). Art base must be white/neutral so these tints render accurately.
- The shape differentiator system (e.g., circle / square / triangle / diamond badge) is an
  art-director decision. UX constraint: badge must not obscure the target number or capacity dots.

---

#### 1.4 Locked Stack State (Phase 1 prototype, scaffold exists in P0)

The code for `set_locked()` exists but uses a solid green tint + "+" label drawn in code.
Full bespoke art is a Phase 1 deliverable.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Lock overlay / badge | Icon or Static | **Locked** (shows cost); **Unlock tap feedback** | Min 44x44 pt (entire stack frame acts as the unlock button) | Shows coin cost. Cost label is code-drawn. Art needed: a padlock icon or lock-state visual treatment that reads over the stack frame. [A3] Cost label: "350" (3 chars, fits comfortably). |

---

#### 1.5 Discard Row

Rendered in `discard_row.gd`. 5 base slots (expandable to 7 via booster). Slots are
40x51 pt visual, 44 pt touch-target minimum with invisible padding. Currently non-interactive.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Discard slot frame | 9-slice | **Normal** (cool grey); **Warning** (tinted red when nearly full — currently `Color(1.0, 0.55, 0.55)` tint applied in code, no separate art asset needed if base is neutral); **Occupied** (a card is shown inside the slot at reduced scale via `fly_to` with `target_scale`); **Newly added slot** (fades in when Extra Discard booster is purchased) | 44 pt minimum (invisible padding, visual is 40x51 pt) | [A1] Warning state must be distinguishable by more than color alone — a shape or pattern cue (e.g., border style change, or an exclamation icon overlay) must accompany the red tint for colorblind users. [A2] The slot-grow animation (slide + fade) has a `reduced_motion` code gate; static alternative is an instant rebuild — no additional art needed. |

---

### Screen: HUD (Heads-Up Display)

Built in `hud.gd`. Lives as a `CanvasLayer`. Two zones: top header bar and bottom booster tray.

#### 2.1 Header Bar

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Settings / gear button background | 9-slice (round) | **Default**; **Pressed** (tint or scale feedback — currently code-driven) | 60x60 pt (current size, above 44 pt minimum) | Currently uses `kenney/round_grey.png`. Replace with bespoke rounded button art. |
| Gear icon | Icon | **Default** | — | Currently `kenney/gear.png`. Replace with bespoke gear/settings glyph. Clean, 30x30 pt display, white or dark depending on button background. |
| Level badge / pill | 9-slice | **Default** | Not interactive | Displays "LV{n}" — leave room for 4 characters minimum (LV99). Currently `kenney/rect_green.png`. [A3] "LV99" = 4 chars — straightforward. |
| Progress / completion badge (%) | 9-slice (round) | **Default** | Not interactive | Displays "{n}%" — leave room for "100%". Currently `kenney/round_blue.png`. [A3] "100%" = 4 chars. |
| Coin balance display | Icon + Label | **Default** | Not interactive | Phase 1 — the coin/wallet balance will appear in the HUD. Needs a coin icon (small, inline with a numeral). See `icons/coin_sm.svg` (exists, may be redesigned for v1 skin). [A3] Balance could reach "9999999" (7 digits) in edge cases — ensure label area accommodates. |

#### 2.2 Booster Tray (3 buttons)

Full interaction spec in `design/ux/booster-icons.md`. Summary for asset purposes:

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Booster tile frame | 9-slice | **Affordable** (warm tint); **Unaffordable** (desaturated); **Precondition-disabled** (desaturated + slash — see below); **Picker-armed** (dashed border or static thick border under reduced_motion) | 72x72 pt (current layout, above 44 pt minimum) | Base is `kenney/slot_grey.png` → replace with bespoke slot art. Art must be white/neutral base so warm/cool tints read accurately. |
| Booster glyph — Picker | Icon (SVG) | **Affordable** (full opacity); **Unaffordable / disabled** (40% opacity, or code-driven) | — | "Finger reaching through horizontal layer bars." `icons/booster_picker.svg` exists as placeholder. Replace for v1. White on transparent, 42x42 pt display. [A1] Shape is the primary semantic cue (not color). |
| Booster glyph — Reshuffle | Icon (SVG) | **Affordable**; **Unaffordable / disabled** | — | "Circular refresh arrow with 3 dots inside." `icons/booster_reshuffle.svg` exists as placeholder. Replace for v1. White on transparent. [A1] |
| Booster glyph — Extra Discard Slot | Icon (SVG) | **Affordable**; **Unaffordable / disabled** | — | "Discard slot shape + bold '+' symbol." `icons/booster_extra_discard.svg` exists as placeholder. Replace for v1. White on transparent. [A1] |
| Slash overlay (precondition-disabled) | Icon or Procedural | Single state | — | Diagonal line across the glyph. Currently specified as code-drawn (`Line2D`). If art-director prefers a bespoke slash art overlay, it needs to be a transparent SVG sized to match the glyph area. |
| Dashed border (Picker-armed) | Procedural | Armed / Not-armed | — | Currently specified as code-drawn. Reduced-motion alternative is a static thick border. No art file needed unless art-director wants a bespoke treatment. |
| Cost badge — coin icon (affordable) | Icon (SVG) | **Affordable**; **Unaffordable** (coin + X stroke) | — | `icons/coin_sm.svg` (affordable) and `icons/coin_unavailable_sm.svg` (coin + diagonal X). Both exist as placeholders. 18x18 pt display. [A1] The X stroke makes the unavailable state distinguishable by shape. |
| Spend-confirm modal (≥250 cost) | Static or Procedural | **Visible** (confirm/cancel prompt) | Min 44 pt each for Confirm and Cancel buttons | Small modal above the tapped button. "[coin icon] Spend 250? [Confirm] [Cancel]" — two buttons, both min 44 pt. [A3] "Spend 350?" (longest cost) = 10 chars including coin glyph. |

---

### Screen: Pause Menu

Built in `pause_menu.gd`. A `PopupBase` modal: semi-transparent backdrop + centered panel.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Backdrop (dimmed overlay) | Procedural | Active / Dismissed | — | Currently `Color(0,0,0,0.55)` drawn in code. If art-director wants a bespoke blurred or textured backdrop, that is a Godot shader or a Static overlay; flag to shader-specialist. |
| Panel body | 9-slice | Default | — | Currently `kenney/rect_blue.png`. 324x416 pt. [A3] "PAUSE" header — short string, not a concern. |
| Panel header strip | 9-slice | Default | — | Darker blue strip, same base art with darker tint. Could share the panel art with a color pass. |
| Close (X) button | 9-slice + Label | **Default** (red); **Pressed** | 44x44 pt | Round button with "X" label. Currently `kenney/round_grey.png` with red tint. Bespoke round button needed. |
| Audio toggle buttons (Sound / Music / Haptics) | 9-slice | **On** (green tint); **Off** (grey tint) | 66x66 pt each | Three round buttons. Text label "SFX" / "BGM" / "VIB" drawn in code. Base art must be white/neutral for tints to render. [A1] On/off must be distinguishable by shape or icon, not only green/grey color difference — consider adding a speaker/mute icon overlay, or a checkmark/X. [A3] "VIB" (3 chars) is the longest label — fine at current size. |
| Colorblind Mode pill switch | 9-slice (track) + Icon/Sprite (knob) | **On** (track green + knob right); **Off** (track grey + knob left) | 58x30 pt track; full row (280+ pt) is the button hit target | Track: `kenney/slot_grey.png`. Knob: `kenney/round_grey.png`. Bespoke track + knob art for v1. [A1] On/off must be positionally distinct (knob position carries primary cue — color is secondary). |
| Reduced Motion pill switch | 9-slice + Sprite | Same states as above | Same as above | Same art as Colorblind switch — same asset, same states. |
| Row background for switch rows | 9-slice | Default | — | `kenney/rect_blue.png` with darker tint. Shared asset with panel body. |
| Reset Tutorial text button | 9-slice + Label | **Default**; **Pressed** | 280x40 pt (current size) | "Reset Tutorial" — label in code. Bespoke button treatment. [A3] "Reiniciar Tutorial" (ES, 18 chars) is approximately the longest translation — button must be wide enough. Currently 280 pt wide, which should accommodate. |
| Home button | 9-slice + Icon | **Default** (red); **Pressed** | 86x56 pt | Currently uses "⌂" text glyph. Replace with a bespoke house icon. [A3] Not a text button — icon only. Confirm icon legibility at 86 pt width. |
| Continue button | 9-slice + Label | **Default** (green); **Pressed** | ~190x56 pt | "CONTINUE" label in code. [A3] "FORTFAHREN" (DE, 10 chars) or "CONTINUAR" (ES/PT-BR, 9 chars) — button must accommodate. Currently ~190 pt wide; verify at large-text mode. |

---

### Screen: Result Screen — Win State

Built in `result_screen.gd`, `Mode.WIN`.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Win backdrop / background | Procedural or Static | Active | — | Currently code-drawn (no background art). Art-director may introduce a celebratory backdrop. [A2] Any animated backdrop must have a static alternative under `reduced_motion`. |
| Confetti particle burst | Animation (CPUParticles2D) | **Active** (plays on open, one-shot); **Suppressed** (under `reduced_motion` — already gated, particles simply not added) | Not interactive | Uses `CPUParticles2D` — no art file, the particle is a colored quad. Art-director may want a particle texture (a small confetti shape sprite) for a more polished look. [A2] `reduced_motion` already suppresses this — no additional action needed. [A6] Confetti at moderate density is not a flashing hazard, but if density is increased, review against WCAG 2.3.1. |
| Win title "WELL DONE!" | Procedural (Label) | Default | — | Gold text, 52 pt, dark outline. Not an art asset. [A3] "SEHR GUT!" (DE) / "MUITO BEM!" (PT-BR, 9 chars) — label area is full viewport width, fine. |
| Hero star (celebration) | Procedural (Label "★") | Default | — | Currently a Unicode star glyph at 140 pt (foreground) + 220 pt (background glow at 22% alpha). A bespoke illustrated star asset would significantly improve visual quality at this hero size. If replaced with art, provide a 2-layer approach: hero star + soft glow layer, or a single asset with pre-composed glow. [A2] If the star has an entrance animation, static fallback required. |
| Star rating row (1-3 stars) | Icon x3 | [M2] **Filled star**; **Empty star**; **Half star** (optional) | Not interactive | Placeholder reserved (`_star_rating` node). Art needed in Phase 1. Must be distinguishable by shape (solid vs. outline) not color alone. [A1] |
| Reward chips row (coins/gems) | Icon + Label | [M4] Default | Not interactive | Placeholder reserved (`_reward_chips` node). Coin and gem icons per the economy skin. |
| Tournament / live-ops strip | Static or Animation | [M3] Default | Variable | Placeholder reserved (`_tournament_strip` node). |
| "TAP TO CLAIM" / Next button | 9-slice + Label | **Default** (green); **Pressed** | Min 300x66 pt (current size, well above minimum) | Bottom-anchored. [A3] "TOCA PARA RECLAMAR" (ES, 18 chars, approximate) — button is 300 pt wide; verify longest localization fits at 24 pt font. |

---

### Screen: Result Screen — Lose State

Built in `result_screen.gd`, `Mode.LOSE`.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Lose modal card panel | 9-slice | Default (light cream background) | — | 336x330 pt. [A3] All copy is code-driven, not embedded in art. |
| Lose header strip | 9-slice | Default (blue) | — | 336x64 pt. "GAME OVER" label in code. [A3] "GAME OVER" is used across locales; confirm with localization team. |
| Close (X) / Home button | 9-slice + Label | **Default** (red); **Pressed** | 46x46 pt | Top-right corner of panel. Bespoke round button. |
| Card icon (lose illustration) | Icon or Illustration | Default | — | Currently a "🃏" text emoji. Replace with a bespoke illustrated card-back or lose-state icon — emoji rendering is platform-inconsistent. ~60 pt display. |
| "The discard row filled up." subtext | Procedural (Label) | Default | — | Not an art asset. [A3] Localized lose reason string — longest may be German/PT-BR. Reserve 280 pt width at 18 pt font (current allocation is full panel width). |
| Revive button (rewarded ad) | 9-slice + Label | [M4] **Default**; **Ad unavailable** (greyed) | Min 44 pt height | Placeholder reserved. Ad-gated; must comply with ADR-0005 (no children). |
| Play On button (soft currency) | 9-slice + Label | [M4] **Default**; **Insufficient balance** | Min 44 pt height | Placeholder reserved. |
| Retry button | 9-slice + Label | **Default** (gold); **Pressed** | 288x60 pt (current size) | [A3] "REINTENTAR" (ES, 10 chars) / "TENTAR NOVAMENTE" (PT-BR, 16 chars) — widest at ~280 pt; verify at large-text mode. |
| Special Offer IAP banner | Static + Label | [M4] Default | Full-width strip, min 44 pt height | Bottom-anchored placeholder. ADR-0005: no child-directed ads; gate through `ComplianceService`. |

---

### Screen: Tutorial / Coach Overlay

Built in `coach_overlay.gd`. Overlays the board; parented to the HUD `CanvasLayer`.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Highlight ring around target card | Procedural (ColorRect strips) | **Default** (solid gold border, semi-transparent fill); **Pulsing** (alpha pulse animation, looping); **Static** (reduced_motion = no pulse) | Not interactive | Currently 4x ColorRect borders. A bespoke shader-based ring would be higher quality (refer to `godot-shader-specialist`). [A2] Pulse already gated by `reduced_motion`. [A6] Alpha pulse is slow (0.9s period) — not a flashing hazard. |
| Attention arrow | Procedural (Label "v" / "^") | **Pointing down** (card below the flip threshold); **Pointing up** (card in top band); **Bobbing animation** (looping); **Static** (reduced_motion = no bob) | Not interactive | Currently a text glyph. Replace with a bespoke vector arrow asset for v1. Arrow flips direction based on card position. [A2] Bob already gated by `reduced_motion`. |
| Coach banner (instruction text) | Procedural (Label) | **Default** (fade in); **Hidden before grace period** | Not interactive | 358x48 pt, centered. Text in code. [A3] "Solve it — your answer picks the stack." (EN, 38 chars) — longest localized equivalent may reach ~50 chars. Banner uses `AUTOWRAP_WORD`, so it can wrap. Ensure 2-line wrap does not push below the floor cards at _BANNER_BOTTOM_Y = 652. |
| Confirm toast ("Matched — nice work!") | Procedural (Label) | **Visible** (after successful route); **Fading out** | Not interactive | Same position as banner. [A3] "Matched — nice work!" (EN, 20 chars) — localized equivalents likely similar length. |

---

## Phase 1 — Game Feel, Content, and Operation Worlds

Needed for v0.2–v0.5. Builds on P0 art; introduces themed skins and meta-progression chrome.

---

### System: Operation Worlds / Themed Skins

Phase 1 introduces 4–5 "worlds," each with a different arithmetic operation (Addition,
Subtraction, Multiplication, Division, Mixed). Each world has its own themed skin.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Table background (per world theme) | Static (full-bleed) | Default; [A2] Static fallback if animated | Not interactive | One per world (~5 total). Must pass accessibility check: cards/stacks/discard must remain legible against all themes. Provide as world 0 = base warm neutral; subsequent worlds escalate visual complexity carefully. |
| Card face panel (per world) | 9-slice | Same states as P0 card | As P0 | One per world. The card's interior (exercise text) must remain legible against each world's card art. [A3] Same constraints as P0 card. |
| Stack frame (per world) | 9-slice | Same states as P0 stacks | Not interactive (stack frame) | One set of 4 per world, or a world-specific tint/border layer over the base art. Shape differentiator for colorblind must persist across all world skins. [A1] [A5] |
| World select icon / thumbnail | Static or Icon | **Locked** (greyed, lock badge); **Unlocked** (full); **Current** (highlighted border or badge) | Min 44x44 pt (if tappable in world map) | Represents each world on the map screen. Needs a distinct iconic image per world (e.g., plus sign, minus sign, multiplication cross, division slash, mixed). |
| Locked stack chrome (bespoke) | Icon + 9-slice | **Locked** (coin cost displayed); **Unlock tap** | Full stack frame (see P0 §1.4) | Replaces the current code-drawn green lock treatment. Needs a padlock icon and a coin-cost badge that matches the v1 coin art. |

---

### System: Star / Score Rating

Per-level 1–3 star efficiency rating. Shown on the win result screen (placeholder reserved).

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Star icon (filled) | Icon | Single state | Not interactive (display only) | Gold star. ~48 pt display on result screen. Must be distinguishable from empty star by shape (not only fill color). [A1] |
| Star icon (empty / outline) | Icon | Single state | Not interactive | Outline of same star shape. [A1] |
| Star icon (half, optional) | Icon | Single state | Not interactive | Half-filled variant. Only if the design adopts a half-star precision level. |
| 1-3 star row container | Procedural | Default | Not interactive | Three stars in a row. Spacing driven by code. |
| "New record!" or "Best: 3 stars" badge | Static or Procedural | Default | Not interactive | Optional embellishment shown when the player beats their previous score. |

---

### System: Undo / Hint (Picker) / Reshuffle — already covered in P0 HUD booster tray

The booster icons are P0 assets (see §2.2). No additional Phase 1 art unless world themes introduce
themed booster tile frames.

---

## Phase 2 — Meta and Retention Systems

Needed for v0.6–v0.9. New screens introduced: world map, daily challenge, streaks/rewards, XP,
achievements, stats, cosmetics/collections.

---

### Screen: World Map

The primary navigation screen between levels and worlds.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Map background | Static | Default | Not interactive | Represents the overall "journey" metaphor. Should accommodate level node overlays without legibility conflict. Phase 4 expands with seasonal reskins. |
| Level node (dot/pin on map) | Icon | **Completed** (star badge visible); **Current** (highlighted / pulsing — [A2] static border under reduced_motion); **Locked** (dimmed + lock icon); **Available** (default, ready to play) | Min 44x44 pt | Displays 1-3 star rating if completed. [A1] States must be distinguishable by shape/icon, not only color. Lock icon required for locked state. |
| World gate / door | Icon or Static | **Locked** (lock icon + star requirement text); **Unlocked** (open) | Min 44x44 pt | Separates worlds on the map. [A3] "15 stars to unlock" (EN, 18 chars) — star count in code. |
| Path / connector between level nodes | Static or Procedural | **Completed segment** (full tint); **Upcoming segment** (dimmed/dashed) | Not interactive | [A1] Path state must be distinguishable by shape (solid vs. dashed) as well as color. |
| Player avatar / position indicator | Icon or Animation | **Default** (stationary); **Moving** (tween, [A2] static fallback) | Not interactive | Optional but common in the genre. If used, must have a reduced-motion static position snap. |
| World title text | Procedural or Embedded | Default | Not interactive | e.g., "Addition World." [A3] Longest world title in DE/FR may run longer — do not embed text in world background art. |

---

### Screen: Daily Challenge Entry Point

Could be a banner on the world map or a dedicated tab.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Daily challenge banner / card | Static + Label | **Available** (today's challenge not yet done); **Completed** (check badge); **Unavailable** (yesterday's past, new one not yet unlocked) | Min 44x44 pt (full banner area) | [A3] "Daily Challenge" (EN, 15 chars) / "Défi quotidien" (FR, 14 chars) — consistent length. |
| Countdown timer display | Procedural | Default (ticking) | Not interactive | "Next in 23:59:59" format. Timer is code-driven. No art asset; ensure label area accommodates 14 chars. |
| Shareable result card (post-completion) | Static template + Label | Single state | Not interactive (generated image for share) | The result card is generated as a screenshot/export for the OS share sheet. It needs a branded template frame (CardSortMath branding, score, date). Art-director deliverable: a frame asset that can be composited over a screenshot. |

---

### System: Streaks and Daily Rewards

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Streak flame icon | Icon | **Active** (n-day streak); **Broken** (0-day, desaturated or cracked) | Not interactive (display) | Flame metaphor is genre-standard. [A1] Active vs. broken must differ by shape, not only color. |
| Streak counter label | Procedural | Default | Not interactive | "7 day streak" — code-driven. |
| Daily reward slot (7-day calendar row) | Icon or Static | **Claimed** (tick / greyed); **Today** (highlighted); **Future** (locked/dim) | Min 44x44 pt each | A row of 7 reward slots. [A1] Claimed/unclaimed must be distinguishable by icon shape. [A3] Reward label (e.g., "50 coins") — keep short, 10 chars max. |
| Claim reward button | 9-slice + Label | **Available** (green); **Already claimed** (greyed/disabled); **Pressed** | Min 44x44 pt | [A3] "CLAIM" / "BEANSPRUCHEN" (DE, 12 chars) — button must accommodate. |

---

### System: XP Bar and Player Level

Displayed in the HUD or a dedicated profile tab.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| XP progress bar | 9-slice (track) + Procedural (fill) | **Default** (partial fill animated on XP gain); **Full / level up** (sparkle or pulse, [A2] static fallback) | Not interactive | Track and fill are separate art elements. Fill color must be distinguishable from track without relying only on hue. [A1] |
| Player level badge | Icon or 9-slice + Label | **Default** | Not interactive | "Lv. 42" — numeral in code. Badge art should accommodate up to 3-digit levels ("Lv. 999"). [A3] |
| Level-up celebration | Animation | **Plays on level-up** (one-shot, [A2] disabled under reduced_motion); **Suppressed** | Not interactive | Could reuse confetti particle system from win screen. If bespoke, must have a reduced-motion no-animation path. [A6] Avoid rapid flashing. |

---

### Screen: Achievements

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Achievement icon (per achievement) | Icon | **Locked** (greyed/silhouette); **Unlocked** (full color) | Not interactive (icon; full row is 44 pt) | One unique icon per achievement (estimated 15-30 at launch). [A1] Locked silhouette must be visually distinguishable from unlocked without relying solely on color. |
| Achievement row | 9-slice + Label | **Locked**; **Unlocked**; **Newly unlocked** (highlight or badge) | Min 44 pt row height | [A3] Achievement title e.g., "100 Multiplications Cleared" (EN, 28 chars) — allow 2-line wrap in large-text mode. [A4] |
| Achievement unlock toast / notification | Static + Label | **Appears** (slide in / fade in, [A2] instant-show under reduced_motion); **Dismissed** | Not interactive | Small badge that appears during gameplay. Icon + short title. ~200 pt wide, 60 pt tall. [A2] |

---

### Screen: Stats Dashboard

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Stat row / card | 9-slice + Label | Default | Not interactive | e.g., "Total sums solved: 1,240" — all text is code-driven. No embedded text in art. |
| Accuracy gauge or progress bar | 9-slice (track + fill) | Default | Not interactive | Shows math accuracy trend. Same visual system as XP bar. [A1] |
| Sharing CTA (for UA) | 9-slice + Label | Default; Pressed | Min 44x44 pt | "Share your stats" — a social share trigger. [A3] "Partager mes stats" (FR, 18 chars). |

---

### Screen: Cosmetics / Collection Screen

Where players browse and equip card skins, table themes, and clear-effect VFX.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Cosmetic item thumbnail | Static | **Owned / equipped** (check badge or border); **Owned / unequipped** (owned indicator); **Locked / not owned** (lock badge, greyed); **Purchasable** (price badge) | Min 44x44 pt | Thumbnail of each cosmetic (card back, table skin, VFX). [A1] Owned/locked must differ by icon shape. |
| Equip button | 9-slice + Label | **Equip** (default green); **Equipped** (grey/disabled, "Equipped" label); **Pressed** | Min 44x44 pt | [A3] "EQUIP" / "EQUIPAR" (ES/PT-BR, 7 chars) / "AUSRÜSTEN" (DE, 9 chars). |
| Category tabs (card backs / table themes / VFX) | 9-slice + Label | **Active** (selected); **Inactive** | Min 44 pt height | [A3] "Table Themes" (EN, 12 chars) / "Thèmes de table" (FR, 15 chars) — longest FR tab label; tabs should accommodate. |

---

## Phase 3 — Monetization and Live Ops

Needed for v1.0. IAP store, currency displays, ad surfaces, consent screens.

---

### Screen: IAP Store / Shop

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Store tab bar | 9-slice + Label | **Active**; **Inactive** | Min 44 pt | Tabs: Gems / Coins / Boosters / Remove Ads / Cosmetics. [A3] "Remove Ads" / "Publicité" (FR, 9 chars) — fine. |
| IAP product tile | 9-slice + Label | **Default**; **Best value badge** (sticker overlay); **Limited time** (countdown badge); **Owned / purchased** (greyed + "Purchased") | Min 44x44 pt (full tile, ideally 88+ pt) | Product image + name + price label. Price is OS-supplied (localized currency) and must be in a code-driven label, never embedded in art. [A3] Product names: "Gem Pack — Starter" (EN, 18 chars) — allow room. [A4] Large-text must not overflow tile bounds — use flexible tile height or ellipsis. |
| "Best value" sticker | Static | Single state | Not interactive | Overlays a product tile. e.g., ribbon or badge. [A3] "BEST VALUE" / "MEILLEUR RAPPORT" (FR, 16 chars) — if text is in the art, French version needs its own sticker. Prefer code-drawn text on an art shape. |
| "Remove Ads" hero product tile | Static + Label | **Default**; **Purchased** | Full tile (min 88 pt height recommended) | The flagship conversion SKU. Deserves hero treatment. [A3] "$2.99 — One-Time Purchase" — price is OS-localized, keep in code. |
| Currency icon — Gems (hard) | Icon | Default | Not interactive (display) | Gem icon used inline with balances and product tiles. Must be visually distinct from Coins at small sizes (18 pt display in badges). |
| Currency icon — Coins (soft) | Icon | Default; **Unavailable** (coin + X) | Not interactive | `icons/coin_sm.svg` exists; redesign for v1. [A1] Coin and Gem icons must be distinguishable by shape alone. |
| Purchase button | 9-slice + Label | **Default** (green); **Processing** (spinner or shimmer, [A2] static "Processing..." text fallback); **Success** (brief tick, [A2] no animation under reduced_motion); **Purchased / disabled** | Min 44x44 pt | [A3] "$4.99" — OS-provided, code label. Button text "BUY" / "KAUFEN" (DE, 6 chars) / "ACHETER" (FR, 7 chars). |
| Restore Purchases button | 9-slice + Label | **Default**; **Processing**; **Success** | Min 44x44 pt | Required by Apple App Store review guidelines. Plain text button acceptable; small, not prominent. [A3] "Restore Purchases" / "Restaurer les achats" (FR, 20 chars) — longest; ensure label fits. |

---

### Surface: Rewarded Ad Triggers

Ad triggers appear at specific rescue moments (undo after fail, daily reward boost, continue
after near-loss). These are UI prompt surfaces, not the ad itself (the ad is served by the
ad SDK fullscreen).

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Rewarded ad prompt button | 9-slice + Icon + Label | **Default** (available — shows video play icon + "Watch Ad"); **Ad unavailable** (greyed, "No ads available"); **Pressed** / **Loading** | Min 44x44 pt | Video play icon (triangle in circle) — must be recognizable at 24 pt. [A1] Available/unavailable must differ by shape (icon changes or X overlay). [A3] "Watch Ad to Undo" / "Ver anuncio para deshacer" (ES, 24 chars) — widest label; ensure button accommodates or wraps. ADR-0005: only shown when `ComplianceService.age_band` is not child (under-13). |
| "Ad loading" indicator | Procedural or Animation | Active / Resolved | Not interactive | Small spinner or text. [A2] Text fallback under reduced_motion. |
| Interstitial ad close button overlay | Procedural | Active (timer) | Min 44x44 pt | The X/close button shown after mandatory view time. This is usually provided by the ad SDK, not the game. Note here for awareness. |

---

### Screen: Consent / Age Gate (First Launch)

Required by COPPA/GDPR (ADR-0005). Shown once on first launch before any data collection.

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Age gate background | Static | Single state | Not interactive | Neutral, welcoming. Must not use child-directed imagery regardless of age input. Warm, puzzle-themed, age-neutral. |
| "Enter your age" / date picker area | Procedural | Input active / Input idle | OS date picker (no minimum) | UX: a birth year selector or "I am 13 or older / I am under 13" binary choice is recommended over a full date picker (reduces friction). [A3] "I am 13 or older" / "Tengo 13 años o más" (ES, 20 chars). |
| Age confirm button | 9-slice + Label | Default; Pressed; Disabled (no selection made) | Min 44x44 pt | [A3] "CONTINUE" / "FORTFAHREN" (DE, 10 chars). |
| Privacy Policy / Terms links | Procedural (underlined text) | Default; Pressed | Min 44 pt height | Plain text links. Must be visible and accessible before consent is granted. |
| GDPR consent toggle / CMP (EU users) | Platform CMP dialog or in-game equivalent | Accept / Reject / Manage | Per CMP SDK | If using an in-game consent UI: each toggle must be min 44 pt. [A1] Accepted/rejected states must differ by shape. |

---

### Surface: Banner Ad Placement (optional, map/menu screens only)

Per GAME_PLAN §9, banners are optional and only on non-gameplay screens. If used:

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Banner ad container / safe area | Static placeholder | Default | Not applicable (ad fills the area) | Reserve a 320x50 pt or 320x90 pt zone at screen bottom on map/menu screens. This area must not overlap interactive elements. ADR-0005: no banners for under-13 users. |

---

## Phase 4 — Growth (Post-Launch)

Needed post-global-launch. Lower priority for initial asset pipeline.

---

### Screen: Leaderboard / Async Social

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Leaderboard row | 9-slice + Label | **Own row** (highlighted); **Other row** (default) | Min 44 pt row height | Rank number + anonymized username + score. No embedded usernames in art. [A3] Allow for 12-char usernames + 7-digit scores. |
| Friends tab / global tab | 9-slice + Label | Active / Inactive | Min 44 pt | [A3] "FRIENDS" / "AMIGOS" (ES/PT-BR, 6 chars) — consistent. |
| Platform leaderboard button | Icon + Label | Default | Min 44x44 pt | Opens OS Game Center / Play Games. Use platform-branded assets per Apple/Google guidelines (those assets are provided by the platform, not bespoke). |

---

### Seasonal / Event Content

| Element | Type | States | Touch target | Notes |
|---|---|---|---|---|
| Event banner / landing card | Static + Label | **Active** (live event); **Upcoming** (countdown); **Expired** | Min 44 pt | Seasonal themes (winter, summer, etc.). [A2] Animated banners need static fallbacks. [A6] Festive animations must not contain rapid flashing. [A3] Event names must be in code labels, not art. |
| Limited-time world skin (per event) | See Phase 1 World Skin assets | Same states | — | Same asset structure as P1 world skins, seasonal variant. |

---

## App-Level Assets

These are needed regardless of gameplay phase — some before Phase 0 ships.

| Element | Type | States | Notes |
|---|---|---|---|
| App icon | Static | Default (1 size, multiple export scales via art-director) | Portrait-optimized. Must read at 29x29 pt (notification) through 1024x1024 pt (store). Math/puzzle/card visual language. No text in the icon (illegible at small sizes). Must pass colorblind check (not solely color-coded). |
| Splash / loading screen | Static | Single state | Shown during Godot engine load. Keep minimal and fast-rendering. Branding + brief loading indicator. No complex animation (it won't render during engine init). |
| Notification icon (Android) | Icon | Default | Must be a white-on-transparent monochrome icon per Android notification guidelines. A simplified version of the app icon glyph. |
| Store listing screenshots (framing template) | Static (frame only) | Default | The game screenshots are captured from the live build; art-director provides a branded device frame and background for store listings. Text overlays ("Solve and Sort!", "100+ Levels") go in a code/design-layer, not embedded in the screenshot art. [A3] Text overlays must be localized for each store locale. |
| Store feature graphic (Google Play) | Static | Single state | 1024x500 pt landscape graphic. Separate deliverable from portrait screenshots. |
| Press kit / icon asset set | Static | Multiple sizes | For UA creatives and press use. Provide the app icon in vector where possible. |

---

## Accessibility-Driven Asset Requirements Summary

The following requirements must be treated as non-negotiable constraints on ALL art produced for
this project, not as optional add-ons.

### A1 — Color must never be the sole differentiator

| Element | Required additional cue |
|---|---|
| Stack slots (4 colors) | Distinct shape badge per stack (corner icon: circle / square / triangle / diamond or similar system). Art-director to define the system; UX requires it exists. |
| Discard row warning state | Border style change or exclamation icon overlay in addition to red tint. |
| Booster affordable/unaffordable | Glyph opacity change + coin badge shape change (X stroke) — already specified. Shape change is the load-bearing cue. |
| Pause menu audio toggle on/off | Icon overlay (speaker/mute symbol) or checkmark/X in addition to green/grey tint. |
| Pause menu pill switches on/off | Knob position is the primary cue — already shape-based. Color is secondary only. |
| Level node states (map) | Icon shape for each state (star badge, lock, highlight border). |
| Achievement locked/unlocked | Silhouette vs. full-color icon — silhouette is a shape cue, acceptable. |
| Star rating filled/empty | Solid vs. outline star — shape-based, acceptable. |
| Daily reward claimed/unclaimed | Check icon or distinct shape, not only color change. |

### A2 — Reduced-motion static alternatives

Every asset that has an animated variant must also function without animation. The following
animated assets must have static states that convey the same information:

| Animated asset | Static alternative |
|---|---|
| Confetti burst (win screen) | No confetti shown — win title + star carry the celebration. Already gated in code. |
| Coach overlay ring pulse | Static ring at full opacity. Already gated. |
| Coach overlay arrow bob | Arrow static at base position. Already gated. |
| Level node pulse (current node on map) | Static highlighted border. |
| XP bar fill animation | Instant fill to new value. |
| Level-up celebration | No animation; XP bar + badge update is sufficient. |
| Player avatar movement on map | Instant position snap. |
| Event banner animation | Static banner image. |
| Slot grow animation (extra discard) | Instant rebuild. Already gated. |
| Any animated table background (Phase 1 themes) | Static version of the same background. |

### A3 — Localization clear space

All UI art that has text near or over it must leave a minimum clear zone for the longest expected
localized string. The locales to plan for are EN / ES / PT-BR / DE / FR. German and French tend
to produce the longest strings. Portuguese (Brazil) is also verbose. Key rules:

- Never embed UI strings in raster art.
- For any art element that frames text (buttons, badges, panels), plan for DE/FR strings that
  are 30–50% longer than EN equivalents.
- Buttons should use flexible 9-slice width — do not bake a fixed-width button at EN string length.
- Badge pills (level badge, cost badge) must support 7-character strings minimum ("LV999", "100%", "350").

### A4 — Large-text mode reflow

The game plan references a "large-text mode" accessibility option (not yet implemented in
`Settings`, but planned). Art must accommodate it:

- All text areas should assume a 1.5x font size multiplier may be applied.
- 9-slice panels must be designed to grow vertically without breaking the corner art.
- Fixed-height rows (achievement rows, store product tiles) must be able to grow to 2-line
  text height.
- Booster cost badges must accommodate "350" at 1.5x the current 15 pt size (22.5 pt) without
  overflowing the tile bounds.

### A5 — Colorblind-safe stack differentiation

The four Okabe-Ito tints applied by `StackPalette` under `colorblind = true` are:

| Stack index | Color name | Hex |
|---|---|---|
| 0 | Blue | #0072B2 |
| 1 | Orange | #E69F00 |
| 2 | Bluish-green | #009E73 |
| 3 | Vermillion | #D55E00 |

Art for the stack slot panels must use a **white/neutral base** so these code-applied tints
render accurately. Any pre-colored stack art (default palette) must still be accompanied by the
shape-based badge system described in A1 above, since the shape cue must be present in
both default and colorblind palette modes.

### A6 — No flashing content without warning

Verify the following against WCAG 2.3.1 (no more than 3 flashes per second):

- Win confetti particles — verified safe at current density.
- Stack clear flash (brief pulse) — safe at current 80ms/140ms tween duration.
- Level-up celebration — must be reviewed if bespoke animation is added.
- Event banners — must not use rapid flashing sequences.
- Interstitial ad content — out of game's control, but a pre-interstitial warning screen
  should be considered as a future addition.

---

## Assets Currently Existing (Kenney Placeholders to Replace)

The following are in `assets/ui/kenney/` and `assets/ui/icons/` and must be replaced for v1:

| Current file | Role | Replacement priority |
|---|---|---|
| `kenney/card.png` | Card face 9-slice | P0 (before soft launch) |
| `kenney/slot_red.png`, `slot_yellow.png`, `slot_green.png`, `slot_blue.png` | Stack frames (4 colors) | P0 |
| `kenney/slot_grey.png` | Discard slot, booster tile, pill-switch track | P0 |
| `kenney/dot_empty.png`, `dot_full.png` | Stack capacity dots | P0 |
| `kenney/round_grey.png` | Buttons, pill-switch knob | P0 |
| `kenney/round_blue.png` | Progress badge | P0 |
| `kenney/rect_green.png` | Level badge, Continue button | P0 |
| `kenney/rect_blue.png` | Panel body, header, misc buttons | P0 |
| `kenney/gear.png` | Settings button icon | P0 |
| `icons/booster_picker.svg` | Picker booster glyph | P0 |
| `icons/booster_reshuffle.svg` | Reshuffle booster glyph | P0 |
| `icons/booster_extra_discard.svg` | Extra Discard booster glyph | P0 |
| `icons/coin_sm.svg` | Coin icon (affordable state) | P0 |
| `icons/coin_unavailable_sm.svg` | Coin icon (unaffordable state) | P0 |
| `icons/tool_hammer.png`, `tool_drill.png`, `tool_potion.png` | Old booster icons (superseded) | Remove — not referenced in current code |

---

## Cross-Reference: Scene to Asset Map

| Scene / file | Primary assets consumed |
|---|---|
| `scenes/card/card.gd` | Card face 9-slice |
| `scenes/stack/stack.gd` | Stack slot frames (x4 default + neutral), capacity dots (x2) |
| `scenes/discard/discard_row.gd` | Discard slot 9-slice |
| `scenes/ui/hud.gd` | Round button (gear), rect pills (level badge, progress badge), booster tiles, booster glyphs (x3), coin icons (x2) |
| `scenes/ui/pause_menu.gd` | Rect panel, round buttons (close, audio toggles), slot (pill track), round (pill knob) |
| `scenes/ui/result_screen.gd` | No 9-slice art consumed directly (uses StyleBoxFlat); hero star art opportunity; confetti particles |
| `scenes/ui/coach_overlay.gd` | Attention arrow icon (opportunity to replace text glyph) |
| App level | App icon, splash screen, notification icon, store assets |
