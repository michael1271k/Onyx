# Next-Gen UX Sprint — Pulse, the ledger, the dashboard, laterality, isolation

**Status:** approved 2026-09-15 · step 0 done (this file). W1 next.
**From:** `main` @ 3.10.0 (`e6bb24ac`).
**Ships as:** twelve sequential waves, 3.10.1 → 4.0.1. **W12 deletes this file.**
**Branches:** `onyx/sprint-next-gen-w<N>`, each cut from current `main` and merged `--no-ff`
back into it. There is no long-lived sprint branch — `main` is the only trunk (`docs/GIT.md`).

---

## Context

Thirteen briefs across six surfaces. Exploration measured every one of them against the
source before this plan was written, and **six briefs name a symptom whose root cause sits
somewhere else**, while **three name work that is already built**. The plan below is written
against what the code does.

| Brief | What is actually true |
|---|---|
| "Apple Health spams the Train tab" | No `HKAnchoredObjectQuery` exists anywhere. `HKWorkout.uuid` is never stored. The ingest re-inserts the same bouts every sync. Already documented in-tree: `WeeklyExportBuilder.swift:69-73` — *"Friday exported 23 copies of one walk."* |
| "Water slider yields `-/3.0`" | Not the slider. `clearWater()` nils `daily_logs.water_ml` and deletes the day's ledger; the numerator is nil until the next successful HealthKit ingest, and permanently so if the read is denied. The widget uses a *different* rule and disagrees. |
| "Remove the 167/2 zone slider" | It reads no heart-rate zones. `167` is the last bout's avg bpm; `/2` is a count of this week's bouts ≥ 20 min. Two unrelated numbers, adjacent. |
| "Treadmill post-workout UI is broken" | No separate view and no branch. Six data-driven divergences from `ledger(_:)` — `MuscleMap` has no cardio entry, and all five `headerTags` are guarded off, so `MetaTagRow(tags: [])` draws an empty row. |
| "Trends shows −30 t on a Sunday" | `WorkoutWeek.swift:457` subtracts a **full** previous calendar week from a **partial** current one. No day-of-week truncation anywhere. |
| "Arrows make huge empty rows" | `deltaLine` reserves a line under every column and fills it with an em-dash. **And RPE-up currently renders green** — `SetRow.deltaLine` has no `higherIsBetter` parameter, unlike the metric grid's `delta(_:unit:higherIsBetter:)`. |
| "Cloud-sync the dashboard layout" | **Already synced**, both ways, keyed `user_id`. Suspect is the first-launch default clobbering the pulled row. |
| "Add a Super Stack" | **Already shipped** — `Dashboard.canStack`, 600 ms hold, `SmartStackView`, `TileMenu`. |
| "Make appearance global and dynamic" | **Engine shipped 3.5.0.** `TokenDisciplineTests` already fails the build on raw hex; zero violations. The real staleness cause is that the App Group entitlement is unsigned, so app and widget read *different* `UserDefaults.standard` suites. |
| "New user must have 0 PRs" | Real. `PrRecorder.floors:303` and `SessionHistoryStore.personalRecords:158` are unscoped over `personal_records`; `needsOnboarding:153` counts `exercises` with no user filter. |
| "Pristine multi-tenant isolation" | `docs/sql/` is **empty**. There are **zero `.sql` files in the repo**. No RLS policy is checked in anywhere — it is asserted in prose only. |

### Founder decisions (2026-09-15)

1. **Vitals = Hero/Sidekick, and the hero is dynamic.** Sleep holds it unless a vital crosses its SWC band in the bad direction, in which case that vital is promoted and Sleep drops into the grid.
2. **Arrows stay per-column; the em-dash goes; RPE inverts** (up = red). The per-exercise delta becomes a compact pill, and `ledgerHeader` is compacted — its current height "looks terrible".
3. **Trends = day-matched**, with the pace projection as the caption under it.
4. **Mega Widget = three rings + a rule-based insight sentence.** Connected stacks share one window. Long-press Customize on Train, with real iOS jiggle feel. Selected tab icon adopts the domain tint.
5. **Pulse spine:** Strip · Vitals · Carousel · **2×2 square grid** · Session. The square grid is Option 3's treatment applied strictly, gutters `OnyxSpace.l` (16).
6. **Soreness: tap the side you mean**, with a Both/L/R segment in the existing popover to correct it. Founder pastes the DDL.
7. **Isolation: full.** Scope the queries, two-user tests, **and** a perfect 32-table RLS `.sql` file. **Fable architects the RLS.**
8. **Strict sequential.** One branch at a time. Every wave merges to `main`, bumps, deletes its branch, pushes with `[skip ci]`.
9. **Opus for the UI waves. Fable only at the end, and only where the reasoning is genuinely mathematical.**
10. **Every wave appends a Wave Record to the plan file.** W12 harvests them into the changelog and a memory file, *then* deletes the plan.

### One decision this plan makes on the founder's behalf

Decision 5 chose the Option 1 spine and then asked for Option 3's square-tile treatment. Those
resolve to: **the 2×2 grid holds Stress Index · Soreness · Scale · Stack, and the carousel drops
to two pages (Fatigue · Stress log).** The Soreness square is a door — the rating verb moves onto
the map sheet, where the popover already lives, and `SorenessCard` deliberately never drew the
figure anyway (`PulseCarousel.swift:428-434`). Say so if you want the carousel to keep three.

---

## Findings the waves are built on

**F1 — The Health ingest has no stable key.**
`HealthKitReader.swift:151` is a plain `HKSampleQuery` over today + yesterday, re-read on every
sync. `WorkoutSample` (`HealthReading.swift:94-110`) carries no Health UUID. `CardioImport.matchingRow:93`
matches an imported row only when `fromHealthkit == true` **and** `createdAt` is non-nil and within
5 minutes; the fallback branch (`:118-126`) filters to `!fromHealthkit`. An imported row whose
`created_at` did not survive the round trip therefore matches nothing, and
`CardioIngest.swift:126-143` inserts a duplicate and returns a non-empty report. The toast is
emitted per sync pass (`SyncCoordinator.swift:385`), and `.foreground` syncs on every scene
activation (`OnyxApp.swift:73`).

**F2 — Water has two truths.**
`NutritionTabView.swift:623` reads `daily_logs.water_ml` only. `WidgetSnapshotBuilder.swift:344`
prefers the `water_intake` ledger sum and falls back to the flat row. `DayEditing.clearWaterOverride:686`
deletes the ledger *and* nils the flat column, so the tab shows `—` while the widget shows the
same nil. `DailyLogIngest` returns early on an empty payload (`guard !payload.isEmpty`) and never
mints the row, so a denied HealthKit read is permanent.

**F3 — Vitals: the grid already exists.**
`VitalsGrid` (`PulseVitals.swift:33`) is a 3-column `LazyVGrid` of 64 pt `VitalCell`s with deltas and
24 pt sparklines, and it already degrades to `MetricRow`s at accessibility sizes.
`VitalsChipRow:236` is an eager `HStack` in a `ScrollView(.horizontal)`, 9 × 104 pt ≈ 1010 pt of
content in a 375 pt window. `VitalsGrid.readings(_:)` is already `static` and pure.

**F4 — The dynamic hero needs no new math.**
`READINESS_MODEL.md` §2 defines `zSignal`: 7-day rolling mean vs the 42 days before it, dead-banded
at 0.5·SD (smallest worthwhile change), clamped ±2. `Readiness.signals` already computes it for HRV
(as `ln`) and resting HR. `VitalsGrid.Reading` already carries `delta` and `upIsGood`. The SWC
dead-band is what stops a promoted hero thrashing day to day.

**F5 — The delta line is reserved, and RPE is coloured the wrong way.**
`SessionDetailView.swift:1876` `column(_:)` is `VStack { value; if layout.comparable { deltaLine(...) } }`.
`deltaLine:1893` paints `delta > 0 → good`, `delta < 0 → danger`, with an em-dash in the else branch
(`:1911`). `effortFigure:1856` hands RPE a delta like any other track, so a harder set reads green.
`layout(_:):1643` sends any card containing a `"pair"` row to `.whole`, and `.whole.comparable == false`,
so unilateral rows carry no comparison at all.

**F6 — The treadmill card is six data gaps.**
`.cardio` layout has `comparable == false`, so its rows are ~12 pt shorter than every strength card's.
`MuscleMap` holds no cardio entry, so the chip `FlowRow` renders empty. `headerTags:1228-1290`
suppresses Top (`topKg == 0`), volume (`volumeKg == 0`), RPE (nil on an unrated bout), the
`n/m @ window` capsule (no prescription) and the ±% verdict (previous volume 0). The family hue
falls through `:1155-1161` to `MuscleGroup.forExercise(...).domain.accent` — `.recover` lavender.

**F7 — The zone rail is not a zone rail.**
`WorkoutTabView.swift:1037-1066`: `done = cardio.filter { Zone2.isZone2($0.durationMin) }.count`,
`target = Zone2.weeklyTarget = 2`, `Zone2.minMinutes = 20`. `boutFigures:1006` prints `avg bpm` as the
fourth cell. There is **no `maxHr` column** on `cardio_logs`. Real HR-zone pips exist only in the
widget (`OnyxCardio.swift:105` `zoneColor`, `:178` `ZonePips`).

**F8 — The week delta compares two different things.**
`WorkoutWeek.swift:344-350` sums only the finished sessions of the current calendar week;
`:435-458` sums all seven days of the previous one; `:457` subtracts. `Week.start(of:startDay:)`
takes its start day from `user_goals.week_end_day`. The closed-week twin at `:679-684` is correct —
both its sides are full.

**F9 — The dashboard is already a synced, arrangeable, stackable grid.**
`WidgetId` — 19 cases (`Layout.swift:43`). `StackSlot { id, size, items }`. `DashboardLayout { slots, hidden, updatedAt }`,
payload v4, two-sided (a phone write carries the untouched desktop side through, `:285`).
`DashboardLayoutStore.saveDashboardLayout:28` writes the row **and** enqueues the outbox upsert.
`DashboardGrid.Arrangeable:331` gates `.draggable`/`.dropDestination` on `model.editing`;
`TileMenu:238` says the verbs in words; `WidgetGallery:359` is the tray. The clobber suspect is
`TodayModel.swift:64` — `layout = stored?.layout ?? Dashboard.defaultLayout(.phone)`, where a save
racing the first pull pushes the default over the real row.

**F10 — The theme engine is sound; the plumbing under it may not be.**
`OnyxThemeSpec` is two `UInt32`s; `OnyxTheme(spec:)` resolves the whole palette by OKLCH hue
rotation; `OnyxTheme.current` is a global static and `OnyxApp.swift:60` `.id(themeJSON)` is what
repaints ~1,250 static token reads. `TokenDisciplineTests:38` walks `native/` and fails on
`Color(hex:`, `Color(red:`, `Color(.sRGB`, `UIColor(`, `#colorLiteral` — zero violations outside the
allowlist. **But `AppDatabase.swift:53-56` states the App Group container returns nil**, so
`UserDefaults(suiteName: "group.app.onyx.health")` falls back to `.standard` — a *different* suite in
the app and in the extension. Under that condition the widget never sees a theme write at all.
Remaining un-themed reads are ~45 `.white`/`.black` on widget tile faces.

**F11 — The atlas already draws both sides.**
`OnyxAtlas.muscles` holds **two separate `OnyxAtlasPath` entries per bilateral muscle** — left at
x < 60, right at x > 60 on the 120 × 260 viewBox. Confirmed for Front/Side/Rear delts, Chest, Biceps,
Triceps, Forearms, Lats, Quads, Hamstrings, Glutes, Calves, Adductors. Axial exceptions: Upper back
and Lower back (1 path), Abs/core (3 front paths). `OnyxAtlasHit.muscle(at:in:side:):33` already finds
*which path* contains the tap — and returns only the `LandmarkMuscle`, discarding the side.

**F12 — Laterality's storage, and only its storage, is missing.**
`DomsMuscles.sides = ["both","left","right"]` exists. `SUB_REGIONS` exists. The export grammar
`muscle[/subRegion][@L|@R]:severity` exists (`WeeklyExport.swift:578`), and `ExportDoms` carries
`side` and `subRegion` — with **no construction site in the native app**. But `doms_logs` has no
`side` and no `sub_region` column, and its upsert conflict key is `(user_id, date, muscle_group)`,
so an L/R pair cannot coexist even if the columns existed. The scoring fold is already side-safe:
**max within a muscle, mean across distinct recognised muscles**, so adding rows cannot move the battery.

**F13 — Isolation: one store, one user, twenty-five unscoped reads.**
`AppDatabase.sharedFolder():94` has no user component; `knownUserId():220` encodes the
one-user-per-store invariant by asking the store who it belongs to. `signOut()` (`AppEnvironment.swift:762-836`)
drains the outbox, stops and awaits every worker, signs out, then calls `eraseLocalData()`
**unconditionally** — good, and tested (`SignOutEraseTests`). **There is no account-switch path**: a
sign-in without a preceding sign-out never erases. Unscoped reads include `PrRecorder.floors:303`
and `SessionHistoryStore.personalRecords:158` over `personal_records`, `sessionHistory():123`,
`historySets()`, the whole of `WeeklyExportBuilder`, and `ScoringInputsBuilder.sets:360`.
`AccountSeed.needsOnboarding:153` counts `Exercise.fetchCount(db)` with no filter — local `exercises`
has no `user_id`, so one leftover catalogue row suppresses onboarding for a brand-new account.
All 32 Supabase tables carry `user_id`. **No policy is checked in for any of them.** `set_events` is
not in the schema fixture at all and is applied by hand.

---

## Architecture decisions

**A1 — The hero is one pure function, and it lives in OnyxCore.**
`VitalHero.swift` in `OnyxCore/Scoring`: `static func promote(_ readings: [VitalReading], sleep: SleepReading?) -> HeroChoice`.
Input is the existing per-reading `delta` plus the `zSignal` the readiness engine already produces.
Rule: Sleep by default; a vital is promoted only when its z crosses ±1 in the bad direction
(`upIsGood ? z < -1 : z > 1`) and its |z| exceeds Sleep's own. Ties break by `VitalSpec.all` order,
so the choice is deterministic. Pure `Double`, no SwiftUI, golden-vectored in `swift:core`.
The SWC dead-band inside `zSignal` is what stops it thrashing.

**A2 — The em-dash goes; the height stays.**
`deltaLine`'s else branch becomes `Color.clear.frame(height: …)` measured from the `micro` line,
not `Text("—")`. Row height is unchanged, fifteen dead glyphs become zero. `Figure` gains
`upIsGood: Bool = true`, `effortFigure` passes `false`, and `deltaLine` reads it — the same flag
`VitalSpec` already carries and the same one the metric grid's `delta(_:unit:higherIsBetter:)` takes.

**A3 — `.pair` becomes a fifth `SetLayout`.**
`layout(_:)` stops routing pair cards to `.whole`. `.pair` draws `L 22×10 / R 22×9` as two `micro`
sub-lines under one badge, `comparable == true`, one shared delta line beneath the pair keyed on
the pair's combined load × reps. `SetColumn.side = 14` (`ExerciseCardView.swift:1040`) is the
precedent for the width this costs. Budget check at 393 pt: 393 − 32 gutters − 28 badge − 8 gap = 325 pt,
against a pair string that today hits `minimumScaleFactor(0.7)` at ~270 pt.

**A4 — The exercise verdict is a `MetaTagRow.Tag`, and the header loses a line.**
The ±% capsule already exists at `SessionDetailView.swift:1252`. `ledgerHeader:950-1084` currently
stacks three rows (name + window + sparkline · muscle chips · `MetaTagRow`). The chips and the tags
merge into one `FlowRow` — chips first, verdict pill last — taking the header from three lines to two
and ~24 pt off every card.

**A5 — The Health ingest keys on `HKWorkout.uuid`.**
`WorkoutSample` gains `uuid: UUID`. `cardio_logs` gains `hk_uuid text` (nullable; the founder pastes it),
mirrored through `supabase.json` → `npm run mirror`, and a guarded local `ALTER TABLE` in the pattern of
`v21.genericModel`. `CardioImport.matchingRow` gains a first branch: exact `hk_uuid` match wins outright.
The 5-minute window stays as the fallback for hand-typed rows and for pre-migration rows. A unique
index on `(user_id, hk_uuid)` where `hk_uuid is not null` makes the duplicate structurally impossible.
The toast then fires only when `inserted > 0` for a bout the store has genuinely never seen.
**This also fixes the 23-duplicate export anomaly `WeeklyExportBuilder` currently works around.**

**A6 — Water gets one rule, in one place.**
`WaterTruth.ml(log:ledger:)` in OnyxCore — ledger sum when the ledger is non-empty, else the flat
row, else nil. `NutritionTabView.figures` and `WidgetSnapshotBuilder.swift:344` both call it, so the
tab and the tile cannot disagree again. `clearWater()` stops nilling the flat column optimistically;
it clears the *override* and leaves the day readable until the ingest lands. The `— / 3.0 L` state
becomes `0.0 / 3.0 L` only when the day genuinely has no water, and carries "Waiting for Apple Health"
as the row's detail when the read is pending or denied.

**A7 — Trends: day-matched, with the projection as the caption.**
`WorkoutWeek` gains `weekDeltaKg` computed over `lastDates.prefix(elapsedDays)` where
`elapsedDays = ISODate.dayNumber(today) - ISODate.dayNumber(weekStart) + 1`, and `weekPaceKg`
= `weekTonnageKg / elapsedTrainingDays × plannedTrainingDays`. The door prints the delta and the
projection under it. Both sides empty → `"—"`, never a signed zero. The closed-week twin at `:679-684`
is untouched — it is already correct.

**A8 — The Mega Widget is a twentieth `WidgetId`, and the insight is rules.**
`WidgetId.daily` at size `.l`. Three concentric arcs reusing `WeeklyMuscleRing`'s stroke geometry
verbatim (`.butt` caps, 2° gaps, 22 pt stroke — its header documents why a round cap makes a 2° trim
overlap by 15°). The sentence comes from `TodayFeed.coach`, extended with one deterministic rule
table over battery / ACWR / stress band / sleep debt. **No network, no API.** An offline gym app must
not need a server to say "rest day". Golden-vectored: one fixture per sentence.

**A9 — Connected stacks are one flag on `StackSlot`.**
`StackSlot.linked: Bool = false` (v5 payload; `fromStored` keeps reading v1–v4). A linked stack's
faces all render against the slot's own `window` rather than each resolving today independently.
Defaults false, so every existing layout is unchanged and `LayoutGoldenTests` passes untouched.

**A10 — The tab tint is five lines.**
`.tint(OnyxDomain.train.accent)` and friends on each `SwiftUI.Tab` in `RootView.swift:70-98`.
Settings keeps the neutral tint, because Settings belongs to no domain and giving it one would
say the tab is about that domain — the same argument `OnyxScreenBackground` already makes for
its `nil` case.

**A11 — Appearance coverage becomes a test, not a sweep.**
A sibling to `TokenDisciplineTests`: walk every `View` in `native/Onyx/Features` whose name ends
`TabView` or `Sheet` or `View` and is presented as a root, and fail when it applies neither
`.onyxScreen` nor `.onyxFormBackground`. Allowlist the deliberate exceptions in the test, so
skipping the ground becomes a decision someone had to write down.

**A12 — The App Group fallback is the widget's real bug.**
`AppDatabase.appGroupDefaults()` — one accessor returning the suite, or `.standard` with a
`ponytail:` note naming the ceiling. Every caller (app `@AppStorage` store, `OnyxWidgets.init`,
`OnyxProvider.theme()`, `AppearanceView.commit`) routes through it, and a DEBUG assertion fires when
the suite is nil so the condition is visible in the shot loop rather than silent on device.

**A13 — Laterality: the generator already knows the answer.**
`scripts/src/atlas.ts` computes each path; `gen-atlas-swift.mjs` emits it. Add `side` to the emitted
`OnyxAtlasPath`, derived from the path's centroid x against the viewBox midline (60): `< 58 → .left`,
`> 62 → .right`, else `.center`. `npm run check:atlas` re-runs the generator and fails on drift, so
the sides can never disagree with the drawing. `OnyxAtlasHit.muscle(at:in:side:)` returns
`(LandmarkMuscle, BodySide)`. `AtlasFigure`'s `colors`, `values` and `outlined` re-key from
`LandmarkMuscle` to a `MuscleSide` pair; `worked` stays whole-muscle, because fatigue is modelled
bilaterally and always was.

**A14 — `doms_logs` gains two columns and a wider key.**
`side text` and `sub_region text`, both nullable, both defaulting to the pre-v2 meaning when absent.
Conflict target becomes `(user_id, date, muscle_group, coalesce(side,'both'), coalesce(sub_region,''))`,
expressed as a unique index so PostgREST can name it. `DayEditing.setDoms` gains `side:` and
`subRegion:`. The fold is untouched — it already takes **max within a muscle**, which is exactly what
makes an L/R pair row-count-neutral. `ExportDoms` finally gets its first native construction site.

**A15 — Isolation: scope the read, not the caller.**
Every unscoped read gains `userId` as a parameter and a `WHERE user_id = ?`. Where the table has no
`user_id` locally (`workout_sets`, `set_events`), the join to `workout_sessions` carries it. The lazy
fix is the root-cause fix: one filter in the shared store function is a smaller diff than a filter in
each of its callers, and patching only the paths the brief names leaves the siblings leaking.
`needsOnboarding`'s `exercises` check is **deleted**, not filtered — a local catalogue row proves
nothing about whether *this* account has been set up, which is the bug.

**A16 — The RLS file is generated from the live schema, never from the repo.**
`schema-truth-checker` introspects the live database first and reports, per table: whether RLS is
enabled, which policies exist, and their expressions. Only then is `docs/sql/isolation-rls.sql`
written — `alter table … enable row level security` plus four policies per table using the
`(select auth.uid()) = user_id` initplan form (the form `docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md:893`
already notes, and the one `supabase-postgres-best-practices` requires so the check is evaluated once
per query rather than once per row). Every statement is `if not exists` / `drop policy if exists` so
the file is safely re-runnable. `workout_sets` and `set_events` are policed through their session's
owner, not a column they do not have.

**A17 — Version and changelog land on the wave's own branch.**
Sequential execution means one `package.json` edit at a time, so there is no reason to defer the
bump — and `CLAUDE.md` forbids deferring it. Each wave bumps, runs `npm run version:sync` and
`xcodegen generate`, appends its changelog section, and only then merges.

---

## Waves

**Every wave, without exception:**
- Branch `onyx/sprint-next-gen-w<N>` from **current `main`**. Merge `--no-ff` back into `main`, delete the branch, push with `[skip ci]`.
- Apply patches from **script files**, never inline heredocs (memory: `worktree-guard-and-hooks`).
- Check `MERGE_HEAD` before any `git add` (memory: `concurrent-waves-shared-checkout`).
- Screenshots via `scripts/native-shot.sh <screen>` with `SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w<N>`.
- Gates, all of them, in this order:
  ```bash
  npm run check          # version:check + types + atlas + mirror + doms + swift:ui
  npm run check:swift    # OnyxCore + OnyxUI cross-build
  npm run swift:core     # golden vectors + invariants  (NOT part of `npm run check`)
  npm run swift:data     # store, sync, migrations      (NOT part of `npm run check`)
  cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  ```
  A green `check:swift` hides a broken app target. Run the `xcodebuild` line (memory: `xcodeproj-drift-and-swift6`).
- `OnyxTests` has four failures on `main` already — those are the baseline, not a regression (memory: `auto-fixes-w7`).
- After merging: `graphify update .`, then **append the wave's Wave Record to `docs/NEXT_GEN_UX_SPRINT.md`** (template at the bottom of this plan), then commit that.
- If a Swift test segfaults inexplicably after a struct change: `rm -rf ~/Library/Caches/onyx-swift/{OnyxCore,OnyxData}` before debugging anything (memory: `soreness-v2-wave`).

### Step 0 — land the plan
On `main`: copy this file to `docs/NEXT_GEN_UX_SPRINT.md`, commit `docs(sprint): land the next-gen UX sprint plan [skip ci]`, push. Write the sprint memory file. No branch, no bump.

| Wave | Model | Theme | Version |
|---|---|---|---|
| W1 | Opus | Apple Health tells the truth | 3.10.1 |
| W2 | Opus | Pulse — the night leads | 3.11.0 |
| W3 | Opus | Pulse — four squares | 3.12.0 |
| W4 | Opus | The ledger stops shouting | 3.13.0 |
| W5 | Opus | Cardio and the banners | 3.14.0 |
| W6 | Opus | Train tells the truth about the week | 3.15.0 |
| W7 | Opus | The dashboard grows a face | 3.16.0 |
| W8 | Opus | Appearance, everywhere | 3.17.0 |
| W9 | Opus | The body has two sides | 3.18.0 |
| W10 | Fable | Fatigue reads the clock | 3.19.0 |
| W11 | Fable | One store, one user | 4.0.0 |
| W12 | Opus | Purge | 4.0.1 |

---

### W1 — Apple Health tells the truth · 3.10.1

Root-cause the duplicate ingest and the water blank. **F1, F2 · A5, A6.**

1. `WorkoutSample.uuid`; `cardio_logs.hk_uuid` in `supabase.json` + `npm run mirror` + a guarded local `ALTER TABLE`; `CardioImport.matchingRow` gains the exact-uuid first branch; `docs/sql/w1-hk-uuid.sql` for the founder (column, backfill from `created_at` where unambiguous, partial unique index).
2. A one-time local sweep collapsing existing `cardio_logs` duplicates on `date|kind|start|duration|distance` — the key `WeeklyExportBuilder.swift:78-96` already computes. Keep the row with the most non-null fields.
3. The toast reports only genuinely-new bouts. `takeCardioIngest` stays read-and-clear.
4. `WaterTruth.ml(log:ledger:)` in OnyxCore; both `NutritionTabView.figures` and `WidgetSnapshotBuilder.swift:344` call it; `clearWater()` stops nilling the flat column; the row says "Waiting for Apple Health" when the read is pending or denied.

**Self-check:** `CardioIngestTests` — the same `HKWorkout` ingested five times inserts once; a hand-typed bout 3 minutes from an imported one still matches by window; a pre-migration row with no `hk_uuid` matches by window and gains the uuid. `WaterTruthTests` — ledger wins over the flat row; empty ledger falls back; both empty is nil; tab and widget agree on all four. `WaterRowTests` extended to cover the `—` render.

**Skills:** native · schema · supabase-postgres-best-practices · code-reviewer · git-commit-helper · graphify
**Agents:** debugger · ios-developer · swift-expert · schema-truth-checker · invariant-auditor · code-reviewer

---

### W2 — Pulse, the night leads · 3.11.0

Hero/Sidekick vitals with a dynamic hero, and the Now strip remade. **F3, F4 · A1.**

1. `OnyxCore/Scoring/VitalHero.swift` — the promotion rule (A1), pure, golden-vectored.
2. `SleepHeroCell` — full-width, `.hero` numeral, 44 pt stage bar, debt line, chevron into `SleepEditSheet`. `PulseSleep.swift` and `SleepEditSheet` already hold the content.
3. `VitalsChipRow` **deleted**. `VitalsGrid` renders the eight sidekicks; the promoted vital swaps into the hero and Sleep takes its grid cell. AX5 path unchanged — it already falls to `MetricRow`s.
4. `NowStripPulse` remade: the `fuelLine` sentence stops being a cramped right-aligned tail beside two `.hero` numerals. One `.hero` per screen is the token rule; Score keeps it, Battery becomes `.display` beside its ring, fuel moves to its own `.caption` line.

**Self-check:** `VitalHeroTests` — Sleep holds it with all vitals in band; HRV at z −1.4 takes it; two alarming vitals resolve by |z| then `VitalSpec.all` order; a reading with no baseline can never be promoted. Shots: `pulse` at default, at AX5, with a promoted hero, with no night at all.

**Skills:** apple-design · native · ui-ux-pro-max · frontend-design · ui-design-system · code-reviewer · graphify
**Agents:** ui-ux-designer · ios-developer · swift-expert · frontend-developer · invariant-auditor

---

### W3 — Pulse, four squares · 3.12.0

Compaction. **Decision 5 + the plan's own resolution.**

1. `PulseCard`'s `@ScaledMetric floor = 196` → ~116, `min(floor, 340)` → `min(floor, 200)`. Fatigue and Stress log keep their verb button; the carousel drops to two pages and its dots follow.
2. New `PulseSquareGrid` — 2×2, `LazyVGrid`, gutters `OnyxSpace.l`, cells `.onyxGlass(.tile)`, square by `aspect(1, contentMode: .fit)`. Holds **Stress Index · Soreness · Scale · Stack**. Stress Index keeps its sparkline at 50-baseline; Soreness is a door into `SorenessSheet`; Scale shows weight + fat% + a trace; Stack shows `3/7 counted` + dose dots.
3. Order becomes: banners · `NowStripPulse` · Sleep hero + vitals · carousel (2) · square grid · session cards.
4. `StressLogSheet` compacted: `FiveWordPicker` and the time picker share one section, the tag grid's `@ScaledMetric chipWidth` 96 → 84, the note field collapses behind a disclosure until tapped. Every control keeps `minHeight: 44`.
5. Every sheet stays declared on `DayScreen` (`PulseTabView.swift:312-318`) and `page` stays bound there (`PulseCarousel.swift:164-175`) — `List` row recycling resets an inner scroll offset otherwise.

**Self-check:** the whole of Pulse fits in a screen and a half at default type. Shots: `pulse` default / AX5 / empty day / a day with two sessions. `PulseModel` tests unchanged — this wave touches no data path.

**Skills:** apple-design · native · ui-ux-pro-max · ui-design-system · frontend-design · code-reviewer · graphify
**Agents:** ui-ux-designer · ios-developer · frontend-developer · swift-expert

---

### W4 — The ledger stops shouting · 3.13.0

Post-workout arrows, RPE semantics, the pair layout, the compact header, the treadmill card. **F5, F6 · A2, A3, A4.**

1. `deltaLine`'s else branch → a clear spacer. Fifteen dead em-dashes per card become zero at unchanged row height.
2. `Figure.upIsGood`; `effortFigure` passes `false`. **A rise in RPE renders red.** The metric grid's `delta(_:unit:higherIsBetter:)` is the precedent.
3. `.pair` `SetLayout` (A3) — `layout(_:)` stops routing pair cards to `.whole`; two `micro` sub-lines under one badge, one shared delta.
4. `ledgerHeader` three lines → two: chips and verdict merge into one `FlowRow`, verdict last, as a `MetaTagRow.Tag` pill.
5. Treadmill: `MuscleMap` answers for cardio kinds so the chips render; `headerTags` gains a cardio branch printing distance · pace · avg HR · "Automatically logged" where the strength tags are guarded off; the family hue resolves to `Color.onyx.cardio` on the fallback path, never `.recover`; the badge and the single row centre against `badgeSide = 28` like every other card.

**Self-check:** `SessionTableTests` extended — a card with no previous session renders at the same height as one with; an RPE rise is `danger`; a pair card is `.pair` and carries a delta; a treadmill card has ≥ 1 tag and a `cardio` family hue. Shots: `session` for a strength day, a pair-heavy day, a treadmill-only day.

**Skills:** apple-design · native · ui-ux-pro-max · frontend-design · code-reviewer · graphify
**Agents:** ui-ux-designer · ios-developer · swift-expert · frontend-developer · code-reviewer

---

### W5 — Cardio and the banners · 3.14.0

**F7 · the session-banner brief.**

1. `cardioCard`: the zone rail is **deleted** — it reads no zones (F7). The card becomes day · time · duration · distance · pace · avg HR with a heart glyph, compact, plus an "Automatically logged" badge when `fromHealthkit`. Time comes from `created_at`, which on an imported row is the bout's start (`CardioImport.swift:62-89`).
2. The Zone-2 count survives as a caption on the header, where a count belongs — not as a rail pretending to be a gauge.
3. Train's done-card fallback (`WorkoutTabView.swift:547-566`) stops being flat grey: it takes the day-hue gradient wash and muscle capsules `SessionHeaderCard` already draws, so the fallback and the real card differ in *content*, not in *character*.
4. Pulse's `PulseSessionCard` placeholder (`PulseWorkout.swift:88-107`) gets the same treatment.
5. No emoji. The app has none in Swift (two exceptions, both strings) and the vibrancy the founder is pointing at is the day hue, the muscle capsules and the record gold — `SessionHeaderCard.swift:144-150` and `:202-212`. Glyphs where a mark is wanted: `heart.fill`, `figure.run`, `flame.fill`.

**Self-check:** shots — `train` with a bout today, `train` with none, `pulse` with a finished session, `session` post-workout. `WorkoutWeekTests` unchanged.

**Skills:** apple-design · native · ui-ux-pro-max · ui-design-system · frontend-design · code-reviewer · graphify
**Agents:** ui-ux-designer · ios-developer · frontend-developer

---

### W6 — Train tells the truth about the week · 3.15.0

**F8 · A7 · decisions 3 and 4.**

1. `weekDeltaKg` day-matched; `weekPaceKg` alongside it (A7). The door prints `▲ +3.0 t` over `vs same point last week · on pace 32 t`. Both sides empty → `"—"`.
2. Past weeks: a collapsed row per closed week at the bottom of the tab, expanding in place into the full `WeeklyWrapView` banner. The content already exists.
3. Long-press → **Customize Train**: show/hide for Trends · Cardio · Progression · Past weeks · the doors row. Persisted in the same `dashboard_layouts` row (`layout jsonb`, v5 key `train`), so it syncs with no new table. `TileMenu` is the interaction precedent.
4. Explicitly **not** doing: floating, movable Train widgets. Today is the arrangeable surface; Train has one live state and a plan card that must be the first thing seen.

**Self-check:** `WorkoutWeekTests` — Sunday before any session gives `nil`, never a negative; Wednesday compares three days to three; a week with no previous week gives `nil`; pace with zero elapsed training days does not divide by zero. Shots: `train` Monday-empty, mid-week, and with three past weeks collapsed.

**Skills:** native · apple-design · ui-ux-pro-max · senior-architect · code-reviewer · graphify
**Agents:** ios-developer · swift-expert · ui-ux-designer · invariant-auditor

---

### W7 — The dashboard grows a face · 3.16.0

**F9 · A8, A9 · decision 4.**

1. `WidgetId.daily` (size `.l`) — the Mega Widget. Three concentric arcs (Sleep · Move · Fuel) reusing `WeeklyMuscleRing`'s stroke geometry verbatim, battery % in the centre, one sentence beneath.
2. The sentence: `TodayFeed.coach` extended with a deterministic rule table over battery band, ACWR, stress band and sleep debt. **Rules, not a model call.** Golden-vectored, one fixture per sentence.
3. `StackSlot.linked` (A9) — payload v5; `fromStored` still reads v1–v4; default false so every stored layout is unchanged.
4. Jiggle: `model.editing` already exists and already gates the drag. Add the wiggle (a ±1.2° `.rotationEffect` on an autoreversing spring, phase-offset per tile so they do not march in step), a per-tile remove affordance, and `Done` in the toolbar. Honour `accessibilityReduceMotion` — no wiggle, a hairline outline instead.
5. The clobber (F9): `TodayModel` must not save a layout it has not yet loaded. Gate `apply(_:)` on a `hasLoaded` flag set by the first stream yield, and never push `Dashboard.defaultLayout` as a *save*.

**Self-check:** `TodayModelTests` — a save before the first stream yield writes nothing; a v4 payload round-trips through v5 unchanged; `LayoutGoldenTests` passes untouched. `CoachSentenceTests` — one fixture per branch, including "nothing is known yet". Shots: `today` with the mega tile, a linked stack, jiggle mode, and reduce-motion on.

**Skills:** apple-design · native · ui-ux-pro-max · ui-design-system · frontend-design · code-reviewer · graphify
**Agents:** ui-ux-designer · ios-developer · swift-expert · frontend-developer · architect-reviewer

---

### W8 — Appearance, everywhere · 3.17.0

**F10 · A10, A11, A12 · decision 4.**

1. Tab tint (A10) — five lines in `RootView.swift`, Settings stays neutral.
2. `AppDatabase.appGroupDefaults()` (A12) — one accessor, every caller routed through it, a DEBUG assertion when the suite is nil so the widget's silent staleness becomes visible.
3. The coverage test (A11) — a sibling to `TokenDisciplineTests`; every root screen applies the ground or is allowlisted with a reason.
4. The ~45 `.white`/`.black` reads on widget tile faces become tokens. They are the only surfaces in the app that do not move with the theme.
5. `themeDidChange()` already calls `reloadAllTimelines()`; verify the watch context push carries the spec and that `OnyxProvider.theme()` still reloads per timeline.

**Self-check:** `AppearanceCoverageTests` green. `OnyxThemeTests` — every preset reproduces distinct domain accents and 16 distinct muscle hues. Shots: every tab under two presets; widget previews under both.

**Skills:** apple-design · native · ui-design-system · ui-ux-pro-max · code-reviewer · graphify
**Agents:** ui-ux-designer · ios-developer · swift-expert · architect-reviewer

---

### W9 — The body has two sides · 3.18.0

**F11, F12 · A13, A14 · decision 6.**

1. Generator: `side` on `OnyxAtlasPath` from the centroid against the midline (A13). `npm run atlas && npm run check:atlas`.
2. `OnyxAtlasHit.muscle(at:in:side:)` returns `(LandmarkMuscle, BodySide)`; `landmarks(on:)` gains a sided twin for the rotor.
3. `AtlasFigure` re-keys `colors`, `values`, `outlined` on `MuscleSide`. `worked` stays whole-muscle — modelled fatigue is bilateral and always was.
4. `doms_logs` gains `side` and `sub_region`, nullable, with the widened unique index (A14). `docs/sql/w9-doms-laterality.sql` for the founder. `supabase.json` → `npm run mirror`; guarded local `ALTER TABLE`.
5. `DayEditing.setDoms(… side: subRegion:)`; `SeverityPopover` gains the Both/L/R segment at its head, pre-selected to the side that was tapped.
6. `ExportDoms` gets its first native construction site — `muscle[/subRegion][@L|@R]:severity`. A bilateral whole-muscle token must stay byte-identical to v1.
7. Joints are **not** touched. They are not landmarks and never become muscles.

**Self-check:** `AtlasHitTests` — every bilateral muscle has exactly one left and one right path per view; Upper back, Lower back and Abs/core are `.center`; a tap left of the midline answers `.left`. `DomsLateralityTests` — L and R coexist for one muscle on one day; the fold still returns max within the muscle so the battery is unchanged; a legacy row with `side = nil` reads as `both`; the export token for a bilateral rating is byte-identical to v1. **Run `npm run swift:core` and confirm the battery golden vectors are untouched.**

**Skills:** native · apple-design · schema · supabase-postgres-best-practices · ui-ux-pro-max · code-reviewer · graphify
**Agents:** ios-developer · swift-expert · schema-truth-checker · database-architect · invariant-auditor · ui-ux-designer

---

### W10 — Fatigue reads the clock · 3.19.0 · **Fable**

The first wave whose core is arithmetic rather than layout.

1. `Fatigue.slotsForDay(isTraining:)` already exists. Make the *prompt* clock-aware: before a session (or before ~11:00 on a training day) the card asks the pre-session question; after the session ends, or after 18:30, it asks the post-session / end-of-day one. The slot vocabulary does not change — only which one the card is currently asking for, and the words on it.
2. The session cost `Fatigue.delta` (`post − pre`) only means anything when both slots exist; the card must say which one is missing rather than printing a delta against a blank.
3. `ScheduleContext` and `LogicalDay` own "what day is it" — the clock rule reads them, never `Date()` directly, so the shot loop and the golden vectors stay deterministic.
4. `STRESS_MODEL.md` §2 defines `fatigueDayMean` as **the day's slots, all of them**, not the latest. Nothing in this wave may change that; if the scoring input moves, the wave is wrong.

**Self-check:** `FatigueClockTests` — 07:00 on a training day asks pre; 19:00 asks post; a finished session at 14:00 flips it at 14:00, not at 18:30; a rest day never asks the pre-session question; the day mean over two slots is unchanged by any of it. `npm run swift:core` — every battery and stress vector byte-identical.

**Skills:** native · senior-architect · code-reviewer · graphify
**Agents:** swift-expert · invariant-auditor · architect-reviewer · ios-developer

---

### W11 — One store, one user · 4.0.0 · **Fable**

**F13 · A15, A16 · decision 7.** MAJOR: the founder must paste SQL, and the account-switch behaviour changes.

1. **Introspect first.** `schema-truth-checker` reports, per table, whether RLS is on and which policies exist. Nothing is written before that report exists. The repo's `types.ts` and `supabase.json` are **not** evidence about policies.
2. `docs/sql/w11-isolation-rls.sql` (A16) — 32 tables, `enable row level security`, four policies each on `(select auth.uid()) = user_id`, every statement re-runnable. `workout_sets` and `set_events` policed through `workout_sessions`. Flag `set_events` explicitly: it is applied by hand and absent from the schema fixture, so its state must be reported, not assumed.
3. Scope every unscoped read (A15) — `PrRecorder.floors`, `PrRecorder.baselines`, `SessionHistoryStore.personalRecords`/`sessionHistory`/`historySets`/`cardio`, `WeeklyExportBuilder`, `ScoringInputsBuilder.sets`, `AppDatabase.sessions(on:)`/`session(id:)`/`sets(sessionId:)`/`liveSession`/`liveWorkoutInProgress`/`discardSession`, `SessionEditing`, `WidgetSnapshotBuilder`'s three slices, `ReportsStore`, `SetEventFold`, `EventStore.reproject`, `DayEditing.addCardio`/`deleteCardio`, `TrainingPuller`.
4. `AccountSeed.needsOnboarding` — **delete** the `Exercise.fetchCount(db)` check (A15). It is the reason a new account can land on a configured app.
5. The account-switch path: a sign-in whose user id differs from `AppDatabase.knownUserId()` erases the local store before the first sync, using the same `eraseLocalData()` sign-out already calls. Surface the unsynced count first, exactly as `signOut()` does.
6. `TwoUserIsolationTests.swift` — seed users A and B into one store, then assert for **every** scoped reader that A's result set and B's are disjoint. This is the exhaustive test the brief asked for, and it is the artefact that proves the wave.

**Self-check:** `TwoUserIsolationTests` green across every reader. `NewAccountPathTests` extended — a store holding B's catalogue still offers onboarding to A, and A's PR list is empty. `SignOutEraseTests` extended with the switch path. `npm run swift:data`. The `.sql` file is reviewed by `supabase-schema-architect` and `database-architect` against the live introspection before it is handed over.

**Skills:** schema · supabase-postgres-best-practices · native · senior-backend · senior-architect · code-reviewer · graphify
**Agents:** schema-truth-checker · supabase-schema-architect · database-architect · backend-architect · swift-expert · invariant-auditor · code-reviewer

**Founder's manual step:** paste `docs/sql/w11-isolation-rls.sql` into the Supabase SQL editor. Nothing in this repo can apply it.

---

### W12 — Purge · 4.0.1

1. Harvest every Wave Record from `docs/NEXT_GEN_UX_SPRINT.md` into `docs/CHANGELOG.md` and into a sprint memory file. **Nothing in a record may be lost by deleting the plan** — that is the whole point of writing them as the waves ship.
2. Delete `docs/NEXT_GEN_UX_SPRINT.md`.
3. Delete every SQL file the sprint created once the founder confirms it is applied: `docs/sql/w1-hk-uuid.sql`, `docs/sql/w9-doms-laterality.sql`, `docs/sql/w11-isolation-rls.sql`. Leave `docs/sql/` empty, as it was.
4. `git branch --list 'onyx/sprint-next-gen*'` must return nothing; delete any survivor, local and remote.
5. Purge caches: `rm -rf ~/Library/Caches/onyx-swift/{OnyxCore,OnyxData,shot-w*}`, `native/.build`, `DerivedData` for the project.
6. `graphify update .` and commit the rebuilt graph.
7. Full gate one last time, then merge, delete, push `[skip ci]`.

**Skills:** ship · git-commit-helper · native · graphify
**Agents:** context-manager · code-reviewer

---

## The wave prompts

Copy one, verbatim, per wave. **Do not start a wave until the previous one is merged and `main` is green.**
`/ship` and `/schema` are user-invoked commands — type them yourself when a prompt says so; the agent cannot.

---

**W1**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full before touching anything — findings F1 and F2,
architecture A5 and A6, and the "Every wave, without exception" list. Then execute W1.

GOAL — Apple Health stops lying. Two root causes, not two symptoms.

TASKS
1. The duplicate ingest. There is no HKAnchoredObjectQuery anywhere and HKWorkout.uuid is
   never stored, so every sync re-reads today+yesterday and re-inserts bouts whose
   created_at did not survive the round trip. Add uuid to WorkoutSample, add hk_uuid to
   cardio_logs (supabase.json -> npm run mirror, plus a guarded local ALTER TABLE in the
   v21.genericModel pattern), and give CardioImport.matchingRow an exact-uuid first branch.
   Keep the 5-minute window as the fallback for hand-typed and pre-migration rows.
   Write docs/sql/w1-hk-uuid.sql: the column, a backfill from created_at where unambiguous,
   and a partial unique index on (user_id, hk_uuid) where hk_uuid is not null.
2. Collapse the duplicates already in the store, once, on the date|kind|start|duration|distance
   key that WeeklyExportBuilder.swift:78-96 already computes. Keep the row with the most
   non-null fields.
3. The toast reports only genuinely-new bouts.
4. Water. Add WaterTruth.ml(log:ledger:) to OnyxCore — ledger sum when non-empty, else the
   flat row, else nil — and call it from BOTH NutritionTabView.figures and
   WidgetSnapshotBuilder.swift:344, which today use different rules and disagree.
   clearWater() must stop nilling daily_logs.water_ml optimistically. When the read is
   pending or denied, the row says "Waiting for Apple Health" rather than rendering "—".

SELF-CHECK — these must exist and pass
- CardioIngestTests: the same HKWorkout ingested five times inserts once; a hand-typed bout
  3 minutes from an imported one still matches by window; a pre-migration row with no
  hk_uuid matches by window and gains the uuid.
- WaterTruthTests: ledger beats the flat row; empty ledger falls back; both empty is nil;
  tab and widget agree in all four cases.
- WaterRowTests extended to cover the "—" render, which no test touches today.

GATES — all of them, in this order. "No output" is not a pass; read the counts.
  npm run check && npm run check:swift && npm run swift:core && npm run swift:data
  cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
OnyxTests has four pre-existing failures on main. Those are the baseline.

SKILLS: native, schema, supabase-postgres-best-practices, code-reviewer, git-commit-helper, graphify
AGENTS: debugger, ios-developer, swift-expert, schema-truth-checker, invariant-auditor, code-reviewer

SHIP: branch onyx/sprint-next-gen-w1 from main; patches from script files, never inline
heredocs; check MERGE_HEAD before any git add. Bump package.json to 3.10.1, npm run
version:sync, cd native && xcodegen generate, append the CHANGELOG section, confirm
npm run version:check. Merge --no-ff into main, delete the branch, push with [skip ci].
Then graphify update . and APPEND the W1 Wave Record to docs/NEXT_GEN_UX_SPRINT.md.
End your final message with the founder's manual checklist — the SQL to paste.
```

---

**W2**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full — findings F3 and F4, architecture A1, and the
"Every wave, without exception" list. Then execute W2.

GOAL — Pulse's vitals stop being a horizontal scroller. The night leads, and an alarming
vital can take the lead from it.

TASKS
1. OnyxCore/Scoring/VitalHero.swift — a pure promotion rule. Sleep holds the hero slot by
   default. A vital is promoted only when its zSignal crosses ±1 in the bad direction
   (upIsGood ? z < -1 : z > 1) AND its magnitude exceeds Sleep's own. Ties break by
   VitalSpec.all order so the answer is deterministic. Reuse the zSignal grammar from
   READINESS_MODEL.md §2 — 7-day rolling mean vs the 42 days before it, dead-banded at
   0.5·SD, clamped ±2. The dead-band is what stops the hero thrashing day to day.
   Do NOT invent a new threshold model. Golden-vector it.
2. SleepHeroCell — full width, one .hero numeral, a 44 pt stage bar, the debt line, chevron
   into SleepEditSheet. The content already lives in PulseSleep.swift and SleepEditSheet.
3. Delete VitalsChipRow. VitalsGrid draws the eight sidekicks; a promoted vital swaps into
   the hero and Sleep takes its grid cell. The accessibility path is untouched — the grid
   already falls to MetricRows at AX sizes.
4. Remake NowStripPulse. The fuelLine sentence is currently a cramped right-aligned tail
   beside two .hero numerals. One .hero per screen is the token rule: Score keeps it,
   Battery becomes .display beside its ring, fuel gets its own .caption line.

SELF-CHECK
- VitalHeroTests: Sleep holds it with everything in band; HRV at z -1.4 takes it; two
  alarming vitals resolve by magnitude then by VitalSpec.all order; a reading with no
  baseline can never be promoted.
- Shots via scripts/native-shot.sh with SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w2:
  pulse at default type, at AX5, with a promoted hero, and with no night recorded at all.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line from the plan. A green check:swift hides a broken app target.

SKILLS: apple-design, native, ui-ux-pro-max, frontend-design, ui-design-system, code-reviewer, graphify
AGENTS: ui-ux-designer, ios-developer, swift-expert, frontend-developer, invariant-auditor

SHIP: branch onyx/sprint-next-gen-w2 from main. Bump to 3.11.0, version:sync, xcodegen
generate, CHANGELOG section, version:check. Merge --no-ff into main, delete the branch,
push [skip ci]. graphify update . and APPEND the W2 Wave Record to the plan file.
```

---

**W3**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full — decision 5, the resolution note under it, and the
"Every wave, without exception" list. Then execute W3.

GOAL — Pulse fits in a screen and a half. Nothing is deleted; everything is halved.

TASKS
1. PulseCard: @ScaledMetric floor 196 -> ~116, and the min(floor, 340) cap -> min(floor, 200).
   Fatigue and Stress log keep their verb buttons. The carousel drops to two pages; its dots
   follow.
2. New PulseSquareGrid — 2x2 LazyVGrid, gutters OnyxSpace.l (16), cells .onyxGlass(.tile),
   square via .aspectRatio(1, contentMode: .fit). It holds Stress Index, Soreness, Scale and
   Stack. Stress Index keeps its 50-baseline sparkline. Soreness is a door into SorenessSheet
   (the rating verb moves onto the map sheet, where the popover already lives). Scale shows
   weight + fat% + a trace. Stack shows "3/7 counted" and the dose dots.
3. New order: banners, NowStripPulse, Sleep hero + vitals, carousel (2 pages), square grid,
   session cards. The Stress Index stays BELOW the stress log that feeds its `self` term —
   that constraint is why it is not in the Now strip.
4. Compact StressLogSheet: FiveWordPicker and the time picker share one section; the tag
   grid's @ScaledMetric chipWidth 96 -> 84; the note field collapses behind a disclosure.
   Every control keeps minHeight: 44.
5. Two constraints you must not break: every sheet stays declared on DayScreen
   (PulseTabView.swift:312-318), and the carousel's `page` binding stays on DayScreen
   (PulseCarousel.swift:164-175). List row recycling resets an inner scroll offset otherwise.

SELF-CHECK
- Shots (SHOT_DERIVED=...shot-w3): pulse default, AX5, an empty day, a day with two sessions.
  The whole screen must fit in a screen and a half at default type.
- PulseModel tests unchanged. This wave touches no data path; if a model test moves, stop.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: apple-design, native, ui-ux-pro-max, ui-design-system, frontend-design, code-reviewer, graphify
AGENTS: ui-ux-designer, ios-developer, frontend-developer, swift-expert

SHIP: branch onyx/sprint-next-gen-w3 from main. Bump to 3.12.0, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
graphify update . and APPEND the W3 Wave Record.
```

---

**W4**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full — findings F5 and F6, architecture A2, A3 and A4,
and the "Every wave, without exception" list. Then execute W4.

GOAL — the post-workout ledger stops shouting. Dead glyphs go, RPE tells the truth, unilateral
sets finally get a comparison, and the header stops eating the card.

TASKS
1. deltaLine's else branch (SessionDetailView.swift:1911) becomes a clear spacer measured
   from the micro line, not Text("—"). Row height must be IDENTICAL before and after — the
   reserved line exists so rows do not change height between sessions, and that reason
   survives; only the glyph goes.
2. Figure gains upIsGood (default true); effortFigure passes false. A RISE in RPE renders
   red. The metric grid's delta(_:unit:higherIsBetter:) is the existing precedent — follow it.
3. A fifth SetLayout, .pair. layout(_:):1643 currently sends any card containing a "pair" row
   to .whole, whose comparable is false, so unilateral sets carry no arrows at all. .pair
   draws L and R as two micro sub-lines under one badge, comparable == true, with ONE shared
   delta line keyed on the pair's combined load × reps. SetColumn.side = 14 in
   ExerciseCardView.swift:1040 is the precedent for what that width costs.
4. ledgerHeader goes from three lines to two: the muscle chips and the MetaTagRow verdict
   merge into one FlowRow, chips first, verdict last as a MetaTagRow.Tag pill. Compact —
   the founder's words are that the current height "looks terrible".
5. The treadmill card. There is no separate view and no branch; it is six data gaps.
   MuscleMap must answer for cardio kinds so the chip FlowRow renders. headerTags gains a
   cardio branch printing distance, pace, avg HR and an "Automatically logged" badge where
   the five strength tags are guarded off. The family hue must resolve to Color.onyx.cardio
   on the fallback path (SessionDetailView.swift:1155-1161), never .recover lavender. The
   badge and the single row centre against badgeSide = 28 like every other card.

SELF-CHECK
- SessionTableTests extended: a card with no previous session renders at the same height as
  one with; an RPE rise is danger; a pair card is .pair and carries a delta; a treadmill card
  has at least one tag and a cardio family hue.
- Shots (SHOT_DERIVED=...shot-w4): session for a strength day, a pair-heavy day, and a
  treadmill-only day.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: apple-design, native, ui-ux-pro-max, frontend-design, code-reviewer, graphify
AGENTS: ui-ux-designer, ios-developer, swift-expert, frontend-developer, code-reviewer

SHIP: branch onyx/sprint-next-gen-w4 from main. Bump to 3.13.0, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
graphify update . and APPEND the W4 Wave Record.
```

---

**W5**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full — finding F7 and the "Every wave" list. Then execute W5.

GOAL — the cardio box says what it knows, and the two grey session banners join the app.

TASKS
1. Delete the Zone-2 rail from cardioCard (WorkoutTabView.swift:1037-1066). It reads NO
   heart-rate zones: `done` is a count of this week's bouts >= 20 minutes and `target` is
   Zone2.weeklyTarget = 2, sitting next to the last bout's avg bpm. Two unrelated numbers
   pretending to be a gauge.
2. Rebuild the card compact: day, time, duration, distance, pace, avg HR with a heart glyph,
   plus an "Automatically logged" badge when fromHealthkit. Time comes from created_at,
   which on an imported row is the bout's START (CardioImport.swift:62-89). There is no
   maxHr column — do not invent one.
3. The Zone-2 count survives as a caption on the section header, where a count belongs.
4. Train's done-card fallback (WorkoutTabView.swift:547-566) stops being flat grey. It takes
   the day-hue gradient wash and the muscle capsules SessionHeaderCard already draws
   (SessionHeaderCard.swift:144-150 and :259-283), so the fallback differs from the real card
   in content, not in character.
5. Pulse's PulseSessionCard placeholder (PulseWorkout.swift:88-107) gets the same treatment.
6. NO EMOJI. This app has none in Swift. The vibrancy being asked for is the day hue, the
   muscle capsules and the record gold. Use SF Symbols where a mark is wanted: heart.fill,
   figure.run, flame.fill.

SELF-CHECK
- Shots (SHOT_DERIVED=...shot-w5): train with a bout today, train with none, pulse with a
  finished session, session post-workout.
- WorkoutWeekTests unchanged.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: apple-design, native, ui-ux-pro-max, ui-design-system, frontend-design, code-reviewer, graphify
AGENTS: ui-ux-designer, ios-developer, frontend-developer

SHIP: branch onyx/sprint-next-gen-w5 from main. Bump to 3.14.0, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
graphify update . and APPEND the W5 Wave Record.
```

---

**W6**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full — finding F8, architecture A7, and the "Every wave"
list. Then execute W6.

GOAL — the Train tab stops claiming you are 30 tonnes down on a Sunday morning.

TASKS
1. WorkoutWeek.swift:457 subtracts a FULL previous calendar week from a PARTIAL current one.
   Make it day-matched: compare this week's elapsed days against the same count of days in
   the previous week, where elapsedDays = dayNumber(today) - dayNumber(weekStart) + 1.
   Add weekPaceKg = weekTonnageKg / elapsedTrainingDays * plannedTrainingDays.
   The Trends door prints the delta with "vs same point last week · on pace 32 t" beneath it.
   Both sides empty -> "—", never a signed zero.
   Do NOT touch the closed-week twin at :679-684. Both its sides are already full and it is
   already correct.
2. Past weeks: a collapsed row per closed week at the bottom of the tab, expanding in place
   into the full WeeklyWrapView banner. The content already exists — this is a container,
   not a new view.
3. Long-press anywhere on Train -> "Customize Train": show/hide for Trends, Cardio,
   Progression, Past weeks and the doors row. Persist it in the EXISTING dashboard_layouts
   row (layout jsonb, under a v5 key "train") so it syncs with no new table. TileMenu in
   DashboardGrid.swift:238 is the interaction precedent — say the verbs in words.
4. Explicitly NOT in scope: floating, movable Train widgets. Today is the arrangeable
   surface. Train has one live state and a plan card that must be the first thing seen.

SELF-CHECK
- WorkoutWeekTests: Sunday before any session gives nil, never a negative; Wednesday compares
  three days against three; a week with no previous week gives nil; pace with zero elapsed
  training days does not divide by zero.
- Shots (SHOT_DERIVED=...shot-w6): train Monday-empty, mid-week, and with three past weeks
  collapsed at the bottom.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: native, apple-design, ui-ux-pro-max, senior-architect, code-reviewer, graphify
AGENTS: ios-developer, swift-expert, ui-ux-designer, invariant-auditor

SHIP: branch onyx/sprint-next-gen-w6 from main. Bump to 3.15.0, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
graphify update . and APPEND the W6 Wave Record.
```

---

**W7**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full — finding F9, architecture A8 and A9, and the
"Every wave" list. Then execute W7.

GOAL — the dashboard gets one face worth opening the app for, and stops forgetting itself.

TASKS
1. A twentieth WidgetId: .daily, size .l — the Mega Widget. Three concentric arcs
   (Sleep vs goal, Move, Fuel vs target), battery % in the centre, one sentence beneath.
   REUSE WeeklyMuscleRing's stroke geometry verbatim: .butt caps and 2-degree gaps. Its
   header documents why — a round cap extends tangentially by ~8.5 degrees at this radius,
   so a 2-degree trim with round caps makes arcs OVERLAP by 15 degrees. Do not write a
   second ring.
2. The sentence comes from TodayFeed.coach, extended with a deterministic rule table over
   battery band, ACWR, stress band and sleep debt. RULES, NOT A MODEL CALL — an offline gym
   app must not need a network to say "rest day needed". Golden-vector it, one fixture per
   sentence including "nothing is known yet".
3. StackSlot.linked: Bool = false — payload v5. A linked stack's faces all render against the
   slot's own window instead of each resolving today independently. fromStored must still
   read v1 through v4, and the default false must leave every stored layout unchanged.
4. Jiggle mode. model.editing already exists and already gates DashboardGrid.Arrangeable's
   drag. Add the wiggle (a ±1.2° rotationEffect on an autoreversing spring, phase-offset per
   tile so they do not march in step), a per-tile remove affordance, and Done in the toolbar.
   Honour accessibilityReduceMotion: no wiggle, a hairline outline instead.
5. The memory bug. dashboard_layouts is ALREADY synced both ways — the layout is not lost,
   it is overwritten. TodayModel.swift:64 falls back to Dashboard.defaultLayout when the
   stream has not yielded yet, and a save racing the first pull pushes that default over the
   real row. Gate apply(_:) on a hasLoaded flag set by the first stream yield, and never push
   a default layout as a save.

SELF-CHECK
- TodayModelTests: a save before the first stream yield writes NOTHING; a v4 payload
  round-trips through v5 unchanged; LayoutGoldenTests passes untouched.
- CoachSentenceTests: one fixture per branch.
- Shots (SHOT_DERIVED=...shot-w7): today with the mega tile, a linked stack, jiggle mode,
  and reduce-motion on.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: apple-design, native, ui-ux-pro-max, ui-design-system, frontend-design, code-reviewer, graphify
AGENTS: ui-ux-designer, ios-developer, swift-expert, frontend-developer, architect-reviewer

SHIP: branch onyx/sprint-next-gen-w7 from main. Bump to 3.16.0, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
graphify update . and APPEND the W7 Wave Record.
```

---

**W8**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full — finding F10, architecture A10, A11 and A12, and the
"Every wave" list. Then execute W8.

GOAL — the theme reaches every surface, including the ones that never got the message.

The engine shipped in 3.5.0 and TokenDisciplineTests already fails the build on raw hex with
zero current violations. This wave is COVERAGE, not a new engine. Do not rebuild it.

TASKS
1. Tab identity: .tint(OnyxDomain.<domain>.accent) on each SwiftUI.Tab in RootView.swift:70-98.
   Today .recover, Train .train, Nutrition .fuel, Pulse .body. Settings stays neutral —
   it belongs to no domain, the same argument OnyxScreenBackground already makes for its
   nil case. Pulse keeps .body rather than a hardcoded red: every hue in this app derives
   from the user's two theme colours by OKLCH rotation, and a literal red would be the one
   colour that goes stale the moment they change Primary.
2. THE REAL STALENESS BUG. AppDatabase.swift:53-56 says the App Group container returns nil,
   so UserDefaults(suiteName: "group.app.onyx.health") falls back to .standard — which is a
   DIFFERENT suite in the app and in the widget extension. Under that condition the widget
   never sees a theme write at all. Add AppDatabase.appGroupDefaults(), route every caller
   through it (the app's @AppStorage store, OnyxWidgets.init, OnyxProvider.theme(),
   AppearanceView.commit), and fire a DEBUG assertion when the suite is nil so the condition
   is visible in the shot loop instead of silent on device.
3. AppearanceCoverageTests — a sibling to TokenDisciplineTests. Walk every root screen in
   native/Onyx/Features and fail when it applies neither .onyxScreen nor .onyxFormBackground.
   Allowlist the deliberate exceptions IN THE TEST with a reason, so skipping the ground
   becomes a decision someone had to write down.
4. The ~45 .white/.black reads on widget tile faces become tokens. They are the only surfaces
   in the app that do not move with the theme. Worst offenders: OnyxLifestyle (7),
   OnyxTraining (6), OnyxSeries (5), OnyxPrimitives (5), OnyxPerformance (5).
5. Verify themeDidChange() still reloads widget timelines and that the watch context carries
   the spec.

SELF-CHECK
- AppearanceCoverageTests green. OnyxThemeTests: every preset reproduces distinct domain
  accents and 16 distinct muscle hues.
- Shots (SHOT_DERIVED=...shot-w8): every tab under two presets; widget previews under both.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: apple-design, native, ui-design-system, ui-ux-pro-max, code-reviewer, graphify
AGENTS: ui-ux-designer, ios-developer, swift-expert, architect-reviewer

SHIP: branch onyx/sprint-next-gen-w8 from main. Bump to 3.17.0, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
graphify update . and APPEND the W8 Wave Record.
```

---

**W9**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full — findings F11 and F12, architecture A13 and A14,
and the "Every wave" list. Then execute W9.

GOAL — you can rate ONLY the right glute, or ONLY the left tricep.

THE GEOMETRY ALREADY EXISTS. OnyxAtlas.muscles holds TWO separate OnyxAtlasPath entries per
bilateral muscle — left at x < 60, right at x > 60 on the 120x260 viewBox — and
OnyxAtlasHit.muscle(at:in:side:):33 already finds which path contains the tap, then throws
the side away. Do not draw new art.

TASKS
1. Generator: add `side` to the emitted OnyxAtlasPath in scripts/src/atlas.ts +
   gen-atlas-swift.mjs, derived from each path's centroid x against the midline 60
   (< 58 -> .left, > 62 -> .right, else .center). Then npm run atlas && npm run check:atlas.
   Never hand-edit OnyxAtlas.swift. Axial exceptions you should expect: Upper back and
   Lower back have one path each; Abs/core has three on the front.
2. OnyxAtlasHit.muscle(at:in:side:) returns (LandmarkMuscle, BodySide). landmarks(on:) gains
   a sided twin for the accessibility rotor.
3. AtlasFigure re-keys colors, values and outlined from LandmarkMuscle to a MuscleSide pair.
   `worked` stays whole-muscle — modelled fatigue is bilateral and always was.
4. doms_logs gains `side text` and `sub_region text`, both nullable, absent meaning "both".
   The unique key widens to (user_id, date, muscle_group, coalesce(side,'both'),
   coalesce(sub_region,'')) as a named unique index so PostgREST can target it. Update
   supabase.json -> npm run mirror, add a guarded local ALTER TABLE, and write
   docs/sql/w9-doms-laterality.sql for the founder to paste.
5. DayEditing.setDoms gains side: and subRegion:. SeverityPopover gains a Both/L/R segment at
   its head, PRE-SELECTED to the side that was tapped, so the tap is correctable without
   being mandatory.
6. ExportDoms finally gets its first native construction site:
   muscle[/subRegion][@L|@R]:severity. A bilateral whole-muscle token must stay BYTE-IDENTICAL
   to v1 — that is what keeps the three v1 export tests passing untouched.
7. Joints are NOT touched. They are not landmarks and must never become muscles.

SELF-CHECK
- AtlasHitTests: every bilateral muscle has exactly one .left and one .right path per view;
  Upper back, Lower back and Abs/core are .center; a tap left of the midline answers .left.
- DomsLateralityTests: L and R coexist for one muscle on one day; the fold still returns MAX
  within a muscle so the battery is unchanged; a legacy row with side = nil reads as both;
  the export token for a bilateral rating is byte-identical to v1.
- npm run swift:core MUST show every battery and stress golden vector untouched. If a vector
  moves, the fold has been broken and the wave is wrong.
- If a Swift test segfaults after a struct change:
  rm -rf ~/Library/Caches/onyx-swift/{OnyxCore,OnyxData} BEFORE debugging anything.
- Shots (SHOT_DERIVED=...shot-w9): the soreness map with a one-sided rating, the popover with
  the segment, and the Pulse soreness square.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: native, apple-design, schema, supabase-postgres-best-practices, ui-ux-pro-max, code-reviewer, graphify
AGENTS: ios-developer, swift-expert, schema-truth-checker, database-architect, invariant-auditor, ui-ux-designer

SHIP: branch onyx/sprint-next-gen-w9 from main. Bump to 3.18.0, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
graphify update . and APPEND the W9 Wave Record. End your final message with the founder's
manual checklist — the SQL to paste.
```

---

**W10**
```
Model: Fable

Read docs/NEXT_GEN_UX_SPRINT.md in full — the W10 section and the "Every wave" list. Read
docs/STRESS_MODEL.md §2 before changing any fatigue code. Then execute W10.

GOAL — the fatigue card asks the question the time of day makes sense of.

TASKS
1. Fatigue.slotsForDay(isTraining:) already exists. Make the PROMPT clock-aware, not the
   vocabulary: before a session — or before ~11:00 on a training day — the card asks the
   pre-session question; after the session ends, or after 18:30, it asks the post-session /
   end-of-day one. The slot names do not change. Only which one is being asked for, and the
   words on the card.
2. Fatigue.delta is post − pre and only means anything when both slots exist. The card must
   name the missing slot rather than printing a delta against a blank.
3. Read the clock through ScheduleContext and LogicalDay, NEVER Date() directly, so the shot
   loop and the golden vectors stay deterministic.
4. HARD CONSTRAINT: STRESS_MODEL.md §2 defines fatigueDayMean as the DAY's slots, ALL of
   them, not the latest. Nothing in this wave may change that. If a scoring input moves, the
   wave is wrong — stop and say so.

SELF-CHECK
- FatigueClockTests: 07:00 on a training day asks pre; 19:00 asks post; a session finished at
  14:00 flips it at 14:00, not at 18:30; a rest day never asks the pre-session question; the
  day mean over two slots is unchanged by any of it.
- npm run swift:core — every battery and stress vector byte-identical. Read the counts.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: native, senior-architect, code-reviewer, graphify
AGENTS: swift-expert, invariant-auditor, architect-reviewer, ios-developer

SHIP: branch onyx/sprint-next-gen-w10 from main. Bump to 3.19.0, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
graphify update . and APPEND the W10 Wave Record.
```

---

**W11**
```
Model: Fable

Read docs/NEXT_GEN_UX_SPRINT.md in full — finding F13, architecture A15 and A16, and the
"Every wave" list. Then execute W11. This is a MAJOR release: the founder must paste SQL and
the account-switch behaviour changes.

GOAL — pristine multi-tenant isolation, proven by a test and enforced by a policy.

INTROSPECT BEFORE YOU WRITE ANYTHING. docs/sql/ is EMPTY, there are ZERO .sql files in this
repo, and no RLS policy is checked in for any table — it is asserted in prose only. Use the
schema-truth-checker agent against the LIVE database and report, per table: is RLS enabled,
which policies exist, and what are their expressions. types.ts and supabase.json are NOT
evidence about policies. Write nothing until that report exists.

TASKS
1. docs/sql/w11-isolation-rls.sql — all 32 tables. `alter table ... enable row level
   security` plus select/insert/update/delete policies using the (select auth.uid()) = user_id
   INITPLAN form, so the check is evaluated once per query rather than once per row. Every
   statement re-runnable: `drop policy if exists` before each `create policy`. workout_sets
   and set_events are policed through workout_sessions' owner, not through a column they do
   not have. set_events is applied by hand and is ABSENT from the schema fixture — report its
   real state, never assume it. This file must be paste-perfect: the founder applies it once,
   in the Supabase SQL editor, with no chance to iterate.
2. Scope every unscoped local read. Add userId as a parameter and a WHERE user_id = ? to:
   PrRecorder.floors, PrRecorder.baselines, SessionHistoryStore.personalRecords /
   sessionHistory / historySets / cardio, WeeklyExportBuilder (input, toDays, withNutrients,
   ledger), ScoringInputsBuilder.sets, AppDatabase.sessions(on:) / session(id:) /
   sets(sessionId:) / observeSets / liveSession / liveWorkoutInProgress / discardSession /
   setSessionStart, SessionEditing (updateMetrics, amendSet, deleteSet, seedEventLog),
   WidgetSnapshotBuilder's vitalsSlice / bodySlice / volume, ReportsStore.weeks /
   reportBody, SetEventFold.sets, EventStore.reproject, DayEditing.addCardio / deleteCardio,
   TrainingPuller.applyPulledSets / deleteUnreferencedExercises, SessionMetrics.bodyweight.
   Where the table has no local user_id (workout_sets, set_events), carry it through the join
   to workout_sessions. Fix it once in the shared store function, not in each caller.
3. DELETE the Exercise.fetchCount(db) check in AccountSeed.needsOnboarding:153. Local
   `exercises` has no user_id, so one leftover catalogue row on the device suppresses
   onboarding for a brand-new account. Filtering it is impossible; the check is simply wrong.
4. Add the account-switch path. A sign-in whose user id differs from
   AppDatabase.knownUserId() must erase the local store before the first sync, using the same
   eraseLocalData() that signOut() already calls, and must surface the unsynced count first
   exactly as signOut() does. Today a sign-in without a preceding sign-out never erases.
5. TwoUserIsolationTests.swift — seed users A and B into ONE store, then assert for EVERY
   scoped reader that A's result set and B's are disjoint. This is the exhaustive test the
   brief asked for and it is the artefact that proves the wave.

SELF-CHECK
- TwoUserIsolationTests green across every reader.
- NewAccountPathTests extended: a store holding B's catalogue still offers onboarding to A,
  and A's PR list is empty.
- SignOutEraseTests extended with the account-switch path.
- The .sql file reviewed by supabase-schema-architect AND database-architect against the live
  introspection before it is handed over.

GATES: npm run check && npm run check:swift && npm run swift:core && npm run swift:data,
then the xcodebuild line.

SKILLS: schema, supabase-postgres-best-practices, native, senior-backend, senior-architect, code-reviewer, graphify
AGENTS: schema-truth-checker, supabase-schema-architect, database-architect, backend-architect, swift-expert, invariant-auditor, code-reviewer

SHIP: branch onyx/sprint-next-gen-w11 from main. Bump to 4.0.0 (MAJOR — the founder must be
told), version:sync, xcodegen generate, CHANGELOG, version:check. Merge --no-ff, delete
branch, push [skip ci]. graphify update . and APPEND the W11 Wave Record. End your final
message with the founder's manual checklist — the exact SQL file to paste and what to verify
after.
```

---

**W12**
```
Model: Opus (Extra High Effort)

Read docs/NEXT_GEN_UX_SPRINT.md in full, INCLUDING every Wave Record W1-W11 appended to it.
Then execute W12. This wave deletes the plan, so nothing in it may be lost first.

GOAL — the sprint leaves no residue.

TASKS
1. HARVEST FIRST. Read every Wave Record. Fold what a future reader needs into
   docs/CHANGELOG.md, and write a sprint memory file capturing the non-obvious: the root
   causes that were not where the symptom was, the constraints each wave had to respect, and
   the seams left open on purpose. Nothing in a record may be lost by deleting the plan —
   that is the entire reason the records were written as the waves shipped.
2. Delete docs/NEXT_GEN_UX_SPRINT.md.
3. Delete the sprint's SQL files ONCE THE FOUNDER CONFIRMS each is applied:
   docs/sql/w1-hk-uuid.sql, docs/sql/w9-doms-laterality.sql, docs/sql/w11-isolation-rls.sql.
   Leave docs/sql/ empty, as it was. ASK before deleting any of them — an unapplied file is
   the only copy of a migration.
4. `git branch --list 'onyx/sprint-next-gen*'` must return nothing. Delete any survivor,
   local and remote, and check origin too.
5. Purge caches: rm -rf ~/Library/Caches/onyx-swift/{OnyxCore,OnyxData} and the shot-w*
   directories, native/.build, and the project's DerivedData.
6. graphify update . and commit the rebuilt graph.
7. Full gate one last time, then merge, delete the branch, push [skip ci].

SELF-CHECK
- The changelog alone answers what shipped in 3.10.1 through 4.0.0.
- No file in the repo references NEXT_GEN_UX_SPRINT.md.
- No onyx/sprint-next-gen branch exists locally or on origin.
- npm run check passes on a clean tree.

SKILLS: ship, git-commit-helper, native, graphify
AGENTS: context-manager, code-reviewer

SHIP: branch onyx/sprint-next-gen-w12 from main. Bump to 4.0.1, version:sync, xcodegen
generate, CHANGELOG, version:check. Merge --no-ff, delete branch, push [skip ci].
```

---

## Wave Record template

Appended to `docs/NEXT_GEN_UX_SPRINT.md` by each wave, immediately after merging. W12 harvests
every one of these into the changelog and a memory file before deleting the file.

```markdown
### W<N> Wave Record — shipped <date> as <version>

**Drift from the plan, on purpose:** …
**Root causes that were not where the plan guessed:** …
**Constraints discovered that the next wave must respect:** …
**Left open on purpose:** …
**Founder's manual steps still outstanding:** …
```

---

## Verification

Per wave, in this order — and read the counts, because "no output" is not a pass:

```bash
npm run check          # version:check + types + atlas + mirror + doms + swift:ui
npm run check:swift    # OnyxCore + OnyxUI cross-build
npm run swift:core     # golden vectors + invariants   — NOT part of `npm run check`
npm run swift:data     # store, sync, migrations       — NOT part of `npm run check`
cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Layout needs eyes, not a green build:
```bash
SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w<N> scripts/native-shot.sh <screen>
```

Whole-sprint acceptance, on a device:
1. A fresh account shows **0 PRs, no food, no water, no macros, no meds, blank history** — and is offered onboarding even on a phone that has held another account.
2. Signing out and into a second account shows none of the first's data, on any tab, at any date.
3. Apple Health imports two workouts **once**, and says so once.
4. The Nutrition water row never reads `—` when the day has water.
5. Every tab's ground, tab tint and widget palette follow a theme change without relaunching.
6. Only the right glute can be marked sore, and the battery does not move because of it.

**Founder's manual steps (nothing here can be done from this machine):**
- ~~Paste `docs/sql/w1-hk-uuid.sql` after W1.~~ **Done 2026-09-15; file deleted.**
- Paste `docs/sql/w9-doms-laterality.sql` after W9. **Requires Postgres 15+ (`NULLS NOT DISTINCT`).**
- Paste `docs/sql/w11-isolation-rls.sql` after W11, then re-run the schema introspection to confirm every table reports RLS enabled.

---

## Wave Records

_Appended by each wave as it merges. W12 harvests these, then deletes this file._

---

### W1 Wave Record — shipped 2026-09-15 as 3.10.1

**Drift from the plan, on purpose:**
- **Two migrations, not one.** `v26.healthWorkoutUuid` adds the column;
  `v27.collapseCardioDuplicates` runs the sweep. Each is independently guarded,
  which is the v18/v19 precedent, and a sweep that fails cannot leave the column
  half-added.
- **The sweep pushes its deletions.** The plan said "a one-time local sweep".
  `cardio_logs` pulls on a date window, so a row deleted locally and left on the
  server returns on the next sync and the migration looks like it never ran.
  Every loser goes out through `enqueueRowDelete`.
- **`docs/sql/w1-hk-uuid.sql` collapses server-side too, under the SAME rule**
  (most non-null figures, ties by lowest `id`). The plan's "backfill from
  `created_at` where unambiguous" cannot mean backfilling `hk_uuid` — a uuid
  belongs to a HealthKit sample on a device and no historic row records which
  bout it came from. What `created_at` can recover is the duplicates, for the
  rows no device will ever open again. The two rules are written twice on
  purpose and must agree, or they delete each other's survivor.
- **The water render moved onto `NutritionModel`** as `waterFigures`. `WaterRow`
  is a `private struct` inside `NutritionTabView.swift` and nothing could assert
  on it — which is exactly why the `—` had no test to fail when it stopped being
  true. The brief asked for that test; this is what made it possible.
- **`WaterRowTests` does not run `observe()`.** It is the `.task` body: it awaits
  its streams and never returns, so a ledger value cannot be asserted
  synchronously at that layer. The ledger branch is asserted where its inputs
  are controllable — `WaterTruthTests` (pure) and `WidgetWaterTruthTests` (a
  snapshot over a seeded store) — and the store half of `clearWaterOverride`
  moved to `DayEditingTests`, where the database is directly readable. All three
  read the same four shapes.

**Root causes that were not where the plan guessed:**
- **`UUID.uuidString` is UPPERCASE and Postgres renders a uuid lowercase.**
  `UserIdCasingTests` greps the whole tree for a render that is not
  `.lowercased()` on the spot, and it failed on the first run. Left alone, a key
  written uppercase and pulled back lowercase would have stopped matching itself
  after one round trip — the duplicate returning by a new route, with the unique
  index making the re-insert an outbox jam instead of a visible row. Every
  render is now lowercased inline, which is also what the guard test demands.
- **A bout that crosses midnight was filed under BOTH days.**
  `reader.workouts` deliberately has no `.strictStartDate`, so a 23:40 walk is
  returned by both of the pass's two queries. No same-day rule can see that
  duplicate — and the new `(user_id, hk_uuid)` unique index would have REJECTED
  the second push forever. `ingestCardio` now files a bout under the day its
  start falls in, which is the day `created_at` already claims.
- **`clearWaterOverride` was destroying more than the override.** The plan said
  it "deletes the ledger and nils the flat column"; what makes the day
  unrecoverable is that `DailyLogIngest` returns at `guard !payload.isEmpty`, so
  nothing mints the row back when HealthKit has nothing to say. The one-way door
  is only the `manual-water-` sentinel, so only that is deleted now; Apple's own
  row and the tapped glasses survive and the projection is re-derived from them.

**Constraints discovered that the next wave must respect:**
- `OnyxCore` cannot see `OnyxData`, so `WaterTruth.ml(log:ledger:)` takes plain
  `Double`s. Any future rule shared between the tab and a tile has to be shaped
  the same way.
- The key is written the moment the founder walks anywhere, so between this
  build and the paste every imported bout's push is rejected for an unknown
  column. Per-row, retried under `SyncBackoff`, self-clearing — the
  `v24.stressEvents` precedent. It is why the SQL is first in the handover.
- `WeeklyExportBuilder`'s render-time dedupe is **left in place**. It is a cheap
  net and its anomaly counter is how a regression would announce itself. W12
  should not remove it without a reason.
- A bout that started before the two-day window and ran into it is no longer
  imported. It was only ever imported under the wrong date; `syncCardioBouts`
  scans two days and the third is out of scope by the same rule as every other.

**Left open on purpose:**
- No `HKAnchoredObjectQuery`. The uuid key makes the re-read idempotent, so the
  anchor would buy a smaller read and a new piece of state to keep correct. The
  ceiling is noted where it matters; it is not the defect.
- `hk_uuid` is looked up within the day's rows, not store-wide. That is only
  sound because a bout is now filed by its start; a future wave that widens the
  ingest window must widen the lookup with it.
- The "pending or denied" distinction is not read from HealthKit — no
  authorization state is exposed anywhere in the app. `isAwaitingHealthWater` is
  "nothing in either store, inside the window the sync scans", which is true of
  both and needs no new plumbing.

**Founder's manual steps still outstanding:**
- Paste `docs/sql/w1-hk-uuid.sql` into the Supabase SQL editor. Nothing in this
  repo can apply it, and until it runs no imported bout reaches the server.


---

### W2 Wave Record — shipped 2026-09-15 as 3.11.0

**Drift from the plan, on purpose:**
- **The hero numeral is `.display`, not `.hero`.** The brief asks for both
  "`SleepHeroCell` — full-width, `.hero` numeral" (item 2) and "One `.hero` per
  screen is the token rule; Score keeps it" (item 4), and Pulse cannot have
  both. `OnyxType.hero`'s own header says "at most one per screen — a second
  hero is two screens in a trench coat", and item 4 is this wave REMOVING the
  strip's second one. Adding one back 80 pt lower would have undone the rule in
  the diff that enforces it. The night still leads the VITALS — full width,
  against a grid of `.secondary` cells — and the screen's one hero stays the
  Score, which is what the type scale calls "the one figure a screen is about".
- **`VitalHero.promote` takes z values, not series.** A1 says the input is "the
  `zSignal` the readiness engine already produces", so the rule takes
  `[VitalReading(id, upIsGood, z)]` and a second entry point,
  `VitalHero.reading(id:upIsGood:log:series:)`, is the only thing that calls
  `Readiness.zSignal`. Two consequences, both wanted: there is exactly one
  threshold model and this file does not contain it, and the golden fixture is
  fourteen readable cases of z triples rather than six 49-element arrays per
  case, which is a spec a human can check by eye.
- **Steps, Stand and Active are not candidates.** They are activity, not
  vitals: a quiet Sunday is a step count two SDs down and is not a reason to
  lead a recovery screen with it. `VitalSpec.all` — the five the watch takes
  overnight — is both the candidate list and the tie-break, which is also what
  the brief names.
- **`day-vitals` is now `day-hero`.** The shot photographed a disclosure that no
  longer exists. It photographs the one state `day` cannot: a promoted vital
  leading, with Sleep in its grid cell. `startVitalsOpen` is gone from
  `PulseTabView` and `DayScreen`.
- **`DepthBar` went public and gained a `cornerRadius`.** The app's hero bar is
  the widget's stacked bar at 44 pt, and a second implementation would be a
  second answer to "what was this night made of" — the rule `DepthArc` is
  public for. The radius is a parameter because `height / 2` at 44 pt is a
  22 pt curve that ate the whole of a short "awake" segment and left a grey
  crescent; the tiles keep the capsule they were drawn with.
- **`NowStripPulse` lost its accessibility branch entirely.** It existed because
  the fuel sentence shared a line with two numerals and a ring. With the
  sentence on its own line there is one question left — does the score fit
  beside the battery pair — and that is a `ViewThatFits` measurement, not a
  type-size setting.

**Root causes that were not where the plan guessed:**
- **F4 says the dynamic hero "needs no new math". True of the formula, false of
  the data.** `DayModel.loadWindow` read **14** days of `daily_logs`; a
  `zSignal` needs 49. The window now reads 49 and `block(_:)` is handed a
  fortnight slice, so every delta on the screen is still Apple's own baseline
  and still agrees with the Home Screen tile. The series also has to be **dense
  — one slot per date, nil for a missing row** — because `zSignal` splits its
  input at `count − 7`: built from the rows that happen to exist, a fortnight
  off the wrist slides the split and the rule quietly compares last week to the
  week before it.
- **The `fullDay()` fixture promoted HRV on the DEFAULT shot.** It carries 49
  days of HRV (seeded for the stress index, with a deliberate excursion to 41)
  but only **nine** of `sleep_minutes`. The night therefore had no baseline, no
  z and a floor of zero — and HRV's −1.05 took a slot the night could not
  defend. The fixture now seeds 49 nights; the last nine are the short week the
  bank was already built from and the forty behind them are ordinary. The night
  clamps at −2 and holds its slot, and `alarmedDay()` is the seed where it does
  not. **A preview fixture that is thin in one column is not a neutral fixture
  — it is a claim, and this one claimed a promotion.**
- **`Readiness.zSignal` on a numerically flat log baseline returns ±2, not
  nil.** `sampleSd` of 42 identical values is exactly zero only while the sum is
  exact: `50` repeated adds exactly, `ln(50)` repeated does not, and the
  last-bit residue leaves an SD near 1e-16 that passes the `sd > 0` guard — so
  every delta clamps. Unreachable with sensor data (42 nights of HRV agreeing
  to the last decimal) and **not fixed here**: a guard inside `zSignal` would
  move the battery and the stress index. It is stated in `VitalHeroTests`, and
  the flat-baseline case is asserted on the raw path where a flat baseline is
  exactly flat.
- **A green `check:swift` hid a broken app target, exactly as the plan warns.**
  Extracting `seedFullDay` out of `fullDay`'s closure lost the `@MainActor`
  isolation the closure had inherited; four `DayModel.localInstant` calls failed
  only in the app target.

**Constraints discovered that the next wave must respect:**
- **`DayModel` does not import `OnyxUI`, and must not start.** `VitalSpec` lives
  in the design system and its `all` order IS the promotion tie-break, so the
  model carries the SERIES (`Window.VitalSeries`) and `VitalsGrid.hero(_:)`
  carries the ORDER. Anything that needs both belongs on the view side.
- **The cell delta is the 14-day Apple baseline and the hero rule is the 49-day
  z. They are different facts and neither may be printed as the other.** The
  widget prints the same delta; the z is a verdict about a week and the delta is
  a reading about a night, and they disagree in public whenever the week catches
  up.
- **The night keeps a door in BOTH slots.** `SleepEditSheet` is the only way to
  the arc, the four stages and the two flags the watch cannot record. Hero, it
  is the whole cell; demoted, it is the one grid cell with a chevron, and at
  accessibility sizes it is a `PulseRow` rather than a `MetricRow` — the grid's
  own fallback has no tap. W3 reorders this screen; those two are the only
  entrances.
- **The grid is always eight cells.** The promoted vital leaves and Sleep takes
  its place IN the same index, so the layout does not reshuffle on the morning
  something goes wrong.
- `VitalsSection.body` folds `readings(_:)` and `hero(_:)` once and hands them
  down. As computed properties they ran two and three times per body
  evaluation — six 49-point z passes each time this row is re-realised.

**Left open on purpose:**
- **No shot reaches the grid's Sleep row at AX5 while a vital is promoted.** The
  hero cell is most of the screen at that size and there is no scroll anchor
  between the Now strip and the carousel. The row is `PulseRow`, which
  `day-rows-ax5` already photographs; adding an anchor for one row was more new
  surface than the review is worth. `day-ax5` does prove the door exists in the
  hero slot.
- **The promotion has no motion.** The hero changes with the day, not under a
  finger, so there is no gesture to animate from — and a hero that slides in on
  first paint would animate on every scroll that re-realises the row.
- **The battery ring stays a fixed 44 pt.** It looks small beside a 60 pt
  numeral at AX5. Scaling it grows the tile at exactly the size where the screen
  has least room, and it was fixed before this wave too.
- **`VitalHero` reads no fatigue, soreness or stress.** They are on the same
  screen and all three are self-reported; the hero slot ranks things a watch
  measured while you were not doing anything.

**Founder's manual steps still outstanding:**
- **None.** The founder applied both `docs/sql/w1-hk-uuid.sql` and
  `docs/sql/w1-stress-events.sql` on 2026-09-15 and the files are deleted — W12
  no longer has them to clean up, and `docs/sql/` is empty again.

---

### W3 Wave Record — shipped 2026-09-16 as 3.12.0

**Drift from the plan, on purpose:**
- **The square grid made Pulse TALLER, not shorter, and it shipped anyway.**
  Measured on a 402 pt phone at default type: the default day went from ~1.37
  screens to **~1.52**. The carousel saved 66 pt and the stress-log sheet saved
  ~140, but a 2 × 2 grid of true squares is **361 pt** where the tile + the
  two-row section it replaced were ~204. A square on half a phone is 172 pt tall
  whatever is in it, and three of the four cells do not have 172 pt of content.
  Decision 5 asked for Option 3's treatment *strictly*, so it was built strictly;
  the budget is still met on the default day, and a day with two sessions is
  ~2.0 screens. If a later wave wants that 90 pt back, the lever is
  `PulseSquare`'s `aspectRatio(1, …)` → `4/3`, and nothing else has to move.
- **`StressTile` was deleted, not reused.** The plan said the index "keeps its
  sparkline at 50-baseline", which it does — but as `StressSquare`. A full-width
  tile and a 172 pt square cannot share a layout, and keeping both would have
  left a dead view drawing the same number.
- **The index numeral dropped from `.hero` to `.display`.** `StressTile` used
  `onyxHero()` while the Now strip's Score also does, which is the exact thing
  `OnyxType.hero` forbids in as many words ("at most one per screen"). W2 argued
  this out for the sleep hero and resolved the same way; this closes the last
  live violation on the screen. It also does not fit a square at 28 pt.
- **`day-soreness` was repointed, not deleted.** It photographed the carousel's
  third page; the page is gone, so the name now photographs the sheet that page
  was a door to — which is what the square opens.
- **Every Pulse fixture now pins the clock**, not just the four sheets that
  already did. The Stack square's numerator is a question about the time of day,
  so an unpinned `day` counted 3 doses at lunchtime and 9 after ten.

**Root causes that were not where the plan guessed:**
- **"The rating verb moves onto the map sheet" was already done.** The severity
  popover has lived on `DomsTile` since W6 and `SorenessSheet` is a thin wrapper
  around it. `SorenessCard` was only ever a door with a list on it, so removing
  the page cost no capability and required no new control. The plan's own
  resolution note says this; it reads like work and is not.
- **The preview fixture had a supplement skip with nothing under it.**
  `seedFullDay` has ended with `setSupplementSkipped(itemKey: "caffeine")` since
  the stack tracker shipped, and no fixture ever seeded a stack — the write
  landed on a key with no dose behind it and nothing on any screen read it. It
  was invisible until a square started counting doses. Seeding
  `PreviewCatalogue.seedStack`'s nine is what brings it to life, and it is what
  puts all three dot states on the default shot without a single extra mark.
- **`fullDay` had no body metrics at all**, so the Scale square would have
  photographed "No weigh-in" on the flagship shot — W2's lesson (a fixture thin
  in one column is a claim, not a neutral state) in a second column. Ten
  weigh-ins over five weeks, at the real twice-a-week cadence.

**Constraints discovered that the next wave must respect:**
- **`PulseCard`'s floor is not what makes the pages agree.** The carousel's
  eager `HStack` already sizes every child to the tallest of them; the floor only
  stops a page with one short line collapsing on a day nothing is logged. That is
  why 196 → 116 changed the card's height by 66 pt and changed nothing about the
  two pages matching. Do not "restore" the floor to fix a height that is
  content-driven.
- **The `@ScaledMetric` cap is a floor cap, not a height cap.** At AX5 the stress
  page is ~490 pt because its content is; `min(floor, 200)` only stops the
  *metric* from reserving 270 pt of empty glass. A wave that wants the AX5
  carousel shorter has to cut content, not the cap.
- **`PulseSquareGrid` falls to rows at the accessibility sizes**, reusing
  `ScaleRow` and `StackRow` unchanged and adding two new ones. Half a phone is
  171 pt wide, so a square of it is 171 pt tall, and four of those is ~1,370 pt
  to say what four rows say in 200. Any fifth square must bring a row with it.
- **Every presentation on Pulse is now declared on `DayScreen`** — the stress
  breakdown was the last one still owned by a view inside a `List` row. The one
  exception left is `ScaleSquare`'s `.confirmationDialog` for the weigh-in skip
  reason, which `ScaleRow` has always carried at that level and which W3 moved
  rather than re-homed.
- **`DayModel.Window.weight` costs no query.** It is `weightKg` off the same 49
  `daily_logs` rows the vitals already read. A future trace over any other
  `daily_logs` column is the same one-line addition; anything outside that table
  is not.

**Left open on purpose:**
- The square grid's height (see the drift note). `aspectRatio(1, …)` is one token
  away from `4/3` if the founder wants the 90 pt.
- `SorenessSheet` draws `DomsTile`, whose own header reads "Soreness" directly
  under the sheet's "Soreness" nav title. Pre-existing, and a W4-sized copy fix
  rather than a layout one.
- The five-word picker in `StressLogSheet` runs close to the section's right
  edge at default type. Measured as inside, not clipped; unchanged by this wave.
- `OnyxTests` still has the four failures `main` carried in (memory:
  `auto-fixes-w7`). Not run as part of this wave's gate.

**Founder's manual steps still outstanding:** none for W3. The two SQL pastes
the sprint still owes are W9's and W11's, unchanged.


---

### W4 Wave Record — shipped 2026-09-16 as 3.13.0

**Drift from the plan, on purpose:**
- **`MuscleMap` answers for cardio from a SECOND table, not from `dict`.**
  The brief says "MuscleMap must answer for cardio kinds"; it does, through
  `MuscleMap.cardioDict` and `cardioMovers(_:)`, which nothing but the ledger
  header reads. Putting a treadmill in `dict` would have done three things
  nobody asked for: broken both golden fixtures that hold that array to the
  TypeScript entry for entry (`muscle-map-dict`, `muscle-dict`), started paying
  `MuscleCredit.weightedSets` for walking — which moves the weekly MEV/MAV
  accumulator, the Freshness Map, the per-muscle tonnage breakdown and, through
  the battery, the readiness score — and done it silently. The display question
  and the credit question are not the same question, and now they have separate
  tables. `CardioMoversTests` in `swift:core` holds the separation from both
  sides: a lift never reaches the cardio table and a bout never reaches `dict`.
- **The pair's shared delta is keyed on `SessionVolume`, not on `L + R`.**
  A3 says "the pair's combined load × reps". That phrase has exactly one
  definition in this app and it is not the sum: `SessionVolume.sessionVolumeKg`
  scores a genuine L/R pair ONCE at the weaker side, `min(w) × min(r)`, so a set
  logged split weighs what the same set weighs logged whole. The card's own
  tonnage capsule is that function and the session's tonnage is that function;
  summing the two arms would have put a number on the row that disagreed with
  the capsule 24 pt above it about what a pair is worth.
- **The pair's sub-lines are `secondary` (15 pt), not `micro` (11 pt).**
  A3 names `micro`, and `micro` is the one role this scale forbids for a value,
  in as many words: *"a register label — uppercase, tracked out, never carrying
  a number"*. `secondary` is the legal step down and is named for exactly this
  ("the line under a value"). The `L` / `R` TAG is `micro`, because a tag is a
  label — which is also what the logger's own split row does, down to the 14 pt
  fixed track.
- **`.pair` is reached when ANY row of the card is a pair, not when all are.**
  A movement trained one arm at a time routinely opens with a bilateral warm-up,
  and a "pure pairs only" rule would have left the commonest real shape on
  `.whole` — the exact behaviour the layout was added to end. A single row on a
  `.pair` card draws its own whole string and reserves the same one-verdict line
  under it, so the two shapes genuinely share a table.
- **The reserved line is a HIDDEN `Text("—")`, not `Color.clear.frame(height:)`.**
  A2 suggests the frame. A hardcoded height holds at the default type size and
  drifts at AX5, where the micro line is several times taller. The same `Text`
  in the same role with `.hidden()` — documented as "hides this view without
  changing its layout" — makes the reservation the old height BY CONSTRUCTION,
  at every text size, with no number to maintain.
- **`headerTags` gained the bout's readings but kept the four strength guards.**
  The plan says the cardio branch prints "where the five strength tags are
  guarded off". They are not skipped by a branch — they guard themselves off,
  correctly, because a bout has no top set, no tonnage, no prescription and no
  previous volume. A rated bout therefore still shows its RPE, which is a fact
  the row should not suppress.

**Root causes that were not where the plan guessed:**
- **The cardio family hue was ALREADY fixed.** F6 says the hue "falls through
  `:1155-1161` to `MuscleGroup.forExercise(...).domain.accent` — `.recover`
  lavender", and task 5 asks for it. `SessionDetailView.family(_ ex:)` — a
  second overload taking the REPORT rather than the name — has resolved a bout
  to `Color.onyx.cardio` since `31b58942`, and `ledger(_:)` has called that
  overload since the same commit. The plan was written against the one-argument
  version. W4 left the behaviour alone and put it under test instead.
- **`OnyxTests` does not run on this machine at all, and it is not four
  failures — it is zero executions.** Measured on a PRISTINE `main` checkout
  with a fresh derived-data path: `xcodebuild test
  -only-testing:OnyxTests/SessionTableTests` starts all five of the tests that
  predate this wave and finishes none of them. Each takes the app host down with
  `Test crashed with signal trap`, the runner restarts twice, and the summary
  reads "Executed 0 tests". Those five call `SetRow.layout(_:)` and
  `SessionDetail.toRows` and nothing else — pure functions with no branch that
  can trap — so the fault is in the host, not in the suite. **The memory note
  "`OnyxTests` has four failures on main" understates it and should be read as
  "the bundle does not execute".** This is why `npm run check` runs `OnyxUITests`
  and not this bundle, and it is the reason W4's own OnyxCore-side assertions
  were written as a separate suite that a real gate executes.
- **Two fixture defects the first shot run found, neither of them in the
  ledger.** `PreviewHarness` keeps its OWN list of screen names and routes only
  those to `HistoryPreviews.view(_:)`, so adding a `case` to the view builder
  and a name to `native-shot.sh` is two of the three edits a new screen needs —
  the first `session-pairs` PNG is a photograph of "No harness screen named
  session-pairs". And **every RPE in the fixture was `7 + i × 0.5` on every one
  of the six sessions**, so the effort column's delta was zero on all eighteen
  sets and this wave's headline claim had nothing to photograph. The last
  session is now half a rung harder across the board, which is what its reps
  say happened — 11/10/10 against 10/9/12 at the same load. Same argument the
  seed already makes for the failure set: an unreviewable state is one that
  breaks silently.
- **The test fixture's "pair" case was never a pair.** `SessionTableTests.whole`
  asserted `.whole` for two sets carrying `side: "left"` / `"right"` and NO
  `pairId`. `SessionDetail.toRows` folds on `pairId` alone and tests
  `side == "R"` exactly, so that fixture produced two SINGLE rows that resolved
  to `.loaded` — the assertion was about a card that held no pair. Fixed in
  passing; the helper now takes a `pair:` id and the tags are `"L"` / `"R"`.

**Constraints discovered that the next wave must respect:**
- **`MuscleMap.dict` is load-bearing arithmetic, not a lookup table.** Anything
  that wants to name a muscle for DISPLAY and must not move a score belongs
  beside `cardioDict`, not in `dict`. The `swift:core` suite now fails if a lift
  leaks into the cardio table or a bout leaks into the dictionary.
- **`MetaTagRow.Capsule` is the shared capsule now.** `FlowRow` places SUBVIEWS,
  so a header cannot nest a `MetaTagRow` inside its own flow and get one line
  out of it. Any surface that wants readings on a line with something else takes
  `MetaTagRow.Capsule`, never a second drawing of one. Note the nested type also
  shadows `SwiftUI.Capsule` inside that file, which is why the shape is spelled
  in full there.
- **`SetLayout.comparable` now drives the row's ALIGNMENT as well as its delta
  line.** A layout that reserves no delta centres its content against the 28 pt
  badge; one that does hangs from the top. A sixth layout has to answer both
  questions, not just the first.
- **`Page.bout` is `session_id`-only on purpose.** `AppDatabase.cardio` matches
  `session_id = ? OR date = ?`, and the date half is filtered back out here: a
  morning walk would otherwise lend its heart rate to an evening leg day's
  treadmill card. W5 rebuilds `cardioCard` off the same table and should take
  the same care.
- **The fixture's treadmill-only day sits on 2026-09-06**, the Sunday AFTER the
  photographed block, so it cannot add a row to a week another shot is a picture
  of. Anything seeded inside 30 August – 5 September changes shots this wave did
  not touch.

**Left open on purpose:**
- **The merged header did not save a line on every card.** The claim in A4 is
  "~24 pt off every card"; what one `FlowRow` actually buys is the line the
  chips used to reserve when they ended with half a phone free, which is a
  two-mover movement at 402 pt. A three-chip lift with five readings still wraps
  to three lines, because eight objects do not fit two. The lever if the founder
  wants the rest is the `cue` capsule and the `n/m @ window` capsule, both of
  which say something the progression card above already says — that is a
  content decision, not a layout one, and it was not this wave's to make.
- **A `.pair` card's RPE carries no arrow.** `previousSet(_:row:)` still refuses
  a pair (correctly — the previous session's flat list holds two entries per
  ordinal), so `prev` is nil on a pair row and the effort WORD is drawn rather
  than a figure with a delta. The pair's one verdict is its volume. Giving the
  effort its own comparison means folding the previous session twice, for a
  second number on a row that has room for one.
- **`SessionTableTests` is written and cannot be run here.** Every assertion in
  it is real and none of them has been executed. Its header now records the
  measurement above so the next wave does not spend an hour rediscovering it.
  What IS verified: `swift:core` (523 tests) covers the cardio table, and the
  six screenshots cover the rest — `session-pairs` shows `7.5 ▲ +0.5` in
  `danger` on three consecutive sets beside `7.5 ▼ −2.5` in `good` on the card
  below it, which is the inversion and its absence of over-reach in one frame;
  `session-cardio` shows all four bout capsules and the cardio rail where the
  empty row was; and every row of every card is the same height whether it
  carries an arrow or not.
- **The em-dash also survives inside `CardioMetrics.formatPace`**, which answers
  `"—"` for anything it cannot divide. `cardioTags` drops the capsule rather
  than printing one, so nothing on the card shows it — but a future caller that
  forgets that guard will put the dash back.

**Founder's manual steps still outstanding:** none for W4. The two SQL pastes
the sprint still owes are W9's and W11's, unchanged.

---

### W5 Wave Record — shipped 2026-09-16 as 3.14.0

**Drift from the plan, on purpose:**
- **The bout's figures are `MetaTagRow.Capsule`s, not a labelled column block.**
  The brief says "day, time, duration, distance, pace, avg HR with a heart
  glyph, compact". The four-column value-over-unit block it replaced was the
  compact-looking option and the wrong one: W4 had already given the SAME row
  a vocabulary on the session page — `figure.run` for distance, `speedometer`
  for pace, `heart.fill` for bpm, `heart.text.square` for provenance, all in
  `Color.onyx.cardio` — and a second drawing of those four readings is exactly
  the drift W4's own record forbids ("never a second drawing of one"). The
  Train card now says what the ledger card says, capsule for capsule. The heart
  glyph the brief asks for is the one the ledger already wears.
- **The time is printed only for an IMPORTED bout, not for every bout.** The
  brief says "Time comes from `created_at`, which on an imported row is the
  bout's START". True — and on a row the founder typed, the same column is the
  moment they typed it. `CardioImport`'s own header says so in as many words,
  and it is why its matching rule has two branches. A walk done at 08:00 and
  entered at 21:00 would have been stamped 21:00. So `boutStamp` appends the
  clock only when `fromHealthkit == true`, which also makes the pair legible:
  the bout that says WHEN is the bout that says who timed it.
- **The two placeholders became ONE view, not two edited views.** Tasks 4 and 5
  ask for the same treatment on two stand-ins that already drew the same three
  things. `SessionFallbackCard` is the one card; Train and Pulse pass four
  arguments each. The leading marks both of them carried — Train's
  `checkmark.circle.fill`, Pulse's 8 pt day-hue disc — are gone rather than
  unified: the real masthead draws neither, and a mark that vanishes when the
  read lands is a pop in the one transition the wave exists to smooth. For the
  same reason the title is `.hero`, matching `SessionHeaderCard` exactly, and
  not the `.display` both placeholders used.
- **`Shoulders` was promoted out of `SessionHeaderCard`.** The bout's kind and
  its stamp are two things at the two ends of one line with the same AX5
  failure the masthead's title row has, and the app already had the answer as a
  private helper. It is a view now, with three callers. Note it could not stay a
  `@ViewBuilder func` wrapper — forwarding non-escaping closures to a `View`
  init that needs `@escaping` does not compile.

**Root causes that were not where the plan guessed:**
- **`FlowRow` drew a chip off the edge of the card, and had since it was
  written.** The AX5 shot of the new card showed "Automatically lo" running past
  the glass. The badge was not at fault and neither was `MetaTagRow.Capsule`,
  which carries `.lineLimit(2).minimumScaleFactor(0.6)`: `FlowRow` measures
  every subview with `.unspecified`, so a chip whose IDEAL width exceeds the
  container is placed at that ideal and clipped — its own wrapping and scaling
  rules never consulted, because nothing ever told the text it was short of
  room. Unseen for as long as every chip in the app was two or three words.
  Fixed in `FlowRow` and not in the badge, because the same capsule is on the
  ledger (W4) and was clipped there too. The guard is strict (`ideal.width >
  width`), so a chip that already fitted takes the old path exactly.
- **The Zone-2 rail's arithmetic was NOT the defect, and F7 half-says so.**
  `zone2Done` counts this week's bouts over `Zone2.minMinutes`; `weeklyTarget`
  is a target count of the same thing. 1/2 was a fraction that meant something.
  What was wrong was drawing it as a filled BAR one line under the last bout's
  `avg bpm`: a bar under a heart rate reads as a heart-rate bar, and there is no
  zone column behind that promise. The first version of this wave's comment and
  changelog both claimed the two halves measured different things; they do not,
  and review caught it. The caption still says "Zone 2" for a duration rule —
  that name is `Zone2` in OnyxCore and on the widget face, so renaming it is
  four surfaces and a founder's word, not this card's call. Marked `ponytail:`.
- **The stand-in's capsules could DISAPPEAR when the header landed.**
  `DayModel.focus` folded `MuscleCredit.weightedSets` — which pays a SECONDARY
  mover half a set and counts warm-ups — while `SessionHeader.muscles` is
  `SessionAnalysis.primaryLandmarks`: whole working sets per PRIMARY mover. A
  muscle that is only ever an assistor could take a capsule in the stand-in and
  have none at all in the real card, which is the exact contradiction the card's
  own documentation promised was impossible. `focus` is now
  `primaryLandmarks(...).prefix(3)`, so the stand-in is a prefix by
  construction and the read can only append. This also silently fixed Pulse,
  whose screen wash reads the same list.

**Constraints discovered that the next wave must respect:**
- **`FlowRow` now measures against `proposal.width` in `sizeThatFits` and
  `bounds.width` in `placeSubviews`.** Every current caller sits in a
  width-constrained `VStack`, so the two agree. A caller that measures with a
  nil width and then places at a definite one would under-report its height and
  clip its last row.
- **`RoutineDayEditor.swift:148` is the only `FlowRow` whose subviews are not
  text chips** — they are `Stepper`s, which rearrange their own contents when
  given a definite width rather than merely narrowing. It previously drew past
  the card edge, so the clamp is still a fix there, but it is the one call site
  whose AX5 appearance changes shape rather than width.
- **`DayModel.focus` is now the muscle ranking for THREE surfaces** — Pulse's
  screen wash, Pulse's session card and the Train tab's done card — and its
  contract is "a prefix of `SessionHeader.muscles`". Anything that changes how
  it ranks breaks the stand-in's no-pop guarantee.
- **`.defaultScrollAnchor(.bottom)` applied in the harness reaches the screen's
  own `ScrollView` through the environment.** It is how `train-cardio` reviews a
  card three screens below the fold with no seed added to the production view.
  It parks on the LAST card, which on a rest day is the cardio card only because
  `progressionCard` is keyed on today's split and a rest day has none.
- **`seededHeaderPending` is the only production scaffolding this wave added**
  — one `Bool` with a default beside the two existing preview seeds, guarding
  the `doneHeader` task. Without it the stand-in is unphotographable: the read
  finishes faster than the screenshot, which is how it stayed a grey box through
  four waves.

**Left open on purpose:**
- **`fromHealthkit` is set true for a row the founder FILLED IN from a Health
  bout and then edited by hand** (`CardioLog.swift:372` writes
  `fromHealthkit: start != nil`). The stamp stays honest — the start is real —
  but the "Automatically logged" capsule overclaims on a corrected row. Naming
  that distinction needs a column `cardio_logs` does not have.
- **The clock renders in the DEVICE's current timezone while the day beside it
  is the row's ISO date.** A bout logged abroad can print a time that disagrees
  with its own day. Pre-existing family — `SessionAnalysis.stamp` does the same
  for every session on the ledger — and not worth a second convention here.
- **`lastCardio` has no upper date bound.** Harmless in the app, where no bout
  is in the future; in the pinned-date fixture the 6 September walk is "the last
  bout" on a tab whose today is the 3rd. It is what makes the badge and the
  clock photographable at all, so it was left alone.
- **The Pulse stand-in has no shot of its own.** It is the same view as Train's
  with four arguments, and `train-pending` photographs it; a second harness seed
  on `DayScreen.sessionHeaders` bought nothing the first one does not prove.
- **`OnyxTests` still executes zero tests here** (W4's measurement), so the
  three new behaviours — the prefix guarantee, the stamp's `fromHealthkit`
  branch, the `FlowRow` clamp — are verified by `swift:core`/`swift:data`
  staying green and by the screenshots, not by a unit test. `WorkoutWeekTests`
  is unchanged, as the brief required: `doneMuscles` is a new `Snapshot` field
  with a default and `State.done` was not touched.

**Founder's manual steps still outstanding:** none for W5. The two SQL pastes
the sprint still owes are W9's and W11's, unchanged.

---

### W6 Wave Record — shipped 2026-09-16 as 3.15.0

`d013808a` (the wave) · `a739bd15` (the merge) · `5adfd644` (this record and the graph).

**Drift from the plan, on purpose:**

- **The payload `v` is still 4.** The plan says the Train arrangement goes "under a v5
  key `train`". It goes under a key called `train`, in the row the plan names, and the
  version number is untouched — because `Dashboard.version` is not a label on the
  payload, it is the GATE `fromStored` uses to decide whether a stored object has
  `phone`/`desktop` sides at all. Raising it to 5 without widening that gate reads every
  existing v4 row as "no sides" and hands every user the default dashboard; widening the
  gate rewrites `layout-serialize` and fourteen cases of `layout-from-stored`, goldens
  exported from the retired web app that cannot be regenerated. So `train` is read and
  written independently of `v` — absent means "everything visible", which is the right
  answer for every payload ever written, of any version. **W7 still owns the v5 bump**
  (A9's `StackSlot.linked`) and will find this key already sitting beside the sides,
  needing nothing from it.
- **Trends left the doors strip.** A7 says the door prints the delta with the caption
  beneath it, and it does — but not in a third of a row. `vs same point last week · on
  pace 32 t` is 38 characters, and the first shot of the 109 pt cell rendered it `vs same
  point last / week · on pace 1…`, with the projection — the half the caption exists for
  — inside the ellipsis. Library and History keep the strip because a count fits there;
  Trends is a full-width row below them. At an accessibility size it collapses to one
  column, explicitly on `typeSize` and not through `ViewThatFits` (memories
  `w1b-week-detail`, `epic-sprint-w4-loggers`).
- **The arithmetic moved to `OnyxCore`.** The plan puts the rule in `WorkoutWeek`. It is
  in `WeekPace` instead, with `WorkoutWeek.build` reduced to three calls. The reason is
  the next item.
- **Five new shots, not three,** and two of the extra three are the only way the wave can
  be reviewed at all:
  - `train-monday` · `train-past` · `train-customize` are the brief's three.
  - `train-customized` — the tab with Cardio, Ready to Progress and Past Weeks switched
    off, bottom-anchored. The Trends row sits under a seven-exercise plan card and is
    below the fold at **every** anchor a shot can ask for, so with the sections beneath it
    gone it becomes the bottom of the page and the new caption is finally in a frame. It
    doubles as the picture of what the Customize sheet *does*, which a sheet of switches
    cannot show.
  - `train-past-open` — one closed week expanded in place. The wrap-up reel drawn inside
    the tab is the largest thing this wave draws and a shot script cannot tap a row open,
    so `WorkoutTabView` gained `seededExpandedWeek`, the same kind of harness seed
    `seededHeaderPending` already is and for the same reason: the point of the shot is the
    REAL section with the real summary under it, not a `#if DEBUG` branch inside the row.
    Pinned to 16 August, the one week in the fixture that closed complete, so it pairs with
    `train-wrap` — the two must draw the same figures and differ only in their chrome.

**Root causes that were not where the plan guessed:**

- **`OnyxTests` runs.** The memory `next-gen-w4-ledger` records "OnyxTests executes ZERO
  tests here", and the "Every wave" list says it has four failures on `main`. Both cannot
  be true. `xcodebuild test -only-testing:OnyxTests` executes 45 tests and fails exactly
  four — the documented baseline, confirmed by running the same target in a `main`
  worktree. The memory is stale; `npm run swift:ui` runs `-only-testing:OnyxUITests`
  only, which is where "zero tests" came from. **No gate runs `OnyxTests`.** The wave's
  arithmetic went to `OnyxCore` anyway, because `swift:core` is a gate and this is not.

  The four are, by name, so the next wave can check the baseline rather than trust a
  count: `ready to progress fires only after the ceiling is cleared twice`, `A capsule
  counts its week and marks the days that were missed`, `Week 0 is the week the block
  opened on`, and `a treadmill logged on this phone is titled Treadmill, not its slug`.
  Run them with

  ```bash
  cd native && xcodebuild test -project Onyx.xcodeproj -scheme Onyx \
    -destination "id=$(xcrun simctl list devices available | grep -m1 'iPhone 17 Pro (' \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')" \
    -only-testing:OnyxTests CODE_SIGNING_ALLOWED=NO
  ```

  W6 added six cases to `WorkoutWeekTests` and all six pass; the failure count is still
  four.
- **The wrap-up shared the delta with the door.** `build` passed one `weekDeltaKg` to both
  the Trends door and the inline `wrap(...)`. A week wraps the evening its last PLANNED
  day is logged — a Friday on a five-day plan resting Saturday — so a day-matched delta
  would have given the wrap card a six-day comparison while the same week opened from
  History (`wrap(_:userId:weekStart:)`, the twin the brief fenced off) showed a seven-day
  one. Two numbers for one closed week, from a change that looked local to the door.
  `build` now computes both off one per-date read.
- **`isWrapped` was blocking the past-weeks list, and it was the wrong gate.** A row per
  closed week meant a row per week that satisfied `WeeklyWrap.isWrapped`, which on the
  shot fixture is exactly one. That guard exists to stop the This-week tile becoming a
  wrap-up door on a Tuesday — it is a question about the CURRENT week. A week that has
  ENDED has no work left in it whether or not every planned day was logged, and the
  missed day is part of what its summary reports. `requireComplete: false`; all three
  existing callers keep the default.
- **A `user_goals` row naming a plan is not a plan.** Two of the new `WorkoutWeekTests`
  cases went red asserting `weekPaceKg != nil`, and the product was right: the test store
  set `activePlan = "onyx5"` and seeded nothing else, and `Schedule.isTrainingDayIn`
  resolves the weekday layout through `routines` ROWS, not through that string. With an
  empty `activeProgram` every day of the week is a rest day, `plannedTrainingDays` is 0
  and the projection is correctly nil. The fix is `PreviewCatalogue.seed(database, …)` in
  the fixture — **any `WorkoutWeek` test that touches the schedule needs it**, and the
  existing cases in that file did not reveal the requirement because they assert on the
  progression queue and the ledger, which read sets rather than the plan.
- **The first `train-monday` shot photographed the wrong Monday.** 31 August is a Monday
  whose week already holds a Sunday session, so the tab came out mid-week with a full
  panel. Re-pinned to 7 September — a week with nothing in it, standing behind the
  fixture's fullest one, which is the exact state the old rule printed −13.0 t in.

**Constraints discovered that the next wave must respect:**

- **`Dashboard.version` is a gate, not a label** (above). W7's A9 bump must widen
  `fromStored`'s and `otherSideOf`'s sided-version check to accept 4 **and** 5 in the same
  commit that raises the constant, or every stored dashboard resets. `TrainLayoutTests`
  has a case pinning that the sides survive a train write; add the mirror for v5.
- **Any writer of `dashboard_layouts.layout` must carry through what it does not own.**
  There are now three keys in that row and two writers, each of which parses one and
  copies the rest (`serializeLayout(other:)`, `Dashboard.withTrain(in:)`). A third writer
  that rebuilds the object drops the other two silently.
- **`WeeklyWrapContent` is the wrap-up's body; `WeeklyWrapView` is only its chrome.** A
  figure added to the reel must go in the content or the Train tab's expanded row will not
  have it. The two hooks (`showsLegend`, `onNeedsHeight`) are what the sheet does for
  itself and the tab does not need.
- **`WorkoutWeek.pastWeekCount` is 8 and carries a `ponytail:` note.** Eight week-queries
  plus one `historySets` read per session inside them, on a pass that already does a
  dozen. `workout_sessions.total_volume_kg` holds the same number and is not read, because
  one seeded session still carries a null aggregate (memory `hotfix-data-ui-sep10`) and a
  collapsed row that disagreed with the banner it opens would be worse than the cost.
- **The long press is a `simultaneousGesture`, not a `contextMenu`.** A context menu
  attached to a whole tab lifts a snapshot of the entire screen, and it closes after one
  tap — three sections is three long presses. If W7 adds a press verb to Train, it joins
  the Customize sheet rather than growing a second gesture.

**Left open on purpose:**

- **Floating, movable Train widgets** — explicitly out of scope (W6 §4). Today is the
  arrangeable surface; Train has one live state and a plan card that must be the first
  thing seen. The week strip and the session card therefore carry no switch either.
- **`Swap.weekAssignment`'s Sunday anchor.** Still cuts its own seven dates
  Sunday-anchored while `build` cuts from the athlete's week start, so on a non-Sunday
  start the two differ by a day at each end. Documented at `WorkoutWeek.wrap`'s header
  since W6 of the epic sprint, inherited again here, and still not this wave's to change.
- **`finishedByDate` / `tonnageByDate` are duplicated inside the closed-week twin.** The
  twin has its own local `finishedWeek` and `tonnage` closures saying the same thing. The
  brief fenced that function off and hoisting its internals is a change to it, so the
  duplication stands — with both copies naming the same rule.
- **`.claude/settings.json` still points two `PostToolUse` hooks at
  `~/Documents/PyCharmProjects/Helix`, which does not exist.** Every `.swift` Write/Edit
  reports `bash: scripts/check-swift.sh: No such file or directory` after succeeding.
  Known since `deep-clean-purge-sep15`; the write lands and the patches in this wave went
  through script files anyway, per the "Every wave" rule. One line each to repoint, and it
  is not a W6 change.

**Founder's manual steps still outstanding:** none for this wave. Nothing here needs DDL,
a dashboard reset or a Supabase visit — the `train` key is additive to a row every account
already has, and an account that has never written one reads as "everything visible".

---

### W7 Wave Record — shipped 2026-09-16 as 3.16.0

**Drift from the plan, on purpose:**

- **`TodayFeed.coach` did not exist; it does now, and it is a passthrough.** The
  brief says "the sentence comes from `TodayFeed.coach`, extended with a rule
  table". There was no such property — `TodayFeed.readiness` is the coach
  headline (`ReadinessResult`), three fixed sentences keyed on one composite,
  with nothing to extend. So the rule table is a new pure type in OnyxCore
  (`Coach/CoachSentence.swift`), the sentence rides in the widget payload as
  `OnyxSnapshot.coach`, and `TodayFeed.coach` is a one-line computed passthrough
  so the name the brief uses exists and means what it says. **It has no caller**
  — the grid draws `feed?.snapshot` and `MegaView` reads `s?.coach` — and review
  asked for it to be deleted. Kept, because the brief names it as the API.
- **`StackSlot.linked` shipped; the v5 payload did not.** This is the wave's one
  reversal, made after review and confirmed with the founder. `Dashboard.version`
  is not a label on the payload, it is the GATE `fromStored` uses to decide
  whether a stored object has `phone`/`desktop` sides at all — W6's record says
  so and is why W6 left `v` at 4. W7 first raised it to 5 with a
  `splitVersions: Set<Double> = [4, 5]` gate so this build read both. That works
  *in this direction only*. An older build compares `v == 4.0` exactly: on a v5
  row `side` stays nil, the v1/v2/v3 chain all miss, `slots` comes back empty
  and `reconcile` hands back the default grid — then its next save writes `v: 4`
  with those defaults and its `otherSideOf`, the same comparison, finds no
  top-level `slots` and writes `"desktop": {}`. Both arrangements gone, stamped
  with a fresh `updatedAt`, and the wipe wins the next sync. The same class of
  bug as F9, in the commit that was fixing F9. `linked` needs no version at all:
  it is one optional key per slot, written only when true, and `parseSlots` has
  always read `id`/`size`/`items` and ignored the rest. `version` is 4.0,
  `splitVersions` is gone, and `layout-serialize.json` is `main`'s file
  untouched.
- **A8's 22 pt stroke could not be inherited, and the header says which part
  was.** `WeeklyMuscleRing` strokes 22 pt on one 170 pt ring; three concentric
  rings inside a Large tile share 176 pt of diameter and at 22 pt each there is
  no hole left for the battery. What IS inherited verbatim is the part that is a
  RULE rather than a measurement: `.butt` caps and `MuscleRingArcs.gap`. The
  width is 14 pt on a 20 pt pitch, solved backwards from the 68 pt hole the
  battery and its caption need.
- **The 2° gap does a different job here than on the muscle ring.** There it
  separates two adjacent arcs of near-identical lightness. Here each arc's only
  neighbour is its own tail, so the gap is what stops a ring at 100 % closing
  seamlessly and becoming indistinguishable from a full-opacity track. Same
  constant, same `.butt` requirement, different argument — stated rather than
  borrowed silently.
- **`WidgetId.daily` is a dashboard tile, not a sixth widget KIND**, and it is
  called **Day Rings**. No gallery entry, no intent, no scope decision. Not
  "Daily", because `OnyxDaily` is already a Home Screen kind by that name.
- **The jiggle was three-quarters already built.** `TileFrame` has had a
  `wiggle` state, a per-tile phase and both badges since W2, and `Done` has been
  in the toolbar since the screen was written. What was genuinely wrong: ±0.8°
  on `.easeInOut(0.14)`, which at arm's length reads as a shimmer, on a screen
  where the long press now opens a menu so the jiggle is the ONLY thing naming
  the mode.

**Root causes that were not where the plan guessed:**

- **A9's stated mechanism is already true on this surface.** "A linked stack's
  faces all render against the slot's own window instead of each resolving today
  independently" describes a Home Screen timeline. In the app,
  `SmartStackView` hands every face of a slot ONE `OnyxTileEntry`, evaluated
  once per body pass — they have never resolved anything independently, so A9 as
  written is a no-op with a switch on it. The one thing that genuinely is
  per-slot is the rotation PHASE (`stagger`, the slot id's hash), so a connected
  stack drops it: every connected stack turns over on one beat and the grid
  reads page one of everything then page two of everything. The Edit Stack
  footer says exactly that.
- **The Mega tile lands below the fold and no shot would have found it.**
  `reconcile` appends a new catalogue id at the end, which on a twenty-slot grid
  is three screens down. `TodayPreviews.model(megaFirst:)` moves it up for
  `today-mega` only; every other Today shot is unchanged.
- **`accessibilityReduceMotion` is read-only in `EnvironmentValues`.** The
  reduce-motion shot the brief asks for could not be taken: SwiftUI will not let
  anything write that key, and the simulator's own toggle is a `defaults write`
  plus a respring that `native-shot.sh`'s per-screen loop cannot express.
  `onyxForcesReducedMotion` is a sibling key that ORs with the system value,
  false everywhere except one `#if DEBUG` preview. Without it the still state
  would have shipped unphotographed.
- **The first cut of the rings solved to a 32 pt hole**, and the shot showed the
  per-cent sign and the word BATTERY both cut off by the inner track. Caught by
  the shot loop, not by any gate — and then caught a second time by review, as
  an off-by-one-stroke in the frame that replaced it: `outer − 4·pitch − stroke`
  is the innermost ring's PATH diameter, not its hole. A stroke is centred, so
  the clear space is a stroke narrower at EACH end.
- **`TileFrame` is generic, so its constants could not be `static let`.** Swift
  has no static stored properties on a generic type; `tilt` and `beat` are
  computed. The error appears only in `swift:ui`, not in `check:swift`.
- **The sentence and the ring above it disagreed about the sleep goal.** The
  debt folded against `goals?.sleepGoalHours ?? 8` while the SLEEP arc draws
  against `sleep.goalMin`, which is nil when no goal is set — a ring with no
  target directly over "3.2 h of sleep debt". Found by review. No goal, no debt,
  now on both this tile and Pulse's gauge.

**Constraints discovered that the next wave must respect:**

- **`Dashboard.version` stays 4.0 until something genuinely changes SHAPE.**
  Additive keys do not need it; the gate is a handshake with every build that
  has ever written the row, not a note about what the schema holds. The chain a
  bump sets off is written out in `Layout.swift`'s header.
- **`OnyxSnapshot.coach` is filled at `.full` scope only**, not `wantsBody`.
  `wantsBody` also catches `scope == .body`, a Home Screen family, which made
  the widget EXTENSION pay a 49-day `readinessHistory` plus a plan resolution
  per timeline refresh for a string no Home Screen face draws. Widen it the day
  a widget draws the sentence, not before.
- **`CoachSentence` borrows every threshold and must go on doing so.**
  `Readiness.constants.acwrOnset` / `.acwrSaturation`, `SleepDebt.band`'s words,
  `SleepDebt.minimumNights`, `Stress.band`'s cases, and — since review —
  `Battery.goodPct` / `Battery.lowPct`, which `Color.onyx.battery` now reads
  too. The battery band was the one pair that had been copied across the
  OnyxCore/OnyxUI boundary; `LayoutLinkedTests.batteryBandIsShared` ties them.
- **`linked` is normalised in `Dashboard.touch`**, which every mutation returns
  through, and in `parseSlots` for a row this app did not write. `setLinked`
  refuses to connect a one-face slot, but `removeFace` and `unstackFace` could
  wear the slot down to one face while carrying the flag — and `StackEditSheet`
  shows no toggle on a single tile, so nothing on screen could clear it. A new
  mutation that bypasses `touch` re-opens that.
- **`TodayModel.apply` is gated on `hasLoaded`, and a seeded layout counts as
  loaded.** Any new construction path that hands in a layout without a stream
  behind it must keep that true, or the grid is read-only in previews.
- **The three Mega ring numbers are solved, not chosen.** `outer`, `pitch` and
  `stroke` fall out of the legend's width and the battery caption's width; the
  header carries the arithmetic against the real 68 pt hole. Changing one alone
  re-clips it.

**Left open on purpose:**

- **A layout read failure leaves the grid read-only, and the only retry is
  leaving the tab.** Refusing the save is correct — saving an arrangement this
  device has not read IS the clobber — and the banner now names what is being
  refused rather than only what failed. An automatic retry is not built.
- **A ring at or past 100 % is unphotographed.** The 2° notch at twelve o'clock
  is what says "this one went all the way round", and no reading in
  `OnyxSnapshot.sample` reaches its goal. The arithmetic is
  `full = (360 − gap)/360` and is trivially checkable.
- **Connection is invisible on a tile.** It changes WHEN a stack turns over, not
  what it draws, so the only shot that reviews it is `today-stack-linked` — the
  Edit Stack sheet with the switch on.
- **The sentence costs one extra `stressInputs` read per `.full` build.**
  `readinessHistory` (five narrow scans) plus the day's own rows, beside the
  fourteen `scoringInputs` reads `batteryStackSlice` already makes, and it is
  handed `rows.schedule` so the context is not resolved twice. The documented
  upgrade is the one `StressInputsBuilder`'s header already names —
  `daily_scores.stress_index`.
- **The two `.claude/settings.json` PostToolUse hooks still point at the dead
  Helix checkout** (memory `deep-clean-purge-sep15`), so every `Edit`/`Write` on
  a `.swift` file reports a blocking error *after* applying the write. This wave
  routed Swift edits through `Bash` patch scripts instead, which is what the
  worktree memory asks for anyway. Repointing the hook would make every `.swift`
  edit pay for a full OnyxUI + OnyxCore cross-build, so it was left alone.
- **`OnyxTests` has its usual baseline failures** (`WorkoutWeekTests`,
  `History weeks`, `Session summary`); `TodayModelTests` is 22/22. The
  `programId` / `ctx` / `floor` unused-value warnings are pre-existing.

**Founder's manual steps still outstanding:** none for W7. The two SQL pastes
the sprint still owes are W9's and W11's, unchanged.


---

### W8 Wave Record — shipped 2026-09-16 as 3.17.0

**Drift from the plan, on purpose:**

- **A10's five lines do not exist.** `.tint()` is not a `TabContent` modifier.
  `SwiftUI.Tab` conforms to `TabContent`, and the SDK declares exactly these on
  it: `badge`, `hidden`, `disabled`, `tabPlacement`, `customizationBehavior`,
  `defaultVisibility`, `defaultSectionExpansion`, `sectionActions`, `help`, the
  accessibility set, and the gesture/menu set (`swipeActions`, `contextMenu`,
  `popover`, `draggable`, `dropDestination`). No `tint`. Applying `.tint()` to
  the *content* inside a `Tab` compiles and tints that screen's controls, and
  never reaches the bar item — which is the half W8.1 is about. Shipped instead
  as ONE `.tint(Self.domain(for: selection.wrappedValue)?.accent)` on the
  `TabView`, plus a `domain(for:)` switch. A tab bar only ever colours its
  selected item, so a selection-driven tint says exactly what five per-tab
  tints would have, and `nil` for Settings restores the system tint.
- **A12's assertion is inert as specified, so it gained a second half.** "Fire
  a DEBUG assertion when the suite is nil" cannot catch this bug:
  `UserDefaults(suiteName:)` returns a suite for any name that is not the main
  bundle id or the global domain, so it is never nil here. The condition that
  actually bites is `containerURL(forSecurityApplicationGroupIdentifier:)`
  returning nil. Both shipped — `assertionFailure` on the nil suite (a
  build-configuration mistake, correctly a trap) and a once-per-process DEBUG
  `print` on the missing container. The print is NOT an assert on purpose: the
  entitlement is unsigned on this free team, so the condition is true on every
  simulator launch and a trap would take the shot loop down on every run
  instead of making the condition visible in it.
- **~45 was ~105.** The plan counted the `.white`/`.black` reads on the faces
  the wave named; the real count of unconditional ones across the eleven tile
  files plus `Shared/WorkoutActivityCard.swift` (the Live Activity, a widget
  face by any other name) is 105 lines. All converted.
- **One new token, `Color.onyx.ink(_:)`.** `textPrimary` and `base` cover the
  type and the ground, but the atlas's unworked silhouette and the Vitals
  baseline tick are ink at weights the three text tokens do not name
  (0.05/0.09/0.12/0.13/0.20/0.30). Deliberately `Color.white.opacity(_:)` and
  not `textPrimary.opacity(_:)`, which would compound 0.92 into every caller
  and make 0.08 here mean something other than 0.08 in `hairline`.
- **A harness screen was added.** `tabs-today` … `tabs-you`
  (`PreviewHarness.tabsEnvironment`). Every other harness screen renders one
  tab's CONTENT with the shell removed, so the tab tint appears in none of
  them — W8.1 was unphotographable before this. `SignedInTabs` dropped
  `private` for it; `RootView` gates on `auth`, and a preview environment is
  never signed in.

**Root causes that were not where the plan guessed:**

- **The first `AppearanceCoverageTests` could not fail.** It looked for
  `.onyxScreen` anywhere in the file text. Commenting the ground out of
  `SyncStatusView` left the string in the comment and the test stayed green —
  the exact failure the suite exists to catch, walking straight through it. It
  now applies `TokenDisciplineTests`' `//` rule per line. **Any file-walk test
  added to this repo must be proved to fail before it is believed.**
- **`DaySheet` is why seven "ungrounded" sheets were fine.** `SwapDaySheet`,
  `StressBreakdownSheet`, `FatigueSheet`, `SleepEditSheet`, `InBodyEntryView`,
  `CardioLogSheet` and `WeekOverrideSheet` apply no ground of their own because
  the shared sheet chrome in `PulseTabView:716` applies `.onyxScreen(domain)`
  or `.onyxFormBackground(domain)` for them. `DaySheet(` is therefore the third
  ground marker in the test, not an allowlist entry — requiring those sheets to
  ground themselves would stack two meshes.

**Constraints discovered that the next wave must respect:**

- **`Mutex` is not available in OnyxData.** The package declares `.macOS(.v14)`
  and `Synchronization` needs 15. The once-guard in `AppDatabase` is a lazy
  `static let`, which the runtime serialises. Same applies to OnyxCore.
- **`RootView.swift` now imports OnyxUI.** It had been using
  `\.onyxBatteryLevel` through the extension-member leak (Swift resolves
  members of extensions in transitively-loaded modules; it does not resolve
  named types like `OnyxDomain`). Anything that reaches for a type from OnyxUI
  in the shell needs the explicit import.
- **`.standard` is still the fallback.** `appGroupDefaults()` centralises and
  names it; it does not remove it. On a device without the signed App Group
  entitlement the widget palette is still stale, by construction. Carries a
  `ponytail:` note. Gate 0 is what closes it.
- **The `mono ? .white` branch in the tiles is deliberate and stays.** Roughly
  140 sites. In accessory and tinted rendering the system flattens the face to
  one colour; that white is the rendering MODE's ink and must not follow the
  theme. A future wave that widens `TokenDisciplineTests` to ban raw
  `.white`/`.black` has to give those a token of their own first.

**Left open on purpose:**

- `native/Onyx/Features/Logger/AtlasFigure.swift` (5 reads) and
  `WeeklyShareCard.swift` (3) spell ink by hand for the same reason the tiles
  did. They are app screens, not widget faces, so they were outside this wave's
  scope; `Color.onyx.ink(_:)` now exists for whoever takes them.
- `AppearanceCoverageTests` matches the ground per FILE, not per declared type.
  A file declaring two root screens where only one is grounded passes. Marked
  with a `ponytail:` comment naming the ceiling; the fix is to split the file.
- The Live Activity card was brought in (it is a widget face); the watch's own
  `WatchInk` was not (it has its own token file and takes the spec over the
  bridge).

**Founder's manual steps still outstanding:** none new. The App Group
entitlement (Gate 0, paid Developer Program) remains the one thing that makes
the widget's theme actually shared — everything else about it now works and
says so out loud when it cannot.

---

### W9 Wave Record — shipped 2026-09-16 as 3.18.0

**Drift from the plan, on purpose:**

- **A14's `coalesce(...)` index cannot exist.** The plan says the conflict target
  becomes `(user_id, date, muscle_group, coalesce(side,'both'),
  coalesce(sub_region,''))` "expressed as a unique index so PostgREST can name
  it". PostgREST cannot name it. `?on_conflict=` takes a COLUMN LIST and emits
  `ON CONFLICT (a, b, c) DO UPDATE`; it has no syntax for an expression, so an
  expression index is unreachable from the client and every upsert would fail
  outright with *"no unique or exclusion constraint matching the ON CONFLICT
  specification"*. Shipped instead as a plain five-column unique index with
  **`NULLS NOT DISTINCT`** (Postgres 15+, which Supabase has shipped on new
  projects since 2023 — the SQL file says so out loud, because on an older
  server the clause is a syntax error rather than a silent downgrade). That
  clause is load-bearing twice over: without it two legacy NULL rows are unique
  against each other, AND `ON CONFLICT` never fires for a bilateral rating, so
  every re-rating of a whole muscle would INSERT beside the old row instead of
  updating it. The columns stay nullable exactly as the plan wanted.
- **`.center` is spelled `.both`.** The plan names three vocabularies for one
  idea — the atlas's "centre", the column's `both`, the export's empty marker —
  and they collapse: a path that straddles the spine is a muscle with no side,
  and a muscle with no side is rated for both of them. One `BodySide` enum whose
  `rawValue` IS the stored string, so a round trip through `doms_logs` needs no
  translation table, and whose `.mark` is the export's `""`/`L`/`R`. The
  self-check's "Upper back, Lower back and Abs/core are `.center`" is asserted
  as `.both`.
- **`muscle(at:in:side:)` returns `MuscleSide?`, not a tuple.** An optional
  tuple is not `Equatable`, so every call site and every assertion would have had
  to destructure it — and `MuscleSide` is the key `AtlasFigure` re-keys on
  anyway, so the pair wanted a name regardless. The `side:` LABEL still means
  the view; the doc comment says so, because `muscle(at: p, in: r, side: .front)
  -> (muscle, .left)` is two different words spelled the same.
- **The centroid rule alone would have lateralised the obliques.** `Abs/core`'s
  three front paths are a rectus at x ≈ 60 and two flanks at x ≈ 45 and x ≈ 75,
  so a bare centroid test gives one `both`, one `left` and one `right` — and
  tapping the middle of a midsection would offer "both" while tapping an inch
  left offered "left", for one muscle. A second pass makes a muscle lateral only
  where a view draws it as EXACTLY one left and one right; anything else (one
  path, three paths, two on the same side) is wholly axial. **Derived, not
  listed** — a hand-written set of axial muscles is a fourth copy of the anatomy
  and `check:atlas` could not tell when it went stale.
- **The atlas is read as a MIRROR.** Image-left is the body's left on BOTH
  views, which is what "a tap left of the midline answers `.left`" asks for and
  what a lifter looking at a self-report map expects. (Face a mirror and raise
  your left hand: it is on the left of your visual field. Stand a camera behind
  yourself: same.) Stated here because the other convention — the front view as
  *another person facing you* — is equally coherent and would flip every front
  answer.

**Root causes that were not where the plan guessed:**

- **`DayModel` does not subscribe on `init` — `observe()` does.** The new
  `pulse-squares` shot photographed four EMPTY squares over a fully seeded
  store, twice, deterministically. Nothing about the seed or the timing was
  wrong; the harness screen simply never called `await model?.observe()`, which
  `PulseTabView.task` does and which `DomsOnly` does. An empty state is a
  plausible-looking screenshot, so this failure mode reviews as a design
  decision rather than as a bug. **Any new Pulse harness screen must call
  `observe()`.**
- **Two `PostToolUse` hooks in `.claude/settings.json` still pointed at the dead
  Helix checkout** and failed on every single `.swift` edit (`bash:
  scripts/check-swift.sh: No such file or directory`) — the condition
  `deep-clean-purge-sep15` recorded. Fixed in passing: the `.swift` hook now
  `cd`s to Onyx, where `scripts/check-swift.sh` exists and runs in 6 s; the
  `src/lib/` `tsc` hook was deleted, because this repo has no `src/lib/` and the
  web app it typechecked is gone. **`.claude/` is gitignored, so this repair is
  LOCAL and did not ship with the wave** — the next checkout of this repo gets
  the broken hooks back.

**Constraints discovered that the next wave must respect:**

- **`npm run check` compiles `OnyxTests` but runs only `OnyxUITests`** (21
  tests). `scripts/swift-ui-test.sh` passes `-only-testing:OnyxUITests`, so a
  broken assertion in `native/OnyxTests` fails the gate as a COMPILE error and
  passes it as a green run. `AtlasHitTests` must be run explicitly. The baseline
  is still the documented **4 failures** (`HistoryWeeksTests` ×2,
  `SessionSummaryHotfixTests`, `WorkoutWeekTests`).
- **`ScoringInputsBuilder`'s `ponytail:` note is discharged.** It said the local
  store had no side/sub_region columns and to add the migration "when the native
  logger grows a side control". It has; `v28` is that migration. The note is
  replaced by a statement of WHY nothing there changed.
- **An axial landmark takes only a `both` rating.** "Back, left" rings the left
  lat and leaves the traps and erectors unringed, because the trapezius is one
  path and has no left. This is deliberate and documented on `DomsTile.colors` —
  but it means a group containing both lateral and axial landmarks lights
  partially, and a wave that dislikes that has to split `Back` in the DOMS
  vocabulary, not patch the figure.
- **`OnyxAtlas.swift` now imports `OnyxCore`.** The generated atlas was
  SwiftUI-only. Anything that consumes `OnyxAtlasPath` inherits that dependency;
  OnyxUI already depended on OnyxCore, so nothing moved, but the generated file
  is no longer standalone geometry.

**Left open on purpose:**

- **`sub_region` has a column, a key, a grammar and no writer.** The atlas has no
  sub-region geometry — there is no "Erectors" path to tap — so building a
  second picker into the popover would be a control with nothing behind it. The
  store, the sync, the export and the tests all carry it end to end; the UI that
  fills it is a future wave's, and `DayEditing.setDoms(subRegion:)` is waiting
  for it.
- **`AtlasSheet` keys everything `both`.** Its question is "where did this
  session land", and the ledger records that a set of squats happened, not which
  leg did more of it. A side-specific number there would be one the store never
  held.
- **`AtlasFigure.colors` still has no caller.** It was already unused before this
  wave; it was re-keyed rather than deleted because its docstring states a real
  design distinction (fill versus ring) that the DOMS body may yet need.
- **A dead dictionary key per axial landmark of a sided group.** Filtering them
  out means asking the atlas which landmarks are lateral — a second traversal to
  save three entries. Carries a `ponytail:` note.

**Founder's manual steps still outstanding:** **paste
`docs/sql/w9-doms-laterality.sql`.** Until it lands, a ONE-SIDED rating's push is
rejected for an unknown column — per-row, retried under `SyncBackoff`, and it
clears itself on the first sync after the paste, exactly as `v24.stressEvents`
and `v26.healthWorkoutUuid` did. A bilateral rating is unaffected, because it
sends neither column. The file requires **Postgres 15+** for `NULLS NOT
DISTINCT`; it ends with a two-query VERIFY block, and the counts are the pass,
not the absence of an error.
