# Live UX Sprint — Mini Player, Widgets, Live Stats, Theme Engine, Pulse, Stress

**Status:** approved 2026-09-14 · step 0 done (branch + this doc). W1 next.
**Ships as:** six waves 3.5.0 → 3.10.0. This file is deleted by W6.
**Branch:** `onyx/sprint-live-ux` from updated `main` (3.4.0, `a5446ac9`). Wave branches `onyx/sprint-live-ux-w<N>` merge into it. W6 merges into `main` and purges every branch and this plan. (Wave branches use a dash: a ref cannot live under a name that is itself a branch.)

## Context

Eight UI/UX requirements for the live-training surfaces. Exploration found that four of the eight briefs name a symptom whose root cause sits elsewhere, and one names a control that does not exist. The plan below is written against what the code does, not what the brief assumed.

## Founder decisions (2026-09-14)

1. **Stress = event log.** Add nullable `logged_at timestamptz` to `stress_logs`, drop the `(user_id,date,slot)` unique. Slot stays as a derived value from `logged_at` so scoring (`StressInputsBuilder.swift:82-86`, flat day mean) and the export's shape survive. User logs only when they feel it; backdating allowed via an optional time field. No rows in a day = "Not reported". Head → Stress everywhere user-facing.
2. **Theme Engine.** Presets (6–8 pairs) + native `ColorPicker` for Primary and Secondary. Scope: domains + muscles + macros + day colours. Text, ground, glass, danger, good, record gold stay fixed. Reset to Default.
3. **Mini Player.** 64 pt floating card above the tab bar. Session name + elapsed timer (elapsed only, no rest swap) / "Next · exercise" / sets · volume · PRs. Day ramp over glass. Tap = zoom transition into the logger.
4. **Widgets.** "Next" text enlarged and made true (real next-in-deck). Muscle tag → header row after the session title. Load × reps + RPE right column. Timer coloured by primary-muscle landmark colour. Watch: ring gone, countdown text, session timer top-right on both screens, load × reps + RPE on the rest screen.
5. **Live Stats.** Top Lifts grouped per exercise, arrows vs the last session of that exercise, fire icon when beating the all-time record. Timeline dots coloured by primary-muscle landmark; a ticked cardio bout fills its dot.
6. **History cards.** One `SessionHeaderCard` for Train, Pulse and the session page. Pulse keeps the card, at the bottom of the day.
7. **Pulse.** Now strip → one scrolling vitals chip row → paged horizontal carousel of Fatigue / Stress / Soreness → Scale / Stack → workout card last.
8. **Dashboard.** The stiff swipe is the Smart Stack tile face flip (vertical pager), not a horizontal carousel. Fix its feel.
9. **Holiday** = one-day context like Event (nutrition exception only, no scoring change).
10. **Six waves.** Fable for engines and gates (W1, W6), Opus for UI (W2–W5). W2 ‖ W3, W4 ‖ W5 in separate worktrees.

## Findings (measured 2026-09-14)

### F1. "Resume workout" reads the wrong model
`WorkoutTabView.swift:993-1051` is a `.safeAreaInset(edge: .bottom)` footer bound to `WorkoutWeek.State.live(sets:volumeKg:)`. The tab already keeps the live `LoggerModel` in `session` (`:44`), which has `startedAt :433`, `restEndsAt :438`, the deck cursor, `totalVolumeKg`, `recordCount`. Minimized = `presented == nil` (`:49`); expand = `.fullScreenCover(item: $presented)` (`:163`). No custom transition. iOS 18 target → `.navigationTransition(.zoom)` is available.

### F2. Slider math: the bar never had a denominator
`Shared/WorkoutActivityCard.swift:41-45` `restCountdown` returns `Date()...endsAt`, rebased to now on every render; the bar is `ProgressView(timerInterval:)` over that range (`:250-256`). `restTotalSec` (`OnyxWorkoutAttributes.swift:176`) is written (`LiveActivityController.swift:228`, `RestSkipIntent.swift:95`) and read by no view. The in-app twin (`ExerciseCardView.swift:557`) uses the same helper. Watch: `WatchModel.adjustRest :410-422` moves `endsAt`, keeps `duration`; `RestView.swift:135` fraction exceeds 1.

### F3. "Next" is the current exercise
`LiveActivityController.state(from:)` sets `exercise` (`:206`) and `nextExercise` (`:214`) to the same string. `WorkoutCurrentSet.showsNext` (`WorkoutActivityCard.swift:314`) is really "is resting".

### F4. Top Lifts repeats by design of its keys
`LiveStatsView.swift:608-659`: three independent role maxima (Hardest = rpe×kg, Heaviest, 1RM Epley) keyed by role, so one movement prints three rows.

### F5. The cardio dot cannot fill
`setDots :424-458` fills `index < exercise.workingSets`; the treadmill bout is minted `kind: .warmup` (`LoggerModel.withWarmupCardio :869-895`), excluded from `workingSets` on purpose (tonnage, PR engine). `planned = 1`, `done = 0`, always. Dots use the day accent.

### F6. Colour is 1243 static reads of one hex table
`OnyxTokens.swift:112-471`: `enum Color.onyx` statics, `Color(hex:)` only, no asset catalog, no Environment, forced dark (`OnyxApp.swift:43`). `OnyxDomain :42-92` four ramps; muscle palette 16 hexes `:451-470`, OKLCH L 0.70 / C 0.17 optimised for min ΔE (rationale `:368-401`); macros `:211-223` and `day() :237` already derive from domains. Widgets resolve colour from `dayKey` / `primaryMuscle` widget-side. The token-discipline test died with the web app; `npm run check` enforces nothing about colour.

### F7. Three completed-workout cards, one header
Train `WorkoutTabView.sessionCard :461`, Pulse `WorkoutSummaryCard` (`PulseWorkout.swift:25`), History `DayHistoryRow`. The summary header is `SessionDetailView.band :426-491` (hero label in `dayLabel`, `careerNumber :557`, `planTags :597`, `stamp :497`, `muscleRow :640` over `report.primaryOrder`), fed by `SessionAnalysis.Page` (`SessionPage.swift:37`), whose `careerIndex :59` needs a career-wide query.

### F8. Stress is already a table, keyed by slot
`stress_logs` (`native/schema/supabase.json:128`): `id, user_id, date, slot, level, tags text[], note?, created_at, updated_at`, Postgres unique `(user_id,date,slot)`; slots morning/midday/evening never user-chosen (`PsychStress.swift:21-42`). Writes `DayEditing.setStress :248` delete same-slot shadows (`:281`). Export prints `date slot level` (`WeeklyExport.swift:1001`, `:1100`); tags and note never reach v5. Mirror is generated from `supabase.json` (`npm run mirror`); DDL is pasted by the founder.

### F9. No horizontal carousel exists
`SmartStackView.swift:186-320` is a hand-rolled vertical pager (`DragGesture(minimumDistance: 16)` via `.simultaneousGesture`, `@GestureState held`, `paging` latch → `TodayTabView.swift:123 .scrollDisabled`), competing with the vertical `ScrollView` and `.refreshable` (`:129`). Doc block `:33-60` records why `TabView(.page)` was abandoned.

### F10. Water: no static crash candidate
`WaterRow` (`NutritionTabView.swift:557-620`) tap → `NutritionModel.addWater :429` → `DayEditing.addWaterGlass :663`; long-press → `WaterSheet`. No force-unwrap, `try!`, index or unique-index trap. Must reproduce with the simulator crash log before any edit.

### F11. Holiday is two enums and one force-unwrap
`ContextMode` (`Context.swift:18`), `Context.meta :48` (feeds `rangeLine :109`'s `meta[mode]!`), `ExceptionDay.reasons :32`, picker `NutritionSheets.swift:112-116`. Free-text columns; no DDL; export's `event_days` picks it up.

## Architecture decisions

### A1. Theme value in OnyxCore, colour table in OnyxUI
OnyxUI depends on OnyxCore only (`OnyxUI/Package.swift:22-28`, language mode v6). So:
- `OnyxCore/Design/OnyxThemeSpec.swift` — `struct OnyxThemeSpec: Codable, Equatable, Sendable { primary: UInt32; secondary: UInt32 }`, `static let default = (0x6B78F0, 0xE3A650)`, `normalised()` (A3).
- `OnyxCore/Design/OKLCH.swift` — no conversion code exists anywhere in the repo (prose only at `OnyxTokens.swift:384`). sRGB hex → linear → LMS → cbrt → Lab → LCH and back (Ottosson matrices); `hue(hex)`, `rotate(hex, byDegrees:)` preserving L and C; gamut fit = reduce C in 0.01 steps until in [0,1] (`ponytail:` comment, upgrade = binary search). Pure `Double`, tested in `swift:core`.
- `OnyxUI/DesignSystem/OnyxTheme.swift` — `struct OnyxTheme { spec; start/end: [OnyxDomain: Color]; muscle: [LandmarkMuscle: Color] }`, whole palette resolved once in `init(spec:)`; a token read is a dictionary lookup. `nonisolated(unsafe) static var current` (written on the main actor only; a torn read is one stale frame; `@MainActor` rejected because Sendable value types and the widget timeline read `Color.onyx.*` off-main under v6). `key = "onyx.theme"`, `load(_ defaults:)`, `save(_:to:)`, `presets: [(name, spec)]` (6–8 pairs, secondary ≈ +120° from primary).
- **Derivation, one rule, reproduces the defaults bit-exact:** Δp = hue(primary) − hue(0x6B78F0); Δs = hue(secondary) − hue(0xE3A650). `train.start = primary`, `fuel.start = secondary`; every other default hex (train.end, fuel.end, body.*, recover.*, 16 muscles) = `rotate(defaultHex, Δ)` with Δp for train/body/recover/muscles and Δs for fuel. Body and Recover keep their **measured** default offsets from Train rather than the round 150° / 30° first proposed, so Reset to Default is pixel-identical to 3.4.0. Days (`day() :237`), macros (`:211-223`), `cardio`, `muscleFamily` already derive → untouched. `water`, text, ground, glass, danger, good, record stay literal.
- `OnyxTokens.swift` stays the only hex writer: the 8 domain + 16 muscle literals move into `defaultDomainHex` / `defaultMuscleHex` tables in the same file; `OnyxDomain.start/end` and `Color.onyx.muscle` read `OnyxTheme.current`. Zero call-site changes.

### A2. Persistence and fan-out
App Group defaults (`AppDatabase.appGroupID = "group.app.onyx.health"`, `AppDatabase.swift:44`).
- App: `OnyxApp.swift` `@AppStorage(OnyxTheme.key, store: appGroupDefaults) themeJSON`; `OnyxTheme.apply(themeJSON)` before the root and `.id(themeJSON)` on the root view. That single `.id` is what makes 1243 static reads refresh without an Environment.
- Widgets: `OnyxWidgetBundle.init` → `OnyxTheme.load(appGroupDefaults)` once per process. Settings save → `WidgetCenter.shared.reloadAllTimelines()`. Never read defaults inside `OnyxProvider.snapshot` per entry.
- Watch: `WatchContext` (`WatchPayloads.swift:37`) gains `theme: OnyxThemeSpec?`. Optional fields are the whole payload-versioning story (synthesized `decodeIfPresent`, the `ScheduleContext` precedent). `PhoneWatchBridge.send` attaches `OnyxTheme.current.spec`; `WatchModel.start()` and `receive(.context)` set `OnyxTheme.current`. `WatchInk.day(_:)` wraps `Color.onyx.day` (watch already links OnyxUI).

### A3. Contrast guard
`normalised()` clamps primary and secondary to OKLCH L ∈ [0.60, 0.78], C ≤ 0.20 before derivation. L ≥ 0.60 keeps an accent ≥ 4.5:1 on black (the muscle table's own floor is 4.99:1); L ≤ 0.78 keeps white text legible on the ramp buttons. Rotated muscles keep L and C, so the table's measured separation holds.

### A4. Timer math = one helper
`restCountdown(_ endsAt: Date?, total: Int? = nil) -> ClosedRange<Date>?` (`Shared/WorkoutActivityCard.swift:41`): lower bound = `endsAt − total` when a total is given, else `now`; nil when `endsAt ≤ now`. `Text(timerInterval:)` and `ProgressView(timerInterval:)` both accept a past lower bound; the fraction becomes elapsed / new total and +15 s stops snapping to full. `restTotalSec` gets its first reader. In-app twin fixed by the same call.

### A5. Stress = events
`stress_logs` gains nullable `logged_at timestamptz`; the `(user_id,date,slot)` unique is dropped; `supabase.json` conflict → `id`; `slot` derived at write from `logged_at` (`StressSlot.forMinutes`, extracted from `forClock`). Scoring is already a flat day mean → unchanged. `DayEditing.setStress` and its shadow-delete are deleted (data loss under events), replaced by `logStress(userId:date:loggedAt:level:tags:note:)` and `deleteStress(id:)`. `StressReading.id` becomes the row id and gains `loggedAt`.

### A6. `SessionHeaderCard` + batched career index
One view `Features/History/SessionHeaderCard.swift` over a `SessionHeader` value (label, dayKey, careerIndex?, prCount, planLabel, week, lever, maintenance, stamp, muscles). `SessionDetailView.band` becomes a call to it. Loader `SessionAnalysis.headers(database:userId:sessionIds:)`: one `summaries` pass, career index = position in `filter { sets > 0 }` (the exact fold `SessionPage.swift:206-210` does), returned as `[id: SessionHeader]`. No stored column: a cached index needs rewriting on every delete.

### A7. Next-in-deck
`LoggerModel.nextExercise` = first exercise after the current one (deck order) with an undone non-ghost row. `LiveActivityController.state(from:)` sends it; `exercise` stays current.

### A8. Dots
`LoggerModel.dotProgress(for:) -> (done, planned)`: lifting = today's rule moved into the model; an exercise whose rows are all `isCardio` = (ticked rows, max(1, rows.count)). `workingSets`, tonnage, PRs untouched.

### A9. Smart Stack
Tune, do not replace (`SmartStackView.swift:33-60` already records why `TabView(.page)` and same-axis nested scroll views fail; `.highPriorityGesture` is the dead-patch case). `takeover` 16 → 10 with an axis test (`abs(dy) > abs(dx) * 1.5`) in `.updating` and `.onChanged`; commit distance `h * 0.25` alongside `predictedEndTranslation`; rubber band `h * 0.4 → 0.6`. `.scrollDisabled` latch and `.refreshable` untouched.

### A10. Version bumps on concurrent branches
W2 ‖ W3 and W4 ‖ W5 do **not** bump on their branch. The bump + changelog lands on `onyx/sprint-live-ux` at each merge, in order (W2 → 3.6.0, W3 → 3.7.0, W4 → 3.8.0, W5 → 3.9.0). Otherwise both branches edit `package.json`, `project.yml`, `CHANGELOG.md` and collide on every merge.

## Waves

Every wave: work on its branch, patches from script files (memory: worktree-guard-and-hooks), `swift:core` + `swift:data` (+ `swift:ui` from W1) green, `OnyxTests` baseline failures are not regressions, `graphify update .`, screenshots via `scripts/native-shot.sh` with `SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w<N>`. Check `MERGE_HEAD` before `git add`.

### Step 0 — branch (first execution action)
`git fetch origin && git checkout -b onyx/sprint-live-ux origin/main` (main at 3.4.0). Copy this plan to `docs/LIVE_UX_SPRINT_PLAN.md`, commit. Save a memory file for the sprint.

### W1 — Fable · Engines · v3.5.0 · `onyx/sprint-live-ux-w1`

**Shipped 2026-09-14 as 3.5.0. Drift from the list below, on purpose:** the wire `nextExercise` is set only at a movement boundary (`LoggerModel.restBoundaryExercise`), because sending the following movement mid-exercise headlined it over the current lift's load on the card; the model's `nextExercise` (following movement) exists for the Mini Player and has no caller yet. `OnyxTheme.current` is `internal(set)`; the only writers outside OnyxUI are the `@MainActor` `load/save/apply/set`. Five domain-derived `static let` snapshots (macros, `Color.onyx.series`) became computed. `swift:ui` is `scripts/swift-ui-test.sh` (xcodebuild; OnyxUI has no macOS platform), so `npm run check` now needs a simulator. The builder sorts stress rows by `loggedAt ?? slot-start`. The legacy Head sheet opens blank and its Clear removes the latest event (W4 rewrites it). A stress event logged BEFORE the founder pastes the SQL pushes `logged_at`, fails on the server and is retried per row — paste first. The SQL drops the unique by its columns (no DB access from this machine to read the name). Wave branches use a dash.
**Left for W2:** every `restCountdown` caller still passes no total (the widget and in-app bars behave as in 3.4.0 until W2 passes `restTotalSec` / `restDuration`); `restingExercise` is compared by name — stamp the id when W2 first draws the boundary. **Left for W5:** see W5 task 0.
1. **Timer helper** (A4). `RestCountdownTests.swift`: a total puts the lower bound `total` s before `endsAt`; nil total keeps now; past deadline stays nil; ranges ordered.
2. **Theme core** (A1–A3). `OKLCH.swift`, `OnyxThemeSpec.swift`, `OnyxTheme.swift`, `OnyxTokens.swift:53-69` + `:451-470` rewired, presets. `OKLCHTests`: round-trip within 1/255 for all 24 default hexes; `rotate(_, 0)` and `rotate(_, 360)` identity; L and C preserved within 1e-3; out-of-gamut rotation lands in gamut; `normalised()` clamps and leaves in-range alone. `OnyxUITests`: default spec reproduces every default `Color`; 16 rotated muscles pairwise distinct for Δ ∈ {0, 90, 180, 270}; every domain accent distinct under each preset.
3. **Token discipline test.** `OnyxUITests/TokenDisciplineTests.swift` walks `native/` from `#filePath`, every `.swift` except `OnyxTokens.swift`, `OnyxTheme.swift`, generated `OnyxAtlas.swift`, `.build`; fails on `Color(hex:`, `Color(red:`, `Color(.sRGB`, `UIColor(`, `#colorLiteral`. `package.json`: add `swift:ui`, append `&& npm run swift:ui` to `check`.
4. **Theme plumbing** (A2). `WatchPayloads.swift:37`, `PhoneWatchBridge.swift`, `WatchModel.swift:167` + `receive(.context)`, `WatchInk.day`, `OnyxApp.swift` `@AppStorage` + `.id`, widget bundle `init`. No Settings UI (W5).
5. **Stress schema** (A5). `supabase.json:128` cols += `logged_at:timestamptz?`, conflict → `id`; `npm run mirror`; `AppDatabase.swift` `v24.stressEvents` guarded `ALTER TABLE stress_logs ADD COLUMN logged_at DATETIME` (pattern `v21.genericModel`); `PsychStress.swift` `forMinutes`, `StressReading.id/loggedAt`, `latest` ordered by `loggedAt ?? slot`; `DayEditing.swift:248-295` → `logStress`/`deleteStress`; `PulseModel.swift:581/:591/:600/:741` → `stressEvents`, `logStress`, `deleteStress`; export `ExportStress.time: String?` ("HH:mm", nil for pre-sprint rows), `WeeklyExportBuilder.swift:166-190` sorts by `loggedAt ?? createdAt`, `WeeklyExport.swift:1001` and `:1100/:1127` print `\(time ?? slot) \(level)`. `StressLogTests` rewritten: two events in one slot persist; delete touches one row; slot derived from time (23:30 → evening, 08:00 → morning); export line `HH:mm level`, legacy nil-time row `slot level`. SQL in `docs/sql/w1-stress-events.sql` (founder pastes; `schema-truth-checker` names the constraint first):
   ```sql
   alter table public.stress_logs add column if not exists logged_at timestamptz;
   update public.stress_logs set logged_at = created_at where logged_at is null;
   alter table public.stress_logs drop constraint if exists stress_logs_user_id_date_slot_key;
   ```
   Local rows carry `loggedAt: nil` until the paste (nullable + omitted from the push while nil).
6. **TopLifts engine.** `OnyxCore/Sessions/TopLifts.swift`: `group(_ sets:, previous:) -> [Group]`, one group per exercise that wins any role, roles (Hardest / Heaviest / 1RM) under it, `delta` vs `previous[exercise]` (.up/.down/.flat), `isRecord` = the winning set carries the role's PR axis (`.weight` for Heaviest, `.e1rm` for 1RM; Hardest never flames). Tie rule as today (last maximum wins). Tests: one exercise winning all three → one group, three roles; two exercises → two groups; delta signs; `isRecord` from axes; unrated set cannot win Hardest.
7. **Dots** (A8). `LoggerModelTests`: cardio-only exercise reads (0,1) unticked, (1,1) ticked; lifting equals `(workingSets, planned)`; `workingSets` unchanged by a ticked bout.
8. **Next exercise** (A7). Test: deck A(2), B, C — after A1 next is B; after A2 next is B; on C's last set nil.
9. **Holiday.** `Context.swift:18` `case holiday` after `event`; `meta :48` entry ("Holiday", one-line desc, dayLabel "Holiday"); `isRangeMode` false; scoring → `.normal` at the `.event` site; `ExceptionDay.swift:32` reasons gain "Holiday" after "Event". Test: `Context.meta` holds every case.
10. Version 3.5.0, changelog, `graphify update .`, memory file.

Gate: `swift:core`, `swift:data`, `swift:ui`, `npm run check` green; `OnyxTests` at baseline; app pixel-identical on the default spec (screenshot diff of Train, Pulse, Lock Screen card vs 3.4.0); `schema-truth-checker` confirms `logged_at` after the paste.

### W2 — Opus · Mini Player + widgets + watch · v3.6.0 · `w2` (‖ W3)
1. **Mini Player.** `WorkoutTabView.swift:993-1051` `.live` branch → `MiniPlayerCard(model: session)` (new `Features/Workout/MiniPlayerCard.swift`), 64 pt, `.onyxGlass(.tile)` under a `Color.onyx.day(key)` ramp wash. Row 1 `day.label` + trailing elapsed (`Text(timerInterval:)` from `timerOrigin`; paused → formatted `elapsed`, same rule as `LiveActivityController.swift:186`). Row 2 `Next · nextExercise?.name ?? current ?? "Done"`. Row 3 `done/planned sets · volume kg · N PR` (zero PRs omitted). Tap: `@Namespace`, `.matchedTransitionSource(id:in:)` on the card, `.navigationTransition(.zoom(sourceID:in:))` on the cover content at `:163`. `.none` keeps `startButton`. Stays inside the Train tab's inset; a cross-tab player would need `session` lifted into `AppEnvironment` (upgrade path, not this wave).
2. **Lock Screen / Island.** `WorkoutCurrentSet :307-402`: header row = title + `WorkoutMuscleTag` after it; below it `Next · <exercise>` at 13 pt semibold replacing the NEXT chip; trailing `VStack(.trailing)` of load and RPE capsule. `WorkoutRestBand :243-279` and `OnyxWidgets.swift:212/:239` pass `total: state.restTotalSec`; timer ink = `Color.onyx.muscle(primaryMuscle)` falling back to `day(dayKey)` (extract `WorkoutMuscleTag`'s resolution into `static func tint(_ token:) -> Color`). `ExerciseCardView.swift:557` passes `total: Int(model.restDuration)`.
3. **Watch.** `RestPulse` gains optional `loadKg`, `reps`, `rpe`, `startedAt` (`id` stays `endsAt`). Phone fills them at `LiveLoggerView.swift:740` from the last done row of `restingExercise` and `startedAt`. `WatchModel.adjustRest :410` → `duration: max(rest.duration + seconds, next)`; `sessionStartedAt`. `RestView.swift:133-144` ring deleted; clock row gains `load × reps · RPE`; `.topBarTrailing` session timer on `RestView` and `SetView`, tinted `WatchInk.day`.

Gate: 375 pt + AX5 shots of Mini Player (live, paused), Lock Screen resting/working, Island expanded/compact, watch SetView + RestView (40 mm); +15 s on the card does not reset the bar (recording); old-payload decode test for `RestPulse` without the new keys.

### W3 — Opus · Live Stats + history cards · v3.7.0 · `w3` (‖ W2)
1. **Top Lifts.** `LiveStatsView.swift:608-659` → `TopLifts.group` over `model.exercises` rows (axes from `livePrs`, previous from `model.seed`); header once, roles indented, `arrow.up/down` in `good`/`textSecondary`, `flame.fill` in `record` when `isRecord`. AX5 column rule kept.
2. **Dots.** `:424-458` → `model.dotProgress(for:)`; fill `Color.onyx.muscle(primary)` via a `LoggerModel.primaryMuscle(of:)` helper shared with the activity; cardio → `Color.onyx.cardio`.
3. **SessionHeaderCard** (A6). New file; `SessionDetailView.swift:426-491` calls it; `SessionAnalysis.headers` loader; Train done card `WorkoutTabView.swift:461` → the card inside the existing `NavigationLink`. Pulse swap is W4's. `HistoryWeeksTests`: `headers` numbers three sessions 1,2,3 and skips a zero-set shell.

Gate: shots of Live Stats (grouped lifts with an arrow and a flame; dots with a ticked cardio bout), Train done card, session page band.

### W4 — Opus · Pulse reorg + carousel + Stress UI · v3.8.0 · `w4` (‖ W5, after W3 merges)
1. **Order** (`PulseTabView.swift:118-183`): banners → `NowStripPulse` → `VitalsChipRow` (new; horizontal chip row, tap expands the grid inline; Sleep becomes the first chip) → `PulseCarousel` (`ScrollView(.horizontal) { LazyHStack { FatigueCard; StressLogCard; SorenessCard }.scrollTargetLayout() }.scrollTargetBehavior(.viewAligned).contentMargins(.horizontal, OnyxSpace.l).scrollPosition(id:)` + 3 dots, page width = width − 2·l − peek) → `Section { ScaleRow; StackRow }` → `StressTile` (index) → `ForEach(sessions) { SessionHeaderCard }` replacing `WorkoutSummaryCard` (`DayModel.WorkoutSummary` deleted if unread). Hold `page` in `DayScreen` so cell reuse cannot reset it; `.listRowInsets(EdgeInsets())` on the carousel row.
2. **Stress UI.** `PulseHead.swift` → `PulseStressLog.swift`: `StressLogCard` (time strip of `HH:mm · word` capsules via `MetaTagRow`, or "Not reported"; "Log stress" button; swipe/long-press delete) and `StressLogSheet` (five-word level row, tag chips from the old `tagSection`, `DatePicker(.hourAndMinute)` defaulting to now and bounded to the day → `logStress`). Naming: tile "Stress index", card "Stress log", sheet "Log stress", Quick Log spoke id `stress`. No "Head" string remains (grep gate).

Gate: shots of the whole Pulse day (three carousel pages, chip row collapsed/expanded, two events in one slot, "Not reported"); VoiceOver reads each page once; an exported week shows `HH:mm level`.

### W5 — Opus · Theme settings + dashboard gesture + water crash · v3.9.0 · `w5` (‖ W4)
0. **Binding seam from W1's final review:** the app root's `.id(themeJSON)` discards every `@State` under it — including the live `LoggerModel` kept in `WorkoutTabView` (`:44/:49`) and `LiveLoggerView`. A theme write mid-workout would destroy the running session. The Appearance write must either be disabled while a session is live (the cheapest: the section reads `environment`'s live-session flag and greys the pickers with a footer "Finish or minimise the workout first"), or the session must be hoisted into `AppEnvironment` first. Also: call `WidgetCenter.shared.reloadAllTimelines()` and the watch bridge send on every theme write (W1 wired neither trigger).
1. **Appearance section** in `SettingsTabView.swift` (`OnyxSectionHeader("Appearance", .train)`): preset chips (two-stop swatches), `ColorPicker("Primary", supportsOpacity: false)` / `ColorPicker("Secondary")` bound `Color ↔ UInt32` via one `Color.hex` extension in `OnyxTheme.swift`, "Reset to Default". Save = `OnyxTheme.save(spec.normalised())` + `WidgetCenter.reloadAllTimelines()` + the existing watch bridge send. The `@AppStorage` in `OnyxApp` does the re-render.
2. **Smart Stack** (A9) constants + axis test at `SmartStackView.swift:257-320`.
3. **Water crash.** Reproduce first: simulator, Nutrition tab, rapid taps + long-press on `WaterRow`, `xcrun simctl spawn booted log stream --predicate 'process == "Onyx"'`, then `~/Library/Logs/DiagnosticReports`. Hypotheses in order: (1) `.onTapGesture` + `.onLongPressGesture` + `.sensoryFeedback` firing `onEdit` while `WaterSheet` is presenting; (2) overlapping `writer.write` (GRDB serialises, unlikely); (3) server `hk_uuid` unique vs the glass sentinel (push failure, not a crash, rule out). Fix at the frame the log names; if (1), a `Button` plus long-press on the label only.

Gate: shots of Settings → Appearance, Train, Pulse, Lock Screen card, watch SetView under one preset and one custom pair; Reset restores 3.4.0 pixels; flip recording (short flick pages, slow drag scrolls); 30 rapid water taps + long-press without a crash; crash log + root cause in the report.

### W6 — Fable · Gate + purge · v3.10.0 · `w6`
Merge `onyx/sprint-live-ux` → `main`. `npm run check` (incl. `swift:ui`), `swift:core`, `swift:data`, `OnyxTests` baseline; `grep -rn '"Head"' native` empty; every `restCountdown(` caller with a total passes one; `schema-truth-checker` confirms `stress_logs.logged_at` and no `(user_id,date,slot)` unique; `graphify update .`; changelog 3.10.0; memories marked SUPERSEDED where the sprint changed them. **Final step: delete every `onyx/sprint-live-ux*` branch and worktree, and delete `docs/LIVE_UX_SPRINT_PLAN.md` and `docs/sql/w1-stress-events.sql` once the founder confirms the paste.**

## Seams (concurrent pairs)

| | owns | must not touch |
|---|---|---|
| **W2** | `WorkoutTabView.swift` hunks `:40-52`, `:158-168`, `:990-1051`; `MiniPlayerCard.swift` (new); `LiveLoggerView.swift`, `LiveActivityController.swift`, `ExerciseCardView.swift:557`; `Shared/*`; `OnyxWidgets/*`; `OnyxWatch/*`; `WatchPayloads.swift`; `PhoneWatchBridge.swift` | `LiveStatsView.swift`, `Features/History/*`, `WorkoutTabView.swift:461-` |
| **W3** | `LiveStatsView.swift`; `Features/History/*` (+ `SessionHeaderCard.swift`); `WorkoutTabView.swift:461-`; `LoggerModel.swift` read-only helper `primaryMuscle(of:)` | `Shared/*`, widgets, watch, `LiveLoggerView.swift`, `Features/Pulse/*` |
| **W4** | `Features/Pulse/*`; `Today/QuickLogSheet.swift` | `Settings/*`, `SmartStackView.swift`, `TodayTabView.swift`, `OnyxApp.swift`, `Nutrition/*` |
| **W5** | `Settings/*`; `SmartStackView.swift`, `TodayTabView.swift`; `Nutrition/*`; `OnyxTheme.swift` hex helpers only | `Features/Pulse/*`, `QuickLogSheet.swift`, `PulseModel.swift` |

Frozen after W1: `OnyxTokens.swift`, `OKLCH.swift`, `OnyxThemeSpec.swift`, `MirrorModels.swift`, `supabase.json`, `PsychStress.swift`, `DayEditing.swift`, `LoggerModel.swift` (except W3's helper).

## Risks
- **Static colour re-render.** Views that captured a `Color` into a stored property keep it until `.id(themeJSON)` rebuilds the tree. A running Live Activity recolours only on the next `activity.update` after the widget process relaunches. Document in the changelog.
- **App Group read cost.** One defaults read per widget process launch; never inside a getter; never per timeline entry.
- **Watch payload.** New optional fields decode both directions; a new watch with an old phone shows no session timer until the phone updates. `RestPulse.id = endsAt` unchanged so +15 s re-presentation still works.
- **Shadow-delete.** `setStress`'s sibling delete is data loss under events; it goes with the function. Pull path upsert-by-id already safe.
- **Pull before paste.** `logged_at` nullable locally; push omits nil. The founder pastes before logging the first event or the push is held (PGRST hold from the last sprint's W1).
- **Pulse `List` + horizontal `ScrollView`.** Different axes hit-test cleanly; traps are cell reuse resetting `scrollPosition` (state held in `DayScreen`) and row insets shrinking the peek at AX5.
- **`nonisolated(unsafe)`.** Setter main-only by convention; documented at the declaration.

## Copy-paste prompts

### W1
```
You are Fable (extra high effort), Lead Algorithm & Backend Strategist on Onyx. Read docs/LIVE_UX_SPRINT_PLAN.md fully (Findings F1–F11, decisions A1–A10, W1, Seams, Risks). Execute W1 — the engines — exactly as listed: timer helper, theme core (OKLCH + OnyxThemeSpec + OnyxTheme, OnyxTokens rewired, presets, plumbing to app/widgets/watch), token-discipline test wired into npm run check, stress events (schema + mirror + DayEditing + PulseModel API + export + docs/sql/w1-stress-events.sql), TopLifts engine, dotProgress, nextExercise, Holiday. No screen changes beyond what the rewiring forces; the app must be pixel-identical on the default spec.
Skills: graphify (query before grep), native, supabase-postgres-best-practices, git-commit-helper. Agents: schema-truth-checker (name the unique constraint before writing the SQL; confirm logged_at after the paste), invariant-auditor (StressInputsBuilder unchanged; LoggerModel.workingSets unchanged by a ticked bout), swift-expert (nonisolated(unsafe) static under language mode v6), code-reviewer.
One test per logic branch as listed. Branch onyx/sprint-live-ux-w1 off onyx/sprint-live-ux. Version 3.5.0, changelog, graphify update. Report: per task file:line, the test, and the SQL the founder pastes.
```
### W2
```
You are Opus (extra high effort), Lead Frontend & Design on Onyx. Read docs/LIVE_UX_SPRINT_PLAN.md (F1–F3, A2, A4, A7, W2, Seams). W1 is merged. Execute W2 — Mini Player, Lock Screen/Island layout, watch parity — in a worktree on onyx/sprint-live-ux-w2. You own only the W2 seam files; do not touch LiveStatsView, Features/History or WorkoutTabView below line 461. Do NOT bump the version on the branch (A10).
Skills: graphify, native, apple-design, ui-ux-pro-max, frontend-design, git-commit-helper. Agents: ios-developer (navigationTransition zoom from a fullScreenCover; ProgressView(timerInterval:) with a past lower bound), ui-ux-designer (64 pt card hierarchy at AX5; 40 mm rest screen), swift-expert (optional RestPulse fields, old-payload decode test), code-reviewer.
Report the W2 gate screenshots at 375 pt and AX5 and the +15 s recording.
```
### W3
```
You are Opus (extra high effort), Lead Frontend & Data Display on Onyx. Read docs/LIVE_UX_SPRINT_PLAN.md (F4, F5, F7, A6, A8, W3, Seams). W1 is merged. Execute W3 — grouped Top Lifts with arrows and flames, muscle-coloured dots, SessionHeaderCard + batched headers loader, Train done card — in a worktree on onyx/sprint-live-ux-w3. You own LiveStatsView, Features/History, WorkoutTabView from line 461 down. Do NOT bump the version on the branch; do not touch Features/Pulse.
Skills: graphify, native, apple-design, ui-ux-pro-max, frontend-design, git-commit-helper. Agents: ui-ux-designer, swift-expert (TopLifts.group inputs from livePrs and seed), invariant-auditor (headers' career index equals page.careerIndex for every session), code-reviewer.
Report the W3 gate screenshots.
```
### W4
```
You are Opus (extra high effort), Lead Frontend & UX on Onyx. Read docs/LIVE_UX_SPRINT_PLAN.md (F8, A5, A6, W4, Seams, Risks). W1–W3 are merged. Execute W4 — Pulse reorder, vitals chip row, viewAligned carousel, Stress log card + sheet + Quick Log spoke, Head → Stress rename, SessionHeaderCard on Pulse — in a worktree on onyx/sprint-live-ux-w4. You own Features/Pulse and QuickLogSheet.swift only. Do NOT bump the version on the branch.
Skills: graphify, native, apple-design, ui-ux-pro-max, frontend-design, git-commit-helper. Agents: ui-ux-designer ("Stress index" tile vs "Stress log" card; time strip at AX5), ios-developer (List + horizontal ScrollView, scrollPosition across cell reuse), invariant-auditor (logStress → StressInputsBuilder mean), database-architect (event-log read patterns, none new), code-reviewer.
Report the W4 gate screenshots and one exported week with two events in one slot.
```
### W5
```
You are Opus (extra high effort), Lead Frontend & Product on Onyx. Read docs/LIVE_UX_SPRINT_PLAN.md (F6, F9, F10, A1–A3, A9, W5, Seams, Risks). W1–W3 are merged. Execute W5 — Appearance settings (presets, two ColorPickers, Reset), Smart Stack gesture tune, water crash — in a worktree on onyx/sprint-live-ux-w5. You own Features/Settings, SmartStackView, TodayTabView, Features/Nutrition, OnyxTheme.swift hex helpers. Do NOT bump the version on the branch; do not touch Features/Pulse.
Skills: graphify, native, apple-design, ui-ux-pro-max, ui-design-system, superpowers:systematic-debugging (water: reproduce with a crash log before any edit), git-commit-helper. Agents: ui-ux-designer (preset swatches; contrast at the clamp edges), ios-developer (ColorPicker ↔ UInt32; WidgetCenter reload; gesture constants), debugger (water crash), senior-architect skill for the theme section layout, code-reviewer.
Report the W5 gate screenshots under one preset and one custom pair, the Reset diff, the flip recording, and the water crash log + root cause.
```
### W6
```
You are Fable (extra high effort), Lead Architecture Strategist on Onyx. Read docs/LIVE_UX_SPRINT_PLAN.md (W6). Merge onyx/sprint-live-ux into main, run the full gate (npm run check incl. swift:ui, swift:core, swift:data, OnyxTests baseline, the greps, schema-truth-checker), version 3.10.0, changelog, graphify update, then delete every onyx/sprint-live-ux* branch and worktree, docs/LIVE_UX_SPRINT_PLAN.md and docs/sql/w1-stress-events.sql; mark memories SUPERSEDED.
Skills: graphify, native, git-commit-helper. Agents: schema-truth-checker, code-reviewer (the whole sprint diff, reuse and dead code only).
Report the gate output and the final branch list.
```

## Verification (sprint level)
- After W1: default spec screenshots identical to 3.4.0; `npm run check` runs `swift:ui`; a `Color(hex:` added under `Features/` fails it.
- After W2: +15 s on the Lock Screen bar moves the fill from 50 % to 40 %, not 100 %; the Island names a different "Next" than the current lift; watch rest screen shows load × reps and a session timer.
- After W3: Leg Press appears once in Top Lifts with three roles; a ticked treadmill bout fills its dot in the cardio colour.
- After W4: Pulse opens on the strip, chips, carousel; two stress events at 09:12 and 15:40 both print in the export; an empty day reads "Not reported"; no "Head" in the app.
- After W5: pick a preset → Train, Pulse, Lock Screen and watch recolour; Reset → 3.4.0 pixels; 30 water taps, no crash.
- After W6: `git branch --list 'onyx/sprint-live-ux*'` empty; `docs/LIVE_UX_SPRINT_PLAN.md` gone; main at 3.10.0.
