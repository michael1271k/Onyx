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
- Paste `docs/sql/w1-hk-uuid.sql` after W1.
- Paste `docs/sql/w9-doms-laterality.sql` after W9.
- Paste `docs/sql/w11-isolation-rls.sql` after W11, then re-run the schema introspection to confirm every table reports RLS enabled.

---

## Wave Records

_Appended by each wave as it merges. W12 harvests these, then deletes this file._
