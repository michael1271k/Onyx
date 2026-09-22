# Onyx Expansion — Master Plan

> Canonical location after approval: `docs/Plan-Onyx-Expansion-Done.md`.
> Every wave prompt tells its agent to read that file first and to append a
> "Wave N Summary" to it when the wave closes.

## Context

Onyx is a native iOS + watchOS training/recovery app (`native/`, three Swift
packages, 535 Swift files / ~154k lines, GRDB store syncing to Supabase through
an outbox, event-sourced sets). Version 6.8.1 on `main`. This sprint expands the
Watch into a full logging + dashboard client, hardens retroactive logging,
profiles and trims the app, eradicates the predecessor web app's name from every
byte of the repo, and builds the AI-export path that was the app's original
purpose. Founder decisions (Phase 0, 2026-09-19) are recorded in §2 and are
final; wave agents do not re-open them.

### What the code already has (do not rebuild)

| Claim in the brief | Reality (file) |
|---|---|
| "Build real-time 2-way watch sync" | Exists. `SetEvent` log + Lamport clock (`OnyxData/Events/`), `WatchLink` over `transferUserInfo`/`sendMessage`/`updateApplicationContext` (`OnyxData/Watch/WatchLink.swift:29-40`), idempotent `ingest` (`EventStore.swift:328`), pencil ownership (`LiveSessionOwner.swift`). |
| "Read live HR + calories on watch" | Exists. `WorkoutSessionController` (`OnyxData/Watch/WorkoutSessionController.swift`) runs `HKWorkoutSession` + `HKLiveWorkoutBuilder`; `finishWorkout` writes the `HKWorkout`. Only avg bpm stored. |
| "Redesign sync for retroactive logging" | Nutrition already has a past-day `DatePicker` (`NutritionTabView.swift:151`) and write path. Missing: rescore call, past-date session creation (`LoggerModel.swift:2866-2877` blocks it), PR replay (`PrRecorder` only raises). |
| "Export to AI" | Exists both ways: `WeeklyExport` v5 markdown → `ShareLink` (`WeekDaysView.swift:266`, gated on complete week); paste-back → `ReportsListView` → PDF. |
| "Eradicate the predecessor name" | 56 files. Most are wire values (the `PhaseEra` raw value, the exercise-id prefix, the `.sqlite` store-move, the preference fallbacks). Founder chose full rename (19B). |

### Known gaps found in Phase 0 (each is owned by a wave below)

- Watch-logged sets are stranded from Supabase when the phone marks them synced and never re-queues the session (`Onyx/App/PhoneWatchBridge.swift:210-217`). → W2
- `MirrorRealtime` never retries a failed join (`MirrorRealtime.swift:175`). → W6
- No provenance filter on Health reads: a Hevy `HKWorkout` overlapping an Onyx session is adopted as measured truth (`OnyxData/Health/SessionMetrics.swift:38`). → W5
- Phone never writes to HealthKit (`HealthKitReader.swift:32`, `toShare: []`). → W5
- `WorkoutSessionController.cancel()` has no caller; watch has no pause/discard. → W3
- Cascade = up to 49 sequential day computations each reading a 48-day window (`OnyxData/Scoring/Rescore.swift`). → W2
- 193 synchronous main-actor DB reads in views; `NutritionModel` rebuilds 5 observations per date change; `WeekDaysView` rebuilds the export on every appearance; `WatchContext` ships ~25 KB per push (`WatchPayloads.swift:29`). → W6
- No watch simulator test, no simulator pair, zero `xcodebuildmcp` references in the repo. → W1
- Dead: `.agents/skills/` (5 web-era skills), `.claude/settings.local.json` predecessor allow-entries, `.claude/settings.json.graphify-bak`, `native/graphify-out/`, `scripts/add-supplement.mjs`, `OnyxCore/Sync/RealtimeKeys.swift`, `fmtV2.ts:18` banner, `NutritionGoldenTests.swift:24` shim, two stale plans in live `docs/`. → W1

## 1. Cross-wave laws

1. **Read this file first.** Then `native/README.md`, then the memory index if present. Then `graphify query` before grepping.
2. **Branch per wave off `main`**: `wave/N-<slug>`. Merge to `main` at wave close with the version bump. Never two waves in one checkout (memory: shared git index + shot-derived races). Always pass `SHOT_DERIVED` per worktree.
3. **Versioning is not optional** (CLAUDE.md). Decide bump from what shipped, set `package.json`, `npm run version:sync`, `cd native && xcodegen generate`, changelog section, `npm run version:check`. A wave without a bump and a changelog entry is not finished.
4. **Gates**: `npm run check` (types, atlas, mirror, doms, OnyxUI tests), `npm run swift:core`, `npm run swift:data`, `npm run check:swift` (iOS + watchOS cross-compile). OnyxTests app target: no NEW failures vs the baseline of 11 (memory `founder-constants-wave`).
5. **Fixtures are spec.** A formula change that moves a golden number is reviewed by `invariant-auditor` before the number is edited.
6. **Screens are proven by screenshot**, iPhone via `xcodebuildmcp` (`build_run_sim`, `snapshot_ui`, `screenshot`) and watch via the paired simulator. AX5 pass on any screen that shows text.
7. **Stop-and-show gate**: before closing, the agent STOPS, presents screenshots, explains briefly, asks approval. No merge before approval.
8. **Wave summary**: append `## Wave N Summary — <version>` (what worked / what failed / what is left open, ≤ 25 lines) to `docs/Plan-Onyx-Expansion-Done.md` and commit it with the merge.
9. **One hero per screen; nil is not 0; views read GRDB and nowhere else** (existing laws, still binding).
10. **No new dependency** for what a few lines do. No abstraction with one implementation.
11. **Watch budget**: every watch screen is laid out for 40 mm (162 × 197 pt). The paired watch simulator is an Ultra 2 49 mm, so a screenshot cannot prove the floor; the agent shoots on the pair AND asserts widths in a layout test at 162 pt.

## 2. Founder decisions (final)

| # | Decision |
|---|---|
| 1 | Reorder on watch = swipe actions "Do next" / "Skip". Drag is phone-only. |
| 2 | Watch dashboard = vertical pages Today / Train / Fuel reusing tile faces. |
| 3 | Watch controls: pause/resume, cancel, edit last set, swap from deck, add set. **Scrolling down on a set opens the Set Quality panel** (left/right split, quality reporter, warm-up / drop / failure kind) mirroring the iOS panel, designed compactly for the wrist. |
| 4 | HR on RestView (recovery curve) AND on SetView. Plus an in-workout HR widget on phone (Live Activity) and watch (Smart Stack). |
| 5 | Crown input stays as is; simple and compact. |
| 6 | Smart Stack live-workout widget this sprint. |
| 7 | Hevy stays in use. Never override a Hevy session. After finish, compare Onyx vs Hevy (avg HR, kcal, duration, set count) and show a one-card diff with **Skip**. Do not overthink. |
| 8 | Foreign strength workout overlaps → Onyx does not write its `HKWorkout`; keeps its own HR internally. |
| 9 | Phone-only session → phone writes an `HKWorkout`; HR/kcal from existing Health samples in the interval if present, else from an overlapping Hevy workout, else `Estimates`. |
| 10 | HR series read from Health at view time, no synced table. Prefetch on finish; local-only cache row after first successful read so the view never queries twice. |
| 11 | Rescore at the door (`AppDatabase.onCommit`) for any past-dated write, bounded: auto only for dates within 120 days; older → manual "Recompute" in Settings. |
| 12 | Retro workout entry point: History day → "Log a workout here". |
| 13 | PR correction = incremental per-exercise replay from the edit date. |
| 14 | Nutrition stays day-aggregate this sprint. |
| 15 | Watch strand fixed by phone re-queue of the session upsert on ingest. |
| 16 | Perf: signposts + Instruments on 8 seams AND full main-thread read purge, split across W2 (cascade) and W6 (everything else). |
| 17 | Cascade rewrite: one window read, in-memory compute, one transaction. |
| 18 | `LoggerModel` (3,048 lines) is not split this sprint. |
| 19 | **Full purge of the predecessor name including wire values**: era raw value → `"onyx"`, exercise-id prefix → `onyx-`, legacy store-move and pref fallbacks deleted, fixtures rewritten, docs rewritten. A repo-wide case-insensitive grep for that name must return zero (excluding `.git`). Supabase data migration SQL produced for the founder to paste. |
| 20 | Delete list §Context "Dead" — all of it. |
| 21 | Export gate: drop complete-week requirement; add "since last export". |
| 22 | AI: App Intent + Shortcuts AND Onyx MCP server, **sharing one serializer** (§W7). BYOK in-app call planned for a later sprint (§Appendix A). |
| 23 | Paste-back structured ingest: AI report → `lever_periods` / targets. Ideate + build. |
| 24 | Keep 5 tabs + gym mode. Bloat solved by density and de-duplication, not by hiding (§W6-B). |
| 25 | No hide-until-data. |
| 26 | Gym mode: session due → app opens into the logger, tab bar hidden until finish/cancel. |
| 27 | Enable `xcodebuildmcp` UI automation. |
| 28 | Eight waves as sketched. |

## 3. Wave map

| Wave | Title | Model | Expected version |
|---|---|---|---|
| W1 | Purge, predecessor-name eradication, simulator tooling | Opus 5 (Extra High) | 7.0.0 (data migration the user must be told about) |
| W2 | Sync core: retro logging, cascade, PR replay, watch strand | **Fable 5.1 (High)** | 7.1.0 |
| W3 | Watch live logger v2 | Opus 5 (Extra High) | 7.2.0 |
| W4 | Watch dashboard pages, Smart Stack, HR widgets | Opus 5 (Extra High) | 7.3.0 |
| W5 | Post-workout telemetry, Health provenance, Hevy compare | **Fable 5.1 (High)** | 7.4.0 |
| W6 | Lean: profiling, main-thread purge, compactification, gym mode | Opus 5 (Extra High) | 7.5.0 |
| W7 | AI export: gate, App Intent, MCP server, paste-back ingest | Opus 5 (Extra High) | 7.6.0 |
| W8 | Purge & merge | Opus 5 (Extra High) | 7.6.1 |

## 4. Tooling the founder enables before W1

1. `xcodebuildmcp` UI automation: ALREADY DONE — AXe at `/opt/homebrew/bin/axe`, `XCODEBUILDMCP_UI_AUTOMATION=1` in `~/.claude.json`, `snapshot_ui` available. (Reference: per https://xcodebuildmcp.com/docs/configuration enable the UI-automation workflow (needs AXe: `brew install cameroncooke/axe/axe`) in the server's `env` at `~/.claude.json` → `mcpServers.xcodebuildmcp`. Restart Claude Code. Verify `snapshot_ui` and `tap` tools appear.)
2. Paired simulator: ALREADY DONE — `Apple Watch Ultra 2 (49mm)` ↔ `iPhone 15`, pair `4DF6408A-6E99-43C3-95FE-7365ED491B90`, both booted. Verify with `xcrun simctl list pairs`.
3. Supabase SQL editor open: W1 and W2 hand you SQL to paste (DDL/DML cannot run from this machine).

---

## W1 — Purge, predecessor-name eradication, simulator tooling

**Goal.** Zero bytes of the predecessor name in the repo, dead files gone, and a paired
iPhone+Watch simulator harness that every later wave uses.

**Files / areas.**
- Rename wire values, with migration `v32.onyxWire` in `OnyxData/Database/AppDatabase.swift`:
  - `OnyxCore/Training/Phases.swift:24-27` `PhaseEra.onyx = "onyx"`; local `UPDATE plan_phases SET era='onyx'` for every non-`ppl` row; server SQL for the founder.
  - `OnyxData/Sync/ExerciseIndex.swift:203-235` prefix → `onyx-`; `LoggerModel.swift:336,2616` stamping; local `UPDATE workout_sets`, `UPDATE personal_records` if any slug-keyed rows remain (verify with `schema-truth-checker` FIRST), and a one-time rewrite of `set_events.payload` JSON `exerciseId` strings (documented exception to event immutability; golden test proves the fold output is byte-identical before/after). Server SQL for the same three tables.
  - `AppDatabase.swift:133-137,194,1040,1486,1535,1544`: delete the legacy App Group / sqlite store-move and the legacy-prefix migration query once the founder's device confirms `onyx.sqlite` exists (ask in the approval stop).
  - `OnyxData/Preferences/Preferences.swift:21-22` delete the legacy preference fallbacks.
  - Fixtures under `OnyxCore/Tests/OnyxCoreTests/Fixtures/*.json` and every `OnyxDataTests` file: mechanical rewrite of the legacy slug prefix → `onyx-`, the era raw value → `"onyx"`, and the older era tag → `onyx4`. `deep-link.json` legacy-scheme cases: delete (scheme is already `onyx`, `project.yml:190`).
  - `scripts/src/report/fmtV2.ts:18,470-471` then `npm run report:bundle`; `NutritionGoldenTests.swift:24` shim deleted.
  - Docs: rewrite `docs/CHANGELOG.md`, `docs/Done/*`, `docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md`, `native/README.md`, comments in `SessionSeed.swift`, `TrainingPuller.swift`, `SessionHistoryStore.swift`, `TrainingTrendsStore.swift`, `PrRecorder.swift`, `WidgetSnapshotBuilder.swift`, `SessionAnalysis.swift`, `WorkoutWeek.swift` → "the predecessor web app".
- Delete: `.agents/skills/`, predecessor/netlify/`src/` entries in `.claude/settings.local.json`, `.claude/settings.json.graphify-bak`, `native/graphify-out/`, `scripts/add-supplement.mjs`, `OnyxCore/Sources/OnyxCore/Sync/RealtimeKeys.swift` (+ its test if any). Move `docs/LIVE_UX_SPRINT_PLAN.md`, `docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md` → `docs/Done/`.
- Tooling: `scripts/watch-shot.sh` (pattern of `scripts/native-shot.sh`; drives `ONYX_WATCH_SCREEN`/`ONYX_WATCH_AUTOSTART` env already read in `OnyxWatchApp.swift:49,81`; add screens `start`, `set`, `rest`, `deck`, `dashboard`, `finish`); `npm run check:watch` = `xcodebuild build -scheme OnyxWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)'`; `.mcp.json` documents `xcodebuildmcp` session defaults (project `native/Onyx.xcodeproj`, scheme `Onyx`, simulator `iPhone 15`); a `docs/SIMULATORS.md` runbook (pairing, both shot scripts, `SHOT_DERIVED` rule).
- `graphify update .` at the end.

**Gate.** A repo-wide case-insensitive grep for the predecessor name (`--exclude-dir=.git --exclude-dir=node_modules`) returns 0 lines. All four test gates green. Watch and phone screenshots from the paired pair. Version 7.0.0, changelog names the data migration and the SQL the founder pasted.

### W1 PROMPT (copy/paste)

```
Model: Opus 5 (Extra High Effort)

You are executing Wave 1 of the Onyx Expansion sprint. Read docs/Plan-Onyx-Expansion-Done.md FIRST, in full, then native/README.md. Then run `graphify query` for each area before grepping. Follow every cross-wave law in §1 and every founder decision in §2 — they are final.

Load these skills now: native, graphify, git-commit-helper, ship, schema, supabase-postgres-best-practices.
Use these agents: schema-truth-checker (BEFORE any rename — count live rows carrying the legacy era value in plan_phases.era, and legacy-prefixed exercise ids in workout_sets / personal_records / set_events payloads), caveman:cavecrew-investigator (locate every occurrence), invariant-auditor (review the set_events payload rewrite and the fold golden), code-reviewer (final diff).

Branch: `git checkout -b wave/1-purge` off main. Export SHOT_DERIVED to a wave-specific path.

Do, in this order:
1. Inventory: run the repo-wide case-insensitive grep for the predecessor name (exclude .git, node_modules). Classify every hit against §W1 "Files / areas". Print the table.
2. Data migration v32.onyxWire in AppDatabase (append-only migration; never edit a registered one). Local UPDATEs for plan_phases.era, workout_sets.exercise_id, personal_records if slug-keyed, and a one-time rewrite of set_events.payload exerciseId strings. Write a test that folds a fixture session before and after the rewrite and asserts identical WorkoutSet output. Produce docs/sql/w1-onyx-wire.sql with the equivalent Supabase UPDATEs for the founder to paste; do not attempt to run it.
3. Rename constants and stamping sites (Phases.swift, ExerciseIndex.swift, LoggerModel.swift), rewrite all fixtures and tests mechanically, delete the legacy-scheme deep-link cases, delete the legacy store-move code and pref fallbacks ONLY after asking the founder in the approval stop whether their device already runs onyx.sqlite.
4. Purge the dead list in §W1 and move the two stale plans to docs/Done/. Rewrite every doc and comment so the predecessor is "the predecessor web app".
5. Rebuild the report renderer: edit scripts/src/report/fmtV2.ts, run `npm run report:bundle`.
6. Tooling: write scripts/watch-shot.sh, add `check:watch` to package.json, write docs/SIMULATORS.md, record xcodebuildmcp session defaults. Verify the simulator pair exists (`xcrun simctl list pairs`); if not, print the pair commands from §4 and stop until the founder runs them.
7. Verify with xcodebuildmcp: session_show_defaults, build_run_sim for the Onyx scheme on iPhone 15, snapshot_ui + screenshot of Today, Train and History; run scripts/watch-shot.sh on Apple Watch Ultra 2 (49mm) for start/set/rest/dashboard. Run `npm run check`, `npm run swift:core`, `npm run swift:data`, `npm run check:swift`, `npm run check:watch`. Run the OnyxTests scheme and confirm no new failures over the baseline of 11.
8. Gate: the predecessor-name grep count must be 0. If it is not, you are not done.
9. Versioning: 7.0.0 (the data migration the user must be told about). package.json → `npm run version:sync` → `cd native && xcodegen generate` → changelog section naming the surfaces AND the SQL file → `npm run version:check`.
10. `graphify update .`

STOP and present screenshots of your work to the user. Explain briefly what you did. Ask for approval before proceeding to finish the wave. Ask specifically: (a) has docs/sql/w1-onyx-wire.sql been pasted into Supabase, (b) does the device already run onyx.sqlite.

After approval: commit, merge wave/1-purge into main, append "## Wave 1 Summary — 7.0.0" (what worked, what failed, what is left open) to docs/Plan-Onyx-Expansion-Done.md, commit that, do not push.
```

---

## W2 — Sync core: retroactive logging, cascade, PR replay, watch strand

**Goal.** Logging anything for a past day (food, water, weight, workout, sleep
edit) produces correct scores, PRs and server rows, from any device, with a
cascade that is one read and one transaction.

**Design.**
- **Rescore at the door.** In `AppDatabase` (the single commit observer `onCommit`, already used by widgets and `PhoneWatchBridge`): every write transaction records the minimum `date` it touched (a `TransactionObserver` on the date-bearing tables: `workout_sessions`, `nutrition_entries`, `daily_logs`, `sleep_*`, `stress_logs`, `doms_*`, `body_*`). If that date `< today` and `>= today − 120 d`, enqueue `RescoreQueue.request(from:reason:.dayEdit)`. Older dates set a flag surfaced in Settings → "Recompute history". Delete the per-caller `rescore` calls that the door now covers (LiveLoggerView, FinishSheet, PulseModel, water drain) — keep only the `.migration` and `.manual` callers.
- **Cascade rewrite** (`OnyxData/Scoring/Rescore.swift`, `DailyScoreStore.swift`, `ReadinessHistoryBuilder.swift`): read `[from − 48 d, through]` once, compute every day in memory with the same domain functions, write all `daily_scores` rows in one transaction with `force: true`. Golden: existing `RescoreTests` + a new vector proving per-day output equals the old sequential path on the `PreviewCatalogue` seed.
- **PR incremental replay** (`OnyxData/Training/PrRecorder.swift`): `replay(exerciseId:from:)` deletes PR rows for that exercise dated ≥ from, re-derives from `workout_sets` in date order, enqueues upserts/deletes. Triggered by the door when the touched table is `workout_sets`/`set_events` and the date is past.
- **Past-date session** (`LoggerModel.swift:2866-2877`): `ensureSession(date:)`; entry point History day view "Log a workout here" (`Onyx/Features/History/WeekDaysView.swift` day row → `WorkoutTabView` in `.retro(date)` mode: no rest timer, no Live Activity, no watch mirror, ended_at = started_at + entered duration).
- **Watch strand** (`Onyx/App/PhoneWatchBridge.swift:200-220`): on `.events` ingest, `enqueueSessionUpsert(sessionId)` so the projection reaches Supabase without waiting for a phone touch. Test in `WatchConvergenceTests`.
- **Signposts** for the cascade only (`os_signpost` "rescore.run"), so W6 can compare.

**Gate.** `swift:data` green with new tests: door enqueues for past date, ignores today, ignores > 120 d; PR replay fixture (heavier set logged a week late corrects an interim PR); cascade parity vector; strand test. Manual proof on simulator via xcodebuildmcp: log macros for 3 days ago → `daily_scores` row changes (Sync Doctor screen shows the ledger); create a retro workout; edit a set from last week and watch PR change.

### W2 PROMPT (copy/paste)

```
Model: Fable 5.1 (High Effort)

You are executing Wave 2 of the Onyx Expansion sprint. Read docs/Plan-Onyx-Expansion-Done.md FIRST (all of it, then the Wave 1 Summary), then native/README.md, then `graphify explain RescoreQueue`, `graphify explain DailyScoreStore`, `graphify explain PrRecorder`, `graphify explain PhoneWatchBridge`. Founder decisions §2 are final (11, 12, 13, 15, 17).

Load these skills now: native, graphify, schema, backfill, supabase-postgres-best-practices, git-commit-helper, ship.
Use these agents: schema-truth-checker (confirm live columns before any SQL), invariant-auditor (MANDATORY review of the cascade rewrite and of any golden vector change), database-architect (review the door observer design), debugger (if parity fails), code-reviewer.

Branch: `git checkout -b wave/2-sync-core` off main. Wave-specific SHOT_DERIVED.

Do, in this order:
1. Read Rescore.swift, DailyScoreStore.swift, ReadinessHistoryBuilder.swift, ScoringInputsBuilder.swift, PrRecorder.swift, SessionEditing.swift, PhoneWatchBridge.swift, LoggerModel.swift:2860-2920, WeekDaysView.swift. Write the list of every current `rescore(` caller.
2. Cascade rewrite (§W2 Design): one window read, in-memory per-day compute using the SAME domain functions, one write transaction. Prove parity with a test that runs old and new on the PreviewCatalogue seed for a 60-day range and asserts identical daily_scores rows. Only then delete the old path.
3. Rescore at the door: TransactionObserver in AppDatabase collecting the minimum touched date per commit; enqueue when past and within 120 days; set the "history stale" flag otherwise; Settings row "Recompute history" runs a manual full cascade. Remove the now-redundant per-caller calls. Tests: enqueues for past, not today, not >120 d, coalesces N writes to one request.
4. PR incremental replay per exercise from the edit date; door triggers it for set writes on past dates. Test: heavier set logged a week late removes the interim PR and inserts the correct one; server outbox gets the delete + upsert.
5. Past-date session creation: ensureSession(date:), History day row → "Log a workout here", retro logger mode (no timer, no Live Activity, no watch mirror). Test in LoggerModelTests.
6. Watch strand: enqueue the session upsert on watch-event ingest. Test in WatchConvergenceTests.
7. os_signpost "rescore.run" around the cascade; record before/after duration for 49 days in the wave summary.
8. If any server column is needed, write docs/sql/w2-*.sql for the founder; do not run it.
9. Verify: `npm run swift:core`, `npm run swift:data`, `npm run check`, `npm run check:swift`; OnyxTests no new failures over baseline 11. Then with xcodebuildmcp on the paired iPhone 15: build_run_sim, log macros for a date 3 days back, open Settings → Sync Doctor and screenshot the rescore ledger; create a retro workout from History and screenshot it; edit a week-old set to a heavier load and screenshot the PR bar before/after.
10. Versioning 7.1.0, changelog, version:check, `graphify update .`.

STOP and present screenshots of your work to the user. Explain briefly what you did. Ask for approval before proceeding to finish the wave.

After approval: commit, merge wave/2-sync-core into main, append "## Wave 2 Summary — 7.1.0" (what worked, what failed, what is left open; include the cascade timing) to docs/Plan-Onyx-Expansion-Done.md, commit, do not push.
```

---

## W3 — Watch live logger v2

**Goal.** The wrist logs a full session without the phone: pause/resume,
cancel, swipe reorder, edit last set, add set, swap movement, set quality
panel, HR on set and rest.

**Design (apple-design + ui-ux-pro-max applied).**
- **Set Quality panel by scroll-down** (decision 3). `SetView` becomes a vertical `ScrollView` with two pages via `scrollTargetBehavior(.paging)`: page 1 = current set (unchanged crown rows + tick), page 2 = quality panel. Crown focus must stay on the load/reps rows while on page 1; on page 2 the crown scrolls the list. Panel content, in this order and no more: **Kind** segmented row (Work / Warm-up / Drop / Failure — 4 capsules, one line at 40 mm), **Side** row for unilateral movements only (L / R / Both), **Quality** row as the phone's `SetQuality` set rendered as toggle chips in a `FlowRow`-free 2-column grid (watch has no FlowRow; use `LazyVGrid` with 2 columns). Every choice writes an `amend` event immediately (`WatchModel.amendLast(patch:)`), no Save button. Page indicator: the system dot on the right edge; a 12 pt chevron hint under the tick on page 1 for first-run discoverability, gone after the first scroll (UserDefaults flag in the watch suite).
- **Pause/resume**: toolbar item on `SetView` and `RestView` writes `.pause`/`.resume` events (already exist in `SetEvent.Body`); `WorkoutSessionController.pause()/resume()` on the HK session; elapsed timer honours pauses (mirrors phone `PauseControlling`).
- **Cancel**: long-press on the timer → confirmation → `WorkoutSessionController.cancel()` (finally gets its caller) + `store.voidSession` equivalent (check `LoggerModel.cancel:2057` for the store call) + `releasePencil`.
- **Deck swipe actions** (`DeckView`): leading "Do next" (moves movement to cursor+1, amends `exerciseOrder` on done rows exactly like `LoggerModel.moveExercise:1383` — extract the shared arithmetic into OnyxCore `DeckOrder.move(from:to:)` if not already pure), trailing "Skip" (marks movement skipped for this session; skipped movements sink to the bottom and show a slash). Tapping a movement row jumps the cursor to it (replaces "nothing tappable").
- **Edit last set**: `RestView` receipt row is tappable → small sheet with the two crown rows, writes an `amend`. **Add set**: "+" in `SetView` toolbar appends one planned set to the current movement (local plan only, not a routine edit). **Swap movement**: `DeckView` row context menu "Swap…" → list of same-muscle catalogue names from `WatchContext.schedule` (already contains programs); writes the plan swap the phone already understands (`ScheduleResolution`), never mints a catalogue id (law from `WatchModel.swift:374`).
- **HR**: `SetView` title trailing shows `♥ 142` from `workout.heartRate` (nil → dash); `RestView` shows a 60-second HR sparkline (`Chart` with `LineMark` on samples buffered in `WorkoutSessionController.recentSamples`, capped at 60 points) with the current bpm and the delta since rest began.
- Haptics: `.directionUp` on page change to quality, `.click` on kind change, `.success` on tick (exists).
- Reduce-motion and luminance-reduced states respected (existing `isLuminanceReduced` handling extends to the panel).

**Files.** `OnyxWatch/Views/SetView.swift`, `RestView.swift`, `DeckView.swift`, new `SetQualityPanel.swift`, `OnyxWatch/App/WatchModel.swift`, `OnyxData/Watch/WorkoutSessionController.swift` (pause/resume/recentSamples), `OnyxCore` (pure deck-order move if extracted), tests `WatchPayloadTests`/`WatchConvergenceTests`, new `OnyxWatchLayoutTests` asserting the panel fits 162 pt.

**Gate.** Layout test at 162 pt; `check:watch`; screenshots on Ultra 2 49 mm of: set page, quality page, deck with swipe revealed, rest with sparkline, pause state, cancel confirm; same set ticked on watch appears on the paired iPhone within seconds (screenshot both).

### W3 PROMPT (copy/paste)

```
Model: Opus 5 (Extra High Effort)

You are executing Wave 3 of the Onyx Expansion sprint. Read docs/Plan-Onyx-Expansion-Done.md FIRST (all, plus Wave 1–2 Summaries), then native/README.md, then `graphify explain WatchModel`, `graphify explain SetView`, `graphify explain WorkoutSessionController`, `graphify explain SetEventFold`. Founder decisions §2 are final (1, 3, 4, 5).

Load these skills now: native, graphify, apple-design, ui-ux-pro-max, ui-design-system, git-commit-helper, ship.
Use these agents: swift-expert (SwiftUI watchOS paging + crown focus), ios-developer, ui-ux-designer (review the quality panel screenshots at 49 mm before you show the founder), invariant-auditor (deck-order arithmetic extraction), code-reviewer.

Branch: `git checkout -b wave/3-watch-logger` off main. Wave-specific SHOT_DERIVED.

Do, in this order:
1. Read the whole native/OnyxWatch target (7 files, ~2k lines) and the phone's set-quality UI (ExerciseCardView.swift, search SetQuality / SetKind / side) so the watch panel mirrors the phone's vocabulary exactly — same kinds, same qualities, same side labels.
2. Build the Set Quality panel as page 2 of a paging ScrollView under SetView per §W3 Design. Each choice writes an amend event immediately. Crown focus stays on load/reps on page 1. Write OnyxWatchLayoutTests asserting every row fits 162 pt.
3. Pause/resume events + HK session pause; cancel path (WorkoutSessionController.cancel finally gets a caller); elapsed timer honours pauses.
4. DeckView: tap-to-jump, leading "Do next", trailing "Skip". Reuse the phone's exerciseOrder amend arithmetic; if it is not pure, extract it to OnyxCore with a golden vector.
5. Edit last set from the RestView receipt; "+" add set; "Swap…" from the deck restricted to WatchContext.schedule names.
6. HR on SetView title and a 60-point sparkline on RestView from WorkoutSessionController.recentSamples.
7. Verify: `npm run check`, `npm run swift:core`, `npm run swift:data`, `npm run check:swift`, `npm run check:watch`; OnyxTests no new failures over baseline 11. Then with xcodebuildmcp: build_run_sim the Onyx scheme on the paired iPhone 15 AND build the OnyxWatch scheme onto Apple Watch Ultra 2 (49mm) (paired); use ONYX_WATCH_AUTOSTART=1 to enter a session; screenshot set page, quality page, deck with swipe actions revealed, rest with sparkline, pause, cancel confirm. Tick a set on the watch and screenshot the iPhone logger showing it. Run scripts/watch-shot.sh for the full set.
8. Versioning 7.2.0, changelog, version:check, `graphify update .`.

STOP and present screenshots of your work to the user. Explain briefly what you did. Ask for approval before proceeding to finish the wave.

After approval: commit, merge wave/3-watch-logger into main, append "## Wave 3 Summary — 7.2.0" to docs/Plan-Onyx-Expansion-Done.md, commit, do not push.
```

---

## W4 — Watch dashboard pages, Smart Stack, HR widgets

**Goal.** The watch shows Today / Train / Fuel without the phone in hand, a
live-workout Smart Stack widget, and both devices show HR while training.

**Design.**
- **Dashboard** replaces `DashboardView` text rows with a vertical `TabView(.verticalPage)` of three pages, each drawing the existing accessory tile faces (`OnyxTile.accessory`, `WatchTiles` payload, 2 KB budget pinned by `WatchTilesTests`) at rectangular size stacked 2–3 per page: Today (battery, sleep, readiness), Train (next session, week volume / sets done), Fuel (kcal remaining, protein remaining, water with a "+1 glass" button that writes through the same `AddWaterIntent` path the phone widget uses). Reached from `StartView` toolbar (exists) and from a long-press on the timer during a session.
- **`WatchTiles` grows only if a face needs a field that is not there**; if so extend `OnyxCore/Widget/WatchTiles.swift` with optional-and-last fields and re-pin the byte budget.
- **Smart Stack live workout**: `OnyxWatchWidgets` gains an eleventh entry? No — the bundle is at the 10-widget ceiling (`OnyxWatchWidgets.swift:11`). Replace the least-used dashboard complication (decide with the founder at the stop; default: the `.accessoryInline` duplicate) with a `WorkoutLiveWidget` using `RelevanceKit` (`RelevantIntentManager`) so it surfaces in the Smart Stack while a session is live: movement, set n/m, HR, rest countdown. Data path: the watch app writes a `LiveWorkoutSnapshot` (small Codable) to the watch App Group suite on every commit and rest pulse; the widget reads it; timeline `.never` + reload on write (same pattern as `WatchTiles`).
- **Phone HR in Live Activity**: `Shared/OnyxWorkoutAttributes.swift` ContentState gets optional `bpm: Int?`; `LiveActivityController.update` fills it from `PhoneWatchBridge.liveBpm` (exists, 120 s staleness); `WorkoutActivityCard` draws it on the rest band and the Dynamic Island compact trailing. All ContentState fields stay Optional (law from `ux-architecture-sprint`).
- **Watch HR complication** during workout = the same `LiveWorkoutSnapshot` on `.accessoryCircular`.

**Files.** `OnyxWatch/Views/DeckView.swift` (DashboardView), new `DashboardPages.swift`, `OnyxWatchWidgets/OnyxWatchWidgets.swift`, new `LiveWorkoutSnapshot.swift` in OnyxCore/Widget, `Shared/OnyxWorkoutAttributes.swift`, `Shared/WorkoutActivityCard.swift`, `Onyx/Features/Logger/LiveActivityController.swift`, tests `WatchTilesTests`, `OnyxWatchLayoutTests`.

**Gate.** Screenshots: three dashboard pages at 49 mm, Smart Stack widget in a live session (simulator: `simctl` cannot force Smart Stack; screenshot the widget via the widget gallery/preview and the complication face), Live Activity on the iPhone lock screen with bpm, Dynamic Island compact.

### W4 PROMPT (copy/paste)

```
Model: Opus 5 (Extra High Effort)

You are executing Wave 4 of the Onyx Expansion sprint. Read docs/Plan-Onyx-Expansion-Done.md FIRST (all, plus Wave 1–3 Summaries), then native/README.md, then `graphify explain WatchTiles`, `graphify explain OnyxWatchWidgets`, `graphify explain LiveActivityController`, `graphify explain WorkoutActivityCard`. Founder decisions §2 are final (2, 4, 6).

Load these skills now: native, graphify, apple-design, ui-ux-pro-max, ui-design-system, git-commit-helper, ship.
Use these agents: swift-expert (WidgetKit on watchOS, RelevanceKit, ActivityKit ContentState evolution), ios-developer, ui-ux-designer (review the three pages at 49 mm and the Live Activity before showing the founder), code-reviewer.

Branch: `git checkout -b wave/4-watch-dashboard` off main. Wave-specific SHOT_DERIVED.

Do, in this order:
1. Read WatchTiles.swift and its byte-budget test, OnyxWatchWidgets.swift, OnyxTile accessory faces in OnyxUI, WorkoutActivityCard.swift, OnyxWorkoutAttributes.swift, LiveActivityController.swift, PhoneWatchBridge.liveBpm.
2. Dashboard: vertical page TabView with Today / Train / Fuel pages built from existing tile faces; water +1 via the existing AddWaterIntent path; entry from StartView toolbar and long-press on the session timer. Extend WatchTiles only with optional-and-last fields and re-pin the budget.
3. LiveWorkoutSnapshot (OnyxCore/Widget): tiny Codable written to the watch App Group suite by WatchModel on commit and rest pulse. Smart Stack live widget with RelevanceKit relevance while a session runs; it replaces one existing bundle slot (bundle ceiling is 10) — propose which at the approval stop, default the inline duplicate.
4. Live Activity bpm: optional ContentState field, filled from liveBpm, drawn on the rest band and Dynamic Island compact trailing. Every ContentState field stays Optional; add a decode test with the field missing.
5. Verify: `npm run check`, `npm run swift:core`, `npm run swift:data`, `npm run check:swift`, `npm run check:watch`; OnyxTests no new failures over baseline 11. xcodebuildmcp: build_run_sim both paired devices; screenshot the three dashboard pages at 49 mm; start a session (ONYX_WATCH_AUTOSTART=1) and screenshot the live widget face and the circular HR complication; on the iPhone screenshot the Live Activity on the lock screen and the Dynamic Island with bpm. Run scripts/watch-shot.sh.
6. Versioning 7.3.0, changelog, version:check, `graphify update .`.

STOP and present screenshots of your work to the user. Explain briefly what you did. Ask for approval before proceeding to finish the wave. Ask which bundle slot the live widget should take.

After approval: commit, merge wave/4-watch-dashboard into main, append "## Wave 4 Summary — 7.3.0" to docs/Plan-Onyx-Expansion-Done.md, commit, do not push.
```

---

## W5 — Post-workout telemetry, Health provenance, Hevy compare

**Goal.** Post-workout summary shows an exercise-segmented HR graph and
accurate kcal; Onyx never overrides Hevy in Health; phone-only sessions get a
workout in Health.

**Design.**
- **Provenance filter** (`OnyxData/Health/HealthKitReader.swift:151-175`, `SessionMetrics.swift:26-70`): `workouts(start:end:)` returns `sourceBundleId` per workout; `SessionMetrics` classifies overlapping workouts as `.own` (bundle == app's) or `.foreign(name)`. Own wins for measured metrics. Foreign never silently adopted.
- **Hevy compare card** (decision 7): on finish, if a `.foreign` strength workout overlaps [started_at − 10 min, ended_at + 10 min]: `FinishSheet` shows one card "Hevy logged this too" with four rows (avg HR, kcal, duration, sets — Onyx vs Hevy; Hevy sets = `HKWorkout` metadata if present else "—"), one primary button **Skip** (keeps Onyx numbers, writes nothing to Health) and one secondary "Use Hevy HR/kcal" (adopts the two numbers as measured, still writes nothing). Card also appears in `SessionDetailView` for past sessions the puller finds overlapping. Golden vector for the overlap predicate.
- **Phone writes HKWorkout** (decision 9): new `OnyxData/Health/WorkoutWriter.swift` using `HKWorkoutBuilder` on iOS, `.traditionalStrengthTraining`, called from `FinishSheet` only when no watch HK session ran for this session AND no foreign overlap. HR: attach existing HR samples in the interval only if they come from a source Onyx may cite (Apple Watch passive, not Hevy); kcal: existing samples if any, else `Estimates` written as `activeEnergyBurned` with metadata `HKMetadataKeyWasUserEntered = false` and Onyx's own `estimated = true` key. Entitlement: add `HKObjectType.workoutType()` to share types on iOS (`HealthKitReader.requestAuthorization`).
- **HR series read at view time + prefetch + local cache** (decision 10): `SessionTelemetry` actor: `series(for session)` → `HKSampleQuery` heartRate `predicateForObjects(from: ownWorkout)` (fallback: interval predicate with own-source filter) → `[HRSample(t, bpm)]`. Segmenting: `set_events` timestamps (append `created_at`, pause/resume) → `[Segment(exerciseName, start, end, avg, max)]`; rests are gaps. Prefetch: watch calls `series` right after `workout.end()` inside `finish()`; phone calls it in `FinishSheet.onAppear` and in `SessionDetailView.task`. Cache: local-only table `session_telemetry(session_id PK, series_json, segments_json, source, fetched_at)` written after the first successful non-empty read; never synced; never blocks — the view renders skeleton bars until the actor publishes. Samples arriving late from the watch via Health sync: `HKObserverQuery` on heartRate for 10 minutes after finish triggers one refetch if the cache is empty.
- **Graph**: Swift Charts `AreaMark`+`LineMark` per segment with the segment name on a `RuleMark` at each boundary, current-set colour from the muscle palette (existing 16 hexes), rest gaps in ink-2. Max 1 chart, 1 hero number (avg HR), 2 captions (peak, kcal). Card in `FinishSheet` and `SessionDetailView`. AX5: chart hides labels, keeps the three numbers.
- **`SessionMetrics` estimation** unchanged; measured never overwritten by estimate (existing law).

**Gate.** Golden vectors: overlap classification, segmenting from an event fixture with pauses, own-vs-foreign precedence. Simulator: HealthKit on simulator works with synthetic data — the agent seeds an own workout + HR samples via a DEBUG-only `TelemetrySeed` (`#if DEBUG`, launch arg) and a Hevy-bundle-tagged workout cannot be seeded (source is the writer), so the compare card is proven with a fixture-driven preview screen in `PreviewHarness` and the predicate golden.

### W5 PROMPT (copy/paste)

```
Model: Fable 5.1 (High Effort)

You are executing Wave 5 of the Onyx Expansion sprint. Read docs/Plan-Onyx-Expansion-Done.md FIRST (all, plus Wave 1–4 Summaries), then native/README.md, then `graphify explain SessionMetrics`, `graphify explain HealthKitReader`, `graphify explain FinishSheet`, `graphify explain SessionDetailView`, `graphify explain WorkoutSessionController`. Founder decisions §2 are final (7, 8, 9, 10).

Load these skills now: native, graphify, apple-design, ui-ux-pro-max, git-commit-helper, ship.
Use these agents: swift-expert (HKWorkoutBuilder on iOS, HKSampleQuery/HKObserverQuery, Swift Charts), invariant-auditor (MANDATORY: overlap predicate, segmenting arithmetic, own-vs-foreign precedence, estimate-never-overwrites-measured), ios-developer, ui-ux-designer (review the chart card at default and AX5), debugger, code-reviewer.

Branch: `git checkout -b wave/5-telemetry` off main. Wave-specific SHOT_DERIVED.

Do, in this order:
1. Read HealthKitReader.swift, SessionMetrics.swift, HealthSync.swift, CardioImport.swift (the uuid dedupe pattern), WorkoutSessionController.swift, FinishSheet.swift, SessionDetailView.swift, SetEvent.swift (pause/resume), the muscle palette in OnyxUI.
2. Provenance: return sourceBundleId from workouts(start:end:); SessionMetrics classifies own vs foreign; foreign is never silently adopted. Golden vector for classification and precedence.
3. Hevy compare card in FinishSheet and SessionDetailView per §W5 Design: four rows, primary Skip, secondary "Use Hevy HR/kcal", writes nothing to Health either way. Do not overthink it.
4. WorkoutWriter on iOS: HKWorkoutBuilder, only when no watch HK session ran and no foreign overlap; HR/kcal sourcing order per decision 9; add workoutType to iOS share types. Test the guard logic with a fake reader.
5. SessionTelemetry actor: Health read at view time, prefetch on finish (watch and phone), local-only session_telemetry cache table written after the first non-empty read, HKObserverQuery refetch window of 10 minutes for late-arriving watch samples, never blocks rendering. Segment by set_events timestamps honouring pause/resume; golden vector from an event fixture.
6. Segmented HR chart card (one chart, one hero, two captions) in FinishSheet and SessionDetailView; AX5 variant keeps the numbers only.
7. DEBUG TelemetrySeed launch arg that writes an own workout + HR samples into the simulator's Health store so the chart can be photographed; PreviewHarness screen for the Hevy card driven by a fixture.
8. Verify: `npm run check`, `npm run swift:core`, `npm run swift:data`, `npm run check:swift`, `npm run check:watch`; OnyxTests no new failures over baseline 11. xcodebuildmcp on the paired iPhone 15: run with the TelemetrySeed arg, finish a session, screenshot the FinishSheet chart at default and AX5, screenshot SessionDetail for the same session on second open (cache hit — log it), screenshot the Hevy card preview screen. On the watch: finish a session and screenshot FinishView.
9. Versioning 7.4.0, changelog, version:check, `graphify update .`.

STOP and present screenshots of your work to the user. Explain briefly what you did. Ask for approval before proceeding to finish the wave.

After approval: commit, merge wave/5-telemetry into main, append "## Wave 5 Summary — 7.4.0" to docs/Plan-Onyx-Expansion-Done.md, commit, do not push.
```

---

## W6 — Lean: profiling, main-thread purge, compactification, gym mode

**Goal.** Measured, then cut. Every hot path has a signpost and a before/after
number; no synchronous DB read left in a view body; five tabs made dense, not
hidden; gym mode.

**Design — A. Performance.**
- Signposts (`os_signpost`, subsystem `app.onyx.perf`): `launch.firstFrame`, `tab.switch`, `logger.open`, `set.tick`, `session.finish`, `export.build`, `watch.push`, `sync.foreground`. Measure with `xctrace record --template 'Time Profiler'` on the simulator and on the founder's device (ask at the stop for the device trace). Record numbers in the wave summary.
- Main-thread purge: the 193 `try database.` sites in `Onyx/Features` + `Onyx/App`. Rule: a read that feeds a view goes through `ValueObservation` (already the house pattern, 18 in `DayEditing`) or a `@Observable` model loaded in `.task`; never in `body`. Priority hot spots: `RootView.swift:147`, `LiveStatsView.swift:107`, `EraWindowPicker.swift:115-120`, `SettingsModel.swift:267-504`, `SyncStatusView.swift:431-474`, `TodayTabView.swift:275,295`, `PulseModel.swift:171,434`.
- `NutritionModel.swift:121-128`: one combined observation per date instead of five.
- `WeekDaysView.swift:372-383`: build the export only when the export chip is tapped; cache per `(weekStart, rescoreGeneration, lastCommitSeq)`.
- `WatchPayloads.swift:29`: send only the active program + today's day in `WatchContext.schedule`; full catalogue names only when a swap list is requested (W3 swap uses it — send a compact name list instead).
- `MirrorRealtime.swift:175`: retry join with backoff; `.realtime` sync falls back to a 60 s poll while disconnected.
- `PostgRESTRemote.swift:243`: keyset paging on `(updated_at, id)` instead of offset.
- `WidgetSnapshotBuilder.swift:416,773` + `StressInputsBuilder.swift:13`: one window read for the 14-day series.

**Design — B. Compactification without hiding (decision 24 challenge).**
Answer: bloat is *duplication and chrome*, not features. Four moves, each a diff, none a toggle:
1. **De-duplicate surfaces.** Audit every fact drawn in two places (the week volume appears in Train, Week, and History; readiness in Today and Pulse; water in Today, Fuel and the widget). One component per fact (`OnyxUI` tile), reused; delete the second drawing. Deliverable: `docs/COMPACTION_AUDIT.md` table (fact → surfaces → keep) then the deletions.
2. **Density**: section headers become inline captions; card padding steps from `OnyxSpace.l` to `.m` on tab roots; captions merge into one line; every card = one hero + ≤ 2 captions (existing law enforced by a `LayoutGoldenTests` extension counting text nodes per card in the preview catalogue).
3. **Relevance ordering, not hiding**: Today's card order follows the clock and data state (morning: sleep → readiness → plan; evening: fuel → water → tomorrow). Everything stays on the page; the hero moves. `DashboardLayoutStore` already stores order — add a `ranking` that is applied on top unless the user pinned.
4. **Merge sheets that edit one row**: stress log + DOMS + water are three sheets on `daily_logs`-adjacent tables; one "Log day" sheet with three segments. (Stress already collapsed to one screen in 6.8.0; extend.)
- **Gym mode** (decision 26): when `liveWorkoutInProgress` OR (a session is due today AND local time is within the founder's usual training window learned from `workout_sessions.started_at` median ± 90 min) the app launches into `WorkoutTabView` with `.toolbar(.hidden, for: .tabBar)`; a small "Leave" capsule in the nav bar restores the tab bar; ends automatically on finish/cancel. Setting to disable in You.

**Gate.** Before/after table for all 8 seams; zero `try database.` inside any `body`; `COMPACTION_AUDIT.md` with ≥ 10 rows resolved; screenshots of Today (morning + evening order), Train root, Fuel root, gym mode entry, AX5 for each.

### W6 PROMPT (copy/paste)

```
Model: Opus 5 (Extra High Effort)

You are executing Wave 6 of the Onyx Expansion sprint. Read docs/Plan-Onyx-Expansion-Done.md FIRST (all, plus Wave 1–5 Summaries), then native/README.md, then `graphify explain AppEnvironment`, `graphify explain NutritionModel`, `graphify explain DashboardLayoutStore`, `graphify explain MirrorRealtime`, `graphify explain PostgRESTRemote`. Founder decisions §2 are final (16, 18, 24, 25, 26). Do not split LoggerModel.

Load these skills now: native, graphify, apple-design, ui-ux-pro-max, frontend-design, ui-design-system, ponytail:ponytail-debt (harvest the 45 ponytail markers first), git-commit-helper, ship.
Use these agents: debugger (trace analysis), architect-reviewer (observation/model boundaries), supabase-realtime-optimizer (realtime retry + paging), ui-ux-designer (compaction audit review at default and AX5), invariant-auditor (any number that moves), code-reviewer.

Branch: `git checkout -b wave/6-lean` off main. Wave-specific SHOT_DERIVED.

Do, in this order:
1. Signposts on the 8 seams in §W6-A. Record BEFORE numbers with xctrace on the iPhone 15 simulator (cold launch, tab switch ×5, logger open, tick, finish, export build, watch push, foreground sync). Ask the founder at the stop for one device trace.
2. Main-thread purge: list every `try database.` / `try? database.` in Onyx/Features and Onyx/App; move each into ValueObservation or a model's .task; start with the hot spots named in §W6-A. Add a test that greps the app target for `database.` inside a `var body` and fails on any hit.
3. NutritionModel single observation; WeekDaysView export-on-demand with cache; WatchContext diet (active program + today only, compact swap name list); MirrorRealtime join retry with backoff and 60 s poll fallback; PostgRESTRemote keyset paging; single-window 14-day series reads. Golden numbers unchanged — invariant-auditor signs off.
4. Compaction: write docs/COMPACTION_AUDIT.md (fact → surfaces → keep), then delete the duplicate drawings, apply density rules, add the text-node-per-card LayoutGoldenTests check, implement relevance ordering on Today over DashboardLayoutStore, merge the day-log sheets. Nothing is hidden; everything stays reachable on the same page.
5. Gym mode per §W6-B with a You-tab setting to disable it.
6. Record AFTER numbers for all 8 seams.
7. Verify: `npm run check`, `npm run swift:core`, `npm run swift:data`, `npm run check:swift`, `npm run check:watch`; OnyxTests no new failures over baseline 11. xcodebuildmcp: screenshots of Today with the simulator clock at 07:00 and 20:00 (simctl status_bar or the DEBUG clock override), Train root, Fuel root, gym mode entry with the tab bar hidden and the Leave capsule, AX5 for each. Run scripts/native-shot.sh full set and diff against the previous wave's shots for regressions.
8. Versioning 7.5.0, changelog (include the before/after table), version:check, `graphify update .`.

STOP and present screenshots of your work to the user. Explain briefly what you did. Ask for approval before proceeding to finish the wave. Show the before/after table.

After approval: commit, merge wave/6-lean into main, append "## Wave 6 Summary — 7.5.0" to docs/Plan-Onyx-Expansion-Done.md, commit, do not push.
```

---

## W7 — AI export: gate, App Intent, MCP server, paste-back ingest

**Goal.** Getting your data to an AI takes one action from any surface, the
extraction logic exists once, and the AI's answer can write your next week's
targets back.

**Design — one serializer (decision 22 challenge).**
`OnyxCore/Reports/WeeklyExport.swift` already renders markdown from an
`Input`. Make `WeeklyExport.Input` itself the wire: it is `Codable`; add
`ExportEnvelope { version: 6, range, generatedAt, input: Input, markdown }`.
Every consumer receives an `ExportEnvelope`:
- **App** builds it (`WeeklyExportBuilder`) and (a) shares `markdown` via `ShareLink`, (b) uploads the envelope JSON to a new Supabase table `exports(user_id, range_start, range_end, version, envelope jsonb, created_at)` with RLS (SQL for the founder) on every build.
- **App Intent** `ExportForAIIntent` (App Intents, in the app target; `AppShortcutsProvider` phrase "Export my Onyx week") returns the markdown as `IntentFile` + the envelope JSON as a second output. Shortcuts pipes either into Claude / ChatGPT / any action. Parameter: range = `sinceLastExport | thisWeek | lastWeek | last7Days`.
- **MCP server** `tools/onyx-mcp/` (Node, `@modelcontextprotocol/sdk`, reads Supabase with the founder's service key from env; ~200 lines): tools `list_exports(range)`, `get_export(id) → envelope`, `get_latest_markdown()`, `query_sets(since)` (thin passthrough on `workout_sets`), `get_daily_scores(range)`. It never re-implements extraction — it serves envelopes the app already built; live-table tools are raw rows. Registered in Claude Desktop / Claude Code config; README with the two-line setup.
- **Export gate** (decision 21): `WeekReady.isComplete` gate removed from the chip; range picker `Since last export` (default) / `This week so far` / `Last complete week`. `last_export_at` stored in `Preferences`.
- **Paste-back structured ingest** (decision 23): `ReportsListView` paste sheet gains "Apply targets". Parser in `OnyxCore/Reports/TargetsBlock.swift`: the report may contain a fenced block ```onyx-targets``` JSON `{ "weekStart", "levers": [{ "key", "value", "unit" }], "dailyTargets": { "kcal", "proteinG", ... } }` (the schema is printed at the bottom of every export so the AI knows how to answer). Parsed → preview diff → writes `lever_periods` + daily targets through the existing writers (`GoalsEditing`, `TargetResolver`). Golden vectors for the parser (valid, missing block, malformed).
- **Appendix A** plan for BYOK later (not built).

**Gate.** `swift:core` goldens for envelope round-trip, parser; Shortcuts run on the simulator via the Shortcuts app (screenshot the intent output); MCP server smoke test from the terminal (`npx @modelcontextprotocol/inspector` or a direct stdio call) listing exports; apply-targets preview screenshot; export chip on a running week.

### W7 PROMPT (copy/paste)

```
Model: Opus 5 (Extra High Effort)

You are executing Wave 7 of the Onyx Expansion sprint. Read docs/Plan-Onyx-Expansion-Done.md FIRST (all, plus Wave 1–6 Summaries), then native/README.md, then `graphify explain WeeklyExport`, `graphify explain WeeklyExportBuilder`, `graphify explain ReportsListView`, `graphify explain TargetResolver`, `graphify explain GoalsEditing`. Founder decisions §2 are final (21, 22, 23).

Load these skills now: native, graphify, mcp-builder, senior-architect, schema, supabase-postgres-best-practices, apple-design, git-commit-helper, ship.
Use these agents: schema-truth-checker (before the exports table SQL), swift-mcp-expert and backend-architect (MCP server shape; keep it ~200 lines, Node), prompt-engineer (the targets-schema footer the export prints for the AI, and the App Shortcut phrases), invariant-auditor (parser goldens, envelope round-trip), code-reviewer.

Branch: `git checkout -b wave/7-ai-export` off main. Wave-specific SHOT_DERIVED.

Do, in this order:
1. Read WeeklyExport.swift, WeeklyExportBuilder.swift, WeekDaysView.swift export chip, ReportsListView.swift, ReportsStore.swift, Preferences.swift, GoalsEditing.swift, TargetResolver.swift, and the existing App Intents in native/Shared and OnyxWidgets/OnyxIntents.swift.
2. ExportEnvelope in OnyxCore (Codable, version 6); golden round-trip vector. WeeklyExportBuilder produces it; the markdown footer prints the onyx-targets schema.
3. Export gate: remove the complete-week lock, add the range picker with "Since last export" default, persist last_export_at. Upload the envelope to Supabase `exports` on every build; write docs/sql/w7-exports.sql (table + RLS, proved shape with schema-truth-checker) for the founder to paste.
4. ExportForAIIntent + AppShortcutsProvider; outputs markdown file and envelope JSON; range parameter.
5. tools/onyx-mcp/: Node MCP server serving envelopes and thin raw-row tools from Supabase; README with Claude Desktop and Claude Code registration; smoke test script. No extraction logic in it.
6. Paste-back "Apply targets": TargetsBlock parser with goldens (valid / missing / malformed), preview diff sheet, writes through GoalsEditing / TargetResolver only.
7. Write Appendix A (BYOK in-app Claude call: key storage in Keychain, model id, cost display, App Store review notes) into docs/Plan-Onyx-Expansion-Done.md as a plan only.
8. Verify: `npm run check`, `npm run swift:core`, `npm run swift:data`, `npm run check:swift`, `npm run check:watch`; OnyxTests no new failures over baseline 11. xcodebuildmcp on iPhone 15: screenshot the export chip on a running week with the range picker, run the Shortcut from the Shortcuts app and screenshot its output, screenshot the Apply-targets preview. Terminal: run the MCP smoke test and paste the tool list output into the summary.
9. Versioning 7.6.0, changelog, version:check, `graphify update .`.

STOP and present screenshots of your work to the user. Explain briefly what you did. Ask for approval before proceeding to finish the wave. Ask whether docs/sql/w7-exports.sql has been pasted.

After approval: commit, merge wave/7-ai-export into main, append "## Wave 7 Summary — 7.6.0" to docs/Plan-Onyx-Expansion-Done.md, commit, do not push.
```

---

## W8 — Purge & merge

**Goal.** Nothing left behind: no wave branches, no screenshots, no caches,
one clean `main` pushed.

### W8 PROMPT (copy/paste)

```
Model: Opus 5 (Extra High Effort)

You are executing Wave 8, the close-out of the Onyx Expansion sprint. Read docs/Plan-Onyx-Expansion-Done.md FIRST, including every Wave Summary. Load skills: native, git-commit-helper, ship, graphify. Agents: code-reviewer (final main diff since 6.8.1), caveman:cavecrew-reviewer.

Do, in this order, and print each command's result:
1. `git status` must be clean and on main. `git fetch --all --prune`. Confirm every wave/* branch is merged: `git branch --merged main`. Any wave/* branch NOT merged → stop and ask the founder; never force-delete unmerged work.
2. Delete all merged local branches except main (`git branch -d`), including the stale onyx/sprint-widgets-* branches, and delete their remotes if any exist (`git push origin --delete <branch>` only for branches that exist on origin AND are merged).
3. Delete generated screenshots and caches: native/__screenshots__/, native/__store__/ (regenerate the 12 App Store shots first with scripts/store-shots.sh ONLY if the founder wants them kept — ask), every SHOT_DERIVED path used by the waves under ~/Library/Caches/onyx-swift/, ~/Library/Caches/onyx-swift/ui-test-derived, native/Onyx.xcodeproj (gitignored, regenerated), native/graphify-out if it reappeared, docs/sql/*.sql that the founder confirms were applied (move their text into the changelog first), tools/onyx-mcp/node_modules.
4. Move docs/Plan-Onyx-Expansion-Done.md's wave prompts into a collapsed "Appendix B — prompts as run" and make the summaries the body. Move the file to docs/Done/ and update README links. Update docs/SIMULATORS.md if any step changed.
5. Full gate: `npm run check`, `npm run swift:core`, `npm run swift:data`, `npm run check:swift`, `npm run check:watch`; OnyxTests no new failures over baseline 11; the repo-wide predecessor-name grep still 0.
6. Versioning 7.6.1 (hotfix-class close-out), changelog "The sprint leaves no residue" section, version:check, `graphify update .`.
7. `git status` clean, `git worktree list` shows only main.

STOP and present the branch list, the deletion list and the gate output to the user. Explain briefly what you did. Ask for approval before proceeding to finish the wave.

After approval: commit with a message ending in `[skip ci]`, `git push origin main`, confirm `git status` and `git branch -a` are clean, append "## Wave 8 Summary — 7.6.1" to the moved plan file, amend or add a final commit `[skip ci]`, push again.
```

---

## Appendix A — BYOK in-app AI call (planned, not built)

**Status: a plan only.** Nothing below shipped in W7. It is written here at
W7's close because W7 built both of its dependencies — the `ExportEnvelope`
that would be the message body, and the `TargetsBlockParser` that would read
the answer — and the decisions are cheapest to record while the seams are still
in front of us.

**The gap it closes.** After W7, getting a week to a model takes one tap and a
share sheet, and getting the answer back takes a paste. BYOK removes both: the
app calls Anthropic itself, streams the report into the Reports sheet, and the
"Apply targets" button W7 built is already sitting under it. The loop closes
without the athlete leaving the app.

**Why it is the user's key and not ours.** A subscription means a server, a
server means our keys and our bill, and a bill that scales with how much
someone trains is a business this app is not. BYOK also means there is nothing
of ours between the athlete's data and the model.

### A.1 · The key

- `AnthropicKeyStore` beside `KeychainAuthStorage` in `OnyxData/Auth/`. Same
  Keychain, same target-private access group — the free-team constraint in
  `native/README.md` applies here too, so the widget and the watch cannot see
  it, and neither needs to.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. A training key has no reason
  to reach an iCloud backup or a restored device.
- Entered in Settings → You → "AI coach". Validated on save with one cheap
  `POST /v1/messages` of `max_tokens: 1`; a key that does not authenticate is
  refused at the door rather than at the first real call.
- Never logged, never in a crash report, never in an `ExportEnvelope`.

### A.2 · The call

- `claude-opus-5` by default, in a picker with `claude-sonnet-5` beside it for
  a cheaper weekly pass. The id lives in ONE constant; the picker's other
  entries are data.
- `anthropic-version: 2023-06-01`, `x-api-key: <the user's key>`, direct to
  `api.anthropic.com`. No proxy of ours exists, and adding one would be the
  thing this whole design avoids.
- Body: the envelope's `markdown`, not its `input`. The document is what the
  export was written for and it already ends with §9 telling the model how to
  answer; the `input` is thirty times the tokens for a reader that does not
  need the rows.
- Streamed (`stream: true`) into the paste sheet's `TextEditor`, so a long
  report is readable as it arrives rather than after forty seconds of nothing.
  The existing `ReportEditorSheet` is the destination — no new screen.
- `URLSession` and `AsyncThrowingStream` over the SSE body. No SDK: the call is
  one POST and a line parser, and a dependency here would be a dependency in
  the app's signature for one endpoint.

### A.3 · The cost

- Shown BEFORE send, not after: model, estimated input tokens (the document's
  own character count ÷ 3.6, stated as an estimate), and the current per-model
  price from a hand-maintained table with the date it was checked. A number the
  app cannot verify is labelled as a number the app cannot verify.
- After the call, the actual `usage.input_tokens` / `usage.output_tokens` from
  the response, and a running total per month in Settings. Local only —
  a spend figure is not a training fact and does not belong in the outbox.
- A hard stop at a user-set monthly ceiling, default £10, because the failure
  mode of a bad automation is a bill.

### A.4 · App Store review notes

- The key is the user's own and is stored in the Keychain on device. It leaves
  the device only in the `x-api-key` header of a request to `api.anthropic.com`
  made at the user's explicit tap. Say this in the review notes AND in the
  Settings screen, in the same words.
- Guideline 3.1.1 (in-app purchase) does not apply: nothing is sold, and the
  user's relationship is with Anthropic. There is no purchase flow, no unlock,
  and no link to buy anything — the key field is accompanied by prose, not by a
  button that opens a store.
- `NSPrivacyTrackingDomains` is untouched: `api.anthropic.com` is not tracking.
  The privacy manifest gains no new required-reason API.
- Health data crosses a network boundary here for the first time. `docs/APP_STORE.md`'s
  data-collection answers change: "Health & Fitness — used for App Functionality,
  not linked to the user, not used for tracking" becomes a disclosure that the
  report request carries the week's figures to a third-party model at the user's
  instruction. That is a listing change, not a code change, and it must ship in
  the same submission.
- A reviewer with no key must be able to use the whole app. The feature is a
  Settings row that says what it needs; nothing else is gated on it.

### A.5 · What it depends on, and what it does not

Depends on W7's `ExportEnvelope` (the body) and `TargetsBlockParser` (the
answer). Depends on nothing in the MCP server — that path is for a desktop
model and stays. Does **not** depend on the `exports` table: an in-app call has
the document in memory and has no reason to fetch its own copy back.

**One open question for the founder:** whether the in-app call should also file
its request in `exports`. It would make the MCP server and the in-app history
agree; it would also mean a document the athlete never shared is on the server.
Left open deliberately.

## Verification summary (whole sprint)

- Each wave: four npm gates + `check:watch` + OnyxTests baseline + xcodebuildmcp screenshots on the paired iPhone 15 / Apple Watch Ultra 2 49 mm + founder approval stop + version bump + changelog + wave summary.
- W1 gate: predecessor-name grep = 0. W2 gate: cascade parity vector + PR replay vector. W5 gate: provenance goldens. W6 gate: before/after table for 8 seams + no `database.` in any `body`. W7 gate: envelope round-trip + parser goldens + MCP smoke test. W8 gate: clean tree, only `main`, pushed.

---

## Wave 1 Summary — 7.0.0

**Worked.** Zero bytes of the predecessor name in the working tree, by the
gate's own command. `v32.onyxWire` moves all four local places an exercise id
lives in one transaction; `docs/sql/w1-onyx-wire.sql` moved the server's three
and the founder ran it (constraint recreated as `CHECK (era IS NULL OR era IN
('ppl','onyx'))`). Neither half spells the retired brand: the era excludes
`ppl`, the slug is matched by shape, and the Swift predicate and Postgres regex
are pinned to each other by a test. Tooling: `scripts/watch-shot.sh`,
`check:watch`, `check:report`, `docs/SIMULATORS.md`, recorded session defaults.

**The plan was wrong about four things, and the live database said so.**
`workout_sets.exercise_id` is `uuid` server-side (0 rows, structurally
impossible); `personal_records.exercise_key` is a display NAME, never a slug;
`set_events`' column is `body`, not `payload`; and `exercises.slug` — 46 of 46
rows, which the plan never named — had to migrate or every set logged on 7.0.0
would throw `unknownExercise` on push. `Preferences`' `<brand>_*` fallbacks and
`LoggerModel`'s "stamping sites" were comments, not code.

**Failed, and was caught.** The first predicate was looser in Swift than in
SQL (`5-x`, `xx55-x`, `Xx5-x` would have renamed on one machine only). The
first SQL claimed either order was safe — false, a migration runs once. The
rename left `ExerciseIndex` throwing on a straggler under the old stamp, which
a watch on the previous build still produces. `exercises.id` is a PRIMARY KEY
and a stamp collision threw out of `AppDatabase.init`, so the app would not
launch. All fixed; `invariant-auditor` and `code-reviewer` found them, not me.

**`npm run check` had been exiting 1 with no output, on `main` too.**
`swift-ui-test.sh` defaults to a simulator that is not installed, and its UDID
lookup is a pipeline under `set -e` — a non-matching `grep` kills the script
before its own error prints. The 40 OnyxUI tests had not been running. Fixed
here because it is this wave's gate. **Never trust a piped `tail` for a gate;
read the exit code.**

**Left open.** (1) `ExerciseIndex.bySlug` uses `uniquingKeysWith: { first, _ in
first }` where its sibling detects ambiguity and throws — pre-existing, but it
reads the column v32 writes. (2) No golden runs the real `makeMigrator()`
sequence from pre-v23 data; the v23→v32 chain is proved by trace, not fixture.
(3) `v25`/`v27` read `workout_sets` by exercise identity and now run before ids
are resolved on a pre-v23 device — traced, no dependency found, no fixture.
(4) Watch `deck`/`finish`/`dashboard` have no launch hook; `watch-shot.sh`
refuses them by name rather than photographing `StartView` under their filename
(W3/W4 add the seeds).

**The shell `grep` in this environment is a ugrep wrapper that honours
`.gitignore`.** It under-reported the inventory by 66 hits. Use `/usr/bin/grep`
for any gate that must see ignored files.

---

## Wave 2 Summary — 7.1.0

**Worked.** The cascade is `ScoringWindow`: one read of `[from − 48 d, through]`,
every day computed in memory with the same domain functions, one write
transaction. **49 days: 0.6 s per-day → 0.1 s window (0.56–0.64 s vs
0.13–0.16 s, idle machine), 49 commits → 1**; `os_signpost` `rescore.run`.
Parity was proved live (old vs new, 60 days, identical) and is pinned as a
59-row vector captured from the OLD path over `DenseSeed`. Rescore at the
door: TEMP triggers on thirteen dated tables plus `set_events` (date via the
parent session) feed `temp.rescore_touched`; a `TransactionObserver` reads
past a watermark at commit; `Rescore.doorDecision` cascades ≤120 d, marks
history stale beyond, ignores today. Six per-caller `rescore(from:)` calls are
gone. Settings → "Recompute history"; Sync doctor → "Rescores" ledger.
`ingestFromWatch` commits the wrist's events through the phone's outbox.
`createRetroSession` + "Log a workout here" on a past Pulse day opens the
existing edit deck (born closed: no clock, no Live Activity, no pencil).

**The plan was wrong about four things.** (1) `PreviewCatalogue` seeds no
per-day rows and lives in the app target; the parity seed is `DenseSeed` in
OnyxDataTests. (2) A `session.upsert` outbox item carries the session ROW only;
"re-queue the session upsert on ingest" would have pushed no sets, and a forced
row could write `ended_at: null` over a finish the phone had not heard — the
events are queued instead. (3) `PrRecorder.replay` already existed and already
runs inside `SessionEditing.edit`'s transaction; with one `personal_records`
row per axis and no history, "incremental from the edit date" cannot be
cheaper than the full per-exercise replay, so the door does not replay PRs —
SessionEditing does, atomically, and two tests now pin it. (4) No server
column was needed; no SQL.

**Failed, and was caught.** `invariant-auditor`: the ghost guard read a water
SUM where the old path read row presence (a 0 ml row is a logged day); nights
were iterated by bedtime where every old query met them by rowid — fixed, seed
widened, vector regenerated from the old path in a `main` worktree.
`database-architect`: the old account's door heard `prepareForUser`'s mass
delete; `workout_sets` triggers were pure cost. `code-reviewer`: sync acks and
the puller's `seedEventLogs` fired the door (every push of a past session
cascaded again); the `rescore` ledger row flipped `needsBackfill`; Health
re-saved yesterday byte-identical every foreground; a merged `.manual` run lost
its reason; a retro session dismissed with no set was left behind. All fixed.
The first strand test failed honestly and exposed premise (2).

**Left open.** (1) Fault isolation is all-or-nothing per pass (decision 17):
one broken day fails the whole range — documented in `RescoreQueue.runOnce`,
not tested. (2) `stress_logs`, `body_composition` and the undated tables are
outside the door; a goal edit that should re-grade past days is a manual
recompute. (3) HealthKit imports count as local edits: a fresh install's
months-deep import sets the stale mark once. (4) Sync doctor is admin-gated.
(5) The simulator was signed out and no session file exists, so the live
flows (macros three days back → ledger; week-old set → PR bar) were pinned by
tests, not photographed; the new surfaces were shot through `PreviewHarness`
with the `axe` CLI (`xcodebuildmcp` exposed no tap tools; `snapshot_ui` timed
out). `native-shot.sh` had W1's silent-exit bug (uninstalled default device);
fixed. The harness's `day-past` session card is a fixture, not a store row.

---

## Wave 3 Summary — 7.2.0

**Worked.** The wrist runs a session. Set Quality is page two of `SetView` —
four kinds, the side on a one-limb movement, six technique tags several at a
time, every tap an `amend`. Pause writes both halves (the event the clock reads,
and the `HKWorkoutSession` so the rings stop); hold the clock to discard, which
is `WorkoutSessionController.cancel()`'s first caller ever. The deck reorders by
swipe, sharing `DeckOrder.move` with `LoggerModel.moveExercise` under a golden
vector. Rest gains an editable receipt and a recovery curve. The phone's
`SetKind`/`SetQuality` now read `SetTags`, which caught a drift: the chip that
said "Cold start" says "Cold", as the export always has.

**The plan was wrong about four things.** (1) `ScheduleResolution` does not
exist — no swap-the-movement path exists on the phone at all, so the wrist's
swap is its own thing, restricted to names the phone already sent. (2) Four kind
capsules do not fit one line at 146 pt; `WatchPanel` puts them 2 × 2, which is
the call the phone's own sheet makes at an accessibility size. (3) There is no
system page indicator for a `ScrollView` — `PageIndexViewStyle` belongs to
`TabView`, the control this screen cannot use — so the dots are drawn. (4) A
`Chart` was not worth a framework on the launch path for an axis-less polyline;
the sparkline is a `Shape`.

**Failed, and was caught.** `onScrollTargetVisibilityChange(threshold:)` measures
a fraction of the TARGET, and page two is ~380 pt in a ~95 pt viewport — so it
never fired, `page` never left `.set`, and the Crown kept moving a load nobody
could see. My own screenshots showed it (the lit dot stayed on page one) and I
read past it twice. Review also found: a reorder after a swap dropped the
swapped movement AND its logged sets, then re-stamped over their
`exercise_order`; any refused write bricked the app behind "Store unavailable"
until a force-quit; `cancelSession` binned the `HKWorkout` before the database
agreed; "Add set" from a finished row added it elsewhere; the edit door was
unreachable on a wrist-started rest. The five deck properties are now
`DeckArrangement` in OnyxCore — keyed on the SLOT, never the name in it — with a
suite, because none of those five was reachable by any test this repo can run.

**`.scrollInputBehavior(.disabled, for: .handGestureShortcut)` disables the
scroll view's input ENTIRELY on this SDK**, not just the double pinch. With it
on, no swipe of any length moved the pager by a point.

**Left open.** (1) The watch-to-phone tick is unphotographed — the simulator is
still signed out, as W2 recorded; `WatchConvergenceTests` covers it. (2) 40 mm is
asserted by `OnyxWatchLayoutTests`, never seen: the pair is a 49 mm Ultra 2.
(3) The focus ring on the value rows appears in no shot — verify on device.
(4) Double-tap arbitration between the tick and the pager is unverified, and the
fix is NOT to restore the modifier above. (5) The quality panel is three
screenfuls at 40 mm; it scrolls, and nothing shortens it without dropping a tag.

---

## Wave 4 Summary — 7.3.0

**Worked.** The wrist has three pages — Today, Train, Fuel — turned with the
Crown, and every row is the SAME `OnyxTile.accessory` face the complications
and the phone's Lock Screen draw, so a reading cannot say one thing in a
corner of a clock and another on a page. `WatchTiles` grew four
optional-and-last fields (week sets and tonnage, protein and its target) for
under 80 bytes of wire. The Fuel page's "+1 glass" posts over a new
`WatchLink.water` kind into the same `PendingWater` mailbox Control Centre
uses, written by the same `addWaterGlass` — one row whichever device was
tapped. `LiveWorkoutSnapshot` is written on every commit and rest beat and
drawn by a new `WorkoutLiveWidget`, ranked by watchOS 11's
`TimelineProvider.relevance()` with `RelevantContext.fitness(.workoutActive)`.
`ContentState.bpm` puts the wrist's rate on the rest band and the Dynamic
Island. `dashboard` — the last name `watch-shot.sh` refused, since W1 — now
has a hook, with `train`, `fuel` and `widget`.

**The plan was wrong about three things.** (1) **The bundle had headroom.**
`@WidgetBundleBuilder` caps at ten ELEMENTS, not ten widgets, and a nested
bundle is one element — so the "which slot does the live widget take"
question the plan reserved for the founder has no answer: none. All ten
complications kept. (2) **The session timer's long-press is already
discard** (W3, decision 3), so the in-session dashboard is on `DeckView`'s
toolbar — the same glyph in the same corner `StartView` uses. Founder
confirmed. (3) **`AppIntentConfiguration` is not required for relevance**;
the provider-side hook needs no App Intent and no metadata extractor.
Separately, there is no "inline duplicate" complication to replace — every
one of the ten declares all four families.

**Failed, and was caught.** My first layout test **estimated** a 28 pt
navigation bar and a 42 pt row, passed, and asserted that a page fits on
which the water button was photographed hanging half off the display. The
accessibility tree says 64 and 48.5. Corrected, and the suite now states
both halves: three faces fit 49 mm with 33.5 pt spare and overflow 40 mm by
20.5 (78.5 with the button), reached by the Crown — the founder accepted the
scroll rather than cut a face. `code-reviewer` found two blockers:
`publishLiveSnapshot` fired only on the four rest beats, so the card was
confidently wrong after any deck edit or void, and its `cursor` guard
**cleared the card on the last rest of every session**. Both fixed at
`seedCursor`, the funnel all seven mutators already end in, with a
`sameReading` de-dupe so one commit does not spend two reload budgets. It
also found that the phone's `liveBpm` expiry could never fire — a computed
property over stored fields, and time passing is not a mutation — so the
Lock Screen could draw a rate from a watch that had come off the wrist; the
expiry is a real task now, and both devices age a reading over one constant.
`ui-ux-designer` found the rest countdown and the heart rate rendered in the
same hue at the same size on a family that goes monochrome: the red is on
the glyph alone now and the countdown is the card's hero.

**Two second implementations were deleted, not added to.** The Dynamic
Island's compact slot was written out in `OnyxWidgets` and copied into
`WidgetPreviews` — the only thing that photographs it — and the copy had
already drifted, so my first shot reviewed the harness. It is one
`Shared/WorkoutCompactTrailing` now. `PendingWater` moved from `Shared/`
(in neither watch target) to OnyxCore, which also deleted the third spelling
of `250`.

**Left open.** (1) The Smart Stack itself is unphotographed: relevance is the
system's judgement about an `HKWorkoutSession` a simulator has no heart to
drive, and `simctl` cannot force a stack to surface a card. The faces are
shot at their real sizes from the real suite through `LiveWidgetPreview`;
the RANKING is proved by the API and by nothing else. (2) 40 mm is still
asserted and never seen — the pair is a 49 mm Ultra 2, and the new page
budget is measured there and applied as a conservative bound. (3) A newer
watch paired with an older phone loses a tapped glass: the `water` kind hits
`default: return` and the wrist's optimistic 250 reverts at the next push.
(4) The Train page's third row breaks the left text rail — the week marks
are 43 pt wider than a glyph — cosmetic, and a shared face, so it belongs to
a polish wave. (5) The watch's Water complication does not get the
optimistic glass and disagrees with the Fuel page by 250 ml until the phone
confirms; deliberate, a complication must not assert a number no store has
agreed to.

**The first screenshot of every shot run could come back solid black.** Both
loops waited 8 s after installing a fresh binary, which is enough for a warm
launch and not the first one — and a black PNG reviews as "the screen is
broken" under a correct filename. Both scripts take a throwaway launch now.

---

## Wave 5 Summary — 7.6.0

**Worked.** A workout now says whose it is. `WorkoutProvenance` classifies an
`HKWorkout` by its source bundle id — own on either device (`…native` ↔
`…native.watchkitapp`), foreign otherwise, and a source that is missing is
FOREIGN, never own — and `HealthReading.liftingOverlap` is the one read that
`SessionMetrics`, the Hevy card and the phone's `WorkoutWriter` all share, so
they cannot disagree about which workout is the session's. The finish sheet
and the session page draw the heart-rate series cut into its movements
(`HRSegments`: `[previous run's last commit, own last commit)`, split by the
pause ledger), numbered legend, muscle-coloured washes, one hero, two
captions; AX5 keeps the numbers. Read from Health at view time, cached in
`session_telemetry` after the first non-empty read of a CLOSED session, one
refetch inside ten minutes of a finish when the watch's samples land. "Hevy
logged this too" compares four rows, Skip is primary, "Use" fills only what
Onyx could not measure. A phone-only session leaves an `HKWorkout` with its
energy, flagged `app.onyx.estimated` when `Estimates` produced it. Shipped
as **7.6.0** — the report overhaul and export v6 took 7.4.0 and 7.5.0 on
`main` between W4 and this wave.

**The plan was wrong about four things.** (1) `predicateForObjects(from:
ownWorkout)` answers only for builder-attached samples, and a phone-only
session has none — the interval query with a source filter (`com.apple.` or
own) serves both shapes. (2) "Attach existing HR samples" to the phone's
workout: `HKWorkoutBuilder.add` SAVES samples, so re-adding Health's would
duplicate them; the phone writes energy only. (3) The finish sheet draws
before `closeSession`, so a live session reads to `now` and nothing about it
is cached; `sessionFinished`'s prefetch writes the row. (4) The watch's
prefetch warms the WATCH's store — the phone's series arrives through
Health's own sync, which is what the late window listens for.

**Failed, and was caught.** `code-reviewer`: my multi-line patch matched the
teardown in `cancelSession`, not `finish` — the wrist prefetched on discard;
the phone's estimated kcal, written to Health, came back through
`syncSessionMetrics` as a MEASUREMENT (`energyEstimated` now stops it); a
double Finish tap wrote two workouts; the watch starts its `HKWorkoutSession`
on `adopt` with no set ticked, so "an event from another device" was half the
signal (`lastBpmAt` is the other half); `HKObserverQuery` fires once on
execute. `invariant-auditor`: "Use Hevy" could replace a TYPED figure — it
fills only what is not measured now. `ui-ux-designer`: five names on the
plot's top edge collided (legend, numbered); the rest line failed 3:1; the
Skip ramp duplicated Finish's. **An unsigned simulator build has NO HealthKit
entitlement** — the first shot photographed nothing and nothing logged it;
`SHOT_SIGN=1` signs ad hoc. `Logger.info` never reaches `log show`.

**Left open.** (1) The Smart Stack / late-window refetch is proved by
`ScriptedHealth`, not by a watch: the simulator has no heart. (2) Hevy's set
count is a best-effort metadata read; "—" is the ordinary answer. (3) The
harness re-evaluates its view builder, so `telemetry-detail` prefetches
twice into two stores — cosmetic, pre-existing (memory: storeless-preview).
(4) A phone-only session's row learns `avg_bpm` from the series only when the
page or the finish opens on it; nothing back-fills history. (5) Gates:
`swift:core` 673, `swift:data` 699, `npm run check` green, `check:watch`
green, OnyxTests 11 issues / 10 names — the baseline.

---

## Wave 6 Summary — 7.7.0

**Worked.** Eight seams carry `os_signpost` intervals (`Perf`, OnyxCore,
subsystem `app.onyx.perf`) and a DEBUG file sink, because a wave that cannot
read its own before/after table has measured nothing. The four that are pure
store work are timed OLD SHAPE AGAINST NEW IN ONE PROCESS over one seeded
account (`SeamBenchmarkTests`): battery stack 770 → **250 ms**, stress series
244 → **82 ms**, nutrition day 32 → **8 ms**, watch context 20,836 →
**7,040 B**. Cold launch is 661–776 ms on the simulator. Gym mode learns the
window from the median `started_at` ± 90 min and refuses to guess under eight
starts; Leave is a refusal that does not re-arm until midnight, and the state
is re-resolved on every foreground — which is what ends it for a session
finished on the watch. Today's cards reorder by the clock and yield forever to
the first drag. Three day-log sheets became one with three segments, which is
also how soreness finally got a Quick Log entry.

**The plan was wrong about four things.**
(1) **There were no render-time store reads left.** Every hot spot §W6-A names
— `RootView:147`, `LiveStatsView:107`, `EraWindowPicker:115`, `TodayTabView:275`
— was already `nonisolated` or inside `Task.detached` by W5. The real defect
was one level in: reads reached from a `.task` on a `@MainActor` view, which
runs on the main actor. That is what the purge actually cut.
(2) **`(updated_at, id)` keyset paging is not implementable here.** Eleven
mirrored tables have no `id` column and twelve carry no `updated_at`; the
cursor is each table's primary key, the one total order the schema indexes.
(3) **`NutritionModel` had seven observations, not five**, plus two inline
main-actor `stackCredit` reads from two of their callbacks.
(4) **The export could not be built "on tap"** as written — `ShareLink` is a
view and needs its item up front. A `Transferable` moves the cost instead: the
exporter runs when the share is performed.

**Failed, and was caught.** My own gate was the worst of it: the first
`check-body-reads.mjs` excluded a leading `.` from its pattern, so it matched
`database.` and walked past `environment.database.` — the spelling this
codebase actually uses — and it was not wired into `npm run check` at all.
`code-reviewer` found both, plus a `BodyTrendsView` race where a superseded
`All` scan overwrote the window the reader had just picked, a `watchBuild`
handle whose `cancel()` cancelled nothing (a `Task.detached` does not inherit
cancellation, so three pushes ran three `.full` builds at once), gym mode
re-arming itself after Leave on every theme pick, and a `TodayModel` that
ranked an already-ranked layout so the same clock gave two different grids.
`invariant-auditor` found three numbers that would have moved: a stale `today`
frozen into the merged nutrition stream (doses undercounted across midnight), a
watch swap tie-break that could install a different prescription for a name
shared between two programs, and a `daily_logs` read that stopped reproducing
`fetchOne`'s first-row-the-scan-finds rule. **And the AX5 screenshot caught the
last one:** the new resolver lowered the flag the shot harness had seeded, so
gym mode photographed the tab bar it exists to hide.

**Two rows of my own compaction audit were wrong, and the code said so.**
`VitalMetric.fixed` and `OnyxSnapshot.fixed` differ by rounding rule; the week
report's "stress index" is the 1–5 self-report mean, not the 0–100 index.
Both are recorded as non-duplicates in `docs/COMPACTION_AUDIT.md` with the
reason, because the next reader will see the same similarity.

**Left open.** (1) Six of the eight seams are instrumented and unmeasured: the
simulator has no Supabase session, so there is no signed-in shell to switch
tabs in, no deck to open, no sync to run. **The founder's device trace is the
measurement.** (2) The full 113-screen shot set runs at ~1 shot/minute on this
machine (~8 h); a 29-screen regression subset covering every surface the diff
touches was shot instead, 12 differing and all explained. (3) Ten audit rows
are open, the largest being one `SessionTotals.line(…)` across four surfaces
and the three separate battery-ring implementations. (4) `Pagination.all` is
dead but still has a test; `MirrorCoalescer.drain()` now fans out with
`withTaskGroup` and relies on `SyncCoordinator.syncNow`'s own coalescing.
(5) A channel that joins and drops in a loop retries at the floor forever,
because every join resets the ladder — `ponytail:`-noted.
