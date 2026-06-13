# CardSortMath — Art Direction & Asset Spec Sheet

**Owner:** Art Director  
**Status:** Production-ready draft — v1.0, 2026-06-13  
**Parallel doc:** `design/art/ux-asset-inventory.md` (UX designer owns screen/state enumeration;
this document owns dimensions, formats, export standards, and visual direction).  
**References:** `docs/GAME_PLAN.md §13`, `data/stack_palette.gd`, `design/ux/booster-icons.md`

---

## 1. Art Direction Summary

### 1.1 Style Statement

CardSortMath targets calm, productive adults (25–55) and students. The art must
read as **mature casual** — warm, tactile, and satisfying without being childish
or clinical. Think handsome stationery or a well-designed card game, not a
classroom poster and not a sterile fintech app.

Three words to hold in mind for every asset: **warm, legible, satisfying**.

### 1.2 Mood & Tone

- **Calm, not flat.** Slight material warmth (paper, felt) without realism noise
  or skeuomorphic complexity. A card feels like a card; the table feels like a
  table. Keep it composed and gentle.
- **Neutral, not childish.** No cartoon outlines, no mascots, no primary-color
  flag-waving. The reference register is a puzzle-box product for adults: Oink
  Games, Helvetiq, Reiner Knizia editions.
- **Tactile, not glossy.** Prefer matte texture suggestion (subtle grain, soft
  shadow) over specular highlights or plastic shine. Depth comes from layering
  and shadow, not from glass effects.
- **Math is elegant, not scary.** Numerals are the hero content; treat them with
  typographic pride. Generous spacing, high contrast, round-but-purposeful
  letterforms.

### 1.3 Shape Language

| Element | Language |
|---|---|
| Cards | Softly rounded corners (radius ~8–10 px at @1x). Portrait rectangle. |
| Stack frames | Matching card corner radius; slightly bolder visual weight than cards. |
| Discard slots | Smaller version of the card shape; clearly subordinate. |
| Buttons (primary) | Large, chunky pill or rounded rect. Solid fill, subtle bottom-edge border for pseudo-3D lift. |
| Buttons (icon/tool) | Square tile with rounded corners, matching discard-slot family. |
| Panels / modals | Large rounded rect (r ~20–24 px @1x), soft drop shadow at 10 px blur, 45% black. |
| Icons / glyphs | 3 pt stroke (at 24 pt source), rounded caps and joins, white-on-transparent. No fills. |

### 1.4 Color Palette

The palette is split into three layers: **brand neutrals** (backgrounds, surfaces),
**action colors** (primary interactive elements), and **semantic colors** (feedback,
game state). All stacks use the Okabe-Ito colorblind-safe palette from
`data/stack_palette.gd`; do not introduce alternative stack colors.

#### Brand Neutrals

| Role | Name | Hex | Notes |
|---|---|---|---|
| Table / background | Warm Slate | `#BDCCEE` | Current `main.tscn` background `Color(0.74, 0.80, 0.93)` — keep or refine toward warmer. Felt texture optional layer. |
| Card face | Cream | `#F7EFD9` | Warm off-white. Matches `result_screen.gd` `_CARD_BG Color(0.97, 0.94, 0.87)`. |
| Card back (future) | Sand | `#E8D9B4` | Slightly deeper than face; distinguishable but in-family. |
| Panel background | Cream | `#F7EFD9` | Same as card face; panels are card-family objects. |
| Panel header strip | Calm Blue | `#4585C7` | Matches `pause_menu.gd _HEADER_TINT Color(0.16, 0.45, 0.78)`. |
| HUD background | Transparent | — | HUD floats over the table; no separate bg block. |
| Discard slot (normal) | Cool Grey | `#C7CCDF` | Matches `discard_row.gd _NORMAL_TINT Color(0.78, 0.80, 0.88)`. |
| Discard slot (warning) | Warm Coral | `#FF8C8C` | Matches `discard_row.gd _WARNING_TINT Color(1.0, 0.55, 0.55)`. |

#### Action Colors

| Role | Name | Hex | Notes |
|---|---|---|---|
| Primary CTA (win/claim) | Success Green | `#4DC957` | `result_screen.gd _GREEN Color(0.30, 0.78, 0.34)`. |
| Primary CTA deep | Success Green Deep | `#34943D` | Bottom-edge border of CTA button. |
| Star / gold accent | Warm Gold | `#FFCC1F` | `result_screen.gd _GOLD Color(1.0, 0.80, 0.12)`. |
| Star deep | Gold Deep | `#D9940D` | `_GOLD_DEEP Color(0.85, 0.58, 0.05)`. |
| Destructive / danger | Vermillion | `#E74D4D` | `result_screen.gd _RED Color(0.90, 0.27, 0.27)`. |
| Booster tile (affordable) | Warm Ivory | `#FFF5E6` | `hud.gd _TILE_AFFORD Color(1.0, 0.96, 0.90)`. |
| Booster tile (blocked) | Blue-Grey | `#BCC4D4` | `hud.gd _TILE_BLOCKED Color(0.74, 0.77, 0.83)`. |
| Booster glyph | Ink | `#333856` | `hud.gd _GLYPH_AFFORD Color(0.20, 0.24, 0.34)`. |
| Header / level badge | Sky Blue | `#4585C7` | Panel header. |
| Progress / completion | Round Blue | `#4585C7` | Reuses header blue for consistency. |

#### Stack Colors (Okabe-Ito, from `data/stack_palette.gd`)

These are the single source of truth for stack differentiation. Do not use these
hues for any other UI purpose — protect their semantic meaning.

| Stack index | Role | Hex |
|---|---|---|
| 0 | Blue | `#0072B2` |
| 1 | Orange | `#E69F00` |
| 2 | Bluish-Green | `#009E73` |
| 3 | Vermillion | `#D55E00` |

Default (non-colorblind) palette uses pre-colored Kenney slot assets (red /
yellow / green / blue) with white tint. The Okabe-Ito hues above are used as
`self_modulate` tints over a neutral grey slot in colorblind mode. The bespoke
stack frame asset must be the **neutral grey** version; tinting happens in code.

#### Semantic / Feedback Colors

| State | Color | Hex |
|---|---|---|
| Ink / dark text | Deep Navy | `#1E2438` |
| Covered card dim | — | White at 60% opacity (`Color(0.6, 0.6, 0.66)` — code-applied) |
| Locked stack | Lock Green | `#66C757` |
| Confetti burst | Multicolor | Pink `#FF526B`, Sky `#4DB3FF`, Amber `#FFD933`, Mint `#66D973` |

### 1.5 Typography Direction

Typography is handled in-engine (Godot `Label` + `Theme`). The asset team
**does not need to ship fonts**, but must ensure:

1. Numeral glyphs on card faces and stack labels are sized for legibility at
   minimum rendered size. The smallest card on screen is 40×51 px (discard
   slot scale); numerals at that size must still be distinguishable.
2. The chosen project font must have a **tabular numeral set** (fixed advance
   width per digit) so two-digit numbers in stack frames don't cause jitter.
3. If a custom font is introduced, deliver it as `.otf` or `.ttf`, not bitmap.
4. Dyslexia-friendly font is a toggle (Phase 2); design the card face to
   accommodate a different font rendering the same numeral strings.

---

## 2. Delivery Standards

### 2.1 Source Format

| Asset category | Source format | Rationale |
|---|---|---|
| Icons, glyphs, UI chrome (buttons, frames, slots) | **SVG** | Resolution-independent; export to any density bucket from one source; scales cleanly for large-text mode. |
| Card face / back raster art | **PNG** (exported from layered PSD/Affinity) | Raster detail (grain, paper texture) is intentional; export at @3x master, derive @2x and @1x via downscale. |
| Background / table felt | **PNG** tileable texture | Seamless 256×256 @2x tile; engine tiles it across the 390×844 surface. |
| App icon | **PNG** per store size | See §3 App Icon row; no SVG submission to stores. |
| Particle textures | **PNG** power-of-two sheets | Engine `CPUParticles2D`/`GPUParticles2D` compatible. |
| Splash screen | **PNG** | Store guidelines dictate raster; deliver at native resolution. |

### 2.2 Density Buckets and Export Scale

Base viewport is **390×844 dp** (device-independent pixels). The game uses
`canvas_items` stretch with `expand` aspect, meaning the 390×844 logical canvas
scales up to fill the physical screen. Physical pixel density varies:

| Bucket | Density | Scale factor | Physical resolution |
|---|---|---|---|
| @1x (mdpi) | ~160 dpi | 1.0 | 390×844 px |
| @2x (xhdpi) | ~320 dpi | 2.0 | 780×1688 px |
| @3x (xxhdpi) | ~480 dpi | 3.0 | 1170×2532 px |

**Delivery rule:** provide **@3x PNG** as the master for all raster assets.
Godot's import system will downsample; the @1x and @2x derivatives are
generated. For assets that need to be sharp at specific engine-rendered sizes,
also export @1x and @2x named variants with the `_2x` / `_3x` suffix omitted
(Godot loads by resolution override in import settings).

For **SVG** sources: deliver one SVG per icon; Godot imports SVGs at a
configurable render scale. Set import render scale to 3.0 (192 dpi equivalent)
in `res://assets/ui/icons/*.svg.import` files. The technical artist owns import
settings.

### 2.3 Color Space and Transparency

- All textures: **sRGB, 8-bit per channel** (PNG32 with alpha where transparency
  is needed; PNG24 for fully opaque backgrounds).
- Do **not** pre-multiply alpha — Godot handles straight alpha correctly with the
  Mobile renderer.
- Export profiles: Affinity/Photoshop → sRGB IEC61966-2.1, no embedded color
  profile in the final PNG (strip ICC profile on export to keep file size lean on
  low-end Android).

### 2.4 Nine-Slice / Nine-Patch Rules

Nine-patch assets stretch in Godot using `NinePatchRect`. Every panel, button
frame, slot, and card must be nine-patchable. Current Kenney margin is **16 px**
at the Kenney source resolution. The bespoke set must specify margins explicitly.

| Asset family | Recommended 9-slice margin (at @1x) |
|---|---|
| Card face / back | 10 px all sides (corner radius ~8 px plus 2 px bleed) |
| Stack frame | 12 px all sides |
| Discard slot (small) | 8 px all sides |
| Panel / modal frame | 20 px all sides |
| Primary button | 16 px all sides |
| Booster tile | 12 px all sides |
| Round button (settings gear, audio toggles) | 26 px all sides (circular; center 1×1 stretch zone) |

Deliver nine-patch source such that the **corner decoration** (shadow, border
bevel) is wholly inside the margin region. The 1×1 center stretch zone must be a
flat fill; no detail in the stretch zone.

### 2.5 Naming Convention

All assets follow: `[category]_[name]_[variant]_[size].[ext]`

| Segment | Rules |
|---|---|
| `category` | `card`, `stack`, `discard`, `env`, `ui`, `vfx`, `icon`, `char` |
| `name` | snake_case descriptor |
| `variant` | state or style: `normal`, `hover`, `pressed`, `disabled`, `colorblind`, `back`, `front` |
| `size` | `sm`, `md`, `lg`, `xl`, or omit for single-size assets |

Examples:
```
card_face_normal.png
card_face_back.png
stack_frame_normal.png
ui_btn_primary_normal.png
ui_btn_primary_pressed.png
icon_booster_picker.svg
icon_booster_reshuffle.svg
icon_coin_sm.svg
icon_coin_unavailable_sm.svg
env_felt_tile.png
vfx_confetti_sheet.png
ui_panel_modal.png
ui_progress_bar_fill.png
```

Files land in `assets/ui/` (UI/game chrome) or `assets/ui/icons/` (glyphs and
small icons). VFX sheets live in `assets/vfx/` (directory to be created by
technical artist when VFX work begins).

### 2.6 Padding, Safe Area, and Notch

The 390×844 base viewport is the **content area** (notch and navigation bar
excluded at the device layer). Godot's `expand` aspect mode may letterbox or
pillarbox on non-16:9 devices.

**Safe area rule for HUD:** all interactive chrome (buttons, labels) must sit
inside a **20 px margin** from the logical viewport edge. Current code positions
the gear button at `Vector2(12, 12)` — bespoke art should allow for a 12–20 px
safe zone on any side.

**Bottom booster tray:** positioned at y=738 in the 844 dp viewport — 106 dp
from bottom. This is safe above the home-bar region on modern Android/iOS.
Deliver booster tile art that reads clearly against the table felt background
without a contrasting background band (the tray has no background panel by
design).

### 2.7 Godot Import Notes

These are guidance for the technical artist wiring import settings; included here
so artists understand the constraints their source files must meet.

| Setting | Value | Rationale |
|---|---|---|
| Texture filter | **Nearest** for pixel-precise UI; **Linear** for smooth photo-like art | Cards and slots are crisp geometric shapes — use Nearest. Felt texture background may use Linear. |
| Mipmaps | **Off for all UI assets** | Mipmaps cause blurring artifacts on UI at non-power-of-two display scales; the Mobile renderer does not mipmap UI by default. |
| Compress mode | **Lossless (PNG)** for UI; **VRAM Compressed (ETC2/ASTC)** for environment textures | Lean memory on low-end Android; ASTC preferred for iOS. The technical artist decides per-import; artists deliver PNG masters. |
| Atlas / sprite sheet | Prefer atlasing all small UI glyphs and icons into one texture | Batches draw calls; one material per atlas. Group by use: one atlas for game-play chrome (card, stack, discard, dot), one atlas for HUD icons. Coordinate with technical artist. |
| SVG render scale | 3.0 (192 dpi equivalent) | Matches @3x physical pixel density target. |

---

## 3. Master Asset Table

Pixel dimensions below are **@1x logical pixels** (390×844 viewport space). All
raster assets must be delivered at @3x (multiply each dimension by 3) unless
noted.

Phases map to the roadmap in `docs/GAME_PLAN.md §4`:
- **P0** = Phase 0 / M1 — ship-blocking (currently using Kenney placeholders)
- **P1** = Phase 1 / M2 — Game Feel & Content
- **P2** = Phase 2 / M3 — Meta & Retention
- **P3** = Phase 3 / M4 — Monetization & Live Ops

---

### 3.1 Cards

Cards are the primary interactive element. Numeral legibility is a non-negotiable
accessibility requirement at all rendered sizes (72×96 px floor card down to
40×51 px discard miniature).

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `card_face_normal.png` | Exposed (tappable) card face — empty center for engine-rendered numeral label | 72×96 px | PNG @3x | 10 px all sides | Warm cream `#F7EFD9` surface; subtle paper grain optional; soft inner shadow ~2 px. Corner radius ~8 px. Center area must be flat (label renders over it). | P0 |
| `card_face_covered.png` | Covered (inert) card face | 72×96 px | PNG @3x | 10 px all sides | Same shape as normal; engine applies `Color(0.6, 0.6, 0.66)` modulate in code — do not pre-darken. Deliver identical to normal; code handles dim state. Alternative: omit and use modulate only. | P0 |
| `card_face_back.png` | Card back (used when cards are face-down in future modes) | 72×96 px | PNG @3x | 10 px all sides | Pattern or motif on Sand `#E8D9B4`; no numerals. Phase 1 cosmetic unlock candidate. | P1 |
| `card_shadow.png` | Drop shadow beneath floor card pile — ambient occlusion of the stack | ~80×104 px | PNG @3x, no 9-slice | None | Soft ellipse or diffuse blob; black at ~30% alpha, feathered 6–8 px. Engine composite under card layer. Optional: may be drawn in shader. | P1 |

**Card numeral specifications (for font/theme selection — not a raster deliverable):**
- Exercise text (e.g. `3 + 4`): 20 sp in-engine, color `#1A1F33` (`Color(0.10, 0.12, 0.20)`).
- Result text when stacked (e.g. `7`): 30 sp in-engine.
- Stack target label: 34 sp, white with 6 px deep navy outline.
- All numeral labels must remain legible when card is at discard scale (40×51 px rendered).

---

### 3.2 Stacks and Stack Frames

Four stacks sit at the top of the play area (y=112 px, x positions: 14, 108, 202, 296 px).
Each stack frame is card-sized (72×96 px). The frame is tinted by code using
`StackPalette`; deliver **one neutral grey master** that tints cleanly.

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `stack_frame_normal.png` | Stack slot frame — neutral grey master | 72×96 px | PNG @3x | 12 px all sides | Neutral `#ABABBA` fill. Corner radius matches card. Slightly heavier border than card (2–3 px inner stroke) to read as a "destination". The engine tints this with Okabe-Ito colors or Kenney slot colors via `self_modulate`. |  P0 |
| `stack_dot_empty.png` | Capacity indicator dot — unfilled | 16×16 px | PNG @3x | None | Open circle, 2 px stroke, neutral grey. Replaces `kenney/dot_empty.png`. | P0 |
| `stack_dot_full.png` | Capacity indicator dot — filled | 16×16 px | PNG @3x | None | Solid circle, same color family as dot_empty but filled. Replaces `kenney/dot_full.png`. | P0 |
| `stack_frame_locked.png` | Locked stack overlay (prototype locked-decks) | 72×96 px | PNG @3x | 12 px all sides | Same shape as normal; engine applies `_LOCK_GREEN Color(0.40, 0.78, 0.34)` tint. Deliver same neutral master; optionally add a subtle lock-icon watermark centered. | P2 |

---

### 3.3 Discard Slots

Discard slots are smaller card-family shapes (40×51 px). Up to 7 slots rendered
in a centered row at y=240 px. Slots scale-down from the card shape using
`fly_to` tween scale argument in code.

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `discard_slot_normal.png` | Discard slot frame — normal state | 40×51 px | PNG @3x | 8 px all sides | Cool grey `#C7CCDF` fill; same corner radius family as card but smaller. Engine tints warning state to `#FF8C8C`. Deliver neutral; code handles tint. Replaces `kenney/slot_grey.png` at this size. | P0 |

Note: cards in discard slots are the same `card_face_normal.png` scaled to
~0.56× by the engine's `fly_to` `target_scale` parameter. No separate card art
is needed for the discard state.

---

### 3.4 Floor / Table Environment

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `env_felt_tile.png` | Seamless background table felt texture | 256×256 px | PNG @2x (512×512), tileable | None | Subtle woven felt or linen grain. Base color warm slate `#BDCCEE`. Seamless on all four edges. Engine tiles across 390×844. Low-contrast grain (must not compete with card numerals). | P1 |
| `env_felt_tile_dark.png` | Dark/evening table theme variant | 256×256 px | PNG @2x, tileable | None | Phase 2 cosmetic unlock. Same seamless spec; deeper, moodier base. | P2 |

---

### 3.5 HUD Elements

HUD floats in a `CanvasLayer` (layer 10) over the board. Key positions in the
390×844 viewport: gear button at `Vector2(12,12)`, level badge at `Vector2(155,16)`
80×42 px, completion circle at `Vector2(322,10)` 58×58 px, booster tray at y=738.

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_btn_gear_bg.png` | Settings gear button background — circular tile | 60×60 px | PNG @3x | 26 px (circular) | Round shape; neutral to slight warm tint. Currently `kenney/round_grey.png`. | P0 |
| `icon_gear.svg` | Gear / settings glyph | 30×30 px SVG source | SVG | None | White-on-transparent; 3 pt stroke; rounded teeth. Replaces `kenney/gear.png`. Color `#4D568A` (`Color(0.30, 0.34, 0.46)`) applied as modulate in code. | P0 |
| `ui_badge_level.png` | Level number badge background | 80×42 px | PNG @3x | 18 px all sides | Rounded rect; green fill `#4DC957`. Houses engine `Label` "LVnn". | P0 |
| `ui_badge_progress.png` | Completion % circular badge | 58×58 px | PNG @3x | 26 px (circular) | Round shape; calm blue `#4585C7`. Houses engine `Label` "nn%". | P0 |
| `icon_coin_sm.svg` | Coin glyph — small (HUD balance + booster cost badge) | 18×18 px SVG source | SVG | None | Gold circle with inner ring; 2 pt stroke; no fill (ring only or flat gold disc). Replaces `assets/ui/icons/coin_sm.svg`. | P0 |
| `icon_coin_unavailable_sm.svg` | Coin glyph + diagonal X (booster unaffordable state) | 18×18 px SVG source | SVG | None | Same coin base; add 2 pt diagonal X stroke in vermillion `#E74D4D`. Replaces `assets/ui/icons/coin_unavailable_sm.svg`. | P0 |

---

### 3.6 Booster Icons

Three booster glyphs for the HUD tray. See `design/ux/booster-icons.md` for the
full interaction spec including states, accessibility, and metaphors. Art
direction input: these must match the Kenney flat/geometric register — no
shadows, no gradients, 3 pt stroke at 24 pt source.

| Asset name | Description | @1x glyph area | Export | Notes | Phase |
|---|---|---|---|---|---|
| `icon_booster_picker.svg` | Picker booster — finger/pointer descending through 3 horizontal layer bars | 24×24 px SVG source | SVG | White-on-transparent; bars are short horizontal lines (mid-width), not discard slots; pointer is a simple downward finger tip. Replaces `assets/ui/icons/booster_picker.svg`. | P0 |
| `icon_booster_reshuffle.svg` | Reshuffle booster — 270° circular arrow with 3 small dots inside | 24×24 px SVG source | SVG | White-on-transparent; universal shuffle metaphor; 3 dots = cards being repositioned. Replaces `assets/ui/icons/booster_reshuffle.svg`. | P0 |
| `icon_booster_extra_discard.svg` | Extra Discard Slot — single slot-shaped frame + bold "+" | 24×24 px SVG source | SVG | White-on-transparent; slot frame echoes discard slot family; "+" is visually dominant (bold, centered). Replaces `assets/ui/icons/booster_extra_discard.svg`. | P0 |

The booster tile frame is `discard_slot_normal.png` (or a square variant
`ui_booster_tile.png` at 72×72 px for the tray). Current code uses
`kenney/slot_grey.png` nine-patched at 72×72 px with warm/cool tint modulate.
The bespoke tile should be a slightly larger square version of the discard-slot
shape.

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_booster_tile.png` | Square booster button tile frame | 72×72 px | PNG @3x | 12 px all sides | Neutral grey, same visual family as `discard_slot_normal`. Engine applies `_TILE_AFFORD` warm ivory or `_TILE_BLOCKED` blue-grey modulate. | P0 |

---

### 3.7 Buttons — Primary, Secondary, Icon

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_btn_primary_normal.png` | Primary CTA button — normal state | 300×66 px | PNG @3x | 16 px all sides | Chunky rounded rect; success green `#4DC957` fill; 5 px bottom-edge border `#34943D` for lift effect. Text rendered by engine. | P0 |
| `ui_btn_primary_pressed.png` | Primary CTA button — pressed state | 300×66 px | PNG @3x | 16 px all sides | Flat (no bottom border); slightly darker fill. | P0 |
| `ui_btn_secondary_normal.png` | Secondary / danger button (retry, home, close) | 180×56 px | PNG @3x | 16 px all sides | Same shape; vermillion `#E74D4D` fill for danger; gold `#FFCC1F` for retry. Deliver color variants named `_red` and `_gold`. | P0 |
| `ui_btn_secondary_pressed.png` | Secondary pressed | 180×56 px | PNG @3x | 16 px all sides | Flat / deeper color. | P0 |
| `ui_btn_round_normal.png` | Round button (audio toggles) | 66×66 px | PNG @3x | 30 px all sides | Circle; delivered as neutral grey master; engine tints `_ON_TINT` green or `_OFF_TINT` grey. | P0 |
| `ui_btn_close_normal.png` | Close / X button — round, red | 44×44 px | PNG @3x | 20 px all sides | Same round shape; engine tints red. May reuse `ui_btn_round_normal.png`. | P0 |

---

### 3.8 Panels, Dialogs, and Modal Frames

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_panel_modal.png` | General modal / dialog card (result screen, pause menu) | 336×416 px (notional; 9-slice makes this stretchable) | PNG @3x | 20 px all sides | Cream `#F7EFD9` fill; ~22 px corner radius; 10 px drop shadow 45% black. | P0 |
| `ui_panel_header.png` | Modal header strip (rounded top only, flat bottom) | 336×64 px | PNG @3x | 22 px top, 0 px bottom | Calm blue `#4585C7` fill; top corners match modal. Engine composes header over modal body. | P0 |
| `ui_panel_pill_track.png` | Toggle switch track (pill shape) | 58×30 px | PNG @3x | 14 px all sides | Rounded rect / pill. Engine tints green (on) or grey (off). | P0 |
| `ui_btn_pill_knob.png` | Toggle switch knob (circular) | 26×26 px | PNG @3x | 10 px all sides | Solid circle; white fill. Engine slides it left/right. | P0 |

---

### 3.9 Win / Result Screen Elements

See `scenes/ui/result_screen.gd` for layout; see `design/art/ux-asset-inventory.md`
for screen-state enumeration.

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_star_hero.svg` | Large celebratory star (win screen) | 140×140 px SVG source | SVG | None | Warm gold `#FFCC1F`; engine renders two layers (soft glow at 22% alpha behind crisp foreground). Deliver flat gold star shape; glow layer applied by engine via alpha modulate. | P0 |
| `ui_star_rating_full.svg` | 1–3 star efficiency rating — filled star | 36×36 px SVG source | SVG | None | Warm gold. M2 asset (scoring). | P1 |
| `ui_star_rating_empty.svg` | 1–3 star efficiency rating — empty star | 36×36 px SVG source | SVG | None | Cool grey outline. M2 asset. | P1 |

---

### 3.10 Currency Icons

| Asset name | Description | @1x dimensions | Export | Notes | Phase |
|---|---|---|---|---|---|
| `icon_coin_lg.svg` | Coin — large (shop, economy UI) | 48×48 px SVG source | SVG | Same design language as `icon_coin_sm.svg` but at larger display size with more detail if desired. | P2 |
| `icon_gem_sm.svg` | Gem / hard currency — small (HUD, cost badges) | 18×18 px SVG source | SVG | Hard currency gem; distinct shape from coin (diamond facet vs round disc). Warm amethyst or teal; not pink/childish. | P2 |
| `icon_gem_lg.svg` | Gem — large (shop, IAP offer surfaces) | 48×48 px SVG source | SVG | Same gem; larger detail. | P3 |

---

### 3.11 Progress Bars and XP

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_progress_bar_bg.png` | XP / progress bar background track | 300×18 px | PNG @3x | 8 px horizontal, 4 px vertical | Neutral grey rounded pill. 9-slice so it stretches to any width. | P2 |
| `ui_progress_bar_fill.png` | XP / progress bar fill layer | 300×18 px | PNG @3x | 8 px horizontal, 4 px vertical | Warm gold `#FFCC1F` or success green, depending on context. Stretches over the bg track. | P2 |

---

### 3.12 World Map and Level Nodes

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_map_node_locked.png` | World map level node — locked state | 48×48 px | PNG @3x | None | Circular or rounded square; subdued grey fill; padlock icon or no number visible. | P2 |
| `ui_map_node_available.png` | World map level node — available state | 48×48 px | PNG @3x | None | Full warm color; level number label rendered by engine. | P2 |
| `ui_map_node_complete_1star.png` | Completed node — 1 star | 48×48 px | PNG @3x | None | Checkmark or 1-star fill variation. | P2 |
| `ui_map_node_complete_3star.png` | Completed node — 3 stars | 48×48 px | PNG @3x | None | Gold, all three star dots lit. | P2 |
| `env_map_path.png` | Dotted path connecting world map nodes | Tileable segment ~24×24 px | PNG @3x | None | Neutral warm dots or dashes; engine tiles between node positions. | P2 |
| `env_map_bg_world_01.png` | World map background — World 1 (Addition) | 390×844 px | PNG @2x | None | Calm illustrated environment (desk surface, library, garden — warm, adult). One per world. Full-screen raster. | P2 |

---

### 3.13 Daily / Streak / Achievement Badges

| Asset name | Description | @1x dimensions | Export | Notes | Phase |
|---|---|---|---|---|---|
| `icon_badge_daily.svg` | Daily challenge badge | 40×40 px SVG source | SVG | Calendar or sun motif; warm gold accent. | P2 |
| `icon_badge_streak_sm.svg` | Streak counter icon | 24×24 px SVG source | SVG | Flame or chain link; vermillion `#E74D4D`. | P2 |
| `icon_badge_achievement.svg` | Achievement unlock badge frame | 56×56 px SVG source | SVG | Hexagon or shield; gold-accent border; achievement art layered inside by engine. | P2 |

---

### 3.14 IAP / Shop and Ad Surfaces

These assets must comply with ADR-0005 (13+ positioning). No cartoon mascots, no
urgency-panic visuals. Calm value proposition; think typographic product packaging.

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_shop_banner_remove_ads.png` | "Remove Ads" IAP offer banner | 358×88 px | PNG @3x | 16 px all sides | Calm blue or warm neutral; concise headline area (engine renders text); subtle star or sparkle accent only. | P3 |
| `ui_shop_bundle_sm.png` | Currency / bundle offer card | 160×200 px | PNG @3x | 16 px all sides | Product-card style; price tier rendered by engine. | P3 |
| `ui_shop_gem_pile_sm.png` | Gem pile illustration for currency pack tiers | 80×80 px | PNG @3x | None | Small product illustration; 3 size variants (sm/md/lg for tier differentiation). | P3 |
| `ui_ad_placeholder_banner.png` | Banner ad placeholder zone marker (non-gameplay screens) | 390×60 px | PNG @1x | None | Neutral grey zone with "Ad" label — placeholder only; replaced at runtime by ad SDK. Deliver for design/layout reference. | P3 |

---

### 3.15 Settings UI — Toggles, Sliders, Checkboxes

Current pause menu builds toggle UI in code from `kenney/slot_grey.png` and
`kenney/round_grey.png`. Bespoke versions:

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_toggle_track.png` | Settings pill toggle track | 58×30 px | PNG @3x | 14 px all sides | Reuses `ui_panel_pill_track.png` — same asset. Engine tints for on/off. | P0 |
| `ui_toggle_knob.png` | Settings pill toggle knob | 26×26 px | PNG @3x | 10 px all sides | Reuses `ui_btn_pill_knob.png`. | P0 |
| `ui_slider_track.png` | Settings slider track | 260×12 px | PNG @3x | 6 px horizontal, 0 vertical | Pill-shaped track; neutral grey. | P2 |
| `ui_slider_thumb.png` | Settings slider thumb | 28×28 px | PNG @3x | 12 px all sides | Round thumb; warm ivory or white. | P2 |

---

### 3.16 Tutorial / Coach Overlay

| Asset name | Description | @1x dimensions | Export | 9-slice margins | Notes | Phase |
|---|---|---|---|---|---|---|
| `ui_coach_arrow.svg` | Tutorial coach pointing arrow | 48×48 px SVG source | SVG | None | Solid curved or straight arrow; warm gold or white; no outline. Animated by engine (bounce tween). | P0 |
| `ui_coach_bubble.png` | Tutorial speech / instruction bubble | 280×80 px notional | PNG @3x | 16 px all sides | Rounded rect with optional pointer nub; cream fill. Engine renders text inside. 9-slice on all sides; nub is in the stretch zone — design it flush or add nub as a separate element. | P0 |

---

### 3.17 VFX Particle Textures

VFX are `CPUParticles2D` systems in code (see `result_screen.gd _add_confetti`
and `juice_service.gd`). Particle textures need to be simple, power-of-two.
Shader-driven VFX coordinates with the technical artist.

| Asset name | Description | @1x dimensions | Export | Notes | Phase |
|---|---|---|---|---|---|
| `vfx_confetti_sheet.png` | Confetti particle shapes — rectangle chips in 4 colors | 64×64 px sheet (4×1 grid, each cell 16×16 px) | PNG @2x (128×128 px), POT | Colors: pink `#FF526B`, sky `#4DB3FF`, amber `#FFD933`, mint `#66D973`. Engine `color_initial_ramp` picks per-particle. Current confetti uses `CPUParticles2D` point particles; this replaces the point with a chip shape. | P0 |
| `vfx_sparkle_sm.png` | Stack-clear sparkle / burst particle | 16×16 px | PNG @2x (32×32 px), POT | 4-point star or soft circle; white, feathered. JuiceService uses this on clear events. | P1 |
| `vfx_burst_ring.png` | Stack-clear ring pulse — single frame | 64×64 px | PNG @2x (128×128 px), POT | Thin ring, white-to-transparent. Engine scales it from 0→1.5× with fade; pairs with a shader if the technical artist adds one. | P1 |

---

### 3.18 App Icon and Store Assets

Store submission requires platform-specific sizes. Deliver only the sizes below;
do not crop or letterbox — each size must be a purpose-drawn or carefully scaled
version.

| Asset name | Description | Dimensions | Export | Notes | Phase |
|---|---|---|---|---|---|
| `icon_app_android_512.png` | Google Play store icon | 512×512 px | PNG24 (no alpha) | No rounded corners — Play applies its own corner mask. Warm card motif; large legible "=" or arithmetic symbol optional; must read at 48×48 px thumbnail. | P0 |
| `icon_app_ios_1024.png` | App Store icon | 1024×1024 px | PNG24 (no alpha) | No rounded corners (iOS applies mask). Same design language; slightly more detail than Android version acceptable. | P0 |
| `icon_adaptive_fg.png` | Android adaptive icon — foreground layer | 108×108 px (safe zone 72×72 px centered) | PNG32 (with alpha) | Foreground motif (card + numeral) must be fully inside the 72×72 safe zone; outer 18 px on each side may clip. | P0 |
| `icon_adaptive_bg.png` | Android adaptive icon — background layer | 108×108 px | PNG24 (no alpha) | Solid warm slate or felt pattern. Must tile/fill without visible seam on any adaptive mask shape (circle, squircle, square). | P0 |
| `icon_notification_android.png` | Android notification icon (system tray) | 24×24 dp → deliver 96×96 px (@4x xxhdpi) | PNG8 or PNG24, single color white | White on transparent; silhouette only (Android system colorizes). Simple card or "=" silhouette. | P2 |

---

### 3.19 Splash Screen

| Asset name | Description | Dimensions | Export | Notes | Phase |
|---|---|---|---|---|---|
| `splash_android.png` | Android launch image | 1080×1920 px (portrait) | PNG24 | Centered logo/card motif on warm slate background; must look composed at both 16:9 and 19.5:9 aspect ratios. Keep primary content within 390×844 dp center zone. | P0 |
| `splash_ios.png` | iOS launch storyboard placeholder | 1242×2688 px (iPhone 15 Pro Max native) | PNG24 | Engine generates launch screen from project settings; deliver at this size as master, team crops per device class. | P0 |

---

## 4. Priority / Phase Summary

### Phase 0 / M1 — Ship-Blocking (replace Kenney placeholders)

These are blocking for v1 submission. All currently use Kenney CC0 assets.

1. `card_face_normal.png` — the hero asset; everything else derives from it
2. `stack_frame_normal.png` + `stack_dot_empty.png` + `stack_dot_full.png`
3. `discard_slot_normal.png`
4. `ui_booster_tile.png` + three booster SVGs + coin SVGs
5. `ui_btn_gear_bg.png` + `icon_gear.svg`
6. `ui_badge_level.png` + `ui_badge_progress.png`
7. `ui_btn_primary_normal/pressed.png` + `ui_btn_secondary_normal/pressed.png` (result screen)
8. `ui_panel_modal.png` + `ui_panel_header.png`
9. `ui_toggle_track.png` + `ui_toggle_knob.png` (pause menu)
10. `ui_star_hero.svg` (win screen)
11. `ui_coach_arrow.svg` + `ui_coach_bubble.png` (tutorial)
12. `vfx_confetti_sheet.png`
13. `icon_app_android_512.png` + `icon_app_ios_1024.png` + adaptive icon layers + splash screens

### Phase 1 / M2 — Game Feel & Content

1. `card_face_back.png` + `card_shadow.png`
2. `env_felt_tile.png` (background texture)
3. `ui_star_rating_full.svg` + `ui_star_rating_empty.svg`
4. `vfx_sparkle_sm.png` + `vfx_burst_ring.png`
5. `stack_frame_locked.png` variant

### Phase 2 / M3 — Meta & Retention

1. All world map assets (`ui_map_node_*.png`, `env_map_path.png`, `env_map_bg_world_01.png`)
2. Daily / streak / achievement badges
3. `icon_coin_lg.svg` + `icon_gem_sm.svg` + `icon_gem_lg.svg`
4. `ui_progress_bar_bg/fill.png`
5. `ui_slider_track/thumb.png`
6. `env_felt_tile_dark.png` (cosmetic unlock)
7. `icon_notification_android.png`

### Phase 3 / M4 — Monetization & Live Ops

1. All shop / IAP surfaces (`ui_shop_banner_remove_ads.png`, `ui_shop_bundle_sm.png`, `ui_shop_gem_pile_sm.png`)
2. Ad placeholder zone `ui_ad_placeholder_banner.png`

---

## 5. Handoff Checklist (per batch)

Before marking any asset batch as delivered, the artist must confirm:

- [ ] All raster PNGs delivered at @3x (logical px × 3)
- [ ] SVG sources included alongside any reference exports
- [ ] Nine-slice margins documented in the filename or a `_margins.txt` companion file per batch
- [ ] Color space: sRGB, no embedded ICC profile
- [ ] No pre-multiplied alpha
- [ ] File names match the snake_case naming convention exactly
- [ ] Files placed in `assets/ui/` (chrome/frames), `assets/ui/icons/` (glyphs), or `assets/vfx/` (particles)
- [ ] No single-purpose raster textures smaller than 32×32 px — use SVG instead
- [ ] Art director sign-off on numeral legibility (card face reviewed at 40×51 px on-device or in-editor)
- [ ] Colorblind check: stack frame tints reviewed with all four Okabe-Ito colors applied

---

*This spec sheet is owned by the Art Director and updated as new asset categories
are defined by the UX and game design teams. Reference `design/art/ux-asset-inventory.md`
for per-screen state enumeration before commissioning any screen-specific asset.*
