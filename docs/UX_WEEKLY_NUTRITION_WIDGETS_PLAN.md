# UX Sprint — Week Wrapped, Colour Glow-Up, In-App Stacks, Nutrition

Status: findings measured + founder decisions locked 2026-09-12. Waves + prompts
in §Waves. W1a shipped as 2.5.0 on 2026-09-12.

**Version numbers moved once.** This document was written against 2.3.0 and
assigned W1a 2.4.0. The concurrent export-v4.1 audit merged first and took
2.4.0, so every wave here shifted up one minor: W1a 2.5.0, W1b 2.6.0, W2 2.7.0.

## Founder decisions (2026-09-12)

1. **"Widgets" means the in-app dashboard cards** (`Features/Today`), NOT the
   WidgetKit extension. Do not touch `native/OnyxWidgets/`, App Groups, or
   signing entitlements.
2. Week Wrapped presents as a bottom sheet, `.presentationDetents([.height(560), .large])`.
   560 shows the complete reel; dragging up reveals the breakdown. Never leaves
   the Train tab.
3. Wrap content = highlight reel on top, compact Top 3 below. Visual cards: best
   e1RM + delta, heaviest set, top volume session, muscle ring, week tonnage.
   Then Top 3 progressed with a `+N more` chip opening a disclosure.
4. The ring draws **8 families**; the legend breaks out **16 landmarks** at `.large`.
5. Week-detail hero = four big figures, the existing eight-cell row kept below.
6. Training load = **Foster weekly strain, with ACWR as its sub-caption** — one
   cell, two figures, the way tonnage already carries its delta.
7. Actions = `OnyxChipRow` under the hero. Rounded chips in flow, no overlay.
8. **Past weeks get a wrap door.** A chip on any complete week's detail screen
   opens the same reel. The wrap stops being news that expires.
9. In-app stack: replace the rotated `TabView` with a **custom paging carousel**
   owning its own gesture, plus a long-press menu (Create stack / Add to stack /
   Unstack) so stacking needs no drag.
10. Nutrition: specify all three tiers, **no code**.
11. Wave 1 splits into **1a** (wrap) and **1b** (history), sequential — 1b's wrap
    chip depends on 1a's view.
12. **Native only.** The Helix web app is untouched; it has no wrap surface at
    all (`WeeklyWrap` is Swift-only, zero TS port) and is scheduled for sunset.
13. Each wave on its own feature branch.

## Context

Four asks, at four different distances from done — and two are much closer than
the brief assumed. Saying so before anyone writes code is the most valuable
thing in this document.

- **Week Wrapped** — the adaptive entry the brief asks for **already shipped**,
  in v2.2.0 on 2026-09-12. What is actually broken is the presentation (a
  navigation push, not a sheet) and three uncapped movement lists.
- **Week-detail glow-up** — a presentation wave. The data is nearly all there.
- **In-app Smart Stack** — `SmartStackView.swift` exists and auto-rotates. This
  is a defect hunt plus a discoverability fix, not a build.
- **Nutrition** — research only. The ceiling is partly external (MyFitnessPal)
  and partly self-imposed (Onyx discards meal grain at ingest).

---

## Findings (measured 2026-09-12)

### F1. The This-week tile is ALREADY adaptive (v2.2.0, `docs/CHANGELOG.md:127`)

`WorkoutTabView.weekPanel` (`native/Onyx/Features/Workout/WorkoutTabView.swift:228-303`)
is two controls in one:

| Week state | Tap | Long press |
|---|---|---|
| wrapped (`week?.snapshot.wrap != nil`) | `NavigationLink → WeeklyWrapView` `:250-257` | contextMenu → "Rearrange this week" `:258-267` |
| ongoing | `Button → weekSheetOpen = true` `:269-290` | — |

`WeekOverrideSheet` (`Features/Workout/WeekOverrideSheet.swift:31`) is the
seven-day reassignment sheet, presented via `DaySheet` at `WorkoutTabView.swift:173-177`.
**No work is needed on the entry rule.**

`WeeklyWrap.isWrapped` (`OnyxCore/Training/WeeklyWrap.swift:110-116`) is the gate:
every training day the plan asks for this week, past *or future*, is logged.
Deliberately not `WeekReady.isComplete` (calendar; gates the export) and not
`WeekReady.isReady` (can fire on a Tuesday). Three distinct rules, on purpose.

### F2. The wall of text is three uncapped lists

`WeeklyWrapView.swift:47-49` renders `summary.progressions`, `.deloaded` and
`.regressions` through `movementList(_:_:tone:symbol:)` (`:150-185`). Every
movement of the week lands in exactly one of them, one 48 pt row each, with a
percentage at `:171-175`. Thirty movements is thirty rows. There is no cap.

The screen is a **navigation push** with `.navigationBarTitleDisplayMode(.inline)`
(`:56-57`). Its own header (`:8-17`) argues against a *modal that appears on its
own* — which a user-initiated detent sheet is not. That header must be updated,
not contradicted.

### F3. Everything the highlight reel needs already exists

| Datum | Where it already is | New code? |
|---|---|---|
| Week tonnage + delta | `Summary.tonnageKg` / `.tonnageDeltaKg` | none |
| Heaviest set | `Summary.topSet` (`WeeklyWrap.swift:171`) — by LOAD, deliberately not e1RM | none |
| Best e1RM + delta | `Movement.e1rm` / `.previousE1rm` / `.change` (`:34-72`) on every movement | one computed property |
| Top progressed | `Summary.progressions.first` — already sorted by `abs(change)` desc (`:152-157`) | none |
| PR count | `Summary.prCount` | none |
| Muscle distribution | `TodayFeedBuilder.muscleFocus(weekStart:sets:names:phase:overrides:)` (`OnyxData/Dashboard/TodayFeedBuilder.swift:254-276`) → `MuscleFocusSummary.rows`: all 16 landmarks, weighted `sets`, `target` | wire into the wrap builder |
| Family roll-up | `MuscleFamily.of(_:)` (`OnyxCore/Training/MuscleFamily.swift:33`), 8 cases | none |
| Muscle hues | `Color.onyx.muscle(_:)` — the 16 hexes (`OnyxUI/DesignSystem/OnyxTokens.swift:433-452`); `muscleFamily(_:)` `:412` | none |
| Top volume session | per-date volumes already summed in the week loop (`WorkoutWeek.swift:346-349`); `WorkoutSession.totalVolumeKg` (`OnyxData/Database/Models.swift:124`) | pick the max |

**The only genuinely absent datum is the muscle distribution on the wrap**, and
its accumulator is the canonical one the tile, sheet and Trends already share
(W3's single-accumulator rule).

### F4. Week detail is monochrome by construction, not by accident

`WeekDaysView` (`native/Onyx/Features/History/WeekDaysView.swift:12`):

- ground `Color.onyx.base` = **true black** (`OnyxTokens.swift:119`) via
  `.onyxScreen(.train)` `:69`; the mesh bleed peaks at 8–10 % and 5 of its 9 grid
  colours are literally `.black` (`OnyxGlass.swift:168`, `:215-219`)
- the only chroma in the content is 8 vitals numbers and 7 day dots — and both
  derive from the **4 domain accents**. The 16-hue muscle palette never reaches
  this screen.
- `WeekVitalsRow` (`:211-303`) already renders 8 cells: weight Δ, fat Δ, battery,
  sleep score, sleep, steps, tonnage, sessions
- `DayHistoryRow` (`:309-376`) already calls `Color.onyx.day(day.dayKey)` — and
  spends it on an **8 × 8 pt dot** (`:318-327`)
- actions (`:88-146`) are `LabeledContent` rows inside a `List` section

`Color.onyx.day(_:)` (`OnyxTokens.swift:237-256`) maps every split key — `cb_a`,
`cb_b`, `arms`, `legs_a`, `legs_b`, plus the Onyx-4 and PPL mirrors, defaulting
to `textTertiary`. **The split palette exists; it is being rationed to a speck.**

`.onyxMuscleWash(_:secondary:corner:)` (`OnyxUI/DesignSystem/OnyxMuscleWash.swift:36`)
is already the house primitive for "paint a card in its own colour": a 6 %→2 %
top-down hue wash plus a 3 pt leading rail, clipped to the card's radius. It was
built for exercise cards, it is exactly right for a day row, and it needs no
changes. Its own header explains why 6 % and not 28 % — read it before tuning.

### F5. Two weekly figures genuinely do not exist

- **Average bodyweight for a week.** `HistoryWeeks.detail` computes
  `weightDeltaKg` first→last within the week (`HistoryWeeks.swift:249-254`) and
  means for battery / sleep score / sleep / steps (`:255-258`, via the private
  `mean(_:)` at `:337`). There is no weekly mean weight anywhere, Swift or TS.
- **Weekly training load.** `Readiness` (`OnyxCore/Scoring/Readiness.swift:142`)
  has it, but `Readiness.fosterWeek` (`:247`) is **internal**. The public path is
  `Readiness.loadSignal(loads)` (`:256`) → `LoadSignal.strain` / `.weeklyLoad` /
  `.acwr`. Use the public path; do not widen visibility for one caller.

### F6. The in-app Smart Stack exists, and has four defects

`native/Onyx/Features/Today/SmartStackView.swift:23` — a `TabView(.page)` rotated
90° so paging is vertical (`:61-72`), a 9 s period (`:44`), a deterministic
per-slot stagger (`:50-54`), a manual-swipe hold-off (`:76-78`, `:84`), paused in
edit mode and in the background (`DashboardGrid.swift:102`), with a vertical dot
rail (`:96-106`). The face index is hoisted to the grid so a tap opens the face
that is *up* (`DashboardGrid.swift:29`, `:93`).

| # | Defect | Evidence |
|---|---|---|
| **D1** | **Stacking is undiscoverable.** The only route is: long-press 0.45 s into edit mode → drag → hold **600 ms** over a **same-size** tile → drop. The only feedback is a 2 pt border. Drop at 500 ms and you silently get a *move*. | `DashboardGrid.swift:39`, `:114-117`, `:140-144`; `Dashboard.canStack` requires `a.size == b.size` (`OnyxCore/Dashboard/Layout.swift:450-455`) |
| **D2** | **Gesture conflict.** A vertically-paging TabView nested inside the Today tab's vertical ScrollView — both claim the same drag axis. | `SmartStackView.swift:61-72` |
| **D3** | **The rotation clock restarts on every resume.** `.task(id: rotating)` keys on a Bool derived from `editing \|\| !isActive`; each flip re-waits `period + stagger` from zero. | `SmartStackView.swift:80-82`, `DashboardGrid.swift:102` |
| **D4** | **Faces are keyed by position** — `ForEach(id: \.offset)` + `.tag(index)` — while `StackSlot.items` explicitly *may repeat a widget* (`Layout.swift:52`). `Dashboard.reorderFace` (`Layout.swift:487`) keeps the index, so a reorder silently changes what is on screen. | `SmartStackView.swift:62`, `:66`, `:79` |

Minor: the merge highlight reads `slot.items[0].domain.accent`
(`DashboardGrid.swift:116`) — the target's *first* face, even when another is up.
`SmartStackView.swift:84` hardcodes `9` instead of `Self.period`.

### F7. Nutrition — the ceiling, measured

> **Superseded in five places by W3.0.** F7 was written from a grep; W3 re-measured
> it against a live introspection and a full census. The read-site count, the
> dietary-type count, the MyFitnessPal contact route, the "collapses into one row"
> claim and the "HealthKit is read-only everywhere" claim all moved. Read W3.0 and
> W3.5 before acting on anything below.

**External (MyFitnessPal).** The public API was deprecated in **2019** with no
announcement; access is now private and partner-only, by application to
`API@myfitnesspal.com`. MFP writes **meal summaries** to Apple Health — not
individual foods — and **does not sync the timestamps** of when food was logged.
Food names and real meal times are therefore unreachable from MFP through
HealthKit, no matter how good the reader is. There is no shippable sync.

**Internal (Onyx), and this part is fixable.** Onyx already requests **all 24**
`HKQuantityTypeIdentifierDietary*` types (`OnyxData/Health/HealthMetrics.swift:116-130`
ingested, `:159-169` authorized) and then collapses everything into **one row per
day**: `nutrition_entries` with `meal_type = 'daily'`, unique on
`(user_id, date, meal_type)` (`native/schema/supabase.json:84-92`). Twelve read
sites hardcode `.eq('meal_type','daily')`. `src/lib/reports/weeklyExport.ts:898`
states it outright: *"`nutrition_entries` stores a `meal_type = 'daily'`
AGGREGATE with no item"*.

HealthKit is **read-only everywhere** — `requestAuthorization(toShare: [], …)`
(`OnyxData/Health/HealthKitReader.swift:28-32`) and `toShare: nil` in the
Capacitor plugin (`ios/App/App/HelixHealth.swift:35`). There is no
`HKHealthStore.save` call in the repo.

**Barcode capability is zero.** No `NSCameraUsageDescription`, no
`AVCaptureDevice`, no VisionKit, no camera Capacitor plugin. `ios/App/Podfile:12-17`
carries only Capacitor, Cordova, App, Haptics and Preferences.

**Food databases.** Open Food Facts — no API key, ODbL, explicitly free for
commercial use, ~3 M products, strongest on barcodes. USDA FoodData Central —
public domain, free key, 1 000 requests/hour, ~400 k entries, weak on branded
goods. FatSecret — 1.9 M foods, free tier 5 000 calls/day, paid above that.

### F8. Three hazards for whoever executes

- **A concurrent session shares this checkout.** At the time of writing,
  `export-format-overhaul` held uncommitted edits to
  `OnyxCore/Reports/ExportTypes.swift` (+25: `supplementsSkippedUnplanned`,
  `supplementsLater`, `restActualSec`, `primaryMuscles`, `secondaryMuscles`,
  `orderSource`) and `src/lib/reports/weeklyExport.ts` (+75). The
  `concurrent-waves-shared-checkout` rule applies: two sessions share the git
  index, so check `MERGE_HEAD` before `git add` and always pass `SHOT_DERIVED`.
  **No wave in this document may touch the export renderer or its types.**
- **`graphify` IS installed**, at `~/.local/bin/graphify` — an earlier note here
  said otherwise and was wrong. What is missing is `timeout`, which this macOS
  shell does not have, so a command prefixed with it fails with
  `command not found` and looks like the CLI is absent.
- **`docs/sql/actual-rest.sql` is untracked**, awaiting a founder paste. Not this
  sprint's work, but it is sitting in the tree.

---

## Waves

Every wave, without exception: work on its own branch, run patches from script
files, finish with the version bump in `package.json` → `npm run version:sync` →
`cd native && xcodegen generate` → a `docs/CHANGELOG.md` section → `npm run
version:check`. `swift:core` + `swift:data` green; the `OnyxTests` baseline is 5
pre-existing failures, which are not regressions.

### W1a — Opus (extra high) · Week Wrapped curation · v2.5.0 — SHIPPED

Branch `onyx/w1a-week-wrapped`.

**Objective.** The wrap becomes a sheet you can read in five seconds, without
losing a number.

Tasks:

1. `WeeklyWrap.Summary` gains two computed properties in
   `OnyxCore/Training/WeeklyWrap.swift` — no stored fields, no builder change:
   - `bestE1rm: Movement?` — the highest `e1rm` of the week. Distinct from
     `topSet`, which is by **load** and stays. The doc comment at `:165-170`
     already explains why the two differ; extend it rather than replace it.
   - `topProgressed: Movement?` — `progressions.first` (already sorted).
2. `Summary` gains **two stored fields**, both optional and both defaulted in
   `init`, so every existing call site and `WeeklyWrapTests` keep compiling:
   `muscle: MuscleFocusSummary?` and
   `topSession: (label: String, volumeKg: Double, date: String)?`.
3. `WorkoutWeek.wrap(...)` (`Features/Workout/WorkoutWeek.swift:602-678`) fills
   them. The week's sets and exercise names are already in hand in the detached
   `build` (`:457-467`) — call `TodayFeedBuilder.muscleFocus(...)` with the same
   arguments the Today tab passes. Top session = the max of the per-date volumes
   already summed at `:346-349`.
4. `WeeklyWrapView` restructured:
   - **Reel** (visible at the 560 detent): tonnage + delta, best e1RM + delta,
     heaviest set, top volume session, muscle ring. Reuse `stat(...)` (`:103-121`)
     and `topSetCard(...)` (`:123-144`); do not invent a new card style.
   - **Top 3** progressed, then an `OnyxChip` reading `+N more` that expands a
     `DisclosureGroup` holding the full three lists — the existing
     `movementList(...)` verbatim, simply no longer at the top level.
   - Share section unchanged.
   - Update the file header (`:8-17`): its argument is against an *uninvited*
     modal, and that argument still holds for a user-initiated sheet.
5. New `WeeklyMuscleRing` in `Features/Workout/`. Eight arcs by
   `MuscleFamily.of(_:)`, each `Color.onyx.muscleFamily(_:)`, sized by summed
   weighted `sets`. The legend lists the 16 landmarks with their own
   `Color.onyx.muscle(_:)` and set counts — visible only at `.large`.
6. `WorkoutTabView.swift:250-257`: `NavigationLink` → `.sheet(item:)` with
   `.presentationDetents([.height(560), .large])`,
   `.presentationDragIndicator(.visible)` and
   `.presentationBackground(Color.onyx.base)`. The contextMenu rearrange route
   (`:258-267`) is unchanged.

Guardrails:

- **Do not touch** `OnyxCore/Reports/ExportTypes.swift`, `WeeklyExport.swift`,
  `WeeklyExportBuilder.swift`, or anything under `src/lib/reports/` (F8).
- `native-token-discipline` stays green: no raw hex under `Features/`.
- `MuscleFocusSummary` is the **single** weekly-sets accumulator. Do not add a
  second one for the ring.
- `Summary.topSet` stays by load. The reel shows it *and* `bestE1rm`, labelled
  differently, because they answer different questions.

Files: `WeeklyWrap.swift` · `WorkoutWeek.swift` · `WeeklyWrapView.swift` ·
`WeeklyMuscleRing.swift` (new) · `WorkoutTabView.swift` · `WeeklyWrapTests.swift`.

Gate: screenshot loop at 375 pt and AX5 of the 560 detent, the `.large` detent,
the ring and the legend. Eight family hues distinguishable in one ring.

### W1b — Opus (extra high) · Week-detail glow-up · v2.6.0 — SHIPPED

Branch `onyx/w1b-week-detail`. **Depends on W1a** — the wrap chip opens W1a's view.

**Objective.** The week detail stops being black-on-black, gains a hero, and
becomes the permanent door to a past week's wrap.

Tasks:

1. `HistoryWeeks.WeekVitals` (`Features/History/HistoryWeeks.swift:100`) gains
   `weightMeanKg: Double?`, `strain: Double?` and `acwr: Double?`.
   `detail(...)` (`:206-273`) fills the first with the existing private `mean(_:)`
   (`:337`) over the week's weigh-ins, and the other two from
   `Readiness.loadSignal(loads)` — the public path, no visibility change.
2. New `WeekHeroCard` in `WeekDaysView.swift`: four figures — avg weight,
   tonnage, **strain with ACWR as its sub-caption**, fat Δ — as `.onyxType(.display)`
   numerals on `.onyxGlass(.tile)`. `WeekVitalsRow` is kept verbatim underneath.
   Both must collapse to a single column at accessibility sizes, the way
   `WeekVitalsRow` already does (`:243-254`).
3. `DayHistoryRow` (`:309`) gains
   `.onyxMuscleWash(Color.onyx.day(day.dayKey), corner: OnyxCorner.row)`. No new
   modifier. A rest day or a future day gets no wash — a grey rail is honest, a
   coloured one on an empty day is not.
4. `actions(detail)` (`:88-146`) becomes an `OnyxChipRow` under the hero:
   - **Report** — pushes `ReportReaderView`, or the editor when `detail.report == nil`
   - **Export week** — the existing `ShareLink` over `exportFile`
   - **Week wrapped** — opens W1a's `WeeklyWrapView` in the same detent sheet,
     for any complete week (decision 8)
   The `weekIsComplete` lock (`:114-120`) and its dated sentence survive as a
   **disabled chip carrying the same sentence**, not a vanished control.
**Shipped 2026-09-12. Two deviations, both forced and both documented in code:**

- **Task 1's load read is clamped to today.** `Readiness.loadSignal` reports on
  the last seven entries of the series it is handed, so ending the series on
  `window.end` is what makes `strain` this week's. On the LIVE week that end is
  in the future, and `dailyLoads` files a date with nothing on it as a REAL
  zero — which does not merely thin the figures out: it decays the acute side of
  the EWMA through days that have not happened and reports a falling ratio, i.e.
  detraining. The series ends at `min(window.end, today)` instead, and the hero
  says in one line that the live week's window is the seven days ending today.
- **Task 5 was verified and the fallback was NOT taken.** `wrap(...)`'s body is
  already week-agnostic — every week-specific input is a parameter and nothing in
  it reads `today`. What was not reusable was its argument assembly, which lives
  inline in `build` for the live week, plus its `private` visibility. Hoisting
  that is about thirty lines; a `HistoryWeeks`-side `Summary` builder would have
  duplicated the movement tally, the PR replay AND the muscle-focus read, which
  is three accumulators the wave before it spent its length collapsing into one.
  So the smaller move was the entry point, not the second builder.

5. `WorkoutWeek.wrap(...)` is made callable for an arbitrary `weekStart` so a
   past week can be rebuilt. It is already close to pure — it takes its dates,
   sessions and analysis as arguments. Verify before assuming; if it is not, the
   smaller move is a `HistoryWeeks`-side builder assembling the same `Summary`
   from the ledger it has already read.

Guardrails:

- Same export-file prohibition as W1a (F8).
- `WeekDaysView.load()` already builds the full v4 markdown on every screen load
  (`:169-177`). Do not add a second read pass for the wrap — fold it into the
  existing detached `Task`.
- `HistoryWeeks.capsules` is already a whole-history scan, self-documented as
  `ponytail:` debt (`HistoryWeeks.swift:26-28`). Do not make it worse; if the
  wrap rebuild needs a replay, do it in `detail(...)`, which is per-week.

Files: `HistoryWeeks.swift` · `WeekDaysView.swift` · `WorkoutWeek.swift` (if the
arbitrary-week call needs it).

Gate: screenshot loop at 375 pt and AX5 of the hero, the tinted day rows, the
chip row, and the disabled export chip on a live week.

### W2 — Opus (extra high) · In-app Smart Stack carousel · v2.7.0

Branch `onyx/w2-smart-stack`. Independent of Wave 1; shares no files, so it may
run in parallel on its own branch.

**Objective.** Stacking becomes discoverable without a drag, and paging stops
fighting the dashboard's scroll.

Tasks:

1. **Replace the rotated TabView** (`SmartStackView.swift:58-93`) with a custom
   paging carousel: a `ZStack` of faces with an explicit `DragGesture` that
   claims the vertical axis only past a threshold, so the parent ScrollView keeps
   short drags. Fixes **D2**. Preserve every documented behaviour: the 9 s
   period, `stagger(_:)`, the manual hold-off, the pause on edit/background, the
   vertical dot rail, and the hoisted `face` binding.
2. **Face identity by value, not position** (D4): key on a stable composite
   (`"\(index)|\(id.rawValue)"`), so `reorderFace` cannot silently swap what is
   on screen while `items` legitimately repeats a widget.
3. **The clock survives a resume** (D3): track the next-fire instant rather than
   re-sleeping a full period on every `paused` flip.
4. **`Self.period` replaces the hardcoded `9`** (`:84`).
5. **A long-press contextual menu on every tile.** `TileFrame.swift:36` already
   owns the long press; outside edit mode it only enters edit mode today. It
   gains a `contextMenu`:
   - **Create stack / Add to stack →** a submenu of the same-size slots that
     `Dashboard.canStack` accepts, calling `model.stack(_:onto:)`
   - **Unstack this face**, when `slot.items.count > 1` →
     `Dashboard.unstackFace(_:slotId:index:)` (`Layout.swift:474`) on the face
     that is *up*
   - **Edit dashboard** — the existing behaviour, now named
   Fixes **D1** without removing the drag-and-hold route.
6. **The merge highlight reads the visible face** — `DashboardGrid.swift:116`.

Guardrails:

- **Do not touch the WidgetKit extension** (`native/OnyxWidgets/`), App Groups,
  entitlements or `native/project.yml`. Out of scope by decision 1.
- `Dashboard.canStack` / `stackSlots` / `unstackFace` / `reorderFace` are pure
  OnyxCore functions with tests. **Change none of them** — this wave is the UI
  that calls them.
- The carousel must preserve everything documented at `SmartStackView.swift:5-22`.
  That header is the spec; update it, do not contradict it.
- Reduce Motion: animate with `.easeInOut(duration: 0.2)`; auto-rotation stays on
  (already respected at `:86`).
- VoiceOver: the stack stays one element announcing all face titles
  (`TileFrame.swift:49`), with the up face readable.

Files: `SmartStackView.swift` · `TileFrame.swift` · `DashboardGrid.swift` ·
`TodayModel.swift`.

Gate: a stack of three faces pages by swipe without scrolling the dashboard;
rotates on its own 9 s after a resume, not 9 s + stagger; opens the sheet of the
face that is up; survives a reorder without changing what is displayed; and can
be created from a long press with no drag at all.

### W3 — Fable (extra high) · Nutrition Control Center · document only

Branch `onyx/w3-nutrition-plan`. **No code. No version bump.** Researched and
written 2026-09-12 against a live introspection of the database and a full
census of the repo.

**The verdict, up front.** Yes, Onyx can replace MyFitnessPal eventually — but
**not by syncing it**. MFP's public API was withdrawn in **February 2019**
without announcement and is now private; it is not merely partner-gated, it is
**closed to new partners** ("we are not accepting requests for API access at
this time" — [MyFitnessPal Developer Portal](https://www.myfitnesspal.com/apps/api/version);
existing partners contact `api-group@myfitnesspal.com`, not the `API@` address
F7 recorded). MFP writes **meal summaries** to Apple Health — calories and some
nutrients, never food names — and MFP's own support page states it plainly:
*"MyFitnessPal does not support the sync of timestamps when foods are logged in
MFP to Apple Health"*
([Apple Health FAQ](https://support.myfitnesspal.com/hc/en-us/articles/360032271092-Apple-Health-FAQ-and-Troubleshooting)).
Food names and real meal times are therefore unreachable through HealthKit no
matter how good the reader is. Replacing MFP means logging food in Onyx.
Reading MFP can only ever be a bridge — and the bridge with history on it is
Tier 2's CSV, not HealthKit.

#### W3.0 — What re-measurement changed in F7

F7 was written from a grep. This section was written from a census and a live
introspection. Five of its numbers moved, and one of them moves a tier.

| F7 said | Measured | Consequence |
|---|---|---|
| "Twelve read sites hardcode `.eq('meal_type','daily')`" | **20 filtered read sites** — 14 in TS/JS, 6 in Swift — plus **2 unfiltered reads**, 7 write/conflict sites and 3 test assertions | Tier 1 is roughly **twice** the size F7 priced |
| "all 24 `HKQuantityTypeIdentifierDietary*` types" | **25 distinct dietary identifiers**: 15 ingested (`HealthMetrics.swift:116-130`), 10 authorised-but-unread (`:169-179`) | The authorisation sheet is wider than the ingest; per-meal grain buys nothing for the 10 |
| `API@myfitnesspal.com`, "by application" | `api-group@myfitnesspal.com`, **closed to new partners** | There is no application to make. Tier 0 does not exist |
| Onyx "collapses everything into one row per day" | True on the **write** path only. `NutritionModel.eaten` (`:237-245`) and `PulseModel.fuelLine` (`:586-592`) already **sum** every row of the date | Two native surfaces are already Tier-1-shaped; the same change **double-counts** them if the daily aggregate survives beside the meals |
| (not noted) | `scripts/seed-demo-account.mjs:324` writes **`meal_type: 'day'`**, not `'daily'` | A live defect, below |

**The defect the census turned up.** The App Review demo account
(`scripts/seed-demo-account.mjs`, the file `docs/SECURITY_SWEEP_2026-09.md:19`
names as carrying the review credentials) seeds 
`nutrition_entries` with `meal_type: 'day'`. Every one of the 20 filtered read
sites asks for `'daily'`, so on that account the web dashboard, the scorer, the
export and the widget all see **no nutrition at all** — while the native
Nutrition tab and Pulse, which do not filter, see it and sum it correctly. One
seed, two opposite answers, and the split is exactly the aggregate-vs-sum seam
Tier 1 turns on. It is a one-character fix and it should be made whatever the
founder decides about the tiers.

#### W3.1 — The shape today

`nutrition_entries`, from `native/schema/supabase.json:91` (`?` = nullable in
Postgres):

```
id:uuid, user_id:uuid, hk_uuid:text?, logged_at:timestamptz, date:date,
meal_type:text?, calories:numeric, protein_g:numeric, carbs_g:numeric,
fat_g:numeric, fiber_g:numeric?, phase:text?, created_at:timestamptz,
target_kcal:int4?, micros:jsonb?
```

Upsert conflict target `user_id,date,meal_type`; PK `id`; mirror strategy
`window` on `date` (90 days — `MirrorPuller.swift:161`).

Three of those columns are **day-level facts wearing a row-level column**, and
this is what makes Tier 1 more than a filter change:

- **`phase`** is the day's nutrition band (`src/lib/nutrition/phase.ts:7` — "computed
  at write time and stored on nutrition_entries.phase"). A breakfast has no phase.
- **`target_kcal`** is the day's target. A breakfast has no target.
- **`hk_uuid`** carries a UNIQUE index (`nutrition_entries_hk_uuid_key`) and the
  per-day manual sentinel `manual-<date>` (`src/lib/nutrition/manualEntry.ts:24`).
  `manual-2026-07-29` is unique **per day**; four meal rows on one day would need
  `manual-2026-07-29-breakfast` or the second one violates the index — the exact
  bug that file exists to document, reintroduced one grain down.

#### W3.2 — Tier 1: per-meal HealthKit ingest

Stop writing `meal_type='daily'`; write the meal HealthKit's samples group
under. No DDL. That is the whole of the cheap part.

##### The complete read-site inventory

This is the true cost of Tier 1. Twenty sites filter on the literal; two more
read the table with no filter at all and are changed in meaning by the same
edit. **Failure mode** is the column that matters: `LOUD` breaks visibly on the
first multi-row day; `SILENT` keeps returning a number, and the number is wrong.

**TypeScript / JavaScript — 14 filtered sites**

| # | File : line | Shape | On a multi-meal day |
|---|---|---|---|
| 1 | `src/lib/scoring/computeForDate.ts:152` | `.maybeSingle()` | **LOUD** — PGRST116, and it takes **the day's score** with it |
| 2 | `src/app/api/today/route.ts:33` | `.maybeSingle()` in a `Promise.all` | **LOUD** — the whole Today route fails, not just nutrition |
| 3 | `src/lib/hooks/useDayVault.ts:83` | `.maybeSingle()` | **LOUD** |
| 4 | `src/lib/hooks/useNutritionException.ts:56` | `.maybeSingle()` (read-before-restamp) | **LOUD** |
| 5 | `src/lib/ingest/dailyLog.ts:368` | `.maybeSingle()` on `hk_uuid` | **LOUD** — and it is the **manual-override guard**; when it fails, a HealthKit re-sync overwrites a hand-corrected day |
| 6 | `src/lib/hooks/useNutritionException.ts:76` | `.update()` through the filter | **SILENT** — stamps the day's `phase` onto every meal row |
| 7 | `src/lib/hooks/useNutrition.ts:51` | range → `new Map(rows.map(r => [r.date, r]))` at `:105` | **SILENT** — last meal of the day is reported as the whole day |
| 8 | `src/lib/hooks/useCharts.ts:210` | range → macro history chart | **SILENT** — undercount |
| 9 | `src/lib/hooks/useContinuum.ts:51` | range | **SILENT** |
| 10 | `src/lib/hooks/useEnergyBalance.ts:48` | range → deficit ledger | **SILENT** — a wrong energy balance is a wrong weight projection |
| 11 | `src/lib/hooks/useInsights.ts:47` | range | **SILENT** |
| 12 | `src/lib/hooks/useWeeklyLoop.ts:125` | range, incl. `micros` | **SILENT** — and the micros fold is per-row |
| 13 | `src/lib/hooks/useWeeklyLoop.ts:386` | range (multi-week) | **SILENT** |
| 14 | `scripts/repair-calcium.mjs:74` | range, operator script | **SILENT** — a repair script that reads a subset |

**Swift / GRDB — 6 filtered sites** (`Column("meal_type") == "daily"`)

| # | File : line | Shape | On a multi-meal day |
|---|---|---|---|
| 15 | `OnyxData/Scoring/ScoringInputsBuilder.swift:110` | `.fetchOne()` | **SILENT** — arbitrary row wins; **this is the native scorer** |
| 16 | `OnyxData/Health/DailyLogIngest.swift:284` | `.fetchOne()` | **SILENT** — the native manual-override guard, same role as #5 |
| 17 | `OnyxData/Day/DayEditing.swift:597` | `.fetchOne()` in `setManualMacros` | **SILENT** — the override writes one row and the reader sums all of them |
| 18 | `OnyxData/History/WeeklyExportBuilder.swift:260` | `.fetchAll()` → `nutri[r.date] = r` at `:343` | **SILENT** — `:339` says it outright: *"a later duplicate wins"* |
| 19 | `OnyxData/Widget/WidgetSnapshotBuilder.swift:471` | `.fetchAll()` → trend window | **SILENT** |
| 20 | `OnyxData/Widget/WidgetSnapshotBuilder.swift:502` | `.fetchAll()` → ledger window | **SILENT** |

**Unfiltered reads — 2 sites, changed in meaning by the same edit**

| # | File : line | Today | Under Tier 1 |
|---|---|---|---|
| 21 | `OnyxData/Day/DayEditing.swift:580` — `nutritionEntriesStream` | all rows for the date, no `meal_type`; consumers **already sum** (`NutritionModel.swift:239`, `:276`; `PulseModel.swift:587`) | **Already correct** — and **double-counts** the moment a `'daily'` aggregate coexists with meal rows |
| 22 | `OnyxData/Onboarding/AccountSeed.swift:153` | `fetchCount(db) > 0` as an is-this-account-empty gate | unaffected by grain |

**Writes, conflict targets and fixtures — 10 more edits**

| File : line | What |
|---|---|
| `src/lib/ingest/dailyLog.ts:400` | writes `meal_type: 'daily'` |
| `src/lib/ingest/dailyLog.ts:409`, `:412` | `onConflict: 'user_id,date,meal_type'` |
| `src/lib/hooks/useMacroOverride.ts:93`, `:108` | manual override write + conflict target |
| `OnyxData/Health/DailyLogIngest.swift:312` | writes `mealType: "daily"` |
| `OnyxData/Day/DayEditing.swift:601` | writes `mealType: "daily"` |
| `native/schema/supabase.json:86` | the mirror's conflict target |
| `OnyxData/Mirror/MirrorModels.swift:2297`, `:2299` | generated push/pull registry |
| `src/tests/macro-override.test.ts:77`, `:82` | asserts the literal and the conflict target |
| `OnyxDataTests/RowPushTests.swift:76` | asserts the conflict target |
| `scripts/seed-demo-account.mjs:324` | writes `'day'` — the defect above |

##### The precondition nobody has checked: Onyx's reader cannot see a meal at all

Tier 1 is described as writing *"the meal that HealthKit's samples group under"*.
**HealthKit has no such grouping**, and Onyx could not read it if it did.

A dietary sample is a quantity with a start date and optional **metadata**.
Onyx reads every dietary type through **`HKStatisticsQuery`**
(`HealthKitReader.swift:58`, `:99`), which returns a *reduced scalar* — a sum, an
average, a most-recent — and **discards per-sample metadata entirely**. There is
no `HKSampleQuery` anywhere in the ingest path. Whatever meal label MFP may or
may not attach, the current reader is structurally incapable of seeing it.

Getting the grain therefore means moving the dietary reads from
`HKStatisticsQuery` to `HKSampleQuery` — and that is not a neutral swap. The
Capacitor plugin's own header records why the statistics query was chosen
(`ios/App/App/HelixHealth.swift:43-45`):

> *"`HKStatisticsQuery`, which **deduplicates overlapping samples from multiple
> sources** (iPhone + Apple Watch) exactly like the Health app. Using a raw
> `HKSampleQuery` + manual JS sum double-counted steps/energy"*

So Tier 1's enabling change **reintroduces a double-counting bug this repo has
already fixed once**, on the four numbers the nutrition score is computed from.
Dedup would have to be reimplemented by hand against `HKSource` priority, which
is the work `SleepNight.swift:44` already describes as having gone wrong in both
directions on sleep.

**And whether the label exists at all is unverified.** Apple certainly defines
`HKMetadataKeyFoodType` (a string, the food's name or category, **optional**).
Whether Apple defines a *standard meal-slot* key is contested between the sources
consulted for this document, and no claim is made here — **check it in Xcode
against the installed SDK before scheduling Tier 1**, and in the same session
test on a real device whether MyFitnessPal actually populates it. MFP's support
pages say it syncs *meal summaries* without food names and without timestamps;
they say nothing about a meal label, and an unlabelled summary makes Tier 1
buy nothing at all.

**This is the finding that decides Tier 1.** Everything else in this section is
cost; this is feasibility, and it is unresolved. Two hours with a device and
Xcode settle it, and no code should be written before they are spent.

##### Three further hazards that are not read sites

1. **The `daily_logs` mirror trigger.** `src/lib/ingest/dailyLog.ts:406-407` and
   `useMacroOverride.ts:38` both state that *"the DB trigger mirrors macros into
   `daily_logs`"* — and `daily_logs` does carry `protein_g`, `carbs_g` and
   `fats_g` (note the spelling: `fats_g`, not `fat_g`). If that trigger is
   per-row, four meal rows fire it four times and `daily_logs` ends up holding
   **the last meal's macros as the day's**, feeding every reader of `daily_logs`
   — which is a different and larger set than the 20 above. Tier 1 cannot ship
   without rewriting that trigger as a per-day aggregate. *(Live-introspection
   result for this trigger is recorded in W3.6; an earlier audit in
   `docs/sql/e6-auth-deletion.sql:10` found `pg_trigger` unreadable from the
   client, so the code comment was the only evidence until now.)*
2. **`hk_uuid` uniqueness.** Per-day manual sentinels become per-meal sentinels
   or the unique index fires. `manualEntry.ts` exists because this exact bug
   already happened once at day grain.
3. **`phase` and `target_kcal`** stop having a meaning on a row. Either they
   move to `daily_logs` / `daily_targets`, or every meal row carries a copy of
   the day's value and one of the copies will eventually disagree.

##### Tier 1 — cost and ceiling

- **Cost.** 20 filtered reads to convert from *fetch-a-row* to *sum-the-day*, 2
  unfiltered reads to protect from double-counting, 10 write/fixture edits, one
  DB trigger to rewrite, one unique-index scheme to re-derive — **and the
  dietary reader rewritten from `HKStatisticsQuery` to `HKSampleQuery` with
  hand-rolled multi-source dedup**. Five of the reads fail loud (they are the
  cheap ones); **fifteen fail silent**, and four of those are on the scoring or
  export path. No DDL, no new dependency, no new UI.
- **Ceiling — and it is low.** Tier 1 can only redistribute *what MFP already
  wrote*: calories and nutrients per meal summary, with **no food names** and
  **no timestamps**. `logged_at` would remain synthetic. It buys a
  breakfast/lunch/dinner split of numbers the app already has, and nothing else.
  It does not move Onyx one step closer to replacing MFP.

#### W3.3 — Tier 2: MyFitnessPal CSV import (the only route to history)

MFP's **Data Export** is the bridge that survives the API's death. It is a
product feature, not an integration: no credentials, no scraping, no terms-of-
service question, and nothing for MFP to switch off without telling its own
paying customers.

Measured against MFP's own support pages, 2026-09-12
([Export your nutrition, progress, and exercise data](https://support.myfitnesspal.com/hc/en-us/articles/360032273352-Export-your-nutrition-progress-and-exercise-data)):

| Fact | Value | Consequence for Onyx |
|---|---|---|
| Availability | **Premium / Premium+ only** | If the founder does not hold a Premium subscription, Tier 2 has no input at all |
| Where | myfitnesspal.com in a **desktop browser** — not the app | It is a laptop chore, not an in-app flow |
| Selection | confirm email, **choose a date range** | Re-exportable; a backfill can be run once over all history |
| Delivery | **email with a download link**, 1–24 h (usually < 1 h) | Asynchronous by construction — Onyx cannot initiate it |
| Link lifetime | **7 days** | The user must act inside a week |
| Files | three CSVs — **Nutrition**, Progress, Exercise | Onyx wants Nutrition; Progress duplicates `body_composition` |

**What it buys that nothing else can.** Per-entry rows with **food names** and
the meal each belonged to. That is precisely the grain HealthKit throws away,
and it is the only copy of the founder's own logging history that exists
outside MFP.

**What it costs.** A file picker, a CSV parser, a column mapper (MFP's headers
have changed between export generations — the mapper must be tolerant, not
positional), and a **de-duplication rule** against whatever Tier 1 or the
existing HealthKit ingest already wrote for the same dates. The dedup rule is
the hard part and it has no clean key: HealthKit rows carry no food names and
no real timestamps, CSV rows carry both but no `hk_uuid`. The only honest join
is *(user, date)* plus a precedence decision — and the right precedence is
**the CSV wins**, because it is strictly more detailed than the aggregate it
replaces.

**The ceiling.** It is a **snapshot, not a sync**. It stops being current the
moment it is taken, and it stops existing at all the day the user's MFP
subscription lapses. Tier 2 rescues the past; it does not log the present.

**Sequencing.** Tier 2 has no table to land in until Tier 3's `food_entries`
exists. Specifying it before Tier 3 is fine; building it before Tier 3 is not.

#### W3.4a — The constraint that reshapes Tier 3's schema

Before the DDL: one fact about this repo overrides the shape the plan sketched,
and it was not visible from the schema fixture.

**Every mirror pull is hard-scoped to one user.** `MirrorPuller.swift:112`
documents the request it builds:

```
GET /rest/v1/<table>?select=*&user_id=eq.<id>[&<col>=gte.<value>]
```

There is no per-table opt-out. A `foods` row with **`user_id IS NULL`** — the
"null = shared catalogue" shape W3's brief sketched — **would never reach the
phone**. The catalogue would work on the web and be permanently empty in the
native app, which is the app the feature is for.

Three ways out, and they are not equal:

1. **Per-user catalogue rows.** Every lookup writes the food under the looking-up
   user's `user_id`. Duplicates the same Open Food Facts product once per user
   who scans it — which at this app's user count is free — and changes **nothing**
   about the puller. A unique index on `(user_id, source, source_id)` keeps one
   copy per user.
2. **Do not mirror `foods` at all.** `food_entries` already denormalises its
   macros so history renders without the catalogue; the catalogue is only needed
   to *log something new*, which needs the network anyway unless it was cached.
   A device-local SQLite cache outside `MirrorCatalogue` covers the offline
   re-log case.
3. **Teach the puller an unscoped strategy.** Real work in `MirrorPuller`, the
   generator and the registry, and it breaks the one invariant the mirror has —
   that a pulled row belongs to the signed-in user.

**Recommendation: (1), with (2) as the fallback if the catalogue ever grows
large enough that a per-user copy is wasteful.** (3) is the expensive answer to
a problem the app does not have yet.

**Two more generator facts that constrain the DDL** (`scripts/gen-mirror-swift.mjs:149-169`):

- the generated `CREATE TABLE` emits **columns and a primary key only** — no
  foreign keys and **no indexes**. Every server-side index in the sketch below
  buys nothing on device; a local query by `(user_id, date)` on `food_entries`
  is a table scan until someone hand-writes a migration, and `MirrorModels.swift`
  is generated and must never be hand-edited.
- the mirror has exactly **three pull strategies** — `.delta(cursor)`,
  `.window(column)`, `.full`. `food_entries` fits `.window` on `date` like
  `nutrition_entries`. Note the window is **not** 90 days in practice:
  `MirrorPuller.init` defaults to `windowDays: 90`, but the production wiring
  passes **`windowDays: nil`** (`SyncCoordinator.swift:227`), so a `.window`
  table is pulled **whole, every time**. A growing `foods` catalogue fits
  **none** of the three cleanly, which is the second argument for (2).

And the invariant is stronger than a filter. `PostgRESTRemote.swift:89-91`
states it: *"Every mirrored table carries a `user_id`, so one filter serves all
of them, which is what lets the generated catalogue treat twenty-six tables
identically"* — and `:107-108` adds that *"these tables are `NOT NULL` on it"*.
A nullable `user_id` does not merely miss the filter; it breaks the premise the
whole generated mirror is built on.

#### W3.4b — The Tier 3 DDL sketch, table by table

**A sketch, not a migration.** It has not been run and cannot be run from this
machine: there is no `psql`, no Supabase CLI and no exec RPC — PostgREST reads
and writes rows and cannot issue DDL (`docs/sql/w2-generic-model.sql:6-10`).
Shape follows the house style: one file, `begin;`/`commit;`, idempotent
throughout, policies dropped and recreated, a verify query at the end.

Two design decisions are settled before the SQL, because they shape it.

**Micros are `jsonb`, not columns.** Three reasons in order of weight: (1)
`nutrition_entries.micros` is already `jsonb` and the mirror generator maps
`jsonb → JSONText` — 20 typed columns would mean 20 new Swift properties for a
value the scorer only ever reads *aggregated*; (2) source data is ragged — Open
Food Facts reports a different subset of nutrients per product, and
`supabase.json`'s own header is explicit that `nil` must never silently become
`0`; (3) no query needs to filter foods by a micro yet. If one appears, promote
that single key to a real column — `jsonb` does not block it.

**`meal` is `text` + `CHECK`, never a Postgres `enum`.** `gen-mirror-swift.mjs`'s
`TYPES` map has no entry for a custom enum type name, so `parseCols` would throw
the moment the table's `cols` string named one. A `CHECK` constraint is invisible
to the generator, which only reads `name:pgtype`.

##### 1 · `foods` — the catalogue, **per user**

W3.4a is the reason this table differs from the shape the brief sketched:
`user_id` is **NOT NULL**. A `user_id IS NULL` catalogue row cannot reach the
phone, because every mirror pull is `user_id=eq.<id>`. Each user's lookups fill
their own copy. At this app's user count that costs nothing and it keeps the
generated mirror untouched — and it removes an entire risk class, because there
is now no shared row for one user's bad edit to reach another user through.

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- TIER 3 · food logging — DESIGN SKETCH. NOT RUN, NOT A MIGRATION.
-- Paste shape follows docs/sql/w2-generic-model.sql.
-- ─────────────────────────────────────────────────────────────────────────────
begin;

create extension if not exists pg_trgm;

-- ── 1 · foods — this user's catalogue ───────────────────────────────────────
-- user_id is NOT NULL, and that is a SYNC constraint, not a privacy one:
-- PostgRESTRemote.select filters every mirrored table `user_id=eq.<id>` and
-- states that "these tables are NOT NULL on it". A shared catalogue row would
-- be invisible to the native app, which is the app this feature is for.
--
-- Every macro and micro is PER 100 G. food_entries scales them at log time and
-- snapshots the result; nothing ever joins back here to render history.
create table if not exists public.foods (
  id                 uuid        primary key default gen_random_uuid(),
  user_id            uuid        not null references auth.users(id) on delete cascade,

  source             text        not null check (source in ('off', 'usda', 'manual')),
  source_id          text,       -- OFF normalised barcode / USDA fdcId; null for 'manual'
  barcode            text,       -- STORED NORMALISED (OFF rule: <=7 -> 8, 9-12 -> 13)

  name               text        not null,
  brand              text,

  serving_qty        numeric,    -- 1
  serving_unit       text,       -- 'bar', 'cup' — display only, never a conversion
  grams_per_serving  numeric     check (grams_per_serving is null or grams_per_serving > 0),

  calories_100g      numeric     not null check (calories_100g  >= 0),
  protein_g_100g     numeric     not null check (protein_g_100g >= 0),
  carbs_g_100g       numeric     not null check (carbs_g_100g   >= 0),
  fat_g_100g         numeric     not null check (fat_g_100g     >= 0),
  fiber_g_100g       numeric     check (fiber_g_100g is null or fiber_g_100g >= 0),

  micros_100g        jsonb       not null default '{}'::jsonb,
  image_url          text,       -- HOTLINKED. OFF images are CC BY-SA with a
                                 -- third-party-rights carve-out: never copied.
  fetched_at         timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on column public.foods.micros_100g is
  'Keys are exactly the NUTRIENT_TARGETS keys in src/lib/nutrition/nutrientTargets.ts, '
  'units as declared there (mg/mcg/IU/g). A MISSING key means the source did not '
  'report it. Never 0 — the supabase.json nil-is-not-zero rule applies here too.';

create trigger foods_set_updated_at
  before update on public.foods
  for each row execute function public.set_updated_at();

-- One copy of a given upstream record per user.
create unique index if not exists foods_user_source_uq
  on public.foods (user_id, source, source_id)
  where source_id is not null;

-- The VisionKit scan path. Normalised barcode, per user.
create unique index if not exists foods_user_barcode_uq
  on public.foods (user_id, barcode)
  where barcode is not null;

-- Search. Trigram, not tsvector: branded names ("Nature Valley Oats 'n Honey")
-- are SKU-like strings typed as partial, misspelled substrings — trigram
-- similarity tolerates that; tsvector's word ranking is built for prose and
-- would miss "oats n honey". lower() because the app searches case-insensitively
-- and an index on the raw column would not be used by a lower() predicate.
create index if not exists foods_name_trgm_idx
  on public.foods using gin (lower(name) gin_trgm_ops);
create index if not exists foods_brand_trgm_idx
  on public.foods using gin (lower(brand) gin_trgm_ops)
  where brand is not null;

alter table public.foods enable row level security;

drop policy if exists foods_select on public.foods;
create policy foods_select on public.foods
  for select using ((select auth.uid()) = user_id);
drop policy if exists foods_insert on public.foods;
create policy foods_insert on public.foods
  for insert with check ((select auth.uid()) = user_id);
drop policy if exists foods_update on public.foods;
create policy foods_update on public.foods
  for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists foods_delete on public.foods;
create policy foods_delete on public.foods
  for delete using ((select auth.uid()) = user_id);
```

**One deliberate divergence from the other 29 tables.** The policies above wrap
the call as `(select auth.uid())` rather than the bare `auth.uid() = user_id`
that `w2-generic-model.sql:107` uses. Bare, the function is evaluated **once per
row**; wrapped, Postgres evaluates it once and caches it — Supabase's own
guidance puts this at 100× on a large table, and `food_entries` is the first
table in this schema that will hold tens of thousands of rows per user. **This
is a founder call**: adopt the wrapped form for these two tables only and accept
that the file diverges from its 29 siblings, or leave it bare for consistency
and revisit when a query gets slow. Do not adopt it *silently*.

##### 2 · `food_entries` — one logged item

```sql
-- ── 2 · food_entries — one logged item ──────────────────────────────────────
create table if not exists public.food_entries (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users(id) on delete cascade,

  date         date        not null,
  logged_at    timestamptz not null default now(),  -- a REAL instant, unlike
                                                    -- nutrition_entries.logged_at,
                                                    -- which HealthKit ingest sets to midnight

  meal         text        not null check (meal in ('breakfast','lunch','dinner','snack')),

  food_id      uuid        not null references public.foods(id),
  quantity     numeric     not null check (quantity > 0),
  unit         text        not null check (unit in ('g','ml','serving')),

  -- THE COPY OF RECORD. Scaled from foods.*_100g at log time. A later catalogue
  -- correction must NEVER rewrite a day already logged: this repo has shipped a
  -- retroactive re-grade before (hotfix-polish-sprint, "the one-baseline
  -- re-grade of 32 days") and must not ship a second one.
  calories     numeric     not null check (calories  >= 0),
  protein_g    numeric     not null check (protein_g >= 0),
  carbs_g      numeric     not null check (carbs_g   >= 0),
  fat_g        numeric     not null check (fat_g     >= 0),
  fiber_g      numeric     check (fiber_g is null or fiber_g >= 0),
  micros       jsonb       not null default '{}'::jsonb,

  -- Tier 2's idempotency key: a stable hash of the MFP CSV row. Null for
  -- anything logged natively or by barcode.
  external_ref text,

  created_at   timestamptz not null default now()
);

alter table public.food_entries enable row level security;

drop policy if exists food_entries_select on public.food_entries;
create policy food_entries_select on public.food_entries
  for select using ((select auth.uid()) = user_id);
drop policy if exists food_entries_insert on public.food_entries;
create policy food_entries_insert on public.food_entries
  for insert with check ((select auth.uid()) = user_id);
drop policy if exists food_entries_update on public.food_entries;
create policy food_entries_update on public.food_entries
  for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists food_entries_delete on public.food_entries;
create policy food_entries_delete on public.food_entries
  for delete using ((select auth.uid()) = user_id);

-- ── indexes ─────────────────────────────────────────────────────────────────
-- The window pull reads by date; every reader groups by day.
create index if not exists food_entries_user_date_idx
  on public.food_entries (user_id, date);

-- The roll-up's own read: every item for one user+date, by slot.
create index if not exists food_entries_user_date_meal_idx
  on public.food_entries (user_id, date, meal);

-- Re-running a CSV import over the same range must not duplicate rows.
create unique index if not exists food_entries_external_ref_uq
  on public.food_entries (user_id, external_ref)
  where external_ref is not null;

-- FK index: Postgres does not create one for a referencing column, and a
-- `delete from foods` would otherwise seq-scan this table.
create index if not exists food_entries_food_id_idx
  on public.food_entries (food_id);
```

**None of those indexes exist on the phone.** `gen-mirror-swift.mjs:149-169`
emits columns and a primary key only — no foreign keys, no indexes — and
`MirrorModels.swift` is generated and must never be hand-edited. A local query
by `(user_id, date)` is a table scan until someone adds a hand-written GRDB
migration beside the generated one. At 3,650 rows that is fine; it is recorded
here so nobody is surprised at 30,000.

##### 3 · The roll-up seam — `nutrition_entries` stays a table, and `'daily'` becomes derived

This is the piece that makes Tier 3 additive rather than a rewrite. Four options
were compared; the recommendation is **(a), a trigger on `food_entries`**, and
the other three are recorded with the reason they lose.

| Option | Why not |
|---|---|
| **(a) trigger on `food_entries` upserts the `'daily'` row** | **Recommended.** Same table, same PK, same `on conflict (user_id,date,meal_type)` the client already speaks. Nothing about the mirror contract changes. And the pattern is not new here — a trigger already fans `nutrition_entries` macros out to `daily_logs` |
| (b) replace the table with a VIEW | A view has no unique index, so the mirror's `upsert(onConflict:)` push has nothing to conflict against. `INSTEAD OF` triggers would reimplement (a) underneath a view for no gain |
| (b′) MATERIALIZED VIEW | Cannot be upserted at all; `REFRESH … CONCURRENTLY` needs its own unique index and runs on a schedule, so a windowed pull can read a snapshot that predates a food logged seconds ago |
| (c) application-level recompute | The mirror is **bidirectional with two client languages**, both able to be offline. Two clients editing one day would race and silently drop one side — the exact "racy delete-then-insert" `dailyLog.ts:405` says it moved *away* from. A trigger row-locks and serialises for free |
| (d) generated/denormalised hybrid | This *is* (a), stated precisely: one physical table, two write authorities over **disjoint slices of `meal_type`** |

**The sharp question: can Tier 1's per-meal rows and Tier 3's derived daily row
coexist?** Yes, and by construction rather than convention — Tier 1 writes only
`meal_type IN ('breakfast','lunch','dinner','snack')`, the trigger writes only
`meal_type = 'daily'`. No two writers ever target the same row.

The real risk is the opposite of the obvious one. On a day with *both* a
HealthKit breakfast row and a natively logged lunch, a naive
`SUM(food_entries)` **undercounts** — it never sees the HealthKit breakfast.
The precedence rule is therefore **per meal slot, not per day**: for each of the
four slots, `food_entries` wins if it has any row for that `(date, meal)`;
otherwise the HealthKit `nutrition_entries` row for that same slot is used.
Never both for one slot. That is what prevents the double count *and* the
undercount, and it is why the two vocabularies must be identical strings.

```sql
-- ── 3 · provenance, then the roll-up ────────────────────────────────────────
alter table public.nutrition_entries
  add column if not exists source text not null default 'healthkit'
    check (source in ('healthkit', 'onyx'));

create or replace function public.recompute_nutrition_daily()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(new.user_id, old.user_id);
  v_date date := coalesce(new.date,    old.date);
begin
  -- `target_kcal` and `phase` are DAY-level facts written by the goal ladder,
  -- not by food. They are read and written back unchanged so a food edit never
  -- clobbers them — see W3.1 on why those two columns are the awkward ones.
  insert into public.nutrition_entries
    (user_id, date, meal_type, logged_at, source,
     calories, protein_g, carbs_g, fat_g, fiber_g)
  select v_user, v_date, 'daily', now(), 'onyx',
         sum(calories), sum(protein_g), sum(carbs_g), sum(fat_g), sum(fiber_g)
  from (
    -- slots Onyx has native rows for
    select meal as slot, sum(calories) calories, sum(protein_g) protein_g,
           sum(carbs_g) carbs_g, sum(fat_g) fat_g, sum(fiber_g) fiber_g
      from public.food_entries
     where user_id = v_user and date = v_date
     group by meal
    union all
    -- slots Onyx has NOT touched, filled from HealthKit's row for that slot.
    -- This union is what stops the undercount.
    select meal_type, calories, protein_g, carbs_g, fat_g, fiber_g
      from public.nutrition_entries
     where user_id = v_user and date = v_date
       and meal_type <> 'daily' and source = 'healthkit'
       and meal_type not in (
         select distinct meal from public.food_entries
          where user_id = v_user and date = v_date)
  ) slots
  having count(*) > 0
  on conflict (user_id, date, meal_type) do update set
    logged_at = excluded.logged_at, source    = excluded.source,
    calories  = excluded.calories,  protein_g = excluded.protein_g,
    carbs_g   = excluded.carbs_g,   fat_g     = excluded.fat_g,
    fiber_g   = excluded.fiber_g;
  return null;
end;
$$;

drop trigger if exists food_entries_recompute_daily on public.food_entries;
create trigger food_entries_recompute_daily
  after insert or update or delete on public.food_entries
  for each row execute function public.recompute_nutrition_daily();

commit;
```

**Five things this sketch deliberately leaves open rather than faking:**

1. **Deleting the last food of a day leaves a stale `'daily'` row.** When
   `slots` comes back empty — the user deletes their only logged item and
   HealthKit has nothing for that date either — `having count(*) > 0` correctly
   suppresses the insert, and the *existing* `'daily'` row is therefore left
   behind carrying yesterday's totals. The trigger only ever upserts; it never
   deletes. It needs an explicit `delete from public.nutrition_entries where
   user_id = v_user and date = v_date and meal_type = 'daily' and source =
   'onyx'` on the empty branch — guarded by `source = 'onyx'` so it can never
   delete a row HealthKit or the manual override owns.

2. **The `micros` merge is missing.** Summing two `jsonb` bundles keyed by
   nutrient, per contributing slot, is a `jsonb_object_agg` over a lateral
   unnest — mechanical but verbose, and belongs in the implementation, not in a
   sketch dressed up as finished SQL. As written the trigger leaves `micros`
   alone; that is wrong and it is flagged, not hidden.
3. **`FOR EACH ROW` is wrong for Tier 2.** A CSV import of two years inserts
   thousands of rows and re-sums the whole day on every one. Either make the
   import path a statement-level trigger, or drop the trigger for the import
   transaction and recompute once at the end. *(`ponytail:` per-row recompute,
   fine for hand logging, quadratic for bulk import — fix before Tier 2.)*
4. **`nutrition_entries.source` is a new column on a MIRRORED table**, so it must
   be added to `native/schema/supabase.json` `cols` **as nullable** even though
   Postgres declares it `NOT NULL DEFAULT` — that is the `sleep_inaccurate` rule
   the fixture's own header states, and it exists so a pull that ran before the
   DDL paste can still decode a row.
5. **`nutrition_entries` must be on the realtime channel.** A `.window` pull with
   `windowDays: nil` reads whole history today, so a backdated edit does land —
   but the strategy's own doc string warns it "misses an edit to a row older than
   the window" if a window is ever reintroduced. Confirm the table is in
   `MirrorRealtime`'s list before relying on trigger-side writes reaching a
   second device.

##### 4 · `recipes` / `recipe_items` — deferred, deliberately

Not built. The founder has not asked, and they add a **second** snapshot problem
on top of the one `food_entries` already solves: recipe macros drift when an
ingredient is edited, so they need their own snapshot-on-log rule. If asked for
later it is additive and not a redesign — `recipes(id, user_id, name)`,
`recipe_items(recipe_id, food_id, quantity)`, and a nullable
`food_entries.recipe_id`. Confirm the skip; do not build it on spec.

##### 5 · Barcode capture

`VisionKit.DataScannerViewController`, iOS 16+. The native app's deployment
target is **iOS 18.0** (`native/project.yml:24-25`), so it is available with no
pod, no Capacitor plugin and no dependency — `ios/App/Podfile:12-17` stays as it
is. What it needs is **`NSCameraUsageDescription` in `native/project.yml`**, and
the repo has **no camera usage string on any target today**. The string is an
App Review surface: `project.yml:162-165` records that Review rejects a generic
one, so it must name the data and the purpose.

#### W3.4c — Food databases: licence and rate limit, per API

Verified 2026-09-12 against each provider's own documentation, with live probes.
**The decisive column is the last one**, because an offline-first food logger
must keep a local copy of every food it has ever shown, and one of these three
APIs forbids exactly that.

| | **Open Food Facts** | **USDA FoodData Central** | **FatSecret Platform** |
|---|---|---|---|
| Base | `world.openfoodfacts.org`, **API v3** (v2 deprecated) | `api.nal.usda.gov/fdc/v1` | `platform.fatsecret.com/rest/` |
| Key | **none for reads** | **required**, free, api.data.gov | OAuth 2.0 `client_credentials` **or** OAuth 1.0 |
| Rate limit | **15 req/min** product read · **10 req/min** search, per IP | **1,000 req/hour per IP** | **5,000 calls/day** |
| On breach | **IP ban, no status code** (global limits return `503`) | **HTTP 429**, key blocked 1 hour; `X-RateLimit-*` headers on every response | unverified |
| Licence | **ODbL 1.0** (database) + DbCL 1.0 (contents) | **CC0 1.0 — public domain** | proprietary |
| Attribution | **mandatory** | **requested, not required** | **mandatory, incl. the App Store listing** |
| Commercial use | **explicitly permitted** | unrestricted | permitted on their terms |
| Coverage | ~3 M products, strongest barcode coverage, international | strong US whole foods; Branded (with `gtinUpc`) updated monthly; **weak outside the US** | 1.9 M foods |
| **May we cache rows permanently?** | **Yes** | **Yes, unconditionally** | **No — 24 hours** |

##### The FatSecret blocker, quoted

FatSecret's Storable Data guide and ToU §1.5 are explicit:

> *"you may not cache any user data for more than 24 hours, with the exception
> of information that is explicitly 'storable indefinitely'. **Only the
> following parameters are storable indefinitely; all other information must be
> requested from fatsecret each time.**"*

The exhaustive storable list is **identifiers only** — `food_id`, `recipe_id`,
`serving_id`, `food_entry_id` and siblings. **Food names, brands, serving
descriptions and every nutrient value are not on it.** A cached `foods` row
would violate it, and so would a `food_entries` row that denormalises their
kcal and protein — which is precisely what history-that-cannot-be-rewritten
requires. Add that barcode scanning is **Premier-exclusive** (not in the free
tier), attribution is mandatory *in the App Store listing description*, and
ToU §1.7.iii forbids using the API *"to provide diet, nutrition or health advice,
guidance or diagnosis"* — which is arguably what Onyx is.

**FatSecret is out.** Not on price; on terms. Revisit only under a Premier
contract with written storage rights.

##### What ODbL actually obligates

ODbL is a free licence and commercial use is explicitly authorised. Two clauses
bite:

- **§4.3, attribution.** The nutrition screen is a *Produced Work* and must
  carry a notice. ODbL's own example wording: *"Contains information from
  DATABASE NAME, which is made available here under the Open Database License
  (ODbL)."* The database name links to Open Food Facts; "Open Database License"
  links to the licence text. This is one line of UI and it is not optional.
- **§4.4, share-alike — and it only bites on a *Substantial* part.** A cache
  filled on demand with the few hundred products a user personally scanned is
  not substantial. **Bulk-loading the 1.19 GiB CSV dump would be**, and it drags
  §4.6 with it — an obligation to hand every recipient a machine-readable copy
  of the derivative database. §4.5b puts it beyond doubt that using the data to
  make a Produced Work is not itself a Derivative Database.

  **Rule for Onyx: cache on lookup, never bulk-import.** The engineering
  decision and the licence decision happen to agree.

- **Images are a different licence.** Product photos are **CC BY-SA**, not ODbL,
  and OFF adds a carve-out: they *"may contain graphical elements subject to
  copyright or other rights"* — packaging design, trademarks, the image rights
  of people on the packaging — and *"it is the responsibility of individuals and
  entities who wish to re-use… to verify by themselves the rights that may
  apply."* **Hotlink product images; never copy them into our storage.**

##### Four operational facts the sketch depends on

1. **Always send `fields=`.** A full OFF v3 product payload measured
   **138,224 bytes**; the same product projected to the dozen fields Onyx renders
   measured **2,854 bytes**. A 48× difference, and at 1,500 cached foods it is
   the difference between ~1.2 MB and ~207 MB on the device.
2. **v3 returns a clean 404** for an unknown barcode
   (`{"status":"failure","result":{"id":"product_not_found"}}`) where v2 returned
   `200` with `status: 0`. That 404 is the negative-cache signal, and it is one
   more reason v2 is not an option.
3. **Barcodes are normalised by OFF and the cache key must match.** ≤7 digits pad
   to 8; 9–12 digits pad to 13. A probe of `0000000000999` came back as
   `code: "00000999"` with a `different_normalized_product_code` warning. Key the
   cache — and the negative cache — on the **normalised** code, or every miss is
   stored under a string OFF will never return. USDA's `gtinUpc` uses a
   **different** padding (14-digit, zero-padded), so the two cannot share a key.
4. **Neither OFF v2 nor v3 offers server-side full-text search.** The options are
   the legacy `/cgi/search.pl` or Search-a-licious at `search.openfoodfacts.org`
   — which is live, but a probe returned a record stamped
   `"last_indexed_datetime":"2024-10-26"`, i.e. an index roughly two years stale.
   **Verify before depending on it.** OFF also says in terms:
   *"don't use it for a search-as-you-type feature, you would be blocked very
   quickly."* Search fires on submit or a ≥600 ms debounce, never per keystroke.

   *(USDA gotcha, measured: passing `&nutrients=1008,1003,…` to `/food/{id}`
   returned `"foodNutrients":[]` on a Branded food in both comma-list and
   repeated-param forms. Take the full ~17 KB and project it server-side.)*

##### Who calls the API

**A Next.js API route proxies both.** One reason: **the USDA key cannot be
rotated without an App Store release.** Anything in the iOS binary is
extractable, USDA deactivates keys found in public repositories, and the limit
is per-key/per-IP anyway — so shipping it buys nothing and costs a submission
cycle every time it leaks. `SUPABASE_SERVICE_ROLE_KEY` already lives
server-side; the USDA key joins it there.

The counter-argument is recorded with its trigger. OFF states: *"If your
requests come from your users directly (ex: mobile app), the rate limits apply
per user."* A proxy collapses every user into one 15 req/min budget. At Onyx's
user count that is far more headroom than any human needs. **Move the OFF leg to
direct device calls — keeping USDA on the proxy — if sustained aggregate OFF
traffic approaches ~10 req/min**, and not before, because doing so means
shipping and maintaining the required `AppName/Version (ContactEmail)`
User-Agent inside a binary.

##### Offline

Reuse the four pieces the app already has; add no fifth. `MirrorPuller`
(server → SQLite), the **outbox** (`RowPush.enqueueRowUpsert(table:id:nulls:in:)`,
enqueued *inside the caller's transaction* so the row and the intent to upload
it land together or not at all), `MirrorRealtime`'s 400 ms coalescer, and
`SyncCoordinator`'s `push → health → pull → score`. For 429/503, reuse
`SyncBackoff` (`Sync/SyncTranslation.swift:80` — base 10 s, doubling, cap
3600 s, 25 % jitter); do not write a second backoff.

A barcode lookup is a **read**, and reads do not belong in an outbox whose
contract is "this write must reach the server".

| Offline action | Works | Why |
|---|---|---|
| Log a food already cached | **yes** | local row, local write, outbox drains later |
| **Re-scan a barcode already cached** | **yes** | the common case — people eat the same yoghurt |
| Manual macro entry | **yes** | no network in the path |
| Edit or delete a log row | **yes** | the outbox already collapses opposing items |
| Text search within cached foods | **yes** | local `LIKE` over a few hundred rows |
| **First-time barcode scan** | **no — genuinely impossible** | the data is not on the device. No design fixes this |
| First-time text search | **no** | same |

On an offline miss, say so and go straight to manual entry with the scanned
barcode recorded on the row. Do not queue a retry or promise to fill it in later.

##### Volume

5 foods/day for 2 years = **3,650 `food_entries` rows** ≈ **0.9–1.8 MB** in
SQLite. For scale, `workout_sets` already holds **2,389 rows live** and sits in
the same mirror comfortably. A habitual logger touches **300–800 distinct
foods** in two years; at a pessimistic 1,500 cached foods × ~800 B projected,
the catalogue is **~1.2 MB**. **Total ≈ 3–6 MB. Nothing here threatens the
mirror** — provided fact 1 above holds and only the projection is ever stored.

#### W3.5 — Decision point: should Onyx ever WRITE dietary samples to HealthKit?

**Stated, not resolved.** This is a founder decision and it is deliberately left
open. What follows is the evidence on both sides and the one fact that makes it
sharper than it looks.

**First, a correction to F7 and to the brief.** "Every HealthKit call in this
repo is read-only" is **not true**, and the exception matters because it removes
one of the arguments against writing.

Read-only, confirmed:

- `OnyxData/Health/HealthKitReader.swift:32` — `try await store.requestAuthorization(toShare: [], read: types)`
- `ios/App/App/HelixHealth.swift:35` — `self.store.requestAuthorization(toShare: nil, read: types)`

**Already writing, in the watch app:**

- `OnyxData/Watch/WorkoutSessionController.swift:71-77` —
  `let share: Set<HKSampleType> = [HKObjectType.workoutType()]` then
  `try await store.requestAuthorization(toShare: share, read: read)`
- `:142` — `builder.finishWorkout { … }` writes the workout, with heart-rate and
  active-energy samples attached. `:154` names the alternative explicitly:
  *"Stop without writing anything to Health — the discard path."*
- `native/project.yml:180` already carries an `NSHealthUpdateUsageDescription`.

So the accurate statement is narrower and more useful: **Onyx already writes to
HealthKit, but only workouts, and only from the watch. No dietary type has ever
appeared in a `toShare:` set, on any target.** The precedent, the authorization
pattern and the plist key all exist. What does not exist is a dietary write —
and the reason to be careful about one is not precedent, it is the ingest loop
below.

One concrete cost either way: the existing update string is scoped to workouts
— *"Onyx saves the strength workouts you log — their duration, active energy and
heart rate"* — and `project.yml:162-165` records that **App Review rejects a
generic string**. Writing dietary samples means rewriting that copy to name food
data and its purpose, which is an App Review surface, not just a plist edit.

**The argument for writing.** If Tier 3 lands and the user logs food in Onyx,
Onyx becomes the source of truth for their diet — and every other app that reads
dietary energy from Health (rings, third-party coaches, a doctor's app) goes
blind. Writing back is what makes Onyx a citizen of Health rather than a
one-way consumer of it. It is also the only way a user can leave Onyx later
without losing their data to a proprietary store.

**The argument against, and it is specific to this repo.** Onyx reads dietary
energy with a plain cumulative sum over *every* source:

```swift
// HealthKitReader.swift:52-59 — no source predicate
let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum)
```

If Onyx writes its logged food to Health, the **next sync reads its own writes
back and adds them to the day**. That is a feedback loop, not a duplicate —
the number grows on every sync until something clamps it. Breaking it needs
`HKQuery.predicateForObjects(from:)` excluding Onyx's own source on every
dietary read, which is a change to the one function every metric in the app
goes through.

And the loop would be **invisible on exactly the numbers that matter**. Onyx
already has per-source attribution — `quantityBySource(_:start:end:)`
(`HealthKitReader.swift:88`, `.separateBySource`) and the `key@source` fan-out
into the micros bundle (`DailyLogIngest.swift:351-355`) — but `HealthSync.swift:94`
gates it on `HealthCatalogue.microKeys`, which is the **nine micros only**.
Calories, protein, carbohydrate and fat — the four figures the nutrition score
is computed from — carry no source breakdown at all. A doubling there would
show up as a person who suddenly eats twice as much, with nothing in the row to
say why.

**The duplicate problem is also not ours to clean up.** Two apps writing dietary
samples for the same meal produce two samples; HealthKit does not de-duplicate
discrete dietary samples across sources the way it does overlapping step
counts. The user's only remedy is Health → Sources → Onyx → Delete All Data,
which deletes the good history with the bad.

**The question to answer.** Three positions, and they are not equally cheap:

1. **Never write.** Onyx stays a reader. Cheapest, and it keeps the ingest
   loop provably acyclic. Cost: Onyx-logged food is invisible to the rest of
   the user's Health ecosystem.
2. **Write, and exclude our own source on read.** The correct version of
   "write". Requires the source predicate on every dietary read, per-source
   attribution extended from the 9 micros to the 4 macros, and a one-way
   ownership rule (a day Onyx logged is a day Onyx does not ingest). This is
   the largest single piece of HealthKit work in the tier.
3. **Write only on explicit export.** A user-initiated "push this week to
   Health" with a visible warning, never automatic. Sidesteps the loop by
   making it rare and consented, but leaves Health permanently behind.

**Nothing in Tier 1 or Tier 2 requires an answer.** Tier 3 does, and the answer
changes its size. Decide it before the first `foods` row exists, not after.

#### W3.6 — What could not be measured from here, and the query that settles it

The live introspection for this document ran through **PostgREST's OpenAPI
document and REST reads**, because there is no Supabase MCP server configured
in this session, no `psql`, no Supabase CLI on the machine, and no direct
Postgres connection string in `.env.local`. That channel returns columns,
Postgres types, NOT-NULL-ness and defaults. It does **not** return constraint
bodies, index definitions, RLS policy text, triggers, function bodies or the
extension list.

**What it did settle** (live, 2026-09-12):

| Fact | Value |
|---|---|
| `nutrition_entries` rows | 162, one `user_id`, `date` 2026-03-09 → 2026-09-12 |
| `meal_type` distinct values, live | **`'daily'` only** — 162 of 162. No meal split exists yet anywhere |
| `meal_type` default | **`DEFAULT 'daily'`** — not recorded in `native/schema/supabase.json` |
| `calories`, `protein_g`, `carbs_g`, `fat_g` | **NOT NULL DEFAULT 0** |
| `id` default | `extensions.uuid_generate_v4()` → **uuid-ossp is installed** |
| `hk_uuid` | text, nullable; 107 of 162 populated, all distinct |
| `foods`, `food_entries`, `recipes`, `recipe_items`, `food_log`, `meals`, `nutrition_targets`, `nutrient_targets` | **none exist** |
| Live table count | **34** — two more than the 32 in `native/schema/supabase.json`: `set_events` (433 rows) and `joint_flags` (0 rows) are live and unmirrored |
| Anon key, no session, on `nutrition_entries` | `200` with `[]` and `content-range: */0` — behaviourally consistent with RLS on and user-scoped, which is **not** the policy text |

**What it could not settle — and all of it is load-bearing for Tier 1:**

- whether the `daily_logs` macro-mirror trigger exists, and whether it is
  `FOR EACH ROW` or an aggregate;
- the exact definition of `nutrition_entries_hk_uuid_key` and whether it is
  partial;
- whether `meal_type` carries a CHECK constraint;
- the RLS policy bodies on `nutrition_entries`;
- whether `pg_trgm` is installed, which decides how food-name search is built.

`docs/sql/e6-auth-deletion.sql:10` records that `pg_trigger`, `pg_policies`,
`pg_constraint` and the advisors were already out of reach once before. This is
the same wall. **Paste this into the Supabase SQL editor before Tier 1 is
scheduled** — it is read-only and it answers all five:

```sql
-- 1 · triggers on nutrition_entries (the daily_logs macro mirror)
select tgname, pg_get_triggerdef(oid) as def
from pg_trigger
where tgrelid = 'public.nutrition_entries'::regclass and not tgisinternal;

-- 2 · every index and its exact definition
select indexname, indexdef from pg_indexes
where schemaname = 'public' and tablename = 'nutrition_entries';

-- 3 · every constraint body (CHECK on meal_type included)
select conname, contype, pg_get_constraintdef(oid) as def
from pg_constraint where conrelid = 'public.nutrition_entries'::regclass;

-- 4 · RLS state and policy bodies
select relrowsecurity, relforcerowsecurity
from pg_class where oid = 'public.nutrition_entries'::regclass;
select policyname, cmd, qual, with_check from pg_policies
where schemaname = 'public' and tablename = 'nutrition_entries';

-- 5 · extensions, for the food-search decision
select extname, extversion from pg_extension order by extname;
```

Anything Tier 1 assumes about the trigger before that query runs is a guess,
and the failure mode of guessing wrong is a `daily_logs` row that silently
holds one meal's macros as the day's.

#### W3.7 — The three tiers: cost and ceiling, side by side

| | **Tier 1** per-meal HealthKit | **Tier 2** MFP CSV import | **Tier 3** native logging |
|---|---|---|---|
| **New tables** | none | none of its own — lands in Tier 3's | `foods`, `food_entries` (+`recipes`/`recipe_items`, deferred) |
| **DDL** | none — but one trigger to rewrite | none | a paste-into-the-SQL-editor file, the `w2-generic-model.sql` shape |
| **Call sites touched** | **20 filtered reads + 2 unfiltered + 10 writes/fixtures** | ~0 existing; all new code | the roll-up seam only, if the seam holds |
| **HealthKit reader** | **rewritten** — `HKStatisticsQuery` → `HKSampleQuery`, with multi-source dedup rebuilt by hand | untouched | untouched |
| **Feasibility** | **UNPROVEN.** Depends on a meal label that may not exist and that the current reader cannot see (W3.2) | proven — it is a file | proven |
| **New dependency** | none | none (CSV parse is stdlib-shaped) | none — VisionKit and URLSession are native |
| **New permission** | none | file access | **camera** (`NSCameraUsageDescription` — the repo has none today) |
| **Silent-failure surface** | **15 of 20 reads fail silently**, 4 on scoring/export | duplicate rows against Tier 1 dates | catalogue drift vs denormalised history |
| **Ceiling** | whatever MFP wrote: numbers per meal, **no food names, no real timestamps** | the **only** route to food names and per-entry history — but it is a snapshot, not a sync, and it stops the day the user stops exporting | none of consequence — this is the actual replacement |
| **Buys Onyx independence from MFP?** | **No** | **Partly** — history only | **Yes** |

**The honest ranking.** Tier 1 is the cheapest to *describe* and the most
expensive to *verify*: it costs twenty read-site conversions and a trigger
rewrite to buy a breakfast/lunch/dinner split of numbers that carry no food
names, and it leaves Onyx exactly as dependent on MyFitnessPal as it is today.
Tier 3 is the only tier that changes the answer to the founder's question, and
Tier 2 is the only tier that rescues the history. **If the goal is to replace
MFP, Tier 1 is the tier to skip** — its twenty edits are better spent once, on
the roll-up seam Tier 3 needs, than twice.

The one piece of Tier 1 worth doing on its own merits is the `'day'` vs
`'daily'` seed defect in W3.0, which is a one-character fix and not a tier.

#### W3.8 — What the founder must decide before any of this is built

Ten decisions. Decision 0 gates the others; 1-4 gate the tiers; 5-9 gate Tier 3 only.

0. **Before anything: two hours with Xcode and a device.** Does a standard
   meal-slot metadata key exist in the installed SDK, and does MyFitnessPal
   populate it on the samples it writes? If the answer to either is no, **Tier 1
   is not merely expensive, it is impossible**, and decision 1 answers itself.
   Nothing should be scheduled before this is known (W3.2).
1. **Which tier is the goal?** If the answer is "replace MFP", Tier 1 is a
   detour — say so now and spend its twenty edits on Tier 3's seam instead.
2. **Does Onyx write dietary samples to Health?** W3.5, stated not resolved.
   Positions 1, 2 and 3 have materially different sizes and the answer changes
   Tier 3's scope. This is the single biggest open question in the document.
3. **Is a camera permission acceptable?** Barcode scanning needs
   `NSCameraUsageDescription` in `native/project.yml`. The repo has no camera
   string today, and adding one adds an App Store review surface
   (`docs/APP_STORE.md`). Without it, Tier 3 is text search only — which is
   usable, and is how the whole-foods half of the catalogue works anyway.
4. **Does the MFP history matter enough to pay for Tier 2?** The export is
   Premium-only, emailed, a snapshot, and the link expires in seven days. If
   the founder does not hold an MFP Premium subscription, Tier 2 has no input
   and should not be specified further.
5. **Per-user food catalogue, or a shared one?** Decided by the mirror
   constraint in W3.4 — a shared catalogue cannot reach the phone through the
   existing puller. Pick the per-user copy, the device-local cache, or pay to
   change the puller.
6. **Are micros on `foods` columns or jsonb?** `nutrition_entries.micros` is
   already jsonb and the mirror generator maps `jsonb` to `JSONText`. Consistency
   argues jsonb; queryability argues columns.
7. **Which nutrients does a food carry?** `NUTRIENT_TARGETS`
   (`src/lib/nutrition/nutrientTargets.ts:50-113`) names 21, but six of them —
   creatine, citrulline, caffeine, theanine, glycine, and partly EPA/DHA — come
   from `supplementNutrients.ts` and the stack, not from food. A `foods` table
   carrying all 21 would have six columns nothing can ever fill.
8. **Do recipes exist in v1?** The plan says skip until asked. Confirm the skip.
9. **Who runs the DDL?** It cannot run from this machine — no `psql`, no
   Supabase CLI, no exec RPC (`docs/sql/w2-generic-model.sql:6-10`). Every table
   in Tier 3 is a paste into the Supabase SQL editor by the founder, followed by
   a re-introspection into `native/schema/supabase.json` and `npm run mirror`.

---

## Copy-paste prompts

### W1a prompt

```
You are Opus (extra high effort), Lead Frontend & Design on Onyx. Read
docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md fully (F1-F3, F8, decisions 2-4, 11-13,
W1a). Execute W1a — Week Wrapped curation. You own Features/Workout only.

IMPORTANT, read before you plan: the adaptive This-week entry ALREADY SHIPPED in
v2.2.0. Do not rebuild it. WeeklyWrapView, WeekOverrideSheet and
WeeklyWrap.isWrapped all exist and work. Your job is the PRESENTATION (push ->
detent sheet) and the CONTENT (three uncapped lists -> highlight reel + Top 3
behind a disclosure).

Skills: graphify (query before grep; note the CLI is not installed on this
machine — say so rather than faking it), native, apple-design, ui-design-system,
ui-ux-pro-max, frontend-design, visual-check (screenshot loop, ALWAYS pass
SHOT_DERIVED), git-commit-helper.
Agents: ui-ux-designer (are 8 family arcs distinguishable in one ring at 375 pt,
and does the 16-landmark legend read at AX5), ios-developer (a ScrollView inside
a .height(560) detent that must not fight the drag-to-expand), swift-expert
(adding two stored fields to WeeklyWrap.Summary without breaking Equatable /
Sendable or any existing call site), invariant-auditor (MANDATORY —
TodayFeedBuilder.muscleFocus is reaching a new consumer; it must stay the single
weekly-sets accumulator), code-reviewer (final diff).

Tasks 1-6 from W1a. Reuse stat(...) and topSetCard(...) — do not invent a new
card style. Summary.topSet stays by LOAD; bestE1rm is a separate, separately
labelled figure. Update the WeeklyWrapView file header rather than contradicting
it: its argument is against an UNINVITED modal, which a user-initiated sheet is
not.

DO NOT TOUCH: OnyxCore/Reports/ExportTypes.swift, WeeklyExport.swift,
WeeklyExportBuilder.swift, or anything under src/lib/reports/ — a concurrent
session owns those files. Check MERGE_HEAD before any git add.

Branch onyx/w1a-week-wrapped. Version v2.5.0 + changelog. Report: screenshots at
375 pt and AX5 of the 560 detent, the .large detent, the ring and the legend.
```

### W1b prompt

```
You are Opus (extra high effort), Lead Frontend & Design on Onyx. Read
docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md fully (F4, F5, F8, decisions 5-8, 11-13,
W1b). W1a is merged. Execute W1b — the week-detail glow-up. You own
Features/History.

Skills: graphify, native, apple-design, ui-design-system, ui-ux-pro-max,
frontend-design, visual-check (ALWAYS pass SHOT_DERIVED), git-commit-helper.
Agents: ui-ux-designer (wash intensity behind ultraThinMaterial across seven
rows — read OnyxMuscleWash.swift's own header on why 6% and not 28% before
tuning; and the chip-row hierarchy against the hero), ios-developer,
invariant-auditor (MANDATORY — the new weekly mean weight and the strain/ACWR
read), code-reviewer.

Tasks 1-5 from W1b. Training load is Foster weekly STRAIN with ACWR as its
sub-caption, both via the PUBLIC Readiness.loadSignal(loads) — do not widen
fosterWeek's visibility for one caller. Reuse .onyxMuscleWash and OnyxChipRow;
write no new modifier and no new chip component. The export lock keeps its dated
sentence as a DISABLED chip, never a vanished control. A rest day and a future
day get no wash.

Before task 5, VERIFY whether WorkoutWeek.wrap(...) can be called for an
arbitrary weekStart. If it cannot without restructuring, build the Summary on the
HistoryWeeks side from the ledger detail() has already read, and say so in the
report — do not force the refactor.

DO NOT TOUCH: the export renderer or its types (see F8).

Branch onyx/w1b-week-detail. Version v2.6.0 + changelog. Report: screenshots at
375 pt and AX5 of the hero, the tinted day rows, the chip row, and the disabled
export chip on a live week — plus the wrap chip opening a month-old week.
```

### W2 prompt

```
You are Opus (extra high effort), Lead iOS Engineer on Onyx. Read
docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md fully (F6, decisions 1 and 9, W2).
Execute W2 — the in-app Smart Stack carousel. You own Features/Today.

IMPORTANT: "widgets" here means the IN-APP dashboard cards. Do NOT touch
native/OnyxWidgets/, App Groups, entitlements or native/project.yml. The in-app
stack ALREADY EXISTS and auto-rotates — SmartStackView.swift is a 90-degree
rotated TabView(.page). This is a defect wave plus a discoverability fix, not a
build.

Skills: graphify, native, apple-design, ui-ux-pro-max, frontend-design,
visual-check (ALWAYS pass SHOT_DERIVED), git-commit-helper.
Agents: ios-developer (LEAD — DragGesture versus the parent ScrollView;
simultaneousGesture vs highPriorityGesture vs a custom Gesture with a minimum
distance, and which one lets a short drag still scroll the dashboard),
swift-expert (the rotation task's structured-concurrency lifetime across pause
and resume), ui-ux-designer (contextMenu wording, and whether the affordance
actually makes stacking discoverable), code-reviewer.

Tasks 1-6 from W2, which are defects D1-D4 plus two minors. Dashboard.canStack /
stackSlots / unstackFace / reorderFace are pure OnyxCore functions with tests —
change NONE of them; this wave is the UI that calls them. SmartStackView.swift's
header comment (lines 5-22) is the spec: update it, never contradict it.

Branch onyx/w2-smart-stack. Version v2.7.0 + changelog. Report, on device or
simulator: a stack created from a long press with no drag; a swipe that pages
without scrolling the dashboard; a background-and-resume that rotates 9 s later
rather than 9 s + stagger; and a reorder that does not change the visible face.
```

### W3 prompt

```
You are Fable (extra high effort), Lead Architecture & DB Strategist on Onyx.
Read docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md fully (F7, decision 10, W3).
Execute W3 — the Nutrition Control Center specification.

WRITE NO CODE. No migrations, no DDL executed, no logging UI. The deliverable is
the W3 section of this document, expanded in place.

Skills: graphify, schema, supabase-postgres-best-practices, senior-architect,
capacitor-offline-first.
Agents: schema-truth-checker (introspect the LIVE database for every claim about
an existing column — never read src/lib/supabase/types.ts, which declares 17
tables while the app queries 29; native/schema/supabase.json is the generated
source of truth the GRDB mirror is built from), database-architect (the foods /
food_entries shape, and specifically the roll-up seam that keeps
nutrition_entries working as a derived daily row), backend-architect (Open Food
Facts and USDA caching, rate limits, offline behaviour), architect-reviewer.

Produce: (1) the Tier 3 DDL sketch, table by table, with RLS and indexes; (2) the
COMPLETE inventory of read sites that hardcode .eq('meal_type','daily'), file and
line, since that list is the true cost of Tier 1 and it reaches scoring; (3) the
licensing note per food API with its rate limit; (4) a decision point, stated not
resolved, on whether Onyx should ever WRITE dietary samples to HealthKit — every
HealthKit call in this repo is currently read-only.

Branch onyx/w3-nutrition-plan. No version bump. Report the three tiers with an
honest cost and ceiling for each, and name what the founder must decide before
any of it is built.
```

---

## Verification (sprint level)

- **After W1a:** finish the last planned session of a week; the This-week tile
  says "Week wrapped"; tapping it opens a **sheet** at 560 pt showing five visual
  cards and exactly three progressed rows; dragging up reveals the 16-landmark
  legend and the full lists.
- **After W1b:** open a past week in History; four big figures on top (strain
  carrying ACWR beneath it), eight cells below, every logged day row carrying its
  split's hue on a rail, three chips under the hero, and the wrap chip opening
  the same reel for a week that closed a month ago.
- **After W2:** create a stack from a long press with no drag; swipe it without
  scrolling the dashboard; background and resume the app and watch it rotate 9 s
  later; reorder the faces and confirm the visible one does not change.
- **After W3:** the document answers the MyFitnessPal question with a date and a
  source, names every table Tier 3 adds, and contains no code.
