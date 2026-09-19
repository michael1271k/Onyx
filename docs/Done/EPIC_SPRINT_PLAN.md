# Epic Sprint — Bug map, generic scaling, UI/UX overhaul, predecessor sunset

Status: findings + founder decisions locked 2026-09-10. Waves + prompts in §Waves.
W6 (predecessor sunset) shipped 2026-09-13 as 3.0.0 — see `docs/CHANGELOG.md`; the founder checklist below is what remains by hand.

## Founder decisions (2026-09-10)
1. Predecessor web sunset = LAST wave (W6).
2. Founder plan → seeded templates. Decks become routine template rows; phases/levers/PR seeds/stack migrate once into the founder's rows; Swift constants deleted after.
3. Psych stress: new `stress_logs` table, feeds a `self` sub-term of the Stress index. NOT a Battery input.
4. Muscle colour: 8 families (Chest, Back, Shoulders, Biceps, Triceps, Forearms, Legs, Core), landmarks stepped light→dark inside a family. Charts group by 8, atlas paints 16.
5. Dashboard mark → Quick Log radial (water, weigh-in, fatigue, stress, cardio, note).
6. Fatigue: keep 1–5 storage. Words must be plain everyday English felt instantly: **Amazing / Good / Okay / Tired / Exhausted** (or equally simple). UI reflects that simplicity: one row of five big targets, no scroll, no coaching prose.
7. No paid Developer Program this sprint. Watch fix guide = direct Xcode run; 7-day profiles stay.
8. Six waves: W1 Fable bugs+DB · W2 Fable generic data model · W3 Opus palette+atlas+trends · W4 Opus fatigue/stress/stack/reports · W5 Opus smart inputs+onboarding+routine builder · W6 Fable sunset+purge.

## Context

Onyx 1.5.0 is the native iOS app (native/); the predecessor is the legacy Next.js web app (src/) still deployed on Netlify. Wave 9 of `docs/NATIVE_MIGRATION_PLAN.md` (retire the web) was postponed; Wave 10 (Watch) shipped ahead of it. This sprint: close the open defects, make the app generic (not the founder's plan), overhaul six UI surfaces, automate HealthKit inputs, then delete the predecessor.

## Findings (measured 2026-09-10)

### F1. The three "known bugs" are already marked fixed in 1.4.0 (`docs/CHANGELOG.md:179-193`)
- SyncEngine 503 → item now held + retried. Only a missing `set_events` table is swallowed.
- Set quality tags → batch split into tagged/untagged rows.
- Rest-day fatigue fold → legacy slot key folded like the scorer.
Sprint task = **regression-verify**, not re-fix (see bug agent report for residual risk).

### F2. Side delts 0/7 — root cause CONFIRMED: slug id vs UUID catalogue
`TodayFeedBuilder.muscleFocus` (`TodayFeedBuilder.swift:267`) and the widget path (`WidgetSnapshotBuilder.swift:660`) do `guard let name = names[set.exerciseId] else { continue }`. `names` = local `exercises` table (`WidgetSnapshotBuilder.swift:472`), which only ever holds server UUIDs (`TrainingPuller.swift:390`). Phone-logged sets store the predecessor's `<brand>5-<slug>` ids (`LoggerModel.swift:1955-1966`) and are never repaired because `applyPulledSets` skips sessions with local events (`TrainingPuller.swift:320-328`). Every phone-logged set is dropped from muscle credit; side delts is visible because Upper B's lateral raise is the only side-delt source (Shoulder Press deliberately doesn't credit side delts). Fix in ONE place: merge `ExerciseSlug.nameBySlug` (`ExerciseIndex.swift:186`) into `rows.exerciseNames` at `WidgetSnapshotBuilder.swift:472`. Same chain `LoggerModel.restoreLoggedSets:1795` already uses.

### F2b. Residual defects behind the "fixed" three
- **Sync:** plain 503 is held (safe). But `isMissingRelation` (`SyncEngine.swift:472`) treats `PGRST205/PGRST204/42P01/42703` as permanent → acknowledges + deletes the set event. `PGRST205` = "not in schema cache", which PostgREST returns transiently during cache reloads / restarts (same window as 503s). Silent permanent loss path. No test for `MirrorPushRemote` failures.
- **Set quality:** keys match; grammar doesn't. Phone writes `momentum+partial_rom` (`Effort.swift:196`), SQL CHECK accepts it, web `isSetQuality` (`setTags.ts:178`) and zod enum accept single keys only → web export/edit read combination as null and **re-save writes the tag away** (`save.ts:372`). Also OnyxCore `SetTags.isSetQuality` is single-key while app-target `SetQuality.parse` splits on `+`. Dies with web deletion except the OnyxCore/app-target split.
- **Rest day:** load is a real zero (fine). Fatigue fold uses *planned* schedule (`Schedule.isTrainingDayIn`) not logged sessions; `Fatigue.dayMean` averages all 5 slots not the day's 3 (`Fatigue.swift:157`). Self-report term (weight 0.25) drifts on plan/log disagreement.

### F2c. Export audit
- RPE: capped at 10 everywhere; out-of-range → nil (unrated → CR-10 7 default), not clamped. Minor honesty gap.
- 2-minute duration: `SessionDuration` long-idle guard returns `worked + restMin`; `lastSetAt` = event row `createdAt`, and `seedEventLog` (`SessionEditing.swift:466`) stamps seeds with *now* → worked≈0 → duration = last movement's rest target (Pec Deck 120 s = 2.0 min). Fix: seed events with the set's real timestamp / fall back to set `created_at`.
- Micros: no food/supplement catalogue; `SupplementNutrients.swift:22` literal has no calcium for multivitamin; `nutrition_entries` is a `meal_type='daily'` aggregate → bimodal calcium (3,100 mg days) unfixable server-side, only flagged (`IMPLAUSIBLE_FLOOR_MULTIPLE`).
- HRV: zero artifact filtering (`DailyLogIngest.swift:149`); weight has `MIN_VALID_WEIGHT_KG`, HRV has nothing.
- InBody: deprecated `lean_mass` key still outranks derived fat-free mass (`dailyLog.ts:280`); `body_fat`/`muscle_percent`/`visceral_fat` unbounded.

### F3. Watch install loop — code is fine, signing chain verified
Verified on the 2026-09-10 20:03 Debug build in DerivedData:
- Bundle ids: `app.onyx.health.michael.native` ↔ `.watchkitapp`, `WKCompanionAppBundleIdentifier` matches, `WKApplication` true, versions 1.5.0/10500 on both.
- Embed Watch Content phase present (`dstPath $(CONTENTS_FOLDER_PATH)/Watch`).
- Watch profile `iOS Team Provisioning Profile: …watchkitapp` includes BOTH UDIDs (watch `00008310-000F31440C3A601E`, phone `00008120-…`), expires 2026-09-15, TTL 7 days (free personal team).
- Signed entitlements = healthkit + app-id + team-id + get-task-allow; profile is a superset.
- Watch Ultra 2, watchOS 27.0, Developer Mode **enabled**; iPhone 15, iOS 27.0, Xcode 26.6.
- Not verified: the watch bundle carries a 70 MB `OnyxWatch.debug.dylib` + `__preview.dylib` (`ENABLE_DEBUG_DYLIB=YES`). Companion-app installs of debug-dylib watch builds are the leading suspect.

### F4. Predecessor sunset — inventory
- Delete: `src/` (600 files), `ios/` (119), `public/`, `netlify.toml`, `netlify/functions/keep-alive.mts`, `capacitor.config.ts`, `e2e/`, 10 web build configs.
- Native still depends on the web tree for: `scripts/sync-version.mjs` (version SSoT), `src/tests/golden-vectors.test.ts` → 214 fixtures, `scripts/gen-atlas-swift.mjs` ← `src/lib/body/atlas.ts`, `scripts/gen-report-bundle.mjs` ← `src/lib/reports/webview/*` → `native/Onyx/Resources/ReportRenderer.html`, AASA + privacy/support pages on Netlify (`SettingsTabView.swift:325` is the only executable Netlify URL).
- No `supabase/` dir, no edge functions, no `.github`. SQL = `docs/sql/*.sql` pasted by hand.
- Predecessor-name strings: 343 files / 1,614 lines. Shipping native = ~40 lines / 17 files.
- **Load-bearing, must NOT rename:** the predecessor's exercise-id prefix (`workout_sets.exercise_id`), its era wire value (`Phases.swift:24`), its schema tag, the legacy App Group/sqlite names in `AppDatabase.swift:69-71`, its bundle id (dies with ios/), its URL scheme (dies with ios/), its localStorage keys (web only; two read as native pref fallbacks).

### F5. Supabase — 29 tables, all used by both surfaces except `set_events` (native only)
Drop candidates: `widget_tokens`, `notion_credentials`, `notion_exports`, `body_measurements`, `_bak_20260723`, RPC `exercise_history` (web only). `reports.session_summary_md` / `weight_report_md` unread. **Keep** `delete_my_account()` — App Review requirement, native has no caller yet (blocker for sunset).

### F6. Muscle colour — native collapsed 16 landmarks into 3–4 accents
- Taxonomy = 16 landmarks (`Landmarks.swift:17`), shoulders already split front/side/rear, biceps/triceps/forearms separate.
- `OnyxDomain.forMuscle` (`OnyxTokens.swift:112`): chest + 3 delts + 3 arm muscles → **same `.train` accent `#6B78F0`**. `forFamily`: Chest/Shoulders/Arms → one colour. Web had 16 hexes (`palette.ts:328`) with Chest `#E0703C` vs Biceps `#C97A45` (ΔRGB 26.6, the closest pair).
- Token discipline test forbids raw hex under `Features/`; the palette must live in `OnyxTokens.swift`.
- Consumers: 10 native call sites of `Color.onyx.muscle`, 3 of `forFamily` (Trends bars, widget tile, Performance tile).

### F7. Weekly sets per muscle — three accumulators, three currencies
| | grain | secondary credit | week start |
|---|---|---|---|
| `MuscleAggregator.aggregate` (Trends card) | 6 families | none | **hard-coded Sunday** (`MuscleAggregate.swift:88`) |
| `WidgetDerive.volumeByFamily` (widget tile) | 6 families | 0.5 | pref |
| `TodayFeedBuilder.muscleFocus` (sheet, canonical) | 16 landmarks | 0.5 | pref (`user_goals.week_end_day`) |

### F8. Founder hardcodes (native, all in `OnyxCore`)
Decks `Program.swift:214` (ONYX-5, 37 movements), `Decks.swift` (ONYX-4, PPL); `Programs.swift` macros/targets (side delts 7/9), `Phases.swift:81` 8 dated blocks incl. "Thailand Vacation", `PrSeed.swift`/`PrTruth.swift` asserted records, `Levers.swift:116` dated nutrition schedule, `SupplementStack.swift:201` 9-item stack, `Week.swift:9 week0Start`, `Era.onyxCutStart`. Onboarding = email+password only (`RootView.swift:29`); a new user inherits all of it. `exercises` table exists (per-user, names+muscle tags only); routines are code.

### F9. Existing surfaces to extend
- Fatigue: `Fatigue.swift:123` 5 levels (Fresh/Fine/Worn/Heavy/Empty), 5 slots; battery reads latest slot, Stress reads day mean.
- Psych stress: none. `daily_logs.mood` int column exists, mirrored, unused by anything.
- Stack: `supplement_log` + `custom_supplements` (name, dose:String); UI `PulseStack.swift`/`StackView.swift`; no type/archive.
- Reports: `reports` keyed by `period_start`; only writer is web `useSentinelExport.ts:53`; native reads + renders via `ReportWebView`; no PDF, no add button.
- Body: `PulseScale.swift` 11 fields, live derived masses already; HealthKit pulls weight/BMI/bodyFat/leanBodyMass (`HealthMetrics.swift:109`).
- Cardio: `CardioLog.swift`; HK workout import wired (`HealthKitReader.swift:184`) incl. `elevationM`; `cardio_logs` has `active_kcal`,`total_kcal` but **no elevation column**; basal energy authorized but not ingested.
- Week start: `user_goals.week_end_day` → `Week.startDay(fromEndDay:)`.
- Dashboard top-right: `OnyxMark` decorative, `.accessibilityHidden`, swaps to "Done" in edit mode (`TodayTabView.swift:117`).
- Charts: `OnyxChartCard(title, domain, legend:)` fixed plot height; legend impl in `TileSheets.swift:314` (private).

## Architecture decisions (from the design pass)

### D1. Routines = `routines` table with jsonb payload, no child table
`routine_templates` stays as-is (it stores last-performed sets, not the prescription). New `routines(user_id, program_id, day_key, label, sub, weekday, accent, sort, payload jsonb, updated_at)` PK `(user_id, program_id, day_key)`, `.delta` mirror. Payload `{version:1, exercises:[{exerciseId(uuid), name, sets, cutSets, reps, restSec, wk1Kg, note}]}`. Movers come from the catalogue row, never the payload. Mirror generator (`scripts/gen-mirror-swift.mjs`) has no child-table support; a second bespoke puller is not worth it.

### D2. Exercise catalogue = extend per-user `exercises`, no global table this sprint
Add `slug text` (the predecessor's legacy slug as an alias, backfilled by SQL from name), `secondary_muscles text[]`, `rest_sec`, `rep_floor`, `rep_ceiling`, `archived_at`; unique `(user_id, slug) where slug is not null`. New users get a bundled `native/Onyx/Resources/exercise-seed.json` inserted at onboarding (W5). `ponytail:` global read-all catalogue only when a second user needs catalogue updates without an app release. CSV import reads into this per-user table.

### D3. Slug ids survive as aliases via the column
`ExerciseIndex` gains `bySlug`; `id(forSlug:)` reads it; `ExerciseSlug.nameBySlug` becomes `SELECT slug, name FROM exercises WHERE slug IS NOT NULL`, merged into `exerciseNames` (the F2 fix site) and `LoggerModel.restoreLoggedSets`. After W2 `LoggerModel.exerciseId` writes the catalogue uuid; slug path is read-only legacy.

### D4. Founder constants → rows (targets already have the right columns unless marked new)
| Constant | Target |
|---|---|
| `Programs.all` PlanInfo | `plans` (3 rows) |
| ONYX-5 / ONYX-4 / PPL decks | **`routines`** (12 rows) |
| `Programs.weeklySetTargets` cut/bulk | `plan_phase_volume` (32 rows; `GoalsEditing.swift:122` already writes) |
| `PhaseGoals.cut/.bulk` | `plan_phase_goals` (2 rows) |
| `Phases.all` 8 dated blocks | **new `plan_phases`** (`user_id, plan_id, start, kind, name, short, weeks, numbered, first_week, era, era_tag`) |
| `Levers.schedule` | `daily_targets` rows per day via `generate_series` + `target_profiles` rows baseline/lever1/maintenance_week |
| `week0Start`, `onyxCutStart` | `plans.started_on` of active plan |
| `PrTruth.book` floors | `personal_records` rows with `session_id IS NULL` |
| `PrSeed.records` | already materialised by `PrEngine` replay; delete override after `reconcile-pr-counts` parity |
| `Supplements.protocolSeed` | `custom_supplements` (+ new `form`, `dose_amount`, `dose_unit`, `archived_at`, `sort_order`; `schedule.key` = legacy `item_key`) |
Seed parity: a one-off Swift test `SeedDumpTests` prints INSERTs from the live constants → `docs/sql/w2-seed-founder.sql`. No hand-typed numbers. Then constants + 14 orphaned golden fixtures deleted.

### D5. Schema frozen after W2. GRDB migration `v21.genericModel`
`supabase.json` gets `"since": 2` per new table; generator emits `migrateMirrorV2`. W3–W5 add no columns. Every W4/W5 column exists by end of W2 (stack form/dose, `stress_logs`, `cardio_logs.elevation_m`).

### D6. Stress index: psych as second input of the `self` term, weights unchanged
`StressInputs.stressDayMean: Double?`; `selfZ = meanOfAnswered([fatigueDayMean−3, stressDayMean−3])` clamped ±2 (`Stress.swift:265`). Weights stay auto .35 / sleep .25 / self .25 / load .15 (Hooper treats fatigue+stress as one self-report). Only `stress-breakdown.json` gains 3 hand-computed cases. `STRESS_MODEL.md` §2.3 updated.

### D7. Golden fixtures become Swift-owned in W1
From W2 the TS domain no longer matches; `npm run golden` would emit wrong oracles. W1 removes the `golden` script, rewrites the `GoldenVector.swift` header, and new cases are hand-computed.

### D8. W6: keep root `package.json` + `scripts/`; Netlify stays as a static-only site
Generator sources move to `scripts/src/{atlas.ts, report/*}`; `sync-version.mjs` drops the `ios/App` pbxproj edit. `netlify.toml` → `publish = "site"`, no build, keep the AASA content-type header. `site/{index,privacy,support}.html` + `site/.well-known/apple-app-site-association`. GitHub Pages can't set the AASA header; a Supabase bucket can't serve `/.well-known/` at a domain root.

### D9. Fatigue words
Amazing / Good / Okay / Tired / Exhausted. Stored 1–5 unchanged. No hint prose in the row; one line of hint only inside the sheet. Five equal-width targets, one tap, sheet closes.

## Wave seams (shared checkout)
- W2 → W3/W4: `MirrorModels.swift` + `AppDatabase` migrations frozen; `StressInputs.stressDayMean`, `Color.onyx.muscle(_:)`, `OnyxDomain.forFamily(_:)` signatures frozen.
- W3 owns `OnyxUI/*`, `OnyxCore/Training/{MuscleFamily,Landmarks}.swift`, `Charts/MuscleAggregate.swift`, `Widget/Derive.swift`, `TodayFeedBuilder.swift`, `Features/Trends/*`, `Features/{History/AtlasSheet,Logger/AtlasFigure,Pulse/DomsMap}.swift`.
- W4 owns `Features/Pulse/*` (except DomsMap), `Features/Reports/*`, `OnyxData/{Day,Database/ReportsStore}.swift`, `OnyxCore/Supplements/*`, `Features/Today/TodayTabView.swift` (mark → Quick Log); adds feed items only in `TodayFeedBuilder+Stress.swift`.
- W3 ‖ W4 may run concurrently. W5 starts after W4 merges (both hit `PulseTabView`/`SettingsTabView`). Neither W3 nor W4 touches `LoggerModel.swift` (W5's).
- Check `MERGE_HEAD` before `git add`; always pass `SHOT_DERIVED` (memory: concurrent-waves-shared-checkout).

## Watch install — manual guide (no code change needed until step 2)
1. Xcode → scheme **OnyxWatch** → destination **Michael's Apple Watch (via iPhone)** → Run. Direct install bypasses the companion installer.
2. If step 1 installs: companion path is the only broken one. Add `ENABLE_DEBUG_DYLIB: NO` under `OnyxWatch.settings.base` in `native/project.yml`, `npm run native:gen`, reinstall phone app, install from the Watch app. (70 MB `OnyxWatch.debug.dylib` + `__preview.dylib` in the embedded watch bundle is the suspect.)
3. If step 1 fails: Xcode → Settings → Accounts → team → Download Manual Profiles; `rm ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*`; Clean Build Folder; run again.
4. Still failing: Console.app → iPhone → filter `installd` / `nanoregistry` during install → send the rejection line.
5. Profiles are 7-day (`TimeToLive 7`, free team). Reinstall weekly until the paid program.

## Manual checklists for the founder
- **SQL (cannot run from this machine):** paste each `docs/sql/w*.sql` into the Supabase SQL editor when a wave says so; confirm with `schema-truth-checker` after.
- **Netlify (W6):** site renamed to `onyx-health-fitness`; set publish dir to `site`, remove the Next plugin and all `NEXT_PUBLIC_*`/`NOTION_*`/`SUPABASE_SERVICE_*` env vars; delete `keep-alive` function; verify `curl -i https://onyx-health-fitness.netlify.app/.well-known/apple-app-site-association` returns JSON with the native App ID.
- **Supabase (W6):** rotate DB password (outstanding since 2026-09-02); confirm dropped tables gone.
- **Memory (W6):** mark web-only memories SUPERSEDED in `MEMORY.md`.

## Waves

Every wave, without exception: work on a branch `onyx/<wave>`, run patches from script files (memory: worktree-guard-and-hooks), finish with MINOR version bump in `package.json` → `npm run version:sync` → `cd native && xcodegen generate` → changelog section → `npm run version:check` → `graphify update .` → merge to main. `swift:core` + `swift:data` green; `OnyxTests` 7 pre-existing failures are not regressions.

### W1 — Fable (extra high) · Truth wave: bugs, export math, DB cleanup · v1.6.0
Tasks:
1. Side delts: merge slug→name into `exerciseNames` at `WidgetSnapshotBuilder.swift:472` via `ExerciseSlug.nameBySlug`; test asserting a predecessor-stamped set credits its landmark.
2. Sync: `isMissingRelation` holds `PGRST205/PGRST204/42703` (transient schema-cache), only `42P01` acknowledges; jitter in `SyncBackoff`; test for `MirrorPushRemote` failure.
3. Rest day: `isTraining = logged session exists || scheduled`; `Fatigue.dayMean` over `slotsForDay(isTraining:)`.
4. Set quality: collapse `SetTags.isSetQuality` + app-target `SetQuality.parse` into one OnyxCore parser that accepts `+`.
5. Duration: `seedEventLog` stamps events with the set's real timestamp (fall back to set `created_at`); assert Pec Deck session no longer reads 2.0 min.
6. HRV ingest gate: reject/flag samples outside a MAD band of the 42-day baseline (`DailyLogIngest.swift:149`); InBody: `lean_mass` no longer outranks derived FFM; bound `body_fat` 2–70, `muscle_percent` 10–70, `visceral_fat` 1–30.
7. Golden fixtures Swift-owned (D7).
8. `docs/sql/w1-cleanup.sql`: drop `widget_tokens, notion_credentials, notion_exports, body_measurements, _bak_20260723`, RPC `exercise_history`. Founder pastes. `schema-truth-checker` lists tables before/after.
9. Save a memory file for this sprint: plan path, decisions, seams.
Gate: `invariant-auditor` on every scoring diff; tile and sheet show identical side-delt counts after a phone-logged Upper B.

**Shipped 2026-09-10 as v1.6.0 (`onyx/w1-truth`). Drift from the list above, on purpose:** task 3's `dayMean` restriction was NOT done — `Fatigue.dayMean` already averages only logged slots, and after `foldRows` a restriction could only drop modern off-kind answers (real data); the fix is the day kind (`AppDatabase.isTrainingDay` = logged OR scheduled) at the three fold sites. Task 6's `lean_mass` precedence is web-only (`dailyLog.ts:280`); native already derives FFM first. Task 5 carries the server `created_at` through `RemoteSetRow.createdAt` (decode-only) because local `workout_sets` has no timestamp column; `closeSession` ignores a clockless seed. HRV band is asymmetric (½ median below, 1× above). `schema`, `backfill`, `report`, `ship` are user-invoke-only skills and cannot be loaded by a wave prompt.
**Left for W4 (owner of `Features/Pulse`):** `PulseModel.isTraining` still reads the plan alone (offer training slots when a session is logged); `PulseModel.write` maps `BodyMetricError` to the generic "could not be saved" — show `error.description`. `IngestReport.declined` has no reader yet.

### W2 — Fable (extra high) · Generic data model · v1.7.0
Tasks: D1–D5 DDL in `docs/sql/w2-generic-model.sql` (routines, plan_phases, stress_logs, exercises columns, custom_supplements columns, cardio_logs.elevation_m); `supabase.json` + `gen-mirror-swift.mjs` `since:2`; `v21.genericModel`; `ExerciseIndex` slug column (D3); `SeedDumpTests` → `docs/sql/w2-seed-founder.sql`; readers switch from constants to rows (`TodayFeedBuilder:284`, `SettingsModel:241`, `PlanView:143`, `TargetResolver`, `PrTruth.floor` → `personal_records` rows, `LoggerModel` deck from `routines`, `Levers` → `daily_targets`); Stress `self` sub-term (D6) + `StressInputsBuilder` query + `STRESS_MODEL.md`; delete `Program.swift` decks, `Decks.swift`, `Phases.all`, `Levers.schedule`, `PrSeed`, `PrTruth.book`, `SupplementStack.protocolSeed` + 14 orphaned fixtures. Founder pastes both SQL files (model first, seed second).
Gate: `schema-truth-checker` confirms columns; app boots on the founder's account with identical logger deck, targets, phase label, lever, stack, PR floors (screenshot diff vs pre-wave).

**Shipped 2026-09-11 as v1.7.0 (`onyx/w2-generic`). Drift from D4, on purpose:** `Levers.schedule` becomes a `lever_periods` table (one row per period, `starts_on` / `profile_key` / pinned `goals`), not `daily_targets` rows per day — a `daily_targets` row means "the user shaped this day" and fifty-eight synthetic rows would bury the one real override; `Targets.resolve` is unchanged. Rungs are `target_profiles` rows with `kind` deficit/release. Routines are 14 rows (5+4+5), `plan_phase_volume` 96 (16 muscles × 2 phases × 3 plans). `plan_phase_goals` / `target_profiles` merge with `coalesce` so the founder's edited cut (1935 / 190 C) stays. The W2 columns on older tables are nullable in the local mirror (a pull before the paste must still decode). `plan-templates.json` (generated beside the seed) is W5's new-user template. The live DB has a second account (`21c7b986…`, 2026-09-08); every seed statement is scoped to the founder.
**Also decided in W2:** `ScheduleContext` carries `programs` / `plans` / `phases` (so the watch gets the deck in the context the phone already sends); the plan owning a date = the selected plan from the latest `started_on` any plan carries (the boundary `Era.forDate` cut on), the most recently started plan before that, the earliest-started plan before any began; `activatePlanRow` flips `plans.active` and dates a plan only on its FIRST activation. `user_goals.active_lever = "custom"` stays the sentinel for "my own numbers" (wins over the schedule for today+); changing the lever now writes a `lever_periods` row. Legacy predecessor-stamped ids resolve through `exercises.slug` (data), with a computed-slug and a normalised tier for a catalogue pulled before the DDL. The weekly export's programme line reads the plan row ("Onyx-5 Cut", was "Onyx Cut"). `PrSeed` is gone: a replay of a July 2026 session derives its records against the session-less floor rows, not the asserted book. `TargetProfiles.builtin` (Home/Restaurant) is gone — a new account has no day shapes until W5 seeds them. `NutritionPresets` (a second copy of the phase goals with no callers) is deleted.
**Review fixes after the paste (code-reviewer, 2026-09-11):** a keyless `lever_periods` row is pinned when the NEXT change closes it, never when it opens (today reads the live `user_goals` row); `personal_records.floor_value` (`docs/sql/w2-pr-floor-value.sql`, pasted third) keeps a beaten floor inside the record that beat it, and `retract` restores the floor row; a computed-slug collision throws `ambiguousExercise` instead of resolving to whichever row came first. **Known ceiling for W5's plan picker:** a plan holds ONE era (`plans.started_on`), so re-activating an older plan makes it own every date from the latest boundary; a switch-and-back needs an activation log — W5 should write a `plan_phases` row per activation and own dates inside the current era by phase before falling back to `started_on`.
**Every W4/W5 column exists live (schema-truth-checker, 2026-09-11):** routines.payload/accent/weekday/sort · plan_phases.start/kind/era_tag/first_week · lever_periods.starts_on/profile_key/goals · stress_logs.slot/level/tags/note · exercises.slug/secondary_muscles/rest_sec/rep_floor/rep_ceiling/archived_at · custom_supplements.form/dose_amount/dose_unit/sort_order/archived_at · cardio_logs.elevation_m/active_kcal/total_kcal · plans.blurb/is_legacy/sort/started_on · plan_phase_goals.label/fiber_g/body_fat_ceiling_pct · target_profiles.kind · personal_records.floor_value (pasted 2026-09-11, third file) · daily_logs.sleep_inaccurate/sleep_onset_trouble · workout_sets.elevation_m/quality. 33 public tables. Schema frozen.
**Left for W4/W5:** W4's stress "Head" row writes `stress_logs` (slot, level, tags, note); W4's stack list reads `custom_supplements.form/dose_amount/dose_unit/sort_order`; W5's onboarding inserts `plans` + `routines` + `plan_phase_goals` + `plan_phase_volume` from `native/Onyx/Resources/plan-templates.json`, `target_profiles` day shapes and rungs of its own, and the exercise catalogue with `slug`; the routine builder writes `routines.payload` (`RoutinePayload` v1) with `exerciseId` resolved by name through `ExerciseIndex.id(forName:)`.

### W3 — Opus (extra high) · Palette, atlas, Trends muscle focus · v1.8.0
Tasks: 8 families + stepped landmarks in `OnyxTokens.swift` (only hex writer); `MuscleFamily` 6→8; all 13 muscle-colour call sites; `forFamily` collapse removed; one accumulator (`TodayFeedBuilder.muscleFocus`) feeds tile, sheet, Trends; delete `MuscleAggregator`, `WidgetDerive.volumeByFamily`; `MuscleFocusAtlasCard` at top of Trends: `AtlasFigure(.both)` + per-landmark set numbers in the legend (make `TileSheets.legend` public), filter Week / Month / All / Current program (extend `EraWindow` with `.thisWeek` via `Week.startDay(fromEndDay:)` and `.currentProgram` via `plans.started_on`); widget tile grades against targets like the sheet; hand-edit `muscle-family.json`, `widget-family.json`, `volume-split.json`.
Gate: screenshot loop at 375 pt and AX5; `native-token-discipline` test green; Chest/Biceps/Triceps/Side delts distinguishable in one legend.

### W4 — Opus (extra high) · Fatigue, Stress, Stack, Reports, Quick Log · v1.9.0
Tasks: `PulseModel.isTraining` = `Schedule.isTrainingDayIn(context, date) || !loggedDays([date]).isEmpty` (W1 left it); surface `BodyMetricError.description` in `PulseModel.write`; Fatigue row → five equal targets Amazing/Good/Okay/Tired/Exhausted, one tap, sheet closes (D9); Stress row "Head" beside it: 5 levels + tag chips work/study/family/money/health/travel/other + note, writes `stress_logs`, Pulse tile shows the new sub-term; Stack: Apple-Health-style list on `custom_supplements` (add/edit/archive/delete, form pill/capsule/powder/liquid/gummy, dose amount+unit, archived section, swipe actions), `supplement_log` history untouched; Reports: native writer (`reports` upsert keyed `period_start`), "Add report" on every week without a row incl. current, `TextEditor` placeholder "Paste your AI coach reports…", Export PDF via `WKWebView.createPDF` on `ReportRenderer.html` + `ShareLink`; Dashboard mark → Quick Log radial (water, weigh-in, fatigue, stress, cardio, note) reusing existing sheets, keep "Done" in edit mode.
Gate: screenshot loop; VoiceOver labels on all five fatigue targets; PDF opens in Files.

### W5 — Opus (extra high) · Smart inputs, onboarding, routine builder · v2.0.0 (MAJOR: new-user path)
Tasks: Cardio sheet prefills active kcal, total kcal (active + basal over the session window), elevation, avg HR from HealthKit on open, all editable, `cardio_logs.elevation_m`; Body sheet prefills weight/BMI/fat/FFM from HealthKit, every % field shows "= xx.x kg" live; Onboarding after sign-up: bodyweight, week start, goal (cut/bulk/maintain), macros, per-muscle targets from an MEV table, optional 1RM per compound, plan picker (ONYX-5 / ONYX-4 / PPL / blank), exercise seed insert; Hevy-style routine builder over `routines` (days, exercises from catalogue, sets/reps/rest, reorder, duplicate day); CSV import into `exercises`.
Gate: fresh account on a simulator reaches the logger with a chosen routine and no founder data; founder account unchanged.

**Shipped 2026-09-11 as v2.0.0 (`onyx/w5-generic-ui`). Drift from the list above, on purpose:** there is no bundled `exercise-seed.json` (D2) — onboarding seeds the catalogue from the CHOSEN PLAN'S OWN movements, whose names are already in `plan-templates.json`; a second list would drift from the first, and a blank plan honestly seeds nothing rather than sixty rows nobody asked for. Per-muscle targets come from a new `VolumeLandmarks` MEV table, NOT from the templates' `volumeTargets`, which are the founder's tuned numbers. "Maintain" is not a third `ProgramPhase`: it trains on the cut's volume and eats at maintenance, which is how `active_lever` already models it. Macros use kcal/kg multipliers rather than Mifflin-St Jeor, because that equation needs sex and age and guideline 5.1.1 names both as over-collected. A 1RM seeds an `e1rm` floor only — "my bench is 100" is a claim about an estimate, not about a single.
**The gate caught a founder hardcode F8 missed:** `LoggerModel.withWarmupCardio` prepended `WarmupCardio` (a named treadmill, 0.37 km, 2 % incline, "Pace rising 4.3 to 5.0") to **every session of every account**. It is now gated on the athlete's catalogue holding the movement — safe for the founder because his phone-logged treadmill sets could not upload otherwise. The real fix wants `RoutineExercise` to carry `durationSec`/`inclinePct`/`distanceKm`, which D5 froze.
**`exercises` needed a bespoke push.** It is `"bespoke": true` in the schema because the local and Postgres tables share only `id` and `name`, so it cannot join `MirrorCatalogue.tables` (a generated row struct would be unsaveable locally, and `MirrorTests` counts 29). `MirrorCatalogue.pushable` — an extension, not a hand-edit of the generated file — adds it for `SyncEngine` only. Without it every locally created movement fails `unmirroredTable` forever and every set logged against it is rejected by the foreign key.
**Left for W6:** `ExerciseCatalog.exerciseCatalogStream`'s `HAVING COUNT(s.id) > 0` still hides an imported movement from the Exercises library until it has been trained (the importer says where they went instead). And `MuscleCredit.weightedSets` resolves by NAME through `MuscleMap`, while `MuscleMap.resolveMovers(_:stored:)` already takes a stored-tags fallback that **no credit call site passes** — so an imported movement with its own tags still earns zero until `TodayFeedBuilder.muscleFocus` and `WidgetSnapshotBuilder` pass them. W5 stores the tags and flags unclassified rows at import; wiring the fallback is a scoring change and wants `invariant-auditor`. `MuscleMap` also gained a bare `bench+press` entry — the table grew around a deck that never spelled it, so a flat bench credited nothing; both golden fixtures were hand-updated per D7.
**The `OnyxTests` baseline is 5, not 7** (verified by running the suite in a clean worktree of `main`): two week-window cases, the treadmill-slug title, the progression verdict, and a Keychain entitlement that only fails on a simulator.

### W6 — Fable (extra high) · Predecessor sunset + purge · v2.1.0
Tasks: D8 relocation + all three `--check` green; `site/` + `netlify.toml`; `delete_my_account()` caller in Settings → About; `git rm -r src ios public e2e netlify capacitor.config.ts next.config.ts postcss.config.mjs tailwind.config.ts eslint.config.mjs playwright.config.ts vitest.config.ts components.json next-env.d.ts vitest-env.d.ts`; `package.json` shrinks (D8); delete `.claude/skills/{capacitor-*,tanstack-query,nextjs-best-practices,react-best-practices,visual-check}`; predecessor-name purge of the ~40 shipping-native lines + docs, EXCLUDING its slug ids, its era wire value, its schema tag, `AppDatabase.swift:69-71` legacy names; rename `package.json` name to `onyx`; `README.md` rewritten for native-only; memory SUPERSEDED marks; `graphify update .`.
Gate: the predecessor-name grep over `native/ scripts/ docs/` returns only the allow-list; `curl` AASA JSON; app builds; `swift:core`/`swift:data` green.

## Copy-paste prompts

### W1 prompt
```
You are Fable (extra high effort), Lead Algorithm & Backend Strategist on Onyx. Read docs/EPIC_SPRINT_PLAN.md fully (Findings F1–F9, decisions D6–D7, Wave seams, W1). Execute W1 — the truth wave — exactly as listed. Do not touch UI, palette or schema beyond docs/sql/w1-cleanup.sql.

Skills to load first: graphify (query before grep), schema (before any SQL), backfill (dry-run discipline), native (build + typecheck rules), report (export grammar), git-commit-helper, ship.
Agents: schema-truth-checker (list live tables before and after the cleanup SQL; never read types.ts), invariant-auditor (every diff under OnyxCore/Scoring, Recovery, Sessions, Sync), debugger (the 2-minute duration and PGRST205 paths), code-reviewer (final diff).

Tasks 1–9 from the plan. For each bug: failing test first, then the smallest root-cause fix at the shared call site, then green. Branch onyx/w1-truth. Run patches from script files. Finish with the versioning gate (v1.6.0), changelog, graphify update .. Report: per task, the file:line changed, the test that proves it, and what the founder must paste into Supabase.
```

### W2 prompt
```
You are Fable (extra high effort), Lead Architecture & DB Strategist on Onyx. Read docs/EPIC_SPRINT_PLAN.md fully (F8, decisions D1–D7, Wave seams, W2). Execute W2 — the generic data model — so that no founder constant remains in OnyxCore and every reader takes rows.

Skills: graphify, schema, supabase-postgres-best-practices, backfill, native, git-commit-helper, ship, senior-architect, senior-backend.
Agents: schema-truth-checker (introspect before writing DDL; confirm after the founder pastes), supabase-schema-architect (RLS + indexes for routines, plan_phases, stress_logs), database-architect (review D1/D2/D4 mapping before coding), invariant-auditor (Stress self-term change, PR floor lookup, TargetResolver), swift-expert (v21 migration + ExerciseIndex), code-reviewer.

Order: DDL file → supabase.json + gen-mirror since:2 → v21.genericModel → SeedDumpTests → seed SQL → readers switched → Stress sub-term + STRESS_MODEL.md → delete constants + orphaned fixtures. Stop and tell the founder when each SQL file must be pasted; do not continue until schema-truth-checker sees the columns. Schema is frozen after this wave — list every column W4/W5 will need and confirm it exists. Branch onyx/w2-generic. Version v1.7.0. Report the founder-account parity screenshots (logger deck, targets, phase, lever, stack, PR floors) before and after.
```

### W3 prompt
```
You are Opus (extra high effort), Lead Frontend & Design on Onyx. Read docs/EPIC_SPRINT_PLAN.md fully (F6, F7, decision 4, D5 freeze, Wave seams, W3). Execute W3 — palette, atlas, Trends muscle focus. You own only the W3 seam files; do not edit Features/Pulse (except DomsMap), Features/Reports, LoggerModel.swift or any migration.

Skills: graphify, native (atlas is generated — never hand-edit OnyxAtlas.swift), apple-design, ui-design-system, ui-ux-pro-max, frontend-design, visual-check (screenshot loop, always pass SHOT_DERIVED), git-commit-helper, ship.
Agents: ui-ux-designer (review the 8-family ramp for distinguishability on a 56 pt widget figure and an AX5 legend), ios-developer, swift-expert (Color.onyx.muscle signature frozen, values change), invariant-auditor (the single muscleFocus accumulator), code-reviewer.

Tasks per plan W3. Palette lives only in OnyxTokens.swift; native-token-discipline must stay green. Trends gets MuscleFocusAtlasCard at the top with per-landmark set numbers and a Week / Month / All / Current program filter that respects user_goals.week_end_day. Branch onyx/w3-palette. Version v1.8.0. Report screenshots at 375 pt and AX5 of: widget tile, sheet, Trends card, Atlas sheet, exercise card rail.
```

### W4 prompt
```
You are Opus (extra high effort), Lead Frontend & UX on Onyx. Read docs/EPIC_SPRINT_PLAN.md fully (F9, decisions 3/5/6, D4 stack columns, D6, D9, Wave seams, W4). Execute W4 — fatigue, stress, stack, reports, Quick Log. You own Features/Pulse (not DomsMap), Features/Reports, Features/Today/TodayTabView.swift, OnyxData/Day, OnyxCore/Supplements. Feed additions go in a new TodayFeedBuilder+Stress.swift, never in TodayFeedBuilder.swift.

Skills: graphify, native, apple-design, ui-design-system, ui-ux-pro-max, ux-researcher-desginer, frontend-design, visual-check, report (reports grammar + PDF render), git-commit-helper, ship.
Agents: ui-ux-designer (fatigue words Amazing/Good/Okay/Tired/Exhausted — five equal targets, one tap, no coaching prose; stress "Head" row; Health-style stack list), ios-developer (WKWebView.createPDF + ShareLink, swipe actions), swift-expert, invariant-auditor (stress_logs write → StressInputsBuilder read), code-reviewer.

Tasks per plan W4. Native becomes the reports writer. Dashboard mark becomes Quick Log; "Done" stays in edit mode. Branch onyx/w4-loggers. Version v1.9.0. Report screenshots at 375 pt and AX5 for every new sheet and the Quick Log radial, plus a PDF opened in Files.
```

### W5 prompt
```
You are Opus (extra high effort), Lead Frontend & Product on Onyx. Read docs/EPIC_SPRINT_PLAN.md fully (F8, F9, decision 2, D1–D3, Wave seams, W5). W4 is merged. Execute W5 — smart inputs, onboarding, routine builder, CSV import. You own LoggerModel.swift, Features/Workout, Features/Settings, Features/Shell/RootView.swift, Features/Onboarding (new), Features/Routines (new).

Skills: graphify, native (HealthKit reader rules), apple-design, ui-design-system, ui-ux-pro-max, ux-researcher-desginer, frontend-design, visual-check, capacitor-apple-review-preflight (onboarding + HealthKit prompts must pass App Review copy rules), git-commit-helper, ship, senior-fullstack.
Agents: ios-developer (HealthKit prefill on sheet open, basal+active energy over a window), mobile-app-developer (onboarding flow), ui-ux-designer, swift-expert (routine builder over the routines jsonb payload; LoggerModel reads the deck from rows), invariant-auditor (MEV target table, 1RM → PR floor rows), code-reviewer.

Tasks per plan W5. A fresh account must reach the logger with a chosen routine and zero founder data; the founder's account must be unchanged. Branch onyx/w5-generic-ui. Version v2.0.0 (MAJOR). Report: simulator run of a brand-new account end to end, screenshots of every onboarding step and the routine builder.
```

### W6 prompt
```
You are Fable (extra high effort), Lead Architecture Strategist on Onyx. Read docs/EPIC_SPRINT_PLAN.md fully (F4, F5, decision 1, D7, D8, Manual checklists, W6). Execute W6 — the predecessor sunset and purge. Nothing in native/ may reference src/ or ios/ when you finish.

Skills: graphify (query for stragglers before every delete), native, schema, backfill, git-commit-helper, ship, senior-architect.
Agents: schema-truth-checker (tables before/after; confirm delete_my_account() still callable), architect-review (the relocated scripts/ + site/ layout), swift-expert (delete_my_account caller, OnyxLinks host), code-reviewer.

Order: relocate generators + all three --check green → site/ + netlify.toml → delete_my_account caller → git rm the web → package.json shrink → skills delete → predecessor-name purge EXCLUDING the load-bearing allow-list in F4 → README → memory SUPERSEDED → graphify update .. Stop and hand the founder the Netlify + Supabase checklist from the plan before deleting the Netlify build. Branch onyx/w6-sunset. Version v2.1.0. Report: the grep allow-list output, the AASA curl, and the final package.json.
```

## Verification (sprint level)
- After W1: log Upper B on the phone; tile and sheet both show side delts ≥ 3/7. Force a PGRST205 in `SyncEngineTests`; item held.
- After W2: `schema-truth-checker` lists routines, plan_phases, stress_logs, exercises.slug; founder screens identical.
- After W3: one legend shows Chest, Biceps, Triceps, Side delts as four distinguishable hues at 375 pt.
- After W4: stress logged → Pulse Stress tile term changes; PDF in Files.
- After W5: new account → logger with routine, no founder data.
- After W6: the predecessor-name grep over `native scripts docs` = allow-list only; AASA JSON; app builds; both Swift suites green.
