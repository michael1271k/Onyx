---
version: 1
slug: "native-onyxwatch-views-petaldetailview-swift"
primary_target: "native/OnyxWatch/Views/PetalDetailView.swift"
related_targets: ["native/OnyxWatch/Views/GlanceView.swift"]
---

# Surface brief — watch Glance + petal details

Shaped 2026-09-25 by `impeccable shape`, Precision sprint Lane D (D1/D3). No
live interview: the lane brief makes § FOUNDER DECISIONS binding (Q22–Q24,
design 12 "Wrist vitals detail") and forbids questions; assumptions marked.

## Scope and mode
Operate. The watch's first dashboard page (`GlanceView`) and the six screens a
petal pushes (`PetalDetailView`). Nothing else on the wrist changes shape.

## Job and audience
The athlete, wrist raised away from the phone — morning, between sessions,
after a meal — asks "which part of today is short, and by how much?". The
Glance answers the first with six discs; a tap answers the second.

## Outcome and proof
Success = one figure per detail, readable at arm's length on a 40 mm case,
with one drawing that says what the figure is made of: sleep = stage arc,
heart = 24 h trace, water = pitcher, food = energy bar, steps = 7 days,
stress = band. All figures come from `WatchTiles` (the phone's snapshot) except
the heart (the wrist's own `WatchVitals`).

## Selected direction (inside the Stone world)
Structural thesis: the petal opens into itself — the detail is a `WatchSlab`
in the petal's FIXED ink with the same glyph logic, so "opened" never reads as
"somewhere else". One hero per screen (`WatchType.figure`, the sleep arc's bowl
uses `.value`). Refuses the stat-card stack: one slab, one drawing.

## States and ranges
Every figure optional: a missing reading prints "—" in the detail (a petal
never prints "—": hollow ring). Sleep stages may be partial (absent stage
omitted from the legend); steps days may be missing (a gap, never a zero bar);
heart may be stale (the time says when; the petal goes hollow past 90 min).

## Interaction and layout
Crown scrolls a detail; ≤ one screen at 40 mm at default size (assumption:
larger Text Sizes scroll). Heart streams while on screen only. Water keeps the
+1 glass button under the pitcher. Back = system chevron.

## Constraints and open decisions
- `DepthArc`/`PitcherFigure` are iOS-fenced in OnyxUI files no lane owns →
  wrist copies (`WristDepthArc`, `WristPitcher`, complication `WaterJug`);
  W-final asked to lift one copy above the fence.
- Stress band ink duplicated from the app target (`WatchInk.stress`).

## Direction contract
THESIS: a petal opens into itself — one slab in the petal's fixed ink, one figure, one drawing; it refuses the stat-card stack.
OWN-WORLD: Stone — black ground lit by the stone's two radials at half strength, frosted slab, no shadows; fixed inks for meaning.
STORY: the reader raises the wrist, sees which disc is short, taps it, reads the figure and what it is made of.
FIRST VIEWPORT: the whole detail — nav bar, one slab, nothing below the fold at 40 mm.
FORM: slab-with-figure-and-drawing (1st of: slab / list / chart page), seed key: wrist-detail-v1.
FINISH: shots at 49 + 40 mm × 3 stones, one fix batch, one confirm round.
