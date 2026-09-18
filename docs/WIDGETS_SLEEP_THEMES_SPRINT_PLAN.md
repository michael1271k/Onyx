# Widgets · Sleep v2 · Themes · Week · Pulse · Logger · Privacy — Sprint Plan

**Status:** approved 2026-09-18 · step 0 done (this file). W1 next.
**From:** `main` @ 5.0.1 (`3de461a7`).
**Ships as:** eleven sequential waves, 5.1.0 → 6.8.0, plus a close-out wave that retires this file to `docs/Done/`.
**Branches:** `onyx/sprint-widgets-w<N>`, each cut from current `main` and merged `--no-ff`
back into it. No long-lived sprint branch — `main` is the only trunk (`docs/GIT.md`).
**Model:** Fable 5.1 (high effort) for W3, W5, W7; Opus (extra high) for the rest.

---

## Context

The founder asked for eight things at once: a widget refresh that becomes the single source of truth for iOS Home Screen and Apple Watch, a sleep score that stops printing 100 on a night with a three-hour sleep-onset, a hardcoded 3×3 theme grid that tints everything and reacts to Phase and Program, a weekly report relocated and rebuilt with charts, Stress-log and other detail-page compaction, a Pulse tab without side-scrolling, essential micro-interactions on the live logger and post-workout summary, and a multi-tenant privacy audit with migration of every hardcoded personal datum.

Three explorers measured the repo first. Several brief premises were false and reshape the work:

- **Dashboard tiles ARE the Home Screen widget faces already.** `OnyxTile.face` (`native/Packages/OnyxUI/Sources/OnyxUI/Dashboard/OnyxTile.swift:137`) maps every `WidgetId` onto the same OnyxUI view the extension renders; both read `WidgetSnapshotBuilder`. There is nothing to "delete and re-sync". The gap is the WidgetKit *bundle* (7 `kind`s with focus pickers vs 20 ids; `muscle`/`steps` have no family; `deficit`/`consistency` size caps disagree) and the watch, which has **zero WidgetKit** — no complications, no target, every tile `#if os(iOS)`.
- **The sleep score has four inputs** (`Score.swift:88-109`): hours, deep, REM, goal. Bedtime is the min start over ALL samples (`SleepNight.swift:76-78`). No onset timestamp exists anywhere. Awake minutes reach only the stress index. The manual edit edits the window, not onset, and Strategy A re-aggregates the same asleep minutes → same 100. Working as designed; the design is wrong.
- **Nine named presets already exist** (`OnyxTheme.presets`, `OnyxTheme.swift:187-197`). Sliders and pickers are the deletion, not the grid. Phase already tints capsules (`Color.onyx.phase`); Program tints nothing.
- **The weekly report already owns far more than it draws** — `WeeklyExportInput` carries muscle volume, tonnage, DOMS, fatigue, stress, cardio, body comp, per-date targets and micronutrients; `Summary.muscle` is carried and unrendered; `records` is the one uncapped list. `daily_scores.sleep_score` exists, so a weekly sleep average is a fold.
- **The Stress log's fonts are already ≤ `.body`** by an enforced rule. "Massive" is layout. Bloat elsewhere is file length (`SessionDetailView` 2787 lines) and one loose sheet (`CardioLog`, 3× `.display`).
- **Pulse has exactly one horizontal scroller** — `PulseCarousel` (2 pages) — and the square grid is already 2×2. 2×3 = promote two cards, delete the carousel and its three `scrollPosition` mitigations.
- **RLS is live on all 34 tables, `to authenticated`, `auth.uid() = user_id`.** No global table exists; programs are bundle JSON (`plan-templates.json`) seeded into per-user rows. "Programs global, data per-user" is already structurally true. The founder-shaped data that remains is five runtime constants and one JSON.

## Founder decisions (2026-09-18)

| # | Decision |
|---|---|
| D1 | ONE new WidgetKit kind `OnyxTileWidget`, intent enum = `WidgetId`. Seven old kinds stay one release as shells, then die. |
| D2 | Real watchOS WidgetKit target this sprint (`OnyxWatchWidgets`), accessory faces per WidgetId (circular / rectangular / inline / corner). |
| D3 | Extras: Control Center controls (Start session · +250 ml · Log stress), Bedtime widget, live HR on the phone deck (optional-and-last `bpm` on the watch payload). |
| D4 | Three new widgets: **Week Rings** (`weekRings`), **Soreness Map** (`soreness`), **Stress Index** (`stress`). Plus **Bedtime** (`bedtime`). |
| D5 | Sleep v2, five terms, moderate: Duration 40 / Efficiency 20 / Latency 15 (zero at 90 min) / Fragmentation 10 / Regularity 15. Stage +5/+5 stays, capped. Sept 18 reference night lands ≈ 55–60. |
| D6 | Themes: kill sliders + pickers. Keep Ion, Solstice, Meridian, Aurora, Vesper. Remove Basalt, Halcyon, Terracotta, Obsidian. Add Ember, Glacier, Verdigris, Nocturne. |
| D7 | Phase = deterministic mood offset on the chosen theme (Cut chroma −0.10 lift −0.03; Bulk lift +0.03; Deload chroma 0.70). Program = `Color.onyx.day` palette keyed on the program's day set. |
| D8 | Weekly report home = Dashboard (`weekRings` tile is the door) + History; page moves to `Features/Week/`; `WeekReport` moves to OnyxData; Train keeps the Past Weeks shelf. |
| D9 | Pulse 2×3, default order Stress index · Stress log / Soreness · Fatigue / Scale · Stack, **user-reorderable** exactly like the Today tab's edit mode, persisted under `pulseKey` in `dashboard_layouts` (same unparsed-carry pattern as `trainKey`). |
| D10 | Micro-interactions: essentials only (rest actuals, progression cue, PR margin, one FinishSheet spark + IntensityBar, live HR, E1rmTrendChart on summary). Noise rejected: per-set timestamps on ledger, calorie callouts, muscle-vs-target on a session, streaks/confetti. |
| D11 | Privacy: strip the five runtime constants + JSON; wrap `PreviewCatalogue` in `#if DEBUG`; document the one-store-one-user invariant; **no** `programs` table. |

## Cross-wave laws (from the explorers; each cost a prior wave a retry)

1. `Dashboard.version` stays **4.0 forever** (`Layout.swift:236-259`). New per-slot or per-row keys are optional and unparsed by older readers.
2. `WidgetId` declaration order is the catalogue order `reconcile` appends in; `daily` stays last; new ids go before it and the tail golden vectors are updated on purpose. A new id needs `widgetSizes`, `defaultSizePhone`, desktop default, `title`, `domain`, `symbol`, `isNative`, `OnyxTile.face` — `defaultSize` force-unwraps.
3. Tiles are widget faces. New drawing goes in `OnyxUI/Tiles/` (or `OnyxUI/Accessory/` for watch-safe faces), never in `Features/Today/`. Family read as `OnyxSize(tileFamily ?? hostFamily)`.
4. One builder. New snapshot fields are Optional, filled in `WidgetSnapshotBuilder` + tests, scope-gated (`coach` is the `.full`-only precedent).
5. `kind:` strings are permanent. Removing one un-places every instance.
6. Every tile file is `#if os(iOS)`. Watch faces live in unfenced files using `WatchInk` (two ink levels, no glass/mesh).
7. Wire format rule: new `WatchContext`/`RestPulse` fields are **optional-and-last**.
8. Theme-derived tokens are `static var`; `TokenDisciplineTests` fails the build on any hex outside the three token files; `AppearanceCoverageTests` requires every root screen to ground; `mono ? .white` in `.accented` rendering stays.
9. Appearance writes once on exit and refuses during a live workout (root `.id(themeJSON)` rebuild destroys `LoggerModel`).
10. One `.hero` per screen (`OnyxType.swift:46`). Pulse's is the Now strip Score; the weekly report's is the `PhaseBand` numeral.
11. Every sheet on Pulse is presented from `DayScreen`, never from a recyclable cell. `LazyHStack` is banned in a List row (VoiceOver).
12. Missing is `nil`, never zero — scorer (`Score.swift:60-68`) and store (`Sleep.aggregate` returns nil).
13. `manual-sleep-<date>` in `hk_uuid` is the single override mechanism (three consumers).
14. Stress–battery isolation golden vector stays byte-identical. Sleep v2 is a day-score change, not a battery change.
15. Server DDL is paste-SQL by the founder, proved first on a throwaway local PG17 cluster on `127.0.0.1` (W11's bar). Local guarded `ALTER TABLE` ships beside it.
16. `AppEnvironment.userIdString` is `""` in the harness and previews — detached reads fall back to `database.localUserId()`.
17. App Group is Gate 0 (paid Developer Program). On this machine widgets are stale/empty on device by construction. Not code.
18. `OnyxTests` is run by nothing in `npm run check` (baseline 10 failures). Do not claim it green; do not make it worse.

## Waves — eleven, strictly sequential, 5.0.1 → 6.8.0

Every wave: cut from `main`; bump `package.json`; `npm run version:sync && cd native && xcodegen generate`; append `docs/CHANGELOG.md` (name the surfaces); `npm run check` + `check:swift` + `swift:core` + `swift:data` + the runbook `xcodebuild` line; shots with `SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-W<nn>`; merge `--no-ff`. A wave touching `LoggerModel` runs `OnyxTests` by hand and stays ≤ 10 failures. Each wave appends a Wave Record to this file immediately after merging (template at the end).

| Wave | Version | Name |
|---|---|---|
| W1 | 5.1.0 | Privacy seams |
| W2 | 5.2.0 | Theme grid |
| W3 | **6.0.0** | Sleep v2 (MAJOR: history rescored, two columns, paste-SQL) |
| W4 | 6.1.0 | New WidgetIds + snapshot |
| W5 | 6.2.0 | Generic kind + Controls |
| W6 | 6.3.0 | Ten tile redesigns + interactive water |
| W7 | 6.4.0 | Accessory faces, watch snapshot, `OnyxWatchWidgets` |
| W8 | 6.5.0 | Weekly report relocation |
| W9 | 6.6.0 | Pulse 2×3, reorderable |
| W10 | 6.7.0 | Logger micro-interactions |
| W11 | 6.8.0 | Compaction + `SessionDetailView` split |

Hotfix slot: if the `setSleepOnsetTrouble` rescore fix must ship alone, cut it as 5.0.2 PATCH before W1.

---

### W1 — Privacy seams (5.1.0)

**Goal.** Strip founder data from runtime; one behavioural fix. No UI.

**Files.**
- `native/Onyx/Resources/plan-templates.json` — delete every `wk1Kg` and all `phaseGoals`; `native/Onyx/App/PlanTemplates.swift` decodes without them.
- `native/Onyx/App/PreviewCatalogue.swift` — wrap the whole file in `#if DEBUG` (mirror `PreviewHarness.swift:1`).
- `native/Packages/OnyxCore/Sources/OnyxCore/Coach/ScheduleReadiness.swift:26-38` — delete `isReentryWeek` constant and the "Onyx-5 … 150–250 kcal" literal; `apply` takes a `reentry: Bool` from the caller and the program label from the `plans` row. Reader: `schedule_overrides` gains kind `"reentry"` (existing table, no DDL); `TodayFeedBuilder.swift:161` passes it.
- `native/Packages/OnyxCore/Sources/OnyxCore/Sessions/SessionSeed.swift:214-225` — `WarmupCardio.seed(from lastBout: CardioLogRow?)`; the 300 s / 0.37 km / 2 % literals die. `LoggerModel.swift:1078-1092` — delete `catalogueHasWarmupCardio`; opener = user's last `cardio_logs` row exists.
- `native/Onyx/Features/Pulse/PulseModel.swift:1068-1073` — `setSleepOnsetTrouble` calls `AppEnvironment.rescore(from:reason:)` like the window edit at `AppEnvironment.swift:281`.
- `native/README.md` — one paragraph on the one-store-one-user invariant naming the unscoped reads (`AppDatabase.exercises()`, `ExerciseCatalog.exerciseCatalogStream`, `nutrition_days`, `PlanCatalogue.localUserId()`) and why `prepareForUser`/`eraseLocalData` (both off `sqlite_master`) make them safe.

**Non-goals.** No `programs` table. No bundle-id rename. No UI.

**Hazards.** `OnyxTests/LivePrIdentityTests.swift:52`, `LiveStateRestoreTests.swift:148`, `HistoryWeeksTests.swift:115` reference the treadmill gate — update. `PreviewHarness.swift:191` `programLabel: "Onyx-5"` is harness data, stays.

**Verify.** Gates; `swift:data` seed tests; shots `logger`, `train`, `day` unchanged. No goldens change.

---

### W2 — Theme grid (5.2.0)

**Goal.** Nine presets in a 3×3 of live mini-mesh swatches; sliders and pickers deleted; phase mood offset; program day palette; tint gaps closed. Runs before the tile waves so tiles draw on final tokens.

**Files.**
- `native/Packages/OnyxUI/Sources/OnyxUI/DesignSystem/OnyxTheme.swift:187-197` — presets: keep Ion, Solstice, Meridian, Aurora, Vesper; drop Basalt, Halcyon, Terracotta, Obsidian; add Ember, Glacier, Verdigris, Nocturne. Each pair re-solved with `OKLCHConvert.hex(from:)` inside the guard, secondary at h+120°, `normalised()` a fixed point, pairwise primary hue ≥ 35°. Delete `Color.onyxHex`, `OnyxTheme.picked`, `OnyxTheme.swatch`.
- `native/Packages/OnyxCore/Sources/OnyxCore/Design/OnyxThemeSpec.swift` — pure `func reacting(to: PhaseKind?) -> OnyxThemeSpec`: cut chroma −0.10 / lift −0.03; bulk lift +0.03; deload chroma 0.70; result through `normalised()`. `chroma`/`lift` fields stay (decode compat).
- `native/Onyx/App/OnyxApp.swift` — second `@AppStorage(OnyxTheme.phaseKey)` written by `AppEnvironment` when `scheduleContext` resolves; root `.id(themeJSON + phase)`; `OnyxTheme.set(spec.reacting(to:))`. `OnyxProvider.swift:96-100` reads the phase key too. `PhoneWatchBridge.swift:105` sends the REACTED spec (zero watch change).
- `native/Onyx/Features/Settings/AppearanceView.swift` — delete picker and slider sections; `LazyVGrid` three fixed columns; swatch = 2×2 `MeshGradient` from `OnyxTheme(spec:)`'s four domain ramps + name + mood word. Keep the `locked` live-workout path and commit-on-exit.
- `native/Packages/OnyxUI/Sources/OnyxUI/DesignSystem/OnyxTokens.swift` — `:247` water → `OnyxDomain.body.end`; `:603-637` deep/REM → `OnyxDomain.recover.at(…)` stops, awake → `textSecondary`; `:265` add `Color.onyx.day(_:in program:)` spreading `train.at(i/n)` over the program's day set.

**Reuse.** `OnyxTheme(spec:)`, `OnyxDomain.at(_:)`, `Color.onyx.phase(PhaseKind)`, `OKLCHConvert`.

**Non-goals.** No hex outside `OnyxTheme.swift`; no custom theme; `good`/`danger`/`record` untouched.

**Hazards.** `OnyxThemeTests.swift:82,100,136` name "Terracotta" → "Ember"; count stays 9. Theme tokens stay `static var`. `TokenDisciplineTests` — mesh colours only via ramps.

**Verify.** `swift:ui` (OnyxThemeTests, coverage); shots `appearance`, `appearance-locked`, `today`, `day`, `fuel`, `body-trends` at two presets via `SHOT_THEME`.

---

### W3 — Sleep v2 (6.0.0 MAJOR)

**Goal.** Five-term sleep score; onset and awakenings persisted; regularity baseline; third wheel; history rescored.

**OnyxCore.**
- `Scoring/ScoringInputs.swift` — optional-and-last `sleepInBedHours`, `sleepLatencyMin`, `sleepAwakeMin`, `sleepAwakenings`, `sleepBedtimeDeltaMin` (`decodeIfPresent`; memberwise callers untouched).
- `Scoring/Score.swift:88-109` — Duration 40 (existing quadratic shape rescaled) · Efficiency 20 (asleep ÷ in-bed, linear 0.75→1.0) · Latency 15 (`1 − latency/90`) · Fragmentation 10 (`clamp(1 − awakeMin/90) × clamp(1 − awakenings/6)`) · Regularity 15 (`1 − |Δ|/120`). A nil term drops and the rest renormalise (file's own rule). Stage +5/+5 stays, `clamp100`. `penaltyMult` still scales penalties. `Battery.swift`, Recovery term, <6 h cap untouched.

**OnyxData.**
- `Health/SleepNight.swift` — `SleepNight` gains `onset: Date?` (earliest start over values 1/3/4/5), `awakenings: Int` (merged awake intervals ≥ 5 min), `inBedMinutes`; computed in `aggregate` (`clip` inherits).
- `Health/DailyLogIngest.swift:442-488` writes `onset_time`, `awakenings`.
- `Day/DayEditing.swift:502-593` — `editSleepWindow(…, onset: Date? = nil)`; guard `start <= onset < end` (store is the trust boundary); Strategy A takes onset from re-aggregation unless the wheel gave one; Strategy B keeps proportional stages and takes the wheel's onset. `Health/HealthSync.swift:161` threads it.
- `Database/AppDatabase.swift` — migration `v31.sleepOnset`, guarded `ALTER` ×2 exactly like `v30.waistCm` (`:1301`). `native/schema/supabase.json` `sleep_sessions` += `onset_time:timestamptz?`, `awakenings:int4?` → `npm run mirror` regenerates `SleepSessionRow`.
- `Scoring/ScoringInputsBuilder.swift:281-284` fills the five fields. Regularity: new `AppDatabase.bedtimeOffsets(userId:before:limit: 14)` = `start_time − NightWindow.range(...).from` in minutes (noon-anchored, no midnight wrap); median of ≥ 5 nights else nil.
- `docs/sql/w3-sleep-onset.sql` — two `ALTER TABLE … ADD COLUMN IF NOT EXISTS`, proved on a local PG17 cluster on `127.0.0.1` (W11's bar).

**App.** `Features/Pulse/SleepEditSheet.swift` third wheel "Fell asleep" bounded by the other two → `AppEnvironment.editSleepWindow(…, onset:)`. Pulse vitals label "Fell asleep" → "In bed" while `onset_time` is nil. First launch after migration runs the rescore cascade over all `daily_scores` (the user-visible migration; changelog says so).

**Goldens — frozen by rule (`GoldenVector.swift:20-26`): never regenerated from the code under test.** The sleep formula change retires the v1 sleep cases and adds a v2 fixture whose every case is **hand-computed** (spreadsheet in the wave record) with a `note` naming W3, reviewed by `invariant-auditor` before merge: `sleep-score-v2.json` (≥ 12 cases incl. the 2026-09-18 reference night, a nil-latency night, a five-night-baseline edge, each context mode) and the affected `daily-score.json` cases (composite weight 0.25 over a changed sleep term — recompute by hand, not by run). Assert byte-identical: `stress-battery-isolation.json`, `battery*.json`, `recovery-score.json`, `sleep-trim*.json`, `stress-fragmentation.json`.

**Founder by hand.** Paste `docs/sql/w3-sleep-onset.sql` **before** installing the W3 build — the outbox upsert carrying `onset_time` is rejected until the column exists.

**Verify.** `swift:core`; `swift:data` (ingest, edit-window with onset inside/outside, builder); shots `day`, `day-hero`, sleep edit sheet. Reference night 2026-09-18 scores ≈ 55–60 in a builder test.

---

### W4 — New WidgetIds + snapshot (6.1.0)

**Goal.** `weekRings`, `soreness`, `stress`, `bedtime` in the catalogue with faces; Day Rings to three rings on theme ramps.

**Files.**
- `OnyxCore/Dashboard/Layout.swift:43-56` — four cases inserted **before** `daily`; `:137-190` `widgetSizes` (weekRings `[.s,.m]`, soreness `[.s,.m,.l]`, stress `[.s,.m]`, bedtime `[.s]`), `defaultSizePhone` and desktop defaults for every id (force-unwrap).
- `OnyxCore/Widget/Snapshot.swift` — optional fields `weekRings: [WeekRingDay]?` {date, trained, fuelHit, sleepHit}, `soreness: [SorenessRegion]?` {landmark, level}, `stress: StressFace?` {index, series14}, `sleep.medianBedtime: String?`.
- `OnyxData/Widget/WidgetSnapshotBuilder.swift` — `.full` and `.body` fill them; `WidgetSnapshotBuilderTests`.
- `OnyxUI/Dashboard/OnyxTile.swift` — `title`, `domain`, `symbol`, `isNative`, `face` arms. New `OnyxUI/Tiles/OnyxWeekRings.swift`, `OnyxSoreness.swift` (reuse the atlas figure), `OnyxStress.swift` (reuse `Sparkline`), `OnyxBedtime.swift`. `OnyxMega.swift` → three rings on `train/fuel/recover` ramps. `OnyxSnapshot+Sample.swift` sample data.

**Goldens.** `layout-catalogue.json`, `layout-defaults.json` are hand-edited: the four new ids inserted before `daily` in the expected arrays with their default sizes, `note` naming W4; tail still `daily`. Not regenerated. `Dashboard.version` stays 4.0.

**Non-goals.** No WidgetKit kinds; `bar`/`micros`/`stack` still projected out; no redesigns.

**Verify.** `swift:core` layout vectors; `swift:data` builder; shots `today`, `today-edit`, `WidgetPreviews`.

---

### W5 — Generic kind + Controls (6.2.0)

**Design.** `native/OnyxWidgets/OnyxWidgets.swift` — one `OnyxTileWidget`, `kind: "OnyxTile"`, `AppIntentConfiguration(intent: TileConfiguration)`. `OnyxIntents.swift` — `enum TileOption: String, AppEnum` mirroring the native `WidgetId` raw values (extractor refuses imported enums; `bar/micros/stack` omitted), bridged `WidgetId(rawValue:)!`, display names from `title`, gallery = every native id. Scope `.full` for the generic kind (`ponytail:` note: per-id scope map if timelines get slow).

**Family trap.** `supportedFamilies` is static per kind. Resolution: supported = small/medium/large; the face clamps DOWN — if `Dashboard.widgetSizes[id]` lacks the host family, draw the largest supported size below it via `onyxTileFamily`; if none (e.g. `daily` at small) draw `TileNote(caption: id.title, text: "Needs a larger widget")`.

**Old kinds.** Same seven `kind:` strings become shells: body maps focus → `WidgetId`, renders `OnyxTile.face`, description "Moved to the Onyx tile". Deleted next release. `OnyxLockWidget` gains `.bedtime` focus.

**Controls.** `ControlWidget`s: Start session, Log stress (`openAppWhenRun = true` + existing deep-link router); +250 ml via shared `AddWaterIntent` in `native/Shared/` (like `RestSkipIntent.swift`). Extension DB is read-only, so the intent adds 250 to App Group key `onyx.pending.waterMl` and reloads timelines; the app drains the key on `scenePhase == .active` through the existing water edit + rescore; the tile reads the key for the optimistic figure.

**Verify.** `xcodebuild` app + extension; gallery in simulator; shots `WidgetPreviews`; one `OnyxTests` case for the drain if cheap.

---

### W6 — Ten tile redesigns + interactive water (6.3.0)

**Files.** `OnyxUI/Tiles/OnyxLifestyle.swift` (recovery charge arc; fuel macro rails "remaining"; water 8-segment arc + `Button(intent: AddWaterIntent)`), `OnyxVitals.swift` (lead-vital rule: most-deviant z leads, 3 chips), `OnyxTraining.swift` (next session with muscle wash from new optional `today.muscles`; PR trophy + margin from new optional `Record.previous`), `OnyxPerformance.swift` / `OnyxSeries.swift` (volume 16-muscle heat strip from `muscleFocus`; consistency N-of-7 + 4-week dots; deficit diverging bars via `DivergingBar` moved from `PulseStress.swift:274` into OnyxUI; fatigue sparkline with awake shading), sleep hypnogram strip from stage minutes as proportional blocks (builder reads `sleep_sessions` only; sample-level stages are the stated ceiling). Snapshot + builder + tests for each new field.

**Non-goals.** No new WidgetIds; no Pulse changes.

**Verify.** `swift:data`; shots `today`, `today-sheet`, `today-sheet-vitals`, `WidgetPreviews`; `.accented` render check (`mono ? .white` rule).

---

### W7 — Accessory faces, watch snapshot, `OnyxWatchWidgets` (6.4.0)

**Faces.** New `native/Packages/OnyxUI/Sources/OnyxUI/Accessory/` — NOT fenced `#if os(iOS)`; imports `WidgetKit`, `SwiftUI`, `OnyxCore` only; no glass, no mesh, no `OnyxSize(WidgetFamily)`; two-level ink. `OnyxTile.accessory(id:family:tiles:)` switching `.accessoryCircular/.accessoryRectangular/.accessoryInline` and `#if os(watchOS) .accessoryCorner #endif`. iOS `LockView` delegates to it so Lock Screen and watch draw one face.

**Transport.** New `OnyxCore/Widget/WatchTiles.swift` (Codable, ≤ 2 KB: battery, score, sleep min/score, water ml/goal, steps/goal, kcal/goal, today label/logged, stress index, soreness count, weekRings 7 bools, medianBedtime). `WatchContext.tiles: WatchTiles?` optional-and-LAST after `theme` (`WatchPayloads.swift:37-58`). Application context chosen over `transferUserInfo` (one-slot state channel delivered on wake; FIFO would deliver stale snapshots in order; a second context kind would clobber the schedule). `AppEnvironment.pushWatchContext` gains a 30 s trailing throttle and is called from the `onCommit` hook that already fires `reloadAllTimelines`. Watch: `WatchModel.receive(.context)` writes `tiles` JSON to `UserDefaults(suiteName: "group.app.onyx.health.watch") ?? .standard` under `onyx.watch.tiles` and calls `WidgetCenter.shared.reloadAllTimelines()`. `WatchContextCache` (`WatchModel.swift:590-602`) moves to the suite.

**Target.** `native/project.yml`: `OnyxWatchWidgets` (`type: app-extension`, `platform: watchOS`, deps OnyxCore + OnyxUI only — no GRDB in a watch extension), App Group entitlement `group.app.onyx.health.watch`, `NSExtensionPointIdentifier: com.apple.widgetkit-extension`, bundle id `app.onyx.health.michael.native.watchkitapp.widgets`, `SKIP_INSTALL: YES`; `- target: OnyxWatchWidgets` under `OnyxWatch.dependencies`; both schemes. Files: `OnyxWatchWidgets/OnyxWatchWidgets.swift` (`@main WidgetBundle`, one `StaticConfiguration` per wearable WidgetId, families circular/rectangular/inline/corner), `Support/Info.plist`, `.entitlements`.

**Founder by hand.** Xcode → `OnyxWatch` and `OnyxWatchWidgets` → App Groups capability (paid program). Without it the watch widget is empty on device — Gate 0, same as the phone.

**Verify.** `check:swift` (OnyxUI builds `Accessory/` on watchOS); `swift:data` `WatchContext` round-trip with and without `tiles` (old-JSON decode); `xcodebuild -scheme OnyxWatch`; watch simulator complication gallery.

---

### W8 — Weekly report relocation (6.5.0)

**Files.**
- Move `WeekReport` + `build` (`WeeklyReportView.swift:474-666`) → `native/Packages/OnyxData/Sources/OnyxData/History/WeekReport.swift`, `public`, still a pure fold over `WeeklyExportBuilder.input(weekStart:today:)`. Add `sleepScoreAvg` (mean `daily_scores.sleep_score`), `batteryAvg`, `nutritionAdherencePct`, `kcalByDay` + target rule, `macroTable` (mean vs target), `flaggedMicros` (move `WeeklyExport.weeklyNutrients/flaggedNutrients` beside it), `volumeByMuscle` vs `plan_phase_volume`, `sleepByDay`, `batterySpark`, `stressMean`, `domsPeak`, `cardio`, `records` capped at 3 + `hasMore`.
- New `native/Onyx/Features/Week/WeekReportView.swift` + `WeekSections.swift`: `PhaseBand` hero → banner capsules Sleep · Battery · Adherence (verdict-coloured) → three `OnyxStatCell(spark:)` → Body → Training (`MuscleTagRow` from `SessionHeaderCard.swift:301` + heat strip) → Nutrition (`BarChart` + macro table + flagged micros) → Recovery (`BarChart` + `Sparkline`) → Cardio → Records (3 + `DisclosureGroup`, `topThree` precedent) → Share. All charts through `onyxChart(_:)`.
- Doors: `TodayTabView:208` becomes the `weekRings` tile tap (push `WeekReportDoor`); `WeekDaysView:165`, `PastWeeksLibrary:121`, `WorkoutTabView:324` stay. Delete `Features/Workout/WeeklyReportView.swift`. Repoint `HistoryPreviews.swift:315-338` and harness `train-wrap*`, `history-week-wrapped`.

**Hazards.** New root applies `.onyxScreen` (`AppearanceCoverageTests`). `userIdString` is "" in harness → fall back to `database.localUserId()`. `swift:data` test for `WeekReport.build` (previously untestable in the app target).

**Verify.** Shots `train-wrap`, `train-wrap-large`, `history-week-wrapped`, `today` (tile door).

---

### W9 — Pulse 2×3, user-reorderable (6.6.0)

**Reorder reuse.** Extract `Arrangeable` (`DashboardGrid.swift:331-357`) to `OnyxUI/Dashboard/Arrangeable.swift` as `public`; `TileMenu` stays private (stack-specific). Pulse edit = toolbar "Edit" toggling `model.editingSquares`; squares wear `Arrangeable` and the existing jiggle (`OnyxMotion`).

**Layout.** `OnyxCore/Dashboard/PulseLayout.swift` mirroring `TrainLayout.swift:78-125`: `enum PulseSquare: String, CaseIterable { stress, stressLog, soreness, fatigue, scale, stack }`, `struct PulseLayout { order; updatedAt }` with `reconcile` (missing appended in declaration order, unknown dropped), `Dashboard.pulseKey = "pulse"`, `pulseLayout(from:)`, `withPulse(_:in:)`; `serializeLayout` (`Layout.swift:404`) carries `pulseKey` unparsed in one more line. JSON: `{"v":4,"phone":{…},"train":{…},"pulse":{"order":[…],"updatedAt":0}}`. `DashboardLayoutStore.swift` gains `pulseLayout(userId:)` / `savePulseLayout`. `layout-serialize.json` gains one case, deliberately.

**UI.** Delete `PulseCarousel.swift`; `FatigueCard` (`:314`) → `FatigueSquare`, `StressLogCard` → `StressLogSquare` in `PulseSquares.swift`; `LazyVGrid` 2 × 3 in stored order; AX fallback rows same order. Every sheet stays on `DayScreen`. Hero stays the Now strip Score.

**Verify.** `swift:core` (`PulseLayout` tests + serialize vector); `swift:data` store round-trip; shots `day`, `day-rows`, `day-stress`, `day-soreness`, plus an edit-mode shot.

---

### W10 — Logger micro-interactions (6.7.0)

**Files.** `Features/History/SessionDetailView.swift` `SetRow:1818` shows `actualRestSec` with delta vs previous (already on `HistorySetRow`); `Features/Logger/ExerciseCardView.swift:598` live rest bar (actual vs planned); progression cue chip on the exercise card from `LoggerModel.progressionAlerts:1729`; PR margin inline 2 s beside the trophy (`ExerciseReport.records`); `FinishSheet.swift` one `Sparkline` (tonnage vs previous same-split) + `IntensityBar` (move from `SessionDetailView.swift:1637` to OnyxUI `Charts/`); `RestPulse.bpm: Int?` optional-and-LAST (`WatchPayloads.swift`), filled from `WorkoutSessionController.heartRate` in `WatchModel`, drawn in `LoggerHero`/`LiveStatsView`; `E1rmTrendChart` presented from the summary's per-movement spark tap (second caller after `ExerciseDetailView:159`).

**Verify.** `swift:data` (`RestPulse` old/new decode); `OnyxTests` by hand ≤ 10; shots `logger*`, `logger-finish`, `day-session`.

---

### W11 — Compaction + `SessionDetailView` split (6.8.0)

**Files.** `Features/Exercises/ExerciseDetailView.swift:445` `FlowRow` → `OnyxUI/DesignSystem/FlowRow.swift` public; `PulseStressLog.swift:265` `StressLogSheet` single screen `.presentationDetents([.medium])` (five level capsules one row, `DatePicker(.compact)`, `FlowRow` tag chips, one-line note), `:511` list rows 44 pt; `Workout/CardioLog.swift` one `.display` (was three); `Nutrition/NutritionTabView.swift:161` drop the nested `ScrollView`; `PulseStress.swift:121` `.clock` → `.display`; `SessionDetailView.swift` (2787 lines) → `SessionDetail/` folder: `SessionDetailView.swift`, `SessionLedger.swift` (`LedgerHeader`, `SetRow`), `SessionCharts.swift` (`SplitVolumeChart`) — file moves only, zero behaviour change.

**Verify.** Shots `day-stress`, `cardio`, `fuel`, `day-session`, stress sheet; `OnyxTests` unchanged.

---

## Order rationale

- W1 first: no UI, smallest blast radius, and the rescore fix is a real defect.
- W2 before W4/W6: tiles must draw on final ramps or every tile shot is taken twice.
- W3 before W4: `bedtime`/median and the sleep score Week Rings reads exist first; the one MAJOR lands early so the founder's paste-SQL happens once.
- W4 (ids) before W5 (kind): the AppEnum must enumerate the final native id set.
- W5 before W6: `AddWaterIntent` exists before the tile button uses it.
- W7 after W6: accessory faces read the final snapshot fields.
- W8 after W4: the `weekRings` tile is the door.
- W9 after W8, before W11: `PulseStressLog.swift` edits stay sequential.
- W10/W11 last: lowest coupling; the file split closes the sprint residue-free.

## Five things most likely to blow a wave

1. **Catalogue order and force-unwraps (W4).** A `WidgetId` after `daily`, or missing in any of the eight tables, crashes `defaultSize` or shifts the vectors' tail. `Dashboard.version` stays 4.0.
2. **Sleep v2 collateral (W3).** `Battery`, Recovery and the <6 h cap all read `sleepHours`; the isolation vector must stay byte-identical; the server rejects the outbox upsert until the DDL is pasted; an onset outside `[start, end)` from the wheel poisons the sentinel row unless the store guards it.
3. **Theme tests (W2).** "Terracotta" ×3 in `OnyxThemeTests`; four draft hexes re-solved inside the guard with ≥ 35° separation; any literal outside the three token files fails `TokenDisciplineTests`; the new Week root fails `AppearanceCoverageTests` without a ground.
4. **Wire and platform fences (W7/W10).** `WatchContext.tiles` and `RestPulse.bpm` optional-and-last; `Accessory/` never touches `OnyxSize(WidgetFamily)` or a system family; `.accessoryCorner` is watchOS-only; App Group is Gate 0 on both devices.
5. **Generic kind traps (W5).** `TileOption` must mirror every native `WidgetId` or the force-unwrap crashes on first render; one kind cannot vary families per intent (clamp-down + `TileNote`); a deleted `kind:` un-places widgets — shells this release, deletion next.

## Founder to-do (cannot be done from this machine)

| When | What |
|---|---|
| Before installing W3 | Paste `docs/sql/w3-sleep-onset.sql` in the Supabase SQL editor as `postgres`. |
| W7 | Xcode → `OnyxWatch` + `OnyxWatchWidgets` → App Groups capability (`group.app.onyx.health.watch`). Paid program. |
| Any time | App Group for phone + `OnyxWidgets` (Gate 0). Until then Home Screen and watch widgets are stale/empty on device by construction. |

## Sprint-level verification

- Every wave: `npm run check` green from source (includes `version:check`), `check:swift`, `swift:core`, `swift:data`, the runbook `xcodebuild` for app + `OnyxWidgets` + `OnyxWatch` (+ `OnyxWatchWidgets` from W7).
- Golden fixtures are never regenerated (`GoldenVector.swift:20-26`). A wave that changes a formula hand-computes new cases with a `note`, runs `invariant-auditor` on the diff, and names the fixture in its changelog entry; every other vector byte-identical.
- Shot loop per wave with `SHOT_DERIVED` set; screenshots untracked (gitignored since 3.8.0).
- After every merge: `graphify update .`.
- Close-out wave (as W12 last sprint): retire this plan to `docs/Done/`, delete applied `docs/sql/*.sql`, purge derived data, re-run the gate cold.

---

## The wave prompts

Copy one, verbatim, per wave. **Do not start a wave until the previous one is merged and `main` is green.** `/ship` and `/schema` are user-invoked — type them yourself when a prompt says so.

Every prompt begins the same way, so it is stated once:

> Read `docs/WIDGETS_SLEEP_THEMES_SPRINT_PLAN.md` in full — Context, Founder decisions, all eighteen Cross-wave laws, your wave's section, and every Wave Record already appended. Read `.claude/skills/native/SKILL.md`. Cut `onyx/sprint-widgets-w<N>` from current `main`. Ship on that branch: version bump in `package.json`, `npm run version:sync && cd native && xcodegen generate`, changelog entry naming the surfaces, all gates, shots with `SHOT_DERIVED` set, merge `--no-ff`, `graphify update .`, append your Wave Record here. Never regenerate a golden fixture; hand-compute new cases with a `note` and run `invariant-auditor` on any formula diff.

---

**W1 — Privacy seams · 5.1.0**
```
Model: Opus (Extra High Effort)

GOAL — no founder-shaped constant reaches a second user; one real defect fixed. No UI.

TASKS
1. plan-templates.json: delete every wk1Kg and all phaseGoals; PlanTemplates.swift decodes without them.
2. PreviewCatalogue.swift: wrap the whole file in #if DEBUG (mirror PreviewHarness.swift:1).
3. ScheduleReadiness.swift:26-38: delete isReentryWeek and the "Onyx-5 … 150–250 kcal" literal.
   apply takes reentry: Bool from the caller (schedule_overrides kind "reentry", existing table)
   and the program label from the plans row. TodayFeedBuilder.swift:161 passes both.
4. SessionSeed.swift:214-225: WarmupCardio.seed(from lastBout:) — the 300 s / 0.37 km / 2 %
   literals die. LoggerModel.swift:1078-1092: delete catalogueHasWarmupCardio; opener = the
   user's last cardio_logs row exists.
5. PulseModel.swift:1068: setSleepOnsetTrouble calls AppEnvironment.rescore(from:reason:) like
   the window edit at AppEnvironment.swift:281.
6. native/README.md: one paragraph on the one-store-one-user invariant naming the unscoped
   reads (AppDatabase.exercises(), exerciseCatalogStream, nutrition_days, localUserId()) and why
   prepareForUser/eraseLocalData (both off sqlite_master) make them safe.

NON-GOALS — no programs table, no bundle-id rename, no UI.
HAZARDS — three OnyxTests reference the treadmill gate (LivePrIdentityTests:52,
LiveStateRestoreTests:148, HistoryWeeksTests:115): update, stay ≤ 10 failures.
PreviewHarness.swift:191 programLabel "Onyx-5" is harness data — stays.
VERIFY — gates; swift:data seed tests; shots logger, train, day unchanged; no golden changes.
```

---

**W2 — Theme grid · 5.2.0**
```
Model: Opus (Extra High Effort)

GOAL — nine presets in a 3×3 of live mini-mesh swatches; sliders and pickers deleted; phase
mood offset; program day palette; water and sleep-stage tint gaps closed.

TASKS
1. OnyxTheme.swift:187-197 presets: keep Ion, Solstice, Meridian, Aurora, Vesper; drop Basalt,
   Halcyon, Terracotta, Obsidian; add Ember (#E8734A/#4FB6A8 .9/−.02), Glacier
   (#5FB3E8/#C9A2F0 .8/+.04), Verdigris (#3FBF9A/#E39A5C .85/0), Nocturne
   (#8A7CF0/#E56A8C .7/−.05). Those hexes are DRAFTS: re-solve every pair with
   OKLCHConvert.hex(from:) inside the guard, secondary at h+120°, normalised() a fixed
   point, pairwise primary hue ≥ 35°. Delete Color.onyxHex, OnyxTheme.picked, OnyxTheme.swatch.
2. OnyxThemeSpec.swift: pure reacting(to: PhaseKind?) — cut chroma −0.10 lift −0.03; bulk
   lift +0.03; deload chroma 0.70 — through normalised(). chroma/lift fields stay (decode).
3. OnyxApp.swift: @AppStorage(OnyxTheme.phaseKey) written by AppEnvironment when
   scheduleContext resolves; root .id(themeJSON + phase); OnyxTheme.set(spec.reacting(to:)).
   OnyxProvider.swift:96-100 reads the phase key. PhoneWatchBridge.swift:105 sends the
   REACTED spec — zero watch change.
4. AppearanceView.swift: delete picker + slider sections; LazyVGrid three fixed columns;
   swatch = 2×2 MeshGradient from OnyxTheme(spec:)'s four domain ramps + name + mood word.
   Keep the locked live-workout path and commit-on-exit.
5. OnyxTokens.swift: :247 water → OnyxDomain.body.end; :603-637 deep/REM → recover ramp
   stops, awake → textSecondary; :265 add Color.onyx.day(_:in program:) spreading
   train.at(i/n) over the program's day set.

NON-GOALS — no hex outside OnyxTheme.swift; no custom theme; good/danger/record untouched.
HAZARDS — OnyxThemeTests names Terracotta ×3 → Ember; count stays 9; tokens stay static var;
TokenDisciplineTests (mesh colours only via ramps).
VERIFY — swift:ui; shots appearance, appearance-locked, today, day, fuel, body-trends at two
presets via SHOT_THEME.
```

---

**W3 — Sleep v2 · 6.0.0 (MAJOR)**
```
Model: Fable 5.1 (High Effort)

GOAL — a night with a three-hour sleep-onset stops scoring 100. Five terms, two columns,
regularity baseline, third wheel, history rescored.

TASKS
1. OnyxCore ScoringInputs: optional-and-last sleepInBedHours, sleepLatencyMin, sleepAwakeMin,
   sleepAwakenings, sleepBedtimeDeltaMin (decodeIfPresent).
2. Score.swift:88-109 → Duration 40 (quadratic shape rescaled) · Efficiency 20 (asleep ÷
   in-bed, linear 0.75→1.0) · Latency 15 (1 − latency/90) · Fragmentation 10
   (clamp(1 − awakeMin/90) × clamp(1 − awakenings/6)) · Regularity 15 (1 − |Δ|/120). A nil
   term drops and the rest renormalise. Stage +5/+5 stays, clamp100. penaltyMult still scales.
   Battery, the Recovery term and the <6 h composite cap are NOT touched.
3. OnyxData SleepNight.swift: onset (earliest start over values 1/3/4/5), awakenings (merged
   awake intervals ≥ 5 min), inBedMinutes — computed in aggregate; clip inherits.
   DailyLogIngest.writeSleep writes onset_time, awakenings.
4. DayEditing.editSleepWindow(…, onset: Date? = nil): guard start <= onset < end in the
   STORE; Strategy A takes onset from re-aggregation unless the wheel gave one; Strategy B
   keeps proportional stages and takes the wheel's onset. HealthSync threads it.
5. Migration v31.sleepOnset: guarded ALTER ×2 exactly like v30.waistCm (AppDatabase.swift:1301).
   native/schema/supabase.json sleep_sessions += onset_time:timestamptz?, awakenings:int4?
   → npm run mirror. docs/sql/w3-sleep-onset.sql = two ADD COLUMN IF NOT EXISTS, proved on
   a throwaway local PG17 cluster on 127.0.0.1 (W11's bar; scripts in that wave's scratchpad
   pattern: gen, fixture, probe, run).
6. ScoringInputsBuilder.swift:281-284 fills the five fields. Regularity:
   AppDatabase.bedtimeOffsets(userId:before:limit: 14) = start_time − NightWindow.range(...).from
   in minutes (noon-anchored); median of ≥ 5 nights else nil.
7. SleepEditSheet: third wheel "Fell asleep" bounded by the other two. Pulse vitals label
   "Fell asleep" → "In bed" while onset_time is nil. First launch after migration runs the
   rescore cascade over all daily_scores — say so in the changelog; this is the MAJOR.
8. Goldens: retire the v1 sleep cases; add sleep-score-v2.json with ≥ 12 HAND-COMPUTED cases
   (the 2026-09-18 reference night bed 00:16 / asleep 03:05 / wake ~10:30 / usual 23:30
   lands ≈ 55–60; a nil-latency night; a five-night-baseline edge; each context mode) and
   the affected daily-score.json cases, each with a note naming W3. Run invariant-auditor.
   Assert byte-identical: stress-battery-isolation, battery*, recovery-score, sleep-trim*,
   stress-fragmentation.

FOUNDER — paste docs/sql/w3-sleep-onset.sql BEFORE installing this build (the outbox upsert
carrying onset_time is rejected until the column exists). /schema after.
VERIFY — swift:core, swift:data (ingest, edit-window onset inside/outside, builder), shots
day, day-hero, sleep edit sheet.
```

---

**W4 — New WidgetIds + snapshot · 6.1.0**
```
Model: Opus (Extra High Effort)

GOAL — weekRings, soreness, stress, bedtime join the catalogue with faces; Day Rings become
three rings on theme ramps.

TASKS
1. Layout.swift:43-56 — four cases inserted BEFORE daily (daily stays last). widgetSizes
   (weekRings [.s,.m], soreness [.s,.m,.l], stress [.s,.m], bedtime [.s]), defaultSizePhone
   and desktop default for EVERY new id — defaultSize force-unwraps.
2. Snapshot.swift — optional weekRings: [WeekRingDay]? {date, trained, fuelHit, sleepHit},
   soreness: [SorenessRegion]? {landmark, level}, stress: StressFace? {index, series14},
   sleep.medianBedtime: String?. WidgetSnapshotBuilder fills them at .full and .body; tests.
3. OnyxTile.swift — title, domain, symbol, isNative, face arms. New OnyxUI/Tiles/
   OnyxWeekRings.swift, OnyxSoreness.swift (atlas figure), OnyxStress.swift (Sparkline),
   OnyxBedtime.swift. OnyxMega.swift → three rings on train/fuel/recover ramps.
   OnyxSnapshot+Sample.swift sample data.
4. Goldens layout-catalogue.json, layout-defaults.json: HAND-EDIT the expected arrays
   (four ids before daily, default sizes), note naming W4. Dashboard.version stays 4.0.

NON-GOALS — no WidgetKit kinds; bar/micros/stack still projected out; no redesigns.
VERIFY — swift:core layout vectors; swift:data builder; shots today, today-edit, WidgetPreviews.
```

---

**W5 — Generic kind + Controls · 6.2.0**
```
Model: Fable 5.1 (High Effort)

GOAL — one WidgetKit kind draws every dashboard tile; Control Center gets three buttons.

TASKS
1. OnyxWidgets.swift — OnyxTileWidget, kind "OnyxTile", AppIntentConfiguration(TileConfiguration).
   OnyxIntents.swift — enum TileOption: String, AppEnum mirroring EVERY native WidgetId raw
   value (bar/micros/stack omitted), bridged WidgetId(rawValue:)!, display names from title,
   gallery = every native id. Scope .full with a ponytail: note (per-id scope map if slow).
2. Family trap — supportedFamilies is static per kind: small/medium/large. The face clamps
   DOWN: if Dashboard.widgetSizes[id] lacks the host family draw the largest supported size
   below it via onyxTileFamily; if none (daily at small) draw TileNote "Needs a larger widget".
3. The seven old kind: strings stay as shells — body maps focus → WidgetId, renders
   OnyxTile.face, description "Moved to the Onyx tile". Deleted next release, not now.
   OnyxLockWidget gains .bedtime focus.
4. Controls — ControlWidgets: Start session, Log stress (openAppWhenRun + the existing
   deep-link router; deep-link.json golden documents the scheme); +250 ml via
   AddWaterIntent in native/Shared/ (like RestSkipIntent.swift). The extension DB is
   read-only, so the intent adds 250 to App Group key onyx.pending.waterMl and reloads
   timelines; the app drains the key on scenePhase == .active through the existing water
   edit + rescore; the water tile reads the key for the optimistic figure.

VERIFY — xcodebuild app + extension; gallery in simulator; shots WidgetPreviews; one
OnyxTests case for the drain if cheap.
```

---

**W6 — Ten tile redesigns + interactive water · 6.3.0**
```
Model: Opus (Extra High Effort)

GOAL — every existing face redrawn to one figure, motion from the current value, materials
for hierarchy. Snapshot + builder + tests for each new field.

TASKS (OnyxUI/Tiles)
1. OnyxLifestyle: recovery = hero numeral + charge arc filling from bedtime, state word only;
   fuel = three macro rails, "remaining" framing, small = kcal remaining; water = 8-segment
   arc (goal/250) + Button(intent: AddWaterIntent).
2. OnyxVitals: lead-vital rule (most-deviant z leads) + three chips.
3. OnyxTraining: next session with the Pulse muscleWash gradient (new optional today.muscles)
   + start deep-link; PR = one trophy face, latest record + margin (new optional
   Record.previous); medium = three stacked.
4. OnyxPerformance / OnyxSeries: volume = 16-muscle heat strip ordered by target %;
   consistency = "N of 7 planned" + 4-week dot grid; deficit = 7-day diverging bars around
   zero (move DivergingBar from PulseStress.swift:274 into OnyxUI); fatigue = battery
   sparkline with awake-hours shading.
5. Sleep = one hypnogram strip (deep/core/REM/awake) from stage MINUTES as proportional
   blocks — the builder reads sleep_sessions only; sample-level stages are the stated ceiling.
   Medium adds the 7-night BarChart (OnyxLifestyle.swift:702 already draws it).

NON-GOALS — no new WidgetIds; no Pulse changes.
VERIFY — swift:data; shots today, today-sheet, today-sheet-vitals, WidgetPreviews; the
.accented render check (mono ? .white stays).
```

---

**W7 — Accessory faces, watch snapshot, OnyxWatchWidgets · 6.4.0**
```
Model: Fable 5.1 (High Effort)

GOAL — the watch gets real WidgetKit: circular, rectangular, inline and corner faces drawn
from the same WidgetId and the same snapshot fields as the phone.

TASKS
1. Faces — new OnyxUI/Accessory/, NOT fenced #if os(iOS); imports WidgetKit, SwiftUI,
   OnyxCore only; no glass, no mesh, no OnyxSize(WidgetFamily); two-level ink.
   OnyxTile.accessory(id:family:tiles:) switching accessoryCircular/Rectangular/Inline and
   #if os(watchOS) accessoryCorner. iOS LockView delegates to it — one face, both devices.
2. Transport — OnyxCore/Widget/WatchTiles.swift, Codable, ≤ 2 KB (battery, score, sleep
   min/score, water ml/goal, steps/goal, kcal/goal, today label/logged, stress index,
   soreness count, weekRings 7 bools, medianBedtime). WatchContext.tiles: WatchTiles?
   optional-and-LAST after theme. Application context, not transferUserInfo (one-slot state
   delivered on wake; a FIFO delivers stale snapshots in order; a second context kind would
   clobber the schedule). pushWatchContext gains a 30 s trailing throttle and is called from
   the onCommit hook that already fires reloadAllTimelines. Watch: WatchModel.receive(.context)
   writes tiles JSON to UserDefaults(suiteName: "group.app.onyx.health.watch") ?? .standard
   under onyx.watch.tiles and calls WidgetCenter.shared.reloadAllTimelines(). WatchContextCache
   moves to the suite.
3. Target — project.yml OnyxWatchWidgets: type app-extension, platform watchOS, deps OnyxCore +
   OnyxUI only (no GRDB in a watch extension), App Group entitlement, NSExtensionPointIdentifier
   com.apple.widgetkit-extension, bundle id app.onyx.health.michael.native.watchkitapp.widgets,
   SKIP_INSTALL YES; - target: OnyxWatchWidgets under OnyxWatch.dependencies; both schemes.
   OnyxWatchWidgets/OnyxWatchWidgets.swift (@main WidgetBundle, one StaticConfiguration per
   wearable WidgetId), Support/Info.plist, .entitlements.

FOUNDER — Xcode → OnyxWatch + OnyxWatchWidgets → App Groups capability (paid program).
Without it the watch widget is empty on device: Gate 0, same as the phone.
VERIFY — check:swift (OnyxUI builds Accessory/ on watchOS); swift:data WatchContext
round-trip with and without tiles (old-JSON decode); xcodebuild -scheme OnyxWatch; watch
simulator complication gallery.
```

---

**W8 — Weekly report relocation · 6.5.0**
```
Model: Opus (Extra High Effort)

GOAL — the week lives on the Dashboard and in History, in a neutral module, with one chart
per section and a capped records list.

TASKS
1. Move WeekReport + build (WeeklyReportView.swift:474-666) → OnyxData/History/WeekReport.swift,
   public, still a pure fold over WeeklyExportBuilder.input(weekStart:today:). Add
   sleepScoreAvg (mean daily_scores.sleep_score), batteryAvg, nutritionAdherencePct, kcalByDay
   + target rule, macroTable (mean vs target), flaggedMicros (move
   WeeklyExport.weeklyNutrients/flaggedNutrients beside it), volumeByMuscle vs
   plan_phase_volume, sleepByDay, batterySpark, stressMean, domsPeak, cardio, records capped
   at 3 + hasMore. swift:data test for build (previously untestable).
2. New Features/Week/WeekReportView.swift + WeekSections.swift: PhaseBand hero (the screen's
   one .clock) → banner capsules Sleep · Battery · Adherence (verdict-coloured) → three
   OnyxStatCell(spark:) → Body → Training (MuscleTagRow from SessionHeaderCard.swift:301 +
   heat strip) → Nutrition (BarChart + macro table + flagged micros) → Recovery (BarChart +
   Sparkline) → Cardio → Records (3 + DisclosureGroup, topThree precedent) → Share. Every
   chart through onyxChart(_:). Root applies .onyxScreen.
3. Doors: TodayTabView:208 becomes the weekRings tile tap (push WeekReportDoor);
   WeekDaysView:165, PastWeeksLibrary:121, WorkoutTabView:324 stay. Delete
   Features/Workout/WeeklyReportView.swift. Repoint HistoryPreviews.swift:315-338 and the
   harness screens train-wrap*, history-week-wrapped.

HAZARDS — userIdString is "" in the harness: detached reads fall back to database.localUserId().
VERIFY — shots train-wrap, train-wrap-large, history-week-wrapped, today (tile door).
```

---

**W9 — Pulse 2×3, reorderable · 6.6.0**
```
Model: Opus (Extra High Effort)

GOAL — no side-scrolling on Pulse; six squares the user can rearrange like the Today tab.

TASKS
1. Extract Arrangeable (DashboardGrid.swift:331-357) to OnyxUI/Dashboard/Arrangeable.swift,
   public. TileMenu stays private. Pulse edit = toolbar "Edit" toggling model.editingSquares;
   squares wear Arrangeable and the existing jiggle (OnyxMotion).
2. OnyxCore/Dashboard/PulseLayout.swift mirroring TrainLayout.swift:78-125: enum PulseSquare
   { stress, stressLog, soreness, fatigue, scale, stack }, struct PulseLayout { order;
   updatedAt } with reconcile (missing appended in declaration order, unknown dropped),
   Dashboard.pulseKey = "pulse", pulseLayout(from:), withPulse(_:in:); serializeLayout
   (Layout.swift:404) carries pulseKey unparsed in one more line. DashboardLayoutStore gains
   pulseLayout(userId:) / savePulseLayout. layout-serialize.json gains one hand-written case.
3. Delete PulseCarousel.swift. FatigueCard (:314) → FatigueSquare, StressLogCard →
   StressLogSquare in PulseSquares.swift. LazyVGrid 2×3 in stored order, default Stress index
   | Stress log · Soreness | Fatigue · Scale | Stack. AX fallback rows same order. Every sheet
   stays on DayScreen. Hero stays the Now strip Score.

VERIFY — swift:core (PulseLayout tests + serialize vector); swift:data store round-trip;
shots day, day-rows, day-stress, day-soreness, plus an edit-mode shot.
```

---

**W10 — Logger micro-interactions · 6.7.0**
```
Model: Opus (Extra High Effort)

GOAL — the data the logger already holds and never draws, drawn. Essentials only.

TASKS
1. Ledger SetRow (SessionDetailView.swift:1818): actualRestSec with delta vs previous
   (already on HistorySetRow). ExerciseCardView.swift:598: live rest bar, actual vs planned.
2. Progression cue chip on the exercise card from LoggerModel.progressionAlerts:1729
   (staged dead code today).
3. PR margin inline for 2 s beside the trophy from ExerciseReport.records.
4. FinishSheet: one Sparkline (tonnage vs previous same-split) + IntensityBar (move from
   SessionDetailView.swift:1637 to OnyxUI Charts/).
5. RestPulse.bpm: Int? optional-and-LAST (WatchPayloads.swift), filled from
   WorkoutSessionController.heartRate in WatchModel, drawn in LoggerHero / LiveStatsView.
6. E1rmTrendChart presented from the summary's per-movement spark tap.

NOISE, REJECTED — per-set timestamps on the ledger, calorie callouts, muscle-vs-target on a
session, streaks, confetti.
VERIFY — swift:data (RestPulse old/new decode); OnyxTests by hand ≤ 10; shots logger*,
logger-finish, day-session.
```

---

**W11 — Compaction + SessionDetailView split · 6.8.0**
```
Model: Opus (Extra High Effort)

GOAL — the Stress log writes in one screen; the three loose sheets tighten; the 2787-line
file becomes three. Zero behaviour change on the split.

TASKS
1. ExerciseDetailView.swift:445 FlowRow → OnyxUI/DesignSystem/FlowRow.swift, public.
2. PulseStressLog.swift:265 StressLogSheet single screen, .presentationDetents([.medium]):
   five level capsules one row, DatePicker(.compact), FlowRow tag chips, one-line note.
   :511 list rows 44 pt.
3. CardioLog.swift: one .display (was three). NutritionTabView.swift:161: drop the nested
   ScrollView. PulseStress.swift:121: .clock → .display.
4. SessionDetailView.swift → SessionDetail/ folder: SessionDetailView.swift,
   SessionLedger.swift (LedgerHeader, SetRow), SessionCharts.swift (SplitVolumeChart).
   git mv + cut only.

VERIFY — shots day-stress, cardio, fuel, day-session, stress sheet; OnyxTests unchanged.
```

---

**W12 — Close-out**
```
Model: Opus (Extra High Effort)

Retire this plan to docs/Done/, harvesting every Wave Record into the changelog and a memory
file first. Delete applied docs/sql/*.sql (confirm each with the founder). Delete the seven
shell widget kinds ONLY if the founder says the release carrying W5 has been on device for one
cycle; otherwise record it as the first item of the next sprint. Purge derived data, re-run
the whole gate from a cold cache, PATCH bump, graphify update.
```

---

## Wave Record template

Appended to this file by each wave, immediately after merging. W12 harvests every one into the changelog and a memory file before retiring the file.

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

Per wave, in this order — read the counts; "no output" is not a pass:

```bash
npm run check          # version:check + types + atlas + mirror + doms + swift:ui
npm run check:swift    # OnyxCore + OnyxUI cross-build (watchOS too from W7)
npm run swift:core     # golden vectors + invariants   — NOT part of `npm run check`
npm run swift:data     # store, sync, migrations       — NOT part of `npm run check`
cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
# from W7 also:
xcodebuild -project Onyx.xcodeproj -scheme OnyxWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

Layout needs eyes, not a green build:
```bash
SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w<N> scripts/native-shot.sh <screen>
```

Whole-sprint acceptance, on a device:
1. A night in bed 00:16, asleep 03:05, awake 10:30 scores in the fifties, and moving the "Fell asleep" wheel moves the score.
2. Every dashboard tile can be placed on the Home Screen from one "Onyx" gallery entry, and the same tile appears as a complication on the watch face.
3. Picking a theme in the 3×3 recolours macros, sleep stages, muscle tags, tab tint, cardio and every widget on the next refresh; entering a cut week visibly cools the palette without a relaunch.
4. The week opens from the Dashboard's Week Rings tile and reads as cards with charts; the records list is three rows and a disclosure.
5. Pulse has no horizontal scroll; the six squares can be dragged into a new order that survives relaunch and sync.
6. The Stress log writes in one screen at half height.
7. The ledger shows rest actuals; a trophy tick prints its margin; the finish sheet shows one spark.
8. A second account sees none of the founder's loads, targets, re-entry week or treadmill opener.

## Wave Records

### W1 Wave Record — shipped 2026-09-18 as 5.1.0

**Drift from the plan, on purpose:**
- **"No goldens change" was impossible, and the golden changed.** `readiness-schedule.json` pins `ScheduleReadiness.apply`'s exact `reason` strings as *expected output*, and eight of its 64 cases carried `"Scheduled rest in Onyx-5 — Zone-2 cardio (150–250 kcal) or full recovery."`. Deleting the literal necessarily rewrites them. The eight were hand-edited to the nil-label form (never regenerated — sprint law), and two cases were appended that pass `programLabel: "Onyx-5"`, because the 64-cell sweep has no axis for it and the named branch would otherwise be unvectored. `WeekSoFarGoldenTests` now asserts `64 + 2`.
- **`seed(from lastBout:)` does not take a `CardioLogRow`.** The plan named that type; it lives in OnyxData and `WarmupCardio` is OnyxCore, which may not import it. The seam is `WarmupCardio.Bout` (name, durationSec, distanceKm, inclinePct); `LoggerModel` converts the row, taking the card's name from `CardioKind(row.kind).label` so a cyclist's card says so.
- **`maxSeconds = 600` is a new constant.** Repeating last Sunday's forty-minute run as a lifting warm-up would propose a different workout, so a longer bout is clamped and its distance scaled by the same factor — the printed pace stays the pace that was run. It is a category constant ("what warm-up means"), not an athlete's number.
- **`WarmupCardio.name` survives.** `ExerciseIndexTests` pins `ExerciseSlug.id(...) == "helix5-treadmill"` and the founder's uploaded treadmill sets are filed under it. It is documented as the legacy slug anchor and is no longer the opener's name.
- **`DayModel` gained an `environment` at construction, not just in the sheet.** `SleepEditSheet` is today's only caller of `setSleepOnsetTrouble`, but the cascade belongs where every caller routes. Five sites pass it; previews and tests pass nil.
- **`volumeTargets` stayed in `plan-templates.json`.** The plan named `wk1Kg` and `phaseGoals` only. Weekly set targets describe the deck (what the plan asks of each muscle), not the body running it, and the volume tile is drawn against them.

**Root causes that were not where the plan guessed:**
- **`schedule_overrides` has no `kind` column.** The live table is `user_id, date, day_key, updated_at`. `Schedule.restOverride = "rest"` was already a `day_key` sentinel, so `reentryOverride` is the same trick and needs no DDL — but `scheduleDayIn` and `isTrainingDayIn` treat ANY non-`rest` override as a day swap. An unguarded reentry row would have flipped that date to a training day and reported a fortnight of missed sessions. Both now skip the sentinel and fall through to the weekday default.
- **A storeless `LoggerModel` is a preview, and previews photograph the opener.** The old gate returned `true` for a nil store deliberately. Reading `cardio_logs` instead would have silently emptied the `logger`, `logger-*` and `set-row-cardio` shots, whose fixture (`previewUpperB`) is storeless by design. Fixed with `init(..., warmupBout:)`: production reads the last bout, fixtures hand one in (`LoggerModel.previewBout`).
- **`HistoryWeeksTests.swift:115` does not reference the treadmill gate.** The file has no `WarmupCardio` reference at all. Line 115 is one of the pre-existing failures.
- **`nutrition_days` has not existed since `v9.mirror` dropped it.** The README paragraph names the three unscoped reads that are real: `AppDatabase.exercises()`, `exerciseCatalogStream()`, `PlanCatalogue.localUserId()`.
- **`LoggerModelTests` was a fourth hazard the plan did not list** (`armsBulk()` is storeless and asserts the opener), as was its cold-start test asserting `weightKg == 28` — the bundled template's `wk1Kg`.

**Constraints discovered that the next wave must respect:**
- **The OnyxTests baseline is 11, not 10.** Measured by stashing to `main` and re-running, not assumed. `npm run check` does not run them; only `xcodebuild test -scheme Onyx -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` does. W1 finished at 11 with a byte-identical failure set.
- **Shots are not byte-reproducible run to run** — the status-bar clock moves, so two runs of the *same* build differ. Establish that noise floor first and compare by eye; `cmp` always reports a difference and proves nothing.
- **The two `plan-templates.json` copies are now allowed to diverge.** The bundled one lost `wk1Kg`/`phaseGoals`; `OnyxCoreTests/Fixtures/` keeps both, because `program-onyx5.json` asserts a `wk1Kg` per exercise and a stripped fixture would silently compare nil against nil. `FounderTables.swift`'s header records why — do not "resync" them.
- **`PreviewCatalogue` is `#if DEBUG`.** Anything new that seeds a preview store must be too, or the app target stops building.

**Left open on purpose:**
- **`WarmupCardio` is still not an ordinary movement in `routines.payload`.** That needs the payload to carry `durationSec`, `inclinePct` and `distanceKm` — a schema change, and D5 froze the schema after W2. The existing `ponytail:` note was removed with the gate it sat on; this record is now its home.
- **No UI for the `reentry` override.** The sentinel is readable and the headline honours it, but nothing writes one yet; `WeekOverrideSheet` offers rest and day keys only.
- **`volumeTargets` in the bundled templates are still the founder's tuned numbers** for anyone who picks a template deck. `NewAccountPathTests` pins that the onboarding path uses the MEV table instead, so no new account receives them — but the file still ships them.

**Founder's manual steps still outstanding:** none for this wave. No DDL, no App Store metadata, no Supabase change.
