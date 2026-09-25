---
name: Onyx
description: A training log and body dashboard cut from one dark stone — near-black slabs on a lit black ground, one tinted thing per screen.
colors:
  onyx-base: "#000000"
  stone-slab: "#0B0B0E"
  text-primary: "#FFFFFFEB"
  text-secondary: "#FFFFFF9E"
  text-tertiary: "#FFFFFF66"
  hairline: "#FFFFFF14"
  slate-primary: "#6A7FAF"
  slate-secondary: "#C09A63"
  good-green: "#4CAF87"
  danger-red: "#E5484D"
  heart-red: "#E5484D"
  record-gold: "#FFD35C"
  effort-hard-amber: "#FBB359"
  effort-very-hard-clay: "#F38554"
  water-blue: "#4A9BD6"
  sleep-deep: "#4B4A8A"
  sleep-core: "#7B76B8"
  sleep-rem: "#B8B3E0"
  micro-orchid: "#D98BB3"
  muscle-chest: "#F66D64"
  muscle-lats: "#00D4CE"
  muscle-upper-back: "#00B6B0"
  muscle-lower-back: "#009894"
  muscle-front-delts: "#FF9F46"
  muscle-side-delts: "#E68100"
  muscle-rear-delts: "#C26C00"
  muscle-biceps: "#998BFF"
  muscle-triceps: "#0EA6FF"
  muscle-forearms: "#B49F00"
  muscle-quads: "#8AE171"
  muscle-hamstrings: "#76CC5C"
  muscle-glutes: "#61B647"
  muscle-adductors: "#4DA230"
  muscle-calves: "#388D15"
  muscle-abs-core: "#E66DB6"
typography:
  clock:
    fontFamily: "SF Pro Rounded, system-ui"
    fontSize: "34px"
    fontWeight: 600
    letterSpacing: "-0.03em"
    fontFeature: "tnum"
  hero:
    fontFamily: "SF Pro Rounded, system-ui"
    fontSize: "28px"
    fontWeight: 700
    letterSpacing: "-0.02em"
    fontFeature: "tnum"
  display:
    fontFamily: "SF Pro, system-ui"
    fontSize: "20px"
    fontWeight: 600
    letterSpacing: "-0.01em"
  body:
    fontFamily: "SF Pro, system-ui"
    fontSize: "17px"
    fontWeight: 400
    letterSpacing: "0em"
  secondary:
    fontFamily: "SF Pro, system-ui"
    fontSize: "15px"
    fontWeight: 400
    letterSpacing: "0em"
  caption:
    fontFamily: "SF Pro, system-ui"
    fontSize: "13px"
    fontWeight: 400
    letterSpacing: "0em"
  micro:
    fontFamily: "SF Pro, system-ui"
    fontSize: "11px"
    fontWeight: 600
    letterSpacing: "0.10em"
rounded:
  row: "12px"
  tile: "20px"
  sheet: "28px"
spacing:
  xs: "4px"
  s: "8px"
  m: "12px"
  l: "16px"
  xl: "24px"
  grid: "10px"
components:
  slab-tile:
    backgroundColor: "{colors.stone-slab}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.tile}"
    padding: "{spacing.m}"
  slab-row:
    backgroundColor: "{colors.stone-slab}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.row}"
    padding: "{spacing.m}"
  slab-sheet:
    backgroundColor: "{colors.stone-slab}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.sheet}"
    padding: "{spacing.xl}"
  chip:
    textColor: "{colors.text-secondary}"
    typography: "{typography.caption}"
    padding: "8px 12px"
    height: "44px"
  chip-prominent:
    backgroundColor: "{colors.slate-primary}"
    textColor: "{colors.onyx-base}"
    typography: "{typography.caption}"
    padding: "8px 12px"
    height: "44px"
  muscle-pill:
    textColor: "{colors.muscle-quads}"
    typography: "{typography.caption}"
    padding: "5px 10px"
  session-ticket:
    backgroundColor: "{colors.stone-slab}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.tile}"
    padding: "0 16px 0 12px"
    height: "64px"
  exercise-chip:
    backgroundColor: "{colors.stone-slab}"
    textColor: "{colors.text-primary}"
    typography: "{typography.caption}"
    rounded: "{rounded.tile}"
    padding: "6px 10px"
  body-ring:
    textColor: "{colors.text-primary}"
    typography: "{typography.hero}"
    size: "200px"
  body-petal:
    size: "44px"
---

# Design System: Onyx

## Overview

**Creative North Star: "The Cut Stone"**

Onyx is a slab of black stone held up to a low light. The ground is true OLED black lit from two off-screen corners by the theme's own hues; every surface on it is the same near-black slab, frosted underneath and bevelled with one lit top edge, like the app icon. Hierarchy is carried by material weight, type role and a single tinted thing per screen — not by borders, greys or shadows.

The system is dense and measured, because the product is numbers read standing up in a gym. Every figure is a rounded, tabular numeral that rolls rather than cross-fades; every colour that carries meaning (heart, water, sleep, records, muscles) is fixed across all eight themes so a legend learned once holds; everything else moves with the chosen stone. The theme is two hues, not a palette: all other accents are derived from them by hue rotation under a contrast guard.

Rejected, in the code's own words: a screen that "reads as a web app in a new font" (full-saturation accents on black, Tailwind-transliterated sizes), a rainbow of per-concept colours, "gradient header" panels, and a stack of equal stat cards where one instrument would do.

**Key Characteristics:**
- True black ground (`onyx-base`), lit by two chroma-clamped radials; flat black under Reduce Transparency.
- One material: the Stone slab — `.thinMaterial` + `stone-slab` at 78 % + a lit top-edge stroke, no drop shadow.
- Four domain accents (Train, Fuel, Body, Recover) derived from the theme's two hues; a screen belongs to exactly one.
- Fixed inks for meaning: heart red, water blue, the sleep ramp, record gold, good green, the sixteen-muscle anatomical palette.
- Type roles ARE Apple system text styles; Dynamic Type through AX5 with explicit fallbacks, never truncation of a name.
- Corners 12 / 20 / 28 by depth, continuous squircles, concentric insets.

## Colors

A black stone palette: desaturated theme accents for chrome, a small set of fixed hues that each mean one thing, and a louder categorical palette reserved for data.

### Primary
- **Slate Blue** (`slate-primary`): the default theme's primary (Slate preset, `OnyxThemeSpec.default`) — `OnyxInk.Themed.accent`, the Train domain's start stop, the selection ink, the readiness ring, the prominent chip's fill. Under any other preset this role is that preset's primary (Lagoon `#4F8FA0`, Sage `#6E9A80`, Iris `#8A73AE`, Clay `#B5705A`, Ochre `#B39250`, Moss `#7F8F4E`, Rosewood `#AC6886`; `OnyxTheme.presets`). Guarded to OKLCH L 0.60–0.78 so it holds ≥ 4.5:1 on black.

### Secondary
- **Worn Brass** (`slate-secondary`): the theme's secondary — the Fuel domain's start stop, the carbs/calories ink (weighted), and the bottom-right light of the ground.

### Tertiary
- **Derived domain stops**: Body and Recover accents, and all four domains' end stops, are the origin palette (`OnyxDomain.defaultDomainHex`, Ion `#6B78F0` / Solar `#E3A650` origin) rotated by the theme's hue delta, re-guarded (`OnyxThemeSpec.guarded` for accents, `.floored` L ≥ 0.60 for ends). They have no fixed hex; read them through `OnyxDomain.<domain>.accent / .start / .end / .at(t)`.

### Fixed meaning inks (`OnyxInk.Fixed`)
- **Heart Red** (`heart-red`): every heart-rate trace, Avg HR cell, the ticket's bpm figure and its 20 % spark wash. Same value as `danger-red` under its own name.
- **Water Blue** (`water-blue`): water, always, in every theme (6.95:1 on black).
- **Sleep Ramp** (`sleep-deep` → `sleep-core` → `sleep-rem` → awake = `text-secondary`): the night in order. Deep is 2.6:1 — a fill, never a text ink. REM lavender is also the Sleep petal's ink.
- **Record Gold** (`record-gold`): a personal record. Its one other job is a threshold (moderate soreness, fatigue 3, a peak block).
- **Good Green** (`good-green`): a delta the right way, a target met, battery ≥ the good cut.
- **Danger Red** (`danger-red`): destructive actions, validation failure, over-budget, battery below the low cut.
- **Effort Amber / Clay** (`effort-hard-amber`, `effort-very-hard-clay`): RPE bands, record gold walked toward heart red in Oklab (25 % / 60 %).
- **Muscle Palette** (`muscle-*`): sixteen landmarks in eight families, OKLCH L 0.70 / C 0.17, hue fixed per family and stepped in lightness; closest cross-family pair ΔE 22.8. Never themed. A family's colour is its middle landmark's.

### Weighted nutrition inks
- Protein (coral), carbs/calories (honey = the theme secondary), fat (lavender) and micros (`micro-orchid` under Slate) move by 35 % of the theme's hue shift, chroma ≤ 0.12, lightness kept (`OnyxThemeSpec.nutritionWeight`). Status on a nutrient still reads `good` / `danger`.

### Neutral
- **Onyx Black** (`onyx-base`): the ground. True black so OLED pixels are off and every slab reads as a real layer.
- **Stone Slab** (`stone-slab`): every surface, laid at 78 % over thin material (solid under Reduce Transparency).
- **Primary Ink** (`text-primary`, white 92 %): values, names, titles.
- **Secondary Ink** (`text-secondary`, white 62 %): meta lines, register labels, captions, the neutral verdict.
- **Tertiary Ink** (`text-tertiary`, white 40 %): unit suffixes, chevrons, a rest-day ring, a hollow petal. Fails 4.5:1 by design.
- **Hairline** (`hairline`, white 8 %): 0.5 pt only where content meets chrome; also the empty track of a ring.

### Named Rules
**The One Tinted Thing Rule.** Four domain accents, one per domain, and a screen belongs to exactly one. The accent tints the one thing that matters on it; the furniture stays ink.

**The Fixed Ink Rule.** The theme drives the accent, the Train ramp, selection, the domain mesh and (weighted) the nutrition inks. It never touches heart, water, sleep, good, record, effort or the sixteen muscles. If a colour carries a meaning, it is Fixed.

**The Gold Means Record Rule.** Record gold is the only fifth hue; seeing it means the number under it has never been beaten. Effort, supplements and warnings never borrow it.

**The Tertiary Is Never a Fact Rule.** 40 % ink is for what the reader loses nothing by missing. Never a value, never a control label, never the only copy of a fact — a rest day's label uses `dayLabel` (secondary), not the ring's tertiary.

**The No Raw Hex Rule.** Hexes live only in `OnyxTokens.swift` and `OnyxTheme.swift`; `TokenDisciplineTests` fails the build on a `0x` or `Color(red:` under `Features/`. A stored colour (a routine's accent, a supplement's name) is decoded or mapped by a token function, never drawn raw.

## Typography

**Display Font:** SF Pro Rounded (system `.rounded` design) — figures only: `hero`, `clock`, and every `onyxNumeral()`.
**Body Font:** SF Pro (system default design).

**Character:** Apple's own text styles, named for their job. Rounded, tabular numerals give the figures the tiles' shape language; prose stays in the default design because rounded prose reads as a children's app.

### Hierarchy
- **Clock** (semibold, 34 pt `.largeTitle`, −0.03 em): the live logger's running timer only, read at arm's length. Monospaced digits, no numeric roll.
- **Hero** (bold, 28 pt `.title`, rounded, −0.02 em): the one figure a screen is about — the readiness score, the day's kcal. Monospaced digits, `.numericText()` roll.
- **Display** (semibold, 20 pt `.title3`, −0.01 em): a card's title, a sheet heading, a split name.
- **Body** (regular, 17 pt `.body`): prose, list rows, every value that is not the hero.
- **Secondary** (regular, 15 pt `.subheadline`): the line under a value — target, previous set, meta.
- **Caption** (regular, 13 pt `.footnote`): section captions, unit suffixes, axis labels; semibold for chip and pill labels.
- **Micro** (semibold, 11 pt `.caption2`, +0.10 em, UPPERCASE): a register label naming a figure ("READINESS", "SCORE"). Secondary ink by default; never carries a number. The floor — nothing in the app goes below 11 pt (widget faces have their own `OnyxWidgetType`).

Sizes are the default-Dynamic-Type values; tracking is stored in em and multiplied by `@ScaledMetric` size so it scales with the text.

### Named Rules
**The One Hero Rule.** At most one `.hero` per screen — "a second hero is two screens in a trench coat". On the Body tab it is the readiness numeral inside the ring.

**The System Styles Rule.** Every role is a system text style; `Features/` may not spell a font size. Dynamic Type, optical sizing and system tracking come free because of it.

**The Rolling Numeral Rule.** Every number is `onyxNumeral()`: rounded, monospaced digits, `.contentTransition(.numericText())`. A running clock is the exception — monospaced, no roll.

## Layout

A single-column iPhone layout, portrait and dark only, on a five-step spacing scale: 4 inside a chip, 8 between lines of one thought, 12 a tile's own padding, 16 between sections and the screen's side gutter, 24 above a footer CTA and a sheet's top inset. The one off-scale value is the dashboard grid gap, 10, where a 2-up grid reads as a grid; the Body tab's square grid uses 16 so its trench matches the screen edge.

Screens lead with one instrument or masthead, then a 2-column (squares) or 3-column (exercise chips) grid of slabs, then doors to sheets. Everything secondary is one tap away in a sheet rather than on the scroll.

Dynamic Type is designed through AX5, with explicit fallbacks decided by type size rather than measured truncation:
- The session masthead uses `ViewThatFits` over three tiers (one row → 2×2 → 2×2 in caption, shrinking) and its name wraps to two lines and never truncates.
- The session ticket stacks name over figures from `.xxLarge`; `Shoulders` stacks its two ends at accessibility sizes.
- The six squares become full-width rows at accessibility sizes; muscle pills and tags wrap in a `FlowRow`.
- The Body ring is geometry: it caps Dynamic Type at `accessibility1`, and the words inside the ring cap at `xxxLarge`.
- Every tap target is ≥ 44 pt (chips, petals, exercise chips, the Progression button).
- A figure that does not exist is omitted, never replaced by "—".

## Elevation & Depth

No drop shadows. Depth is material: every surface is the Stone slab — `.thinMaterial` so content scrolling behind frosts, the `stone-slab` near-black laid over it at 78 % so the card is onyx rather than grey glass (and text contrast holds), a continuous rounded clip, and one lit top edge. Navigation chrome is the only `.regularMaterial` level. The ground under everything is black lit by two radials: the domain accent from just off the top-left (radius 70 % of height, peak 14 %) and the theme secondary from just off the bottom-right (55 %, peak 7 %), both clamped to OKLCH chroma 0.10 so the brightest point stays under L 0.35 and secondary ink stays ≥ 4.5:1. The ground dims with the battery (`0.5 + battery/2`, never below half) and the widget container draws it at half strength.

Reduce Transparency draws the slab solid `stone-slab` and the ground flat black.

### Shadow Vocabulary
- **Lit top edge** (1 pt stroke, linear gradient white 12 % at top → 4 % at 30 % → 4 % at bottom): tile, sheet and chrome levels. Rows draw none — they are already inside something.

### Named Rules
**The Stone Rule.** One slab everywhere: thin material + slab at 0.78 + lit top edge, no drop shadow. Depth is the lit edge and the radius.

**The No Stacked Slab Rule.** Never put `.tile` inside `.tile`. A row in a tile is `.row`; a ticket inside a host slab drops its own surface (`framed: false`) and steps its name down to semibold subheadline.

## Shapes

Continuous-corner squircles, concentric by depth: a row 12, a tile 20, a sheet 28 (`OnyxCorner`); an inset radius is its outer radius minus the padding (`OnyxCorner.inner`). Capsules for chips and pills. Circles for the readiness ring (200 pt, 14 pt stroke, round caps, starting at 12 o'clock) and petals (44 pt, 3 pt arc). The day's colour appears as a 3 pt rounded bar (1.5 radius) leading a session name.

## Components

### Chips
Tactile, visible verbs for wet hands.
- **Style:** capsule, caption semibold with a small SF Symbol, 8 × 12 padding, 44 pt min height; `ultraThinMaterial` fill with a 0.5 pt hairline outline; ink defaults to secondary or the caller's tint.
- **Prominent:** at most one per row — filled with its tint, label in `onyx-base`. The screen-ending action (Finish), pinned outside the scroll.
- **Disabled:** keeps its full-strength label; the capsule loses its material and keeps only the outline. A contextual action that has no answer is absent, not disabled.
- **Row:** horizontally scrolled with a faded trailing mask (92 % → clear); the row animates as a whole with `OnyxMotion.move`.

### Pills and tags
- **Muscle pill / tag:** capsule filled with the muscle's fixed ink at 14–16 %, label in that ink (caption semibold for focus pills, micro for tags), set count in secondary numerals. Wrap in `FlowRow`.

### Cards / Containers
- **Corner Style:** tile 20, row 12, sheet 28.
- **Background:** the Stone slab (see Elevation).
- **Shadow Strategy:** none; lit top edge only.
- **Border:** no outline beyond the lit edge; hairline only where content meets chrome.
- **Internal Padding:** 12 (`OnyxSpace.m`) for a tile.
- **Top wash:** a day or phase hue at 22 % → clear over the top 72 pt, applied inside the slab's clip — never a tinted panel.

### Squares
The app's one labelled figure (`OnyxStatCell`): a micro register label, one figure, and a sub line saying what it means; an optional 18 % trail sits behind the figure, hidden from VoiceOver. On the Body tab, six squares in a 2-column grid with 16 pt gaps, reorderable in an edit jiggle; rows at AX sizes.

### Navigation
System tab bar (Today, Train, Body, History, You). Floating chrome is `onyxChrome`: ultra-thin material with the day's accent washed 22 % → clear over 96 pt and a 0.75 pt accent line at 55 %.

### Session Masthead (signature)
"The session, in one line": a 3 pt day-ink bar, the name in `.headline` (two lines, never truncated), then clock · tonnage · heart rate (heart red) · records (gold trophy) in semibold tabular subheadline with small tinted SF Symbols. Shared by the Today widget, Live Activity, Dynamic Island, summary header and the watch banner.

### Session Ticket (signature)
A finished session as one 64 pt slab row: 3 pt day-ink bar · name (`.headline`) · three figures (duration, tonnage, then records or measured avg HR in heart red), with the six-point heart-rate spark behind the figures as a 20 % wash. Padding 12 leading, 16 trailing. Two lines from `.xxLarge`.

### Exercise Chip (signature)
Three across in the summary bento: glyph in the movement's tint on the first line with a 6 pt gold dot opposite when a set was a record, the short name (two lines, caption semibold), the best set in secondary numerals. A tile slab, press-scaled.

### Body Ring and Petals (signature)
The Body tab's one instrument. A 200 pt readiness ring in the theme accent over a hairline track, a 4 pt battery arc inset 10 pt in the battery's band ink, the score as the screen's `.hero` with a "READINESS" micro label and a battery caption. Six 44 pt petals orbit at 60° steps (Sleep · Water · Food above; Heart · Steps · Stress below), 8 pt off the ring, each in its fixed ink: disc fill at 12 % (22 % when there is a reading but no goal), track at 22 %, progress arc at full ink; a hollow tertiary ring and no caption when there is no data. Captions sit on the side away from the ring. Petals press at 0.92 and open their domain's sheet. Reduce Motion draws the arcs at rest; otherwise they move with `OnyxMotion.counter`.

### Motion
Springs, critically damped by default: `move` 0.4 / 1.0 for state changes, `flick` 0.4 / 0.8 only where a finger threw it, `drawer` 0.3 / 0.8, `counter` 0.55 / 1.0 for numbers, `press` 0.1 s ease-out on touch-down (scale 0.96, tiles may brighten 0.06), `fade` 0.2 s — also the Reduce Motion fallback.

## Do's and Don'ts

### Do:
- **Do** put every surface on `.onyxGlass(_:)` at the right level — row 12, tile 20, sheet 28 — and let the slab and its lit top edge carry the depth.
- **Do** stand every screen on `onyxScreen(domain)` (or `onyxScreen()` for Settings), so the ground is lit in that domain's accent and the theme's secondary.
- **Do** read colours through `Color.onyx.*`, `OnyxDomain` and `OnyxInk.Themed` / `OnyxInk.Fixed`; use a Fixed ink for anything that means heart, water, sleep, a record, a good result or a muscle.
- **Do** give each screen exactly one `.hero` figure, set with `onyxHero()` or `onyxType(.hero).onyxNumeral()`.
- **Do** set every number with `onyxNumeral()` and every size through an `OnyxType` role; spacing through `OnyxSpace`.
- **Do** design the AX5 layout explicitly: stack by type size, wrap pills in `FlowRow`, cap geometry-bound instruments, and keep every tap target at 44 pt.
- **Do** honour Reduce Transparency (solid slab, flat black ground) and Reduce Motion (arcs at rest, `OnyxMotion.fade` instead of movement).

### Don't:
- **Don't** spell a hex, a `Color(red:)` or a font size in a feature view; `TokenDisciplineTests` fails the build.
- **Don't** add drop shadows under slabs, sheets or chrome; the Stone world's depth is material and a lit edge.
- **Don't** nest a tile slab inside a tile slab; use `.row`, or an unframed ticket inside a host card.
- **Don't** use record gold for anything but a record or a threshold, or `text-tertiary` for a value, a control label or the only copy of a fact.
- **Don't** theme the Fixed inks or the sixteen-muscle palette, and don't fold a muscle's colour onto a domain accent.
- **Don't** fill a missing figure with "—"; omit it, or draw a hollow ring with no caption.
- **Don't** truncate a session name; wrap it, then shrink the figures under it.
