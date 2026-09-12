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
12. **Native only.** The web app was untouched (no wrap surface; `WeeklyWrap`
    is Swift-only) and was retired in W6 of the epic sprint.
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
(`OnyxData/Health/HealthKitReader.swift:28-32`). There is no
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

Branch `onyx/w3-nutrition-plan`. **No code. No version bump.**

**The verdict, up front.** Yes, Onyx can replace MyFitnessPal eventually — but
**not by syncing it**. MFP's public API died in 2019 and access is now private
and partner-only. MFP writes meal summaries to Apple Health with **no
timestamps**, so food names and real meal times are unreachable through
HealthKit no matter how good the reader is. Replacing MFP means logging food in
Onyx. Reading MFP can only ever be a bridge.

#### Tier 1 — per-meal HealthKit ingest (cheap, no new dependency, no DDL)

Onyx already authorizes all 24 dietary types and then discards the grain by
writing one `meal_type='daily'` row.

- **Schema:** `nutrition_entries` already keys on `(user_id, date, meal_type)`.
  Tier 1 stops hardcoding `'daily'` and writes the meal that HealthKit's samples
  group under. **No DDL.** The `hk_uuid` unique index and the `manual-YYYY-MM-DD`
  sentinel (`src/lib/nutrition/manualEntry.ts:25`) need a per-meal variant.
- **Cost:** the ~12 read sites hardcoding `.eq('meal_type','daily')` must become
  a sum over the day's meal rows. Enumerate every one; the aggregate-vs-sum
  switch is the whole risk, and it reaches scoring.
- **Ceiling:** whatever MFP wrote. No food names, no real timestamps.

#### Tier 2 — MyFitnessPal CSV import (the only route to history)

MFP Premium exports a per-entry nutrition CSV by date range, emailed to the user.

- **Schema:** needs `food_entries` (Tier 3) to land in. A parser and a mapper,
  not a sync — no credentials, no ToS problem, no scraping.
- **Value:** the only way to recover food names and per-entry history.
- **Cost:** a file picker, a CSV parser, a column mapper, and a de-duplication
  rule against Tier 1's HealthKit rows on overlapping dates.

#### Tier 3 — native logging (the actual replacement)

- **Schema** (new tables, all RLS by `user_id`):
  - `foods` — `id`, `user_id?` (null = catalogue, non-null = the user's own),
    `source` (`off` / `usda` / `manual`), `source_id`, `barcode`, `name`,
    `brand`, `serving_qty`, `serving_unit`, `grams_per_serving`, per-100 g
    macros plus the 20 micros `src/lib/nutrition/nutrientTargets.ts` already names.
  - `food_entries` — `id`, `user_id`, `date`, `logged_at` (a **real** timestamp),
    `meal`, `food_id`, `quantity`, `unit`, plus denormalised macros so a
    catalogue edit cannot rewrite history.
  - `recipes` / `recipe_items` — only if the founder asks. Skip until then.
  - **`nutrition_entries` becomes a derived daily roll-up of `food_entries`**,
    which keeps every existing reader, scorer and export working unchanged. This
    seam is what makes Tier 3 additive rather than a rewrite.
  - GRDB mirrors are generated: add the tables to `native/schema/supabase.json`
    and run `npm run mirror`. Never hand-write `MirrorModels.swift`.
- **Barcode:** `VisionKit.DataScannerViewController` (iOS 16+). Native, no pod,
  no dependency. Needs `NSCameraUsageDescription` via `native/project.yml` — the
  repo has **no camera usage string today**.
- **Food database:** **Open Food Facts** (no key, ODbL, commercial-OK, ~3 M
  products, best barcode coverage), with **USDA FoodData Central** (public
  domain, free key, 1 000 req/h) as the whole-foods fallback where OFF is thin.
  Cache both into `foods` on first lookup so the app works offline — the pattern
  `capacitor-offline-first` already describes.
- **Writing back to Health** would be new ground: every HealthKit call in the
  repo is read-only. Decide deliberately — two apps writing dietary samples
  create duplicates that Health cannot clean up.

Deliverable: this section expanded in place with the Tier 3 DDL sketch, the
full read-site inventory Tier 1 must change, and the licensing note per food API.

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
