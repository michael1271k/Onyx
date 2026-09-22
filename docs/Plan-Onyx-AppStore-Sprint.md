# Onyx — App Store Sprint

Sprint plan. Opus agents only, no Fable. Two concurrent git worktrees.
Current version **7.8.1**. Sprint closes at **8.0.0**.

---

## Context

Onyx is a native SwiftUI training/nutrition/recovery app (iPhone + Apple Watch +
two widget extensions) that has never been submitted to the App Store. Seven
sprints of feature work later, the founder is buying the $99 Apple Developer
Program and wants a flawless debut.

Ten problems block that, and an audit of the live code found that most of them
have a single root cause sitting somewhere other than where the symptom shows:

- The Watch main screen is a dead end ("Rest day", one line of text) because the
  dashboard that already exists is a *pushed route* behind a toolbar disc.
- A workout started on one device does not reach the other until a set is
  logged, because session-open is not a message on the WatchConnectivity link.
  That same gap is why the Watch drops off the workout screen — no
  `HKWorkoutSession`, no frontmost-app privilege.
- Home Screen widgets render Apple's "Please adopt containerBackground API"
  placeholder because 12 of 20 tile faces never call the modifier.
- Changing a supplement dose silently rewrites every past day, because
  `custom_supplements` carries one current dose and no effective date.
- Sign in with Apple, Google sign-in and a subscription flow do not exist.

The outcome: a binary and a set of App Store Connect answers that a reviewer
approves on the first pass, on a Watch app the founder is willing to show people.

---

## Founder decisions (binding)

1. **Ship free. No StoreKit in this sprint.** IAP lands in 1.1 against a live
   App ID. Keeps the three subscription review rules, the Terms-of-Use link and
   restore-purchases out of a v1.0 submission.
2. **Rebuild the Watch information architecture from scratch.** Not a re-root —
   new tab model, new card treatment, colour. This reverses W3's documented
   "the set, not a dashboard" decision at `RootView.swift:25-35`; the reversal is
   deliberate and that comment gets rewritten, not deleted.
3. **The HR chart is one colour: `OnyxDomain.recover.accent`**, not a literal
   red. Red-family under the default theme, follows every Appearance preset.
   Exercise separation is opacity steps of that one token.
4. **Supplement dose history is a `dose_periods` jsonb column** on
   `custom_supplements`, beside the existing `schedule` jsonb. One resolver,
   `Supplements.doseAt(_:on:)`. No new table, no new RLS policy.
5. **Sign in with Apple + Google are written now and verified after Gate 0.**
   The `applesignin` entitlement cannot be signed by a free team, so it ships
   commented out in the same block pattern `associated-domains` already uses.
   No wave may claim it works on device.
6. **`.bar`, `.micros` and `.stack` come out of the widget picker.** They stay
   as phone dashboard tiles. Their "No face for this one yet." note stops being
   reachable from the widget gallery.
7. **HealthKit: add the unread types, no background delivery.** Background
   delivery is paid-gated like the App Group; the entitlement is staged behind
   a comment block and flips on in one line after Gate 0.
8. **Two lanes.** Lane A (Watch + Health) and Lane B (Phone + Store) run in
   parallel worktrees. Never three.

---

## What the audit found (facts every wave must respect)

| # | Fact | Where |
|---|---|---|
| 1 | Account deletion **already ships** — `rpc("delete_my_account")` + a two-tap destructive row. But the SQL exists nowhere in this repo; `docs/sql/` was deleted at 7.8.1 and the CHANGELOG migration appendix does not include it. | `AppEnvironment.swift:1004`, `SettingsTabView.swift:316` |
| 2 | Privacy and support pages are **live and return 200**. Not a blocker. | `site/privacy/`, `site/support/` |
| 3 | Phone `openSession` pushes nothing to the Watch. Watch `beginSession` sends nothing to the phone. Context pushes are foreground-only or behind a **30 s trailing throttle**. | `LoggerModel.swift:2837`, `WatchModel.swift:329`, `AppEnvironment.swift:1304` |
| 4 | The Watch starts `HKWorkoutSession` only inside `adopt()`. No adopt → no frontmost privilege → wrist-raise leaves the app. | `WatchModel.swift:409`, `WorkoutSessionController.swift:122` |
| 5 | `WKExtendedRuntimeSession` is absent, and must stay absent. An active `HKWorkoutSession` is the correct and only API for this. | — |
| 6 | 12 of 20 tile faces lack `containerBackground`. Four more have one on a wrapper `OnyxTile.face` bypasses. | `OnyxTile.swift:161-194` |
| 7 | "Last time" is **day-scoped**: the seed filters on `day_key` and iterates `day.exercises(for:)`. A movement outside today's program gets no seed entry at all. | `SessionSeed.swift:309`, `SessionHistoryStore.swift:258` |
| 8 | The exercise picker exists but is `private` and parameterised on `(RoutinesModel, dayKey)`, not a selection closure. | `RoutineDayEditor.swift:253` |
| 9 | Hevy "Skip" is **not** a dismiss — it records `HevyDecision.skip` so the card stops asking. Removing the button without removing the prompt leaves it on screen forever. | `HevyCompareCard.swift:133`, `SessionDetailView.swift:242` |
| 10 | `custom_supplements` has `archived_at` but no dose effective date. `WeeklyExportBuilder` reads today's row for every historical date. | `SupplementStack.swift:96`, `WeeklyExportBuilder.swift:998-1057` |
| 11 | `npm run check` never runs `OnyxTests`, `swift:core` or `swift:data`. A wave verified only by `check` is not verified. | `package.json:7` |
| 12 | The `OnyxTests` baseline is **undefined** — four docs claim 5, 7, 10 and 11, and none names which tests fail. | `docs/Done/*` |
| 13 | `docs/APP_STORE.md` is stale in six places: version 1.0, wrong `project.yml` line numbers, account deletion recorded as N/A, dead web routes. | `docs/APP_STORE.md` |
| 14 | Two real placeholders: `.bar/.micros/.stack` → "No face for this one yet." in the widget gallery, and a Reduce-Motion toggle whose own footer says the native app does not read it. | `OnyxTile.swift:191`, `SettingsTabView.swift:172` |
| 15 | Gate 0 (the $99 program) still blocks: App Group signing, `applesignin`, `associated-domains`, HealthKit background delivery, App Store Connect upload, Instruments on device. | `docs/APP_STORE.md` §8 |

---

## Parallel execution — worktrees

```bash
git worktree add ../onyx-lane-a -b wave/<n>-<slug> main
git worktree add ../onyx-lane-b -b wave/<n>-<slug> main
```

**The one shared-file rule.** `native/project.yml` and `package.json` are the
only files two lanes can collide on.

- **All structural `project.yml` edits happen once, in W1** — entitlements, URL
  schemes, usage strings, capabilities — including for features that land in
  W5 and W7. After W1 no wave touches `project.yml` structurally.
- **No wave hand-edits `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`.** A
  wave sets `package.json` `version` at merge time, then runs
  `npm run version:sync && cd native && xcodegen generate`. A version conflict
  in `project.yml` is resolved by regenerating, never by hand.
- `native/Onyx.xcodeproj` is gitignored and generated. Never merge it.
- Per `concurrent-waves-shared-checkout`: check `MERGE_HEAD` before `git add`,
  and always pass `SHOT_DERIVED` to the screenshot scripts so two lanes do not
  share a derived-data path.

**Simulator contention is real.** Two concurrent `xcodebuild test` runs are the
ceiling on this machine; three wedge the simulator. Lanes must not both run
`npm run check` at the same moment — stagger, or use separate
`-derivedDataPath` values.

---

## Waves

| Wave | Lane | Version | Owns |
|---|---|---|---|
| W1 | solo | 7.9.0 | Baseline, all `project.yml` structure, widget `containerBackground`, placeholder purge |
| W2 | A | 7.10.0 | Watch IA rebuilt from scratch |
| W3 | B | 7.11.0 | Logger: Add Exercise, HR chart, Hevy line |
| W4 | A | 7.12.0 | Bidirectional session sync + Watch stays awake |
| W5 | B | 7.13.0 | Supplements: dose periods, reminders, export |
| W6 | A | 7.14.0 | HealthKit audit, unread types, off-wrist handling |
| W7 | B | 7.15.0 | Auth (Apple + Google), Settings redesign, preflight |
| W8 | solo | 8.0.0 | Final integration, docs, purge, push |

Sequence: `W1` → `W2 ∥ W3` → `W4 ∥ W5` → `W6 ∥ W7` → `W8`.

---

### W1 — Foundations (solo, blocks both lanes)

**Goal.** Establish the measured baseline, make every structural `project.yml`
change the whole sprint will need, and close the two App Store placeholders and
the widget bug — all small, all blocking.

1. Run `npm run check`, then the full `Onyx` scheme test run. **Record the exact
   count and the exact failing test names** in the plan file. Every later wave
   gates against that number, not against a doc.
2. `project.yml`, all of it now:
   - `com.apple.developer.applesignin` in a commented Gate-0 block, in the same
     shape as `associated-domains` at `:118-126`, with a note naming what to
     uncomment.
   - `com.apple.developer.healthkit.background-delivery`, same treatment.
   - Google OAuth callback URL scheme beside the existing `onyx` scheme.
   - `NSUserNotificationsUsageDescription` for W5's supplement reminders.
3. Widget fix: apply `.containerBackground(Color.onyx.base, for: .widget)` once
   at the `TileFace` root in `OnyxWidgets.swift:87`. Do **not** edit 20 tile
   files. Do **not** touch the accessory faces — they are correctly `.clear`.
   Remove the now-redundant inner calls on the four wrapper views only if a
   screenshot shows a double-application artefact.
4. Remove `.bar`, `.micros`, `.stack` from the widget picker's offered ids.
   They stay as dashboard tiles.
5. Reduce-Motion toggle: either wire it to something the native app reads, or
   delete the row and its footer. A control that admits it does nothing is a
   rejection.

**Execution prompt**

```
Read docs/Plan-Onyx-AppStore-Sprint.md in full before anything else.

You are executing Wave 1 (Foundations) on branch wave/1-foundations in the main
checkout — this wave runs solo, no worktree, because it owns native/project.yml.

Load skills: native, schema, ship, apple-design, code-reviewer, graphify.
Load agents: architect-reviewer, ios-developer, code-reviewer, invariant-auditor.

Use `graphify query "<question>"` before grepping or reading source.

Steps 1-5 are in the plan under "W1 — Foundations". Execute them in order.

Verification:
  - npm run check must pass.
  - Run the Onyx scheme test suite and record the EXACT failure count and the
    EXACT failing test names into the plan file. This is the sprint baseline.
  - Use the built-in iOS Simulator tools (mcp__Claude_Code_iOS_Simulator__control
    and mcp__xcodebuildmcp__*) to build, install and screenshot the Home Screen
    widget gallery and at least three placed widgets at small/medium/large.
    Review the screenshots yourself. The "Please adopt containerBackground API"
    string must appear nowhere. Do not stop for visual approval.

Then run the MANDATORY END-OF-WAVE PROTOCOL in the plan, with version 7.9.0.
```

---

### W2 — Watch IA rebuilt (Lane A)

**Goal.** The Watch opens on something worth raising a wrist for.

The dashboard that exists (`DashboardPages.swift`) draws three vertical pages of
three `OnyxTile.accessory` faces and is reached from a toolbar disc. Founder
decision 2 is a rebuild, not a re-root.

- **Root when idle is the dashboard. Root when a session is live is still
  `SetView`.** W3's insight holds *during* a workout and is wrong outside one.
  Rewrite the comment at `RootView.swift:25-35` to say so.
- Page one is a hero: today's split and one large Start, or — on a rest day —
  the readiness score. The "Rest day" dead end disappears; a rest day still
  shows readiness, battery, sleep and water.
- **Colour.** `WatchInk` is two ink levels and one commit colour. The phone has
  four themed domain accents and sixteen muscle hues in `OnyxTheme`. Give each
  dashboard page its domain accent (Today → `recover`, Train → `train`, Fuel →
  `fuel`). That fixes "colourless" with tokens that already exist; do not invent
  a second palette.
- Respect the measured layout facts from `expansion-w4-watch-dashboard`: the
  inline nav bar is **64 pt**, a dashboard card row is **48.5 pt**,
  `WatchDashboard.facesPerPage` is a decision and `WatchDashboard.overflow` is
  its price. Measure anything new with `axe describe-ui`, never estimate.
  A layout test built on a guess is worse than no test.
- `.scrollInputBehavior(.disabled, for: .handGestureShortcut)` disables a scroll
  view's input entirely on this SDK. Do not reintroduce it.
- Keep `.dimmedWhenLuminanceReduced()` on every static face — burn-in.

**Execution prompt**

```
Read docs/Plan-Onyx-AppStore-Sprint.md in full before anything else, and the
"W2 — Watch IA rebuilt" section twice.

Worktree: git worktree add ../onyx-lane-a -b wave/2-watch-ia main

Load skills: native, apple-design, ui-ux-pro-max, ui-design-system,
frontend-design, graphify, code-reviewer.
Load agents: ui-ux-designer, swift-expert, ios-developer, architect-reviewer,
code-reviewer.

Use `graphify query "<question>"` before grepping or reading source.

Do NOT touch native/project.yml structurally — W1 owns it.

Verification:
  - npm run check:watch must pass.
  - Build and run OnyxWatch on BOTH an Apple Watch Ultra 2 (49mm) and a 40mm
    simulator. Screenshot every screen in the new IA on both sizes, review them
    yourself, and fix what you see. Uninstall the watch app before a shot run or
    the previous run's live session is adopted and you photograph the wrong
    state. Take a throwaway launch first — the first screenshot after an install
    comes back black.
  - Measure every new layout constant with `axe describe-ui`. State in the wave
    summary which constants were measured and which were decided.

Then run the MANDATORY END-OF-WAVE PROTOCOL in the plan, with version 7.10.0.
```

---

### W3 — Logger: Add Exercise, HR chart, Hevy (Lane B)

**Three briefs, one screen family.**

**(a) In-session Add Exercise.** No such path exists. Build it:
- Lift `ExercisePickerSheet` out of `RoutineDayEditor.swift:253` into its own
  file, parameterised on an `onPick: (ExerciseCatalogEntry) -> Void` closure.
  Reuse it in both places; do not write a second picker.
- Append to `LoggerModel.exercises`. `exercise_order` is dense from 0 via
  `deckOrder(of:)` at `LoggerModel.swift:2740` — an appended card takes the next
  index and nothing restamps.
- **The global "last time" is the real work.** `seededPrevious` reads a seed
  built from `day.exercises(for: phase)` filtered on `day_key`; a movement
  outside today's program gets nothing. Add a second, narrow lookup:
  most-recent working set for this exercise **across all sessions and all day
  keys**, formatted by the existing `SessionSeedBuilder.previousLabel`. Do not
  widen the day-scoped seed — that would change every existing card's numbers.
  Read `ExerciseCatalog` / `ExerciseDetailView`'s history path; that machinery
  exists and the logger has simply never called it.

**(b) HR chart overhaul.** `TelemetryCard.swift`.
- One colour: `OnyxDomain.recover.accent`. Delete `colour(for exerciseId:)` at
  `:314` and the `MuscleMap.movers` lookup behind it. Exercise separation is
  opacity steps of the one token.
- X axis becomes the exercise (image/name), not wall-clock time. Replace the
  `.chartXAxis { AxisMarks(values: .stride(by: .minute…)) }` at `:197-204`.
- Y axis values are hidden by default and appear on tap. `.chartYAxis(.hidden)`
  plus a tap gesture; keep `yDomain` as the scale.
- **The chart is hidden by default.** It appears only when the "Heart rate"
  summary metric is tapped, sliding up from the bottom. That metric is
  `metricCell("Avg HR", …)` at `FinishSheet.swift:269` and `OnyxStatCell("Avg HR"…)`
  at `SessionDetailView.swift:664` — both must open it.
- Apple-design rules apply to the slide-up: respond on press, spring
  `damping 0.8 / response 0.3` for a sheet, interruptible, enters and exits
  along the same path, and honours Reduce Motion with a cross-fade.

**(c) Hevy.** Collapse the card to one compact line: Hevy glyph + `142 bpm ·
412 kcal`. **It stops being a prompt**, so nothing needs dismissing — tapping it
opens a sheet with the four-row compare and the single "Use Hevy HR & calories"
action. `HevyDecision` is written only on `.use`.
- **Do not simply delete the Skip button.** The section renders while
  `hevyDecision == nil` (`SessionDetailView.swift:242`, `FinishSheet.swift:306`);
  removing the dismissal without removing the prompt leaves it on screen forever.
- It already only renders when a foreign lifting workout overlaps, so
  "only appear if detected" needs no change — verify, do not rebuild.

**Execution prompt**

```
Read docs/Plan-Onyx-AppStore-Sprint.md in full before anything else, and the
"W3 — Logger" section twice.

Worktree: git worktree add ../onyx-lane-b -b wave/3-logger main

Load skills: native, apple-design, ui-ux-pro-max, frontend-design, graphify,
code-reviewer, schema.
Load agents: ios-developer, swift-expert, ui-ux-designer, code-reviewer,
invariant-auditor, architect-reviewer.

Use `graphify query "<question>"` before grepping or reading source.

Run invariant-auditor after the seed change in (a). Widening a scoped lookup is
exactly the class of change that has silently broken this codebase before — see
the live-logger-w2 memory: "widening a PR id set IS the bug".

Do NOT touch native/project.yml structurally — W1 owns it.

Verification:
  - npm run check, plus npm run swift:core and npm run swift:data.
  - Run the Onyx scheme test suite; no NEW failures against W1's recorded
    baseline.
  - Use the built-in iOS Simulator tools to drive a live session: add an
    exercise mid-session that is NOT in today's routine and screenshot that its
    "last time" line is populated. Screenshot the finish sheet with the chart
    hidden, then tapped open. Screenshot the compact Hevy line and its sheet.
    Review all of them yourself.

Then run the MANDATORY END-OF-WAVE PROTOCOL in the plan, with version 7.11.0.
```

---

### W4 — Bidirectional session sync + Watch stays awake (Lane A)

**One root cause, two symptoms.** Session-open is not a message.

- Add a `session` kind to `WatchLink` (`WatchLink.swift:80-84`) carrying open
  and close, sent with `sendMessage` for immediacy when reachable and queued via
  `transferUserInfo` as the durable fallback. Both directions.
- Phone: send it from `LoggerModel`'s `store.openSession` path
  (`LoggerModel.swift:2837`) and from `finish()`.
- Watch: send it from `beginSession()` (`WatchModel.swift:329`) and `finish()`.
- Watch receipt of a phone-opened session must run `rejoinLiveSession()` →
  `adopt()` → `workout.start()`. That is what gives the app frontmost-app
  privilege, which is what returns the user to the workout screen on wrist
  raise. **There is nothing else to build for "stays awake".**
- **Do not add `WKExtendedRuntimeSession`.** Wrong API for a workout; Apple
  rejects the type.
- `WorkoutSessionController.start()` guards on `session == nil`, not
  `!isRunning` — a paused session reads as not running and a rejoin would build
  a second `HKWorkoutSession` over it. Both HK delegates need the
  `=== self.session` identity guard. Do not regress either.
- Review the 30 s trailing throttle at `AppEnvironment.swift:1304`. It is
  correct for tiles and wrong for session state; the new channel should bypass
  it entirely rather than shortening it.
- `storeError` bricks the watch app — it is cleared once per launch and
  `RootView` shows `StoreErrorView` whenever it is non-nil. Any new failure path
  must use `writeError`, not `storeError`.

**Execution prompt**

```
Read docs/Plan-Onyx-AppStore-Sprint.md in full before anything else, and the
"W4 — Bidirectional session sync" section twice.

Worktree: git worktree add ../onyx-lane-a -b wave/4-session-sync main
(delete the previous lane-a worktree first)

Load skills: native, graphify, code-reviewer, senior-architect.
Load agents: architect-reviewer, swift-expert, ios-developer, debugger,
code-reviewer, invariant-auditor.

Use `graphify query "<question>"` before grepping or reading source.

Do NOT touch native/project.yml structurally — W1 owns it.

Verification:
  - npm run check plus npm run check:watch.
  - Run a paired simulator test: boot an iPhone and a paired Apple Watch,
    start a session on the PHONE, and screenshot the Watch reaching the set
    screen WITHOUT a set having been logged. Then repeat in the other direction.
    If the paired-simulator handshake cannot be made to work on this machine,
    say so plainly in the wave summary and state exactly what was and was not
    proved — do not assert a sync you did not photograph.
  - Confirm HKWorkoutSession starts on a phone-originated session by reading the
    watch log, not by inference.

Then run the MANDATORY END-OF-WAVE PROTOCOL in the plan, with version 7.12.0.
```

---

### W5 — Supplements engine (Lane B)

**(a) Dose history.** Founder decision 4.
- Add a nullable `dose_periods` jsonb column to `custom_supplements`, beside the
  existing `schedule` jsonb. **DDL cannot run from this machine** — the wave
  writes the `ALTER TABLE` into `docs/sql/w5-dose-periods.sql`, tells the
  founder to paste it, and does not proceed past the local mirror until told.
- One resolver: `Supplements.doseAt(_ supplement:, on date:)`, in the same file
  and the same spirit as `stackForDate` — one resolver so the checklist, the
  micro totals, the Stack tile denominator and the export cannot disagree.
- Changing a dose today appends a period; it does not mutate the current one.
  Every historical reader goes through `doseAt`. `WeeklyExportBuilder`'s day
  build at `:998-1057` is the one that currently rewrites history.
- The export prints the dose that was in force on each day, plus a note naming
  the date a dosage changed. The golden fixtures will move — regenerate them
  **on purpose** and say so, per the `export-v5-wave` precedent.
- `archived_at` semantics are untouched. Archiving still stops scheduling
  forward and leaves history alone.

**(b) Reminders.** `UNUserNotificationCenter`, scheduled off each slot's
`"HH:MM"`. A single Settings toggle gates the lot. The usage string is already
in `project.yml` from W1. Permission is requested at the moment the toggle is
turned on, never at launch.

**(c) Vitals history** must read `doseAt` so swiping back to a day before the
change shows 300 mg, not 200 mg.

**Execution prompt**

```
Read docs/Plan-Onyx-AppStore-Sprint.md in full before anything else, and the
"W5 — Supplements engine" section twice.

Worktree: git worktree add ../onyx-lane-b -b wave/5-supplements main
(delete the previous lane-b worktree first)

Load skills: native, schema, supabase-postgres-best-practices, backfill,
graphify, code-reviewer, apple-design.
Load agents: database-architect, schema-truth-checker, supabase-schema-architect,
swift-expert, invariant-auditor, code-reviewer.

Use `graphify query "<question>"` before grepping or reading source.
Run schema-truth-checker against the LIVE database before writing any DDL —
never trust a generated types file.

Do NOT touch native/project.yml structurally — W1 owns it.

Verification:
  - npm run check plus npm run swift:core and npm run swift:data.
  - Write the ALTER TABLE to docs/sql/w5-dose-periods.sql and STOP for the
    founder to paste it. Report clearly that this is a founder gate.
  - Prove the history claim with a test, not a screenshot: change a dose, then
    assert the export and the vitals reader both return the OLD dose for a date
    before the change and the NEW dose after it.
  - Screenshot the Stack screen, the Settings reminder toggle, and a vitals
    day from before a dose change. Review them yourself.

Then run the MANDATORY END-OF-WAVE PROTOCOL in the plan, with version 7.13.0.
```

---

### W6 — HealthKit audit, unread types, off-wrist (Lane A)

- **Audit first, write it down.** Produce a table in the plan of every type
  read, every type written, where authorization is requested (three places:
  `HealthKitReader.swift:48`, `HealthSync.swift:37`, and the watch's
  `WorkoutSessionController.swift:100`), and where each reading surfaces.
- **Add the unread types.** `HealthMetrics.swift:167-186` already enumerates
  them as a not-read list: `FlightsClimbed`, `AppleMoveTime`,
  `WalkingHeartRateAverage`, `Height`, `UVExposure`, `DietaryCholesterol`,
  `DietaryFatMono/Poly`, `DietaryIodine`, `VitaminA/B6/B12/E/K`, `Zinc`,
  `Biotin`. Add `HeartRateRecoveryOneMinute` — the Watch writes it after every
  workout and it is the best recovery signal the app is not reading.
- **Every new type must surface somewhere.** `privacy/unnecessary_data` is a
  preflight rule: a read scope with a type no screen shows is a rejection.
  Either it feeds a figure or it does not get added.
- **Off-wrist.** There is no handling today; only `isLuminanceReduced` for
  display. There is nothing to "fix" in HealthKit — the Watch simply stops
  writing. The deliverable is that missing must never read as zero: derive a
  `wristCoverage` fraction per window from the presence of HR samples, and make
  every consumer either show the reading or say *"your watch was off your wrist
  for 6 h — readiness is from 4 signals, not 5."* The app already has this
  instinct for sleep; extend it, do not invent a second mechanism.
- Update all four `PrivacyInfo.xcprivacy` manifests and the App Privacy answers
  in `docs/APP_STORE.md` §3 to match the new scope exactly. A questionnaire that
  disagrees with the manifest is its own rejection.
- Background delivery stays commented out. Do not claim continuous sync.

**Execution prompt**

```
Read docs/Plan-Onyx-AppStore-Sprint.md in full before anything else, and the
"W6 — HealthKit audit" section twice.

Worktree: git worktree add ../onyx-lane-a -b wave/6-health main
(delete the previous lane-a worktree first)

Load skills: native, schema, capacitor-security, graphify, code-reviewer,
backfill.
Load agents: architect-reviewer, swift-expert, ios-developer, invariant-auditor,
code-reviewer.

Use `graphify query "<question>"` before grepping or reading source.

Do NOT touch native/project.yml structurally — W1 owns it. The
background-delivery entitlement stays commented.

Verification:
  - npm run check plus swift:core, swift:data, check:watch.
  - An unsigned simulator build has NO HealthKit (see the expansion-w5-telemetry
    memory). Do not attempt to prove a read on a bare simulator and do not claim
    one. State plainly which reads were proved and which were only compiled.
  - Screenshot the off-wrist copy on a readiness card with a synthetic gap.

Then run the MANDATORY END-OF-WAVE PROTOCOL in the plan, with version 7.14.0.
```

---

### W7 — Auth, Settings, preflight (Lane B)

**(a) Sign in with Apple + Google.**
- `ASAuthorizationAppleIDButton` → `supabase.auth.signInWithIdToken`. Google via
  the URL scheme W1 added. Both beside the existing email/password, which stays.
- The `applesignin` entitlement stays commented out (founder decision 5). The
  wave must say, in its summary and in `docs/APP_STORE.md`, that this is
  **written and not verified on device** until Gate 0.
- Adding Google makes Sign in with Apple **mandatory** under 4.8. Both or
  neither; never Google alone.

**(b) Account deletion** already ships. The work here is verification, not
building: confirm `delete_my_account` exists server-side, confirm it removes the
caller's rows across all 34 mirrored tables and the `auth.users` row, and
**commit the function's SQL into `docs/sql/` so it stops being invisible.**

**(c) Settings redesign.** Nine sections, six static prose footers, text-heavy.
Apply `apple-design`:
- Every row gets one compact sub-line saying what it does. The pattern already
  exists — `LabeledContent("<title>", value: <summary>)` inside a
  `NavigationLink`, used at eleven sites. Extend it; do not invent a second one.
- Section footers shrink to what the sub-lines cannot carry. Grouping and
  mapping: a control sits next to what it affects, and if a label is needed to
  explain a control the mapping is weak.
- Keep the medical disclaimer (1.4.1) and the destructive rows exactly as they
  are — forgiveness before minimalism.

**(d) Preflight.** Rewrite `docs/APP_STORE.md` end to end against the binary:
version, `project.yml` line numbers, the account-deletion row (now **Pass**, not
N/A), `design/sign_in_with_apple` (now in scope), the subscription rows (still
N/A — we ship free), the privacy answers from W6, and the App Review notes.
Re-verify both live URLs with `curl -I`.

**Execution prompt**

```
Read docs/Plan-Onyx-AppStore-Sprint.md in full before anything else, and the
"W7 — Auth, Settings, preflight" section twice.

Worktree: git worktree add ../onyx-lane-b -b wave/7-auth-store main
(delete the previous lane-b worktree first)

Load skills: native, apple-design, ui-ux-pro-max, ui-design-system,
capacitor-apple-review-preflight, capacitor-security, schema, graphify,
code-reviewer, ship.
Load agents: ios-developer, swift-expert, ui-ux-designer, backend-architect,
schema-truth-checker, code-reviewer, architect-reviewer.

Use `graphify query "<question>"` before grepping or reading source.

Do NOT touch native/project.yml structurally — W1 owns it. The applesignin
entitlement stays commented; uncommenting it is a post-Gate-0 one-liner.

Verification:
  - npm run check plus swift:core, swift:data.
  - Run the Onyx scheme test suite; no NEW failures against W1's baseline.
  - Screenshot the sign-in screen with all three options, and every Settings
    section at default and at AX5 text size. Review them yourself.
  - curl -I both live URLs and paste the status lines into the wave summary.
  - State explicitly which auth paths were compiled but NOT exercised.

Then run the MANDATORY END-OF-WAVE PROTOCOL in the plan, with version 7.15.0.
```

---

### W8 — Final integration (solo)

1. Re-run everything: `npm run check`, `swift:core`, `swift:data`,
   `check:watch`, and the full `Onyx` scheme suite. Compare to W1's baseline.
2. Regenerate App Store screenshots — `scripts/store-shots.sh`. Note that its
   default devices are not installed on this machine; fix the script or the
   simulator list, do not skip the step.
3. Version **8.0.0**. `npm run version:sync`, `cd native && xcodegen generate`,
   `npm run version:check`.
4. `docs/CHANGELOG.md` gets an 8.0.0 release section naming every surface.
5. Move the plan: `docs/Plan-Onyx-AppStore-Sprint.md` →
   `docs/Done/Plan-Onyx-AppStore-Sprint-Done.md`. (The repo's directory is
   `docs/Done` with a capital D; the filesystem is case-insensitive so
   `docs/done/…` lands in the same place.)
6. Purge: all caches and derived data, `native/__screenshots__`,
   `native/__store__`. Report GB freed.
7. Branches: every `wave/*` branch deleted locally and on `origin`, every
   worktree removed. `git branch -a` shows `main` and `origin/main` and nothing
   else.
8. `git push origin main`.
9. Produce the final numbered summary — plain everyday English, compact, one
   numbered line per thing that is new or changed.

---

## MANDATORY END-OF-WAVE PROTOCOL

Every wave, without exception, before it is called finished:

1. **Evaluate failures.** List every check that did not pass, every step that
   could not run on this machine, and the workaround taken. A gate that could
   not run is reported as "not run", never as "passed".
2. **Merge into `main`.** Resolve `project.yml` version conflicts by re-running
   `npm run version:sync && cd native && xcodegen generate` — never by hand.
3. **Version + changelog.** Set `package.json` `version` to the wave's number,
   `npm run version:sync`, `cd native && xcodegen generate`, append a
   `docs/CHANGELOG.md` section, confirm `npm run version:check` passes.
   A wave without both is not finished.
4. **Delete the branch**, local and remote, and remove the worktree.
5. **Purge cache and derived data:**
   ```bash
   du -sh ~/Library/Developer/Xcode/DerivedData ~/Library/Caches/onyx-swift ~/Library/Caches/org.swift.swiftpm
   rm -rf ~/Library/Developer/Xcode/DerivedData/* ~/Library/Caches/onyx-swift/* ~/Library/Caches/org.swift.swiftpm/*
   ```
   Report GB freed, measured before and after. Baseline at sprint start was
   **14.4 GB** (6.9 DerivedData + 7.2 onyx-swift + 0.3 SwiftPM).
   *Cost to expect:* `npm run check` uses `~/Library/Caches/onyx-swift`, so the
   next wave's `check:watch` is a cold build.
6. **Update `docs/Plan-Onyx-AppStore-Sprint.md`** with a wave summary: what
   shipped, what the code falsified about the brief, what was left open and why.
7. `graphify update .` to keep the knowledge graph current.

---

## Verification (sprint level)

- `npm run check` — the standing gate. **It does not run `OnyxTests`,
  `swift:core` or `swift:data`; run those separately every wave.**
- `npm run swift:core`, `npm run swift:data` — the pure domain tests.
- Full `Onyx` scheme suite — gated against W1's *measured* baseline, not a doc.
- Simulator: `mcp__Claude_Code_iOS_Simulator__control` and
  `mcp__xcodebuildmcp__*` for build, install, screenshot and UI inspection.
  Watch shots need `axe describe-ui` for real measurements.
- `curl -I` on both live legal URLs.
- End to end at W8: install a fresh build, create an account, log a session on
  each device, add a mid-session exercise, place three widgets, change a
  supplement dose and read a prior day, delete the account.

## Out of scope

- StoreKit, paywall, any subscription (founder decision 1 — 1.1).
- `WKExtendedRuntimeSession`.
- Uncommenting `applesignin`, `associated-domains` or HealthKit background
  delivery — all four are Gate 0 and Gate 0 is a purchase.
- Rotating the Supabase `service_role` key and the demo-account password. The
  founder does this at the provider; no commit can.

---

# Wave summaries

## W1 — Foundations (7.9.0)

### THE BASELINE — measured, and named for the first time

`xcodebuild test -scheme Onyx -destination 'platform=iOS Simulator,name=iPhone 15'`
on `main` @ `cbac4221`, before any W1 edit. **Every later wave gates against
this and against nothing else.** No document in this repo had ever listed
*which* tests fail; four of them disagreed on the count (5, 7, 10, 11).

| Bundle | Tests | Issues |
|---|---|---|
| `OnyxTests` | 64 in 6 suites | **11**, across **9** distinct test names |
| `OnyxDataTests` | 727 in 89 suites | **1** |
| `OnyxCoreTests` | 706 in 136 suites | 0 |
| `OnyxUITests` | 42 in 9 suites | 0 |

**The nine `OnyxTests` names, by suite:**

| Suite | Test |
|---|---|
| History weeks | `A capsule counts its week and marks the days that were missed` |
| History weeks | `Week 0 is the week the block opened on` |
| Live Stats fixture | `a credible previous session still gets its delta` |
| Live Stats fixture | `a previous session's impossible clock produces no delta, not a wrong one` |
| Session summary — the hotfix | `a treadmill logged on this phone is titled Treadmill, not its slug` |
| Session summary — the hotfix | `the ledger rows are this session's sets and only this session's` |
| Session summary — the hotfix | `the seeded previous session reaches TopLifts.previousBests` |
| Workout week | `finishing a session leaves the tab on '.done', with the week and the ledger carrying it` |
| Workout week | `ready to progress fires only after the ceiling is cleared twice` |

**The one `OnyxDataTests` name:** `stores, retrieves and removes a session blob`
(`AppDatabaseTests.swift:254`) — `Keychain error -34018: A required entitlement
is not present`. **Simulator-only, and a Gate 0 symptom**: it passes on macOS
via `npm run swift:data`. It is not a code defect and no wave should try to fix
it before the Developer Program is bought.

So `Plan-Onyx-Expansion-Done.md`'s "11 issues" was the accurate one; the 5, 7
and 10 claims elsewhere in `docs/Done/` are stale and should not be cited again.

### What the code falsified about the brief

1. **`.bar`, `.micros` and `.stack` were never in the widget gallery.** Founder
   decision 6 is already true and has been for a release. `TileOption`
   (`OnyxIntents.swift:104`) lists twenty-one ids and omits those three on
   purpose — its own comment says "an option that draws 'No face for this one
   yet' is not an option". The phone dashboard filters them too
   (`TodayModel.swift:205`, `:212`, `:281`), and `TodayModelTests.swift:59`
   asserts it. The `TileNote("No face for this one yet.")` arm in
   `OnyxTile.face` is an unreachable `switch` arm that cannot be deleted,
   because `WidgetId` is exhaustive. **No edit. The App Store risk I reported
   from a grep was not real** — the string exists, nothing can reach it.
2. **Local notifications need no Info.plist key on iOS.**
   `UNUserNotificationCenter.requestAuthorization` prompts without one;
   `NSUserNotificationsUsageDescription` is a macOS key. W5's reminders need no
   `project.yml` change at all, so the planned usage string was dropped.
3. **Google sign-in needs no new URL scheme.** Supabase OAuth returns to a
   redirect the app already owns — `onyx://`, registered at
   `project.yml:187-191` for widget deep links. The reversed-client-ID scheme
   is only needed when linking Google's own SDK, which W7 will not do. Dropped.
4. **Reduce Motion was deleted, not wired.** The app already honours the SYSTEM
   setting in eight places (`TileFrame`, `DashboardGrid`, `SmartStackView`,
   `TodayCards`, `PulseSquares`, `PulseTabView`, `PulseDoms`, `CardioToast`).
   The row wrote a column nothing reads and credited "the web app", which was
   retired at 3.0.0. A second app-level copy of a system switch is a second
   answer to one question, so the row, its binding and
   `SettingsModel.setReduceMotion` are gone. The column stays — deleting it
   ripples into the mirror generator for no gain.

### The machine this sprint runs on

Found by a destination probe, not assumed. **Later waves must respect it:**

| | |
|---|---|
| iOS simulators installed | **`iPhone 15` (iOS 27.0) — that is the only one.** `iPhone 16 Pro` and `iPhone 17 Pro` do not exist here; `scripts/swift-ui-test.sh` already defaults to 15 for this reason. |
| watchOS simulators installed | `Apple Watch Ultra 2 (49mm)` (watchOS 27.0), and **`Apple Watch SE 3 (40mm)` (watchOS 27.0), created in this wave** — the newest 40 mm device type Xcode offers. |
| Simulator pairs | `Ultra 2 ↔ iPhone 15` (**active**), `SE 3 40mm ↔ iPhone 15` (**inactive**). Only one pair is active at a time — switch with `xcrun simctl pair_activate <pair-udid>`. |
| Physical devices attached | `iPhone`, `Michael's Apple Watch` — both unusable until Gate 0. |

**Consequences.**

- **W2 can now photograph 40 mm.** There was no 40 mm simulator; this wave
  created `Apple Watch SE 3 (40mm)` on watchOS 27.0, paired it to `iPhone 15`
  and booted it. 40 mm has been asserted by `OnyxWatchLayoutTests` and never
  seen since `expansion-w3-watch-logger` recorded it — W2 is the wave that ends
  that, and it has no excuse left.
- **W4 has a real pair to test against.** `Ultra 2 ↔ iPhone 15` is already
  active and both are booted, so the paired-simulator sync test the plan asks
  for is possible on this machine. Activating the 40 mm pair deactivates the
  49 mm one; a wave that needs the other must call `pair_activate` and say so.
- **W8's `scripts/store-shots.sh` will still fail.** It names iPhone 17 Pro Max
  and iPhone 17 Pro; only `iPhone 15` exists here. Either create those device
  types the same way, or change the script. Do not skip the step.

### Changed

- `native/project.yml` — `com.apple.developer.applesignin` and
  `com.apple.developer.healthkit.background-delivery` added as commented Gate-0
  blocks, in the same shape as the `associated-domains` block beneath them, each
  naming exactly what to uncomment and what to tick in the portal.
- `native/OnyxWidgets/OnyxWidgets.swift` — one
  `.containerBackground(Color.onyx.base, for: .widget)` at `TileFace`, the one
  widget root that draws a tile. Twelve of the twenty faces `OnyxTile.face`
  dispatches to never called it, and four more carry it on a wrapper view that
  `face` goes around. Applied at the root rather than in twenty files, because
  "each face remembers" is the rule that already failed.
- `native/Onyx/Features/Settings/SettingsTabView.swift`,
  `SettingsModel.swift` — the Reduce Motion row and its two dead members.
