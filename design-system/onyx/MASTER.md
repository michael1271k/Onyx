# ONYX — Design System, v2

**Status:** the record of record for colour, space, corner, type and the mark.
Written at Wave 2.0 (2026-09-04) from `docs/NATIVE_PHASE_2_PLAN.md` §3, which is
the authority; this file is the same decisions with their reasons and their
Swift call sites, so a screen wave does not have to re-read the plan to know what
a token is called.

**Platform:** iOS 18+, dark only, iPhone only. Every value below is points.
**Owner in code:** `native/Packages/OnyxUI/Sources/OnyxUI/DesignSystem/`.
**Enforced by:** review — a raw hex outside the token file is a defect.

---

## 0. The three layers

```
Primitive        the hex, the number            HelixDomain.train.start = #6B78F0
    ↓
Semantic         what it MEANS                  Color.helix.record, HelixSpace.m
    ↓
Component        what it is FOR, one owner      helixGlass(.tile), helixType(.hero)
```

A view may name a **semantic** or a **component** token and nothing else. A hex
or a bare number in `native/HelixNative/Features/` fails the build. The
primitives exist in exactly two files (`HelixTokens.swift`, and `HelixPalette.swift`
until Wave 2.4 deletes it with the Live Logger's re-skin).

---

## 1. Colour

### 1.1 Ground

| Token | Value | For |
|---|---|---|
| `Color.helix.base` | `#000000` | The screen. True black: an OLED pixel that is off has no edge, so the material above it reads as a layer rather than a lighter rectangle. |
| `Color.helix.hairline` | white 8 % | 0.5 pt, and only where content meets chrome. |

### 1.2 The four domains

One accent per domain; a screen belongs to exactly one. The hue says where you
are before you read a word, and the one tinted thing on a screen is the one that
matters.

| Domain | Name | Start | End | Owns |
|---|---|---|---|---|
| `.train` | Ion | `#6B78F0` indigo | `#4FB6E8` sky | Logger, PRs, volume, muscle, Workout tab |
| `.fuel` | Solar | `#E3A650` honey | `#E07A7A` coral | Nutrition, levers, targets |
| `.body` | Tide | `#46B39D` teal | `#2E9AA6` deep teal | Composition, cardio, atlas intensity |
| `.recover` | Lunar | `#A79FD6` lavender | `#C9D3EE` mist | Sleep, readiness, fatigue, DOMS |

`accent` is the **start** stop, not a midpoint — the midpoint of Solar is a muddy
salmon that reads as neither warning nor warmth. `at(t)` walks the mesh; it is
the only way to derive a related colour, so a tile never mixes one of its own.

**v1 → v2:** every accent came down two steps (Ion was `#7C5CFF`, Tide
`#3DFFB0`). Full-saturation hues on true black are the recipe for a screen that
reads as a web app in a new font: the accent shouts, the glass under it tints,
and every number competes with its own label. Desaturating is what lets the
*material* carry the hierarchy.

### 1.3 Text

| Token | Value | Rule |
|---|---|---|
| `textPrimary` | white 92 % | Values, titles, anything the reader came for. |
| `textSecondary` | white 62 % | The line under a value. |
| `textTertiary` | white 40 % | **Fails 4.5:1 by design.** Only for a label whose absence costs nothing — a unit suffix, a row count, a timestamp VoiceOver already speaks. Never a value, never a control label, never the only copy of a fact. |

### 1.4 Status

| Token | Value | Rule |
|---|---|---|
| `danger` | `#E5484D` | Destructive actions, validation failure, a gauge's over-budget segment. Never a chart series. |
| `good` | `#4CAF87` | A delta in the right direction, a session logged, a target met. A muted green rather than Tide's teal: "yes" and "this is the Body tab" are different statements. |
| `record` | `#FFD35C` gold | A personal record and nothing else. **The only fifth hue in the system** — seeing it means one thing. Raised from the plan's `#D9B25F`, which sat ΔE76 11.0 from `carbs` and met it on one widget face. |

### 1.5 Macros & water — fixed app-wide

Never re-mapped per screen: a bar that is coral in Nutrition and teal in a widget
is two facts the reader has to hold. Three of the four are domain stops, so the
macro rails still read as Solar and Lunar rather than as a fifth palette.

| Token | Value | Source |
|---|---|---|
| `protein` | `#E07A7A` coral | `HelixDomain.fuel.end` |
| `carbs` | `#E3A650` honey | `HelixDomain.fuel.start` |
| `fat` | `#A79FD6` lavender | `HelixDomain.recover.start` |
| `water` | `#5AA9E6` sapphire | its own hue — water is not a macro and must not be mistaken for one |
| `calories` | Solar | `HelixDomain.fuel.accent`; use `.fuel.ramp` where the fill is a gradient |

### 1.6 Sleep stages — four tokens, not four alphas

v1 derived all four from Lunar and the Sleep sheet came out as four lavender bars
a reader had to decode from a legend. The stages are not a ramp of one quantity:
deep and REM are different *kinds* of sleep and awake is not sleep at all.

| Stage | Value |
|---|---|
| `deep` | `#5B62C9` |
| `core` | `#A79FD6` (`HelixDomain.recover.start`) |
| `rem` | `#E07A9A` |
| `awake` | `#6E6E78` |

### 1.7 Split colours — `Color.helix.day(dayKey)`

Keyed by what the day **trains**, so a Helix week and a PPL week are the same
picture.

| Day | Colour |
|---|---|
| `cb_a`, `upper_a`, `ppl_push_*` | Ion at 0.35 |
| `cb_b`, `upper_b`, `ppl_pull_*` | Ion at 0.65 |
| `arms` (Delts & Arms) | Ion end (`#4FB6E8` sky) |
| `legs_a`, `lower_a`, `ppl_legs_*` | Tide at 0.35 |
| `legs_b`, `lower_b` | Tide at 0.65 |
| rest / unknown | `textTertiary` — a rest day is the absence of a session and wears no accent |

`day()` is a **ring/fill** colour. A rest day set as a **word** takes
`Color.helix.dayLabel(dayKey)`, which is identical except that it answers
`textSecondary` on rest — tertiary is 3.7:1 on black, and a label naming the day
is the only copy of that fact.

Two steps *in* from each end rather than 0 and 1: a split colour sits next to the
domain accent on the same screen, and a day drawn in the accent itself reads as
"selected" rather than as "leg day".

### 1.8 Derived ramps

- **Battery** `Color.helix.battery(pct)` — `good` ≥ 60, Solar 30–59, `danger` < 30, `textSecondary` when there is no reading. The one place a traffic light is the right metaphor, because the number genuinely is a fuel gauge.
- **Muscle** `Color.helix.muscle(_:step:of:)` — the family's accent stepped 35 % along its own ramp by position in the list being drawn. Chest/shoulders/arms → Ion, back/legs → Tide, core → Lunar.
- **Chart series** `Color.helix.series` — Ion, Tide, Solar, Lunar, Ion-end, Solar-end, in that fixed order. Domain tokens, not a second palette: a chart in the Body tab is Tide because Tide *is* the Body tab.
- **DOMS severity** (§3.2, no Swift owner yet — Wave 2.7 introduces the type): none `textTertiary` · mild `good` · moderate `record` · severe `danger`.

---

## 2. Space — `HelixSpace`

| Step | Value | For |
|---|---|---|
| `xs` | 4 | Inside a chip; between a glyph and its label. |
| `s` | 8 | Between the lines of one thought. |
| `m` | 12 | A tile's own padding; the gap between rows inside it. |
| `l` | 16 | The gap between sections; the screen's side gutter. |
| `xl` | 24 | Above a footer CTA; a sheet's top inset. |
| `grid` | 10 | The dashboard grid's gap only (`s + 2`). Cells carry `m` inside their own edge, so a full `m` between them reads as a 24 pt trench and `s` lets two tiles touch. |

**Why a scale at all when every value is already a number:** the screens this
replaces used 14, 16 and 18 interchangeably — not as decisions but as whatever
the file next door said. Three values 2 pt apart do not read as three levels of
relationship; they read as a grid that is slightly off, which is the loudest
"this was not made by a designer" signal an iOS screen can send.

**Rows are 44 pt minimum**, and never taller unless they carry two lines.

---

## 3. Corner — `HelixCorner`

| Token | Value |
|---|---|
| `row` | 10 |
| `tile` | 16 |
| `sheet` | 28 |

Concentric: `HelixCorner.inner(outer, padding:)` is `outer − padding`, so a row
inset inside a tile keeps the tile's shoulder. All three came down from 12/20/32
— iOS's own widgets, cards and grouped rows sit near 16, and a 20 pt corner on a
160 pt tile is a lozenge.

Always `style: .continuous`. A circular arc is what the web does.

---

## 4. Material — `helixGlass(_:)`

Hierarchy is material **weight**, not borders and not lighter greys. One modifier
owns it, so raising the deployment target to iOS 26 and swapping in `glassEffect`
is one edit.

| Level | Material | Radius | Hairline | Shadow |
|---|---|---|---|---|
| `.row` | ultraThin | 10 | no | none |
| `.tile` | ultraThin | 16 | yes | none |
| `.sheet` | thin | 28 | yes | 24 / y 12 |
| `.chrome` | regular | 0 | yes | none |

Never stack two directly — `.tile` inside `.tile` is one light translucent
surface on another and both stop reading as glass. A row inside a tile is `.row`.
Under **Reduce Transparency** the fill becomes opaque black + 10 % white.

**Screen ground** `helixScreen(_ domain:)` — true black plus one `MeshGradient`
bleed of the domain at **8 %**, height **240**, top-anchored, blur 40. Was 12 %
over 340: at that strength across a third of the screen it had stopped being a
bleed and become a gradient header, which is what made every screenshot read as
a landing page.

---

## 5. Type — `HelixType`

Six roles. Each **is** a system text style, so Dynamic Type, optical sizing and
Apple's own tracking tables come for free and there is no frozen number to scale.

| Role | Style | Size | Weight | Design | Tracking | For |
|---|---|---|---|---|---|---|
| `.hero` | `.title` | 28 | bold | rounded | −0.02 em | The one figure a screen is about. At most one per screen. |
| `.display` | `.title3` | 20 | semibold | default | −0.01 em | A card title, a sheet heading, a split name. |
| `.body` | `.body` | 17 | regular | default | 0 | Prose, list rows, every value that is not the hero. |
| `.secondary` | `.subheadline` | 15 | regular | default | 0 | The line under a value: a target, a previous set, a meta line. |
| `.caption` | `.footnote` | 13 | regular | default | 0 | A section caption, a unit suffix, an axis label. |
| `.micro` | `.caption2` | 11 | semibold | default | +0.10 em | A register label, set in caps. **Never a number.** |

**Nothing in the app is below 11 pt.** Tracking is size-specific — letterforms
read further apart as they grow, so display takes negative and the floor takes a
little positive; one fixed value across a scale is wrong at both ends.

Modifiers: `.helixType(role)` · `.helixHero()` · `.helixDisplay()` ·
`.helixCaption()` (caption + secondary ink) · `.helixMicro()` (micro + tertiary
ink) · `.helixNumeral()` (rounded + `monospacedDigit` + `.numericText()`).

Emphasis is a `.fontWeight()` **on top of** a role, never a new size —
`.fontWeight`, `.fontDesign` and `.monospacedDigit` are font *transforms* and
compose with a role's font in either order. `helixType(role, tracking:)` takes an
`em` override for the one thing outside the scale, the wordmark.

A glyph or numeral inside a **fixed** frame (a gauge ring, a 24 pt badge) clamps
with `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`. It is decorative and its
meaning is already on the row beside it or in an `accessibilityLabel`; scaling it
to AX5 bursts the ring without telling anyone anything.

**Every number** takes `helixNumeral()`: monospaced digits stop neighbours
shuffling as a value changes, and `.numericText()` rolls the digit instead of
cross-fading it — the difference between a number that *changed* and one that was
replaced.

### 5.1 `HelixWidgetType` — the widget-only scale

Widget faces are typed in **points**, down to 7, and that is deliberate:
WidgetKit delivers no Dynamic Type and a Lock Screen accessory family is 40 pt
tall in total. `HelixWidgetType.hero/figure/label/caption/face` is the only door;
a bare `.font(.system(size:` under `Tiles/` fails the build. It does not exist
inside the app.

---

## 6. Motion & haptics

`HelixMotion` — move 0.4 / 1.0 · flick 0.4 / 0.8 · drawer 0.3 / 0.8 (response /
damping). Critically damped by default; **bounce only after momentum**. Every
drag is 1:1 and interruptible, and every animation starts from the presentation
value, not the target. Under Reduce Motion springs become a 200 ms cross-fade.

Haptics, the whole list: `.selection` on every stepper detent, slider snap,
segmented change and radio row · `.impact(.soft)` on set logged, swipe-complete
commit, tile drop · `.impact(.rigid)` on swipe threshold crossed · `.success` on
session finished, PR, sync complete after pull-to-refresh · `.error` on sync and
sign-in failure. Nothing else — over-feedback trains the user to ignore all of it.

---

## 7. The mark — `OnyxMark`

One ring, stroke 2 pt at 16 pt (`strokeRatio` 0.125), a **13 % trim** centred at
one o'clock — the `.round` caps eat ~17° of it, so the gap you see is ~30° —
painted lavender → indigo (`Lunar.start` → `Ion.start`) top-left to
bottom-right, at **70 %** opacity, sized **12–16** in a tile's top-trailing
corner. `monochrome` for accented widget rendering; `tint:` for the Dynamic
Island, where it carries the running session's own colour.

It replaced a two-strand helix with rungs — five strokes inside a 16 pt box is a
smudge, and the name it was drawn for is gone. A ring is one stroke, survives
12 pt and the accented mode, and is already the app's most-repeated shape (the
battery ring, the score gauge, the Lock Screen arc). The break is what stops it
being a generic circle: it reads as the "O" of Onyx and as a gauge that has not
closed.

**Wordmark:** `OnyxWordmark` — SF Pro Display semibold, −0.03 em, "Onyx".

---

## 8. The "not web" checklist

A screen passes review only if:

- [ ] Nav title `.inline`, or `.large` collapsing (Today only).
- [ ] No tile taller than its content.
- [ ] No box that only repeats the box above it.
- [ ] One accent per screen, plus gold for records.
- [ ] Every number has a unit and a reserved delta line.
- [ ] Every list is a `List` or `Form`, not a `ScrollView` of cards — unless it is a grid.
- [ ] Pull-to-refresh on Today.
- [ ] The AX5 screenshot does not clip.

---

## 9. What the build enforces

`npm test` → `src/tests/native-token-discipline.test.ts`:

1. No `Color(hex:` / `Color(red:` / `UIColor(red:` under `Features/`; no `0x` or `Color(white:` under `Tiles/`.
2. The hex list in `HelixTokens.swift` is exactly the 15 primitives above, each spelled once — a sixteenth is a widened mandate and must be a deliberate diff.
3. `protein` / `carbs` / `fat` are domain stops, not hues.
4. No `.padding(14…29)`, no `spacing: 14…29`, no `.system(size:` under `Features/`.
5. No `.font(.system(size:` under `Tiles/` outside `HelixPrimitives.swift`.
6. `HelixSurface.swift` stays deleted.
7. The Live Logger's legacy exemption list may only shrink (it dies at Wave 2.4).
