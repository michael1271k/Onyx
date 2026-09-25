---
version: 1
slug: "native-onyx-features-pulse-bodyring-swift"
primary_target: "native/Onyx/Features/Pulse/BodyRing.swift"
related_targets: ["native/Onyx/Features/Pulse/PulseTabView.swift"]
---

# Surface brief — Body tab (was Pulse)

Shaped 2026-09-25 by `impeccable shape`, Precision sprint Lane B (B4). No live
interview: the lane brief makes § FOUNDER DECISIONS binding and forbids
questions; every assumption below is marked.

## Scope and mode
Operate. The Body tab root (`BodyTabView`, file `Features/Pulse/PulseTabView.swift`)
and its hero `BodyRing` (`Features/Pulse/BodyRing.swift`). History's past-day
push reuses `DayScreen` and KEEPS its session tickets and "Log a workout here"
(assumption: Q19 says workouts leave THIS tab; the retro door exists nowhere else).

## Job and audience
The athlete, morning or between sets, asks "how ready is my body today, and
which part of today is short?" One glance: the readiness score, the battery,
and six domains' progress. Then the detail: vitals, stress, soreness, scale.

## Outcome and proof
Success = the six petals answer "what is short" without reading a number; the
numbers are one tap (each petal opens its domain's existing sheet/screen).
Real data: daily_scores (score, battery_pct), sleep minutes vs goal, water ml
vs target, kcal vs target, resting HR vs its fortnight, steps vs target, the
stress index 10–90.

## Selected direction (inside the Stone world — no new world)
Structural thesis: one instrument, not a stack of cards. A 200 pt readiness
ring (theme accent, `.hero` numeral — the screen's ONE hero) with a thin inner
battery arc, six 44 pt petal discs evenly around it (Sleep · Water · Food on
the top arc, Heart · Steps · Stress on the bottom), each with its own progress
arc in its FIXED ink and its value as a caption on the outer side. Refuses the
category default: a row of equal stat cards / a hero-metric-plus-grid template.
Sequence: ring → vitals (sleep row compact, it is a petal now) → the 2×3
squares → banners stay above the ring.

## States and ranges
Score 0–100 or unscored (ring hollow, numeral absent → "—" is BANNED on
petals; the centre may say "Not scored"). Petal with no data: hollow ring, no
caption. Water/food/steps can exceed goal: arc caps full. Heart: full when
resting HR ≤ its fortnight baseline (assumption: "recovered heart" reading).
Stress: arc = index/100 in the band's ink.

## Interaction and layout
Petal tap → sheet/screen: Sleep → SleepEditSheet; Water → LogDaySheet(.water);
Food → Nutrition tab; Heart & Steps → Body trends; Stress → breakdown sheet.
44 pt targets. Ring caps Dynamic Type at accessibility1. Reduce Motion: arcs
draw at rest. VoiceOver: ring = "Readiness 78, battery 64"; each petal
"Sleep, 6 h 40, 83 % of goal".

## Constraints and open decisions
- `BodyRingLayout` is local; W-final may swap it for Lane D's six-petal
  `WatchGlance` if the math matches (seam 5).
- NowStripPulse deleted (its score/battery/fuel ARE the ring now). The date
  it carried moves to the ring's caption line.

## Direction contract
THESIS: the body is one instrument — a readiness ring orbited by six petals — not a stack of cards; it refuses the stat-card grid.
OWN-WORLD: Stone — onyx-black ground lit by the stone's two radials, frosted slab tiles, no shadows; fixed inks for meaning (REM lavender, water blue, heart red, calories, stress band), the theme accent for readiness only.
STORY: the reader sees today's readiness, sees which of six parts of the day is short, taps it.
FIRST VIEWPORT: date caption, then the ring+petals instrument centred (~336 pt), then the first vitals row peeking; the banners, when present, above the ring.
FORM: ring-and-petals instrument (1st of: instrument / stat grid / list), seed key: body-ring-v1.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
