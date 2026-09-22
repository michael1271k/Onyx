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

### Verification — what was proved, and how

- **`npm run check` — PASSED** (exit 0), including `check:watch`.
- **The widget fix was proved by placing real widgets**, not by reading the
  diff. A **medium** and a **large** Onyx widget were added to the iPhone 15
  Home Screen: both draw on the obsidian `Color.onyx.base` container with the
  real empty state ("Nothing to show yet / Open Onyx once and the tiles fill
  from its database"), and the string "Please adopt containerBackground API"
  appears nowhere.
- **One false alarm, recorded so the next wave does not repeat it.** The first
  attempt built with `CODE_SIGNING_ALLOWED=NO` and every widget rendered
  **solid white**. That is not a rendering defect: stripping signing strips the
  entitlements, and the log says so plainly —
  `No AppIntent in timeline(for:with:)` followed by
  `CHSErrorDomain Code=1101 "Returned view collection was either nil or empty."`
  **Never verify a widget from a `CODE_SIGNING_ALLOWED=NO` build.** Build it
  signed (the free team signs a simulator build fine) or you are photographing
  your own build flags.

### Left open

- **Widgets cannot show DATA on this machine** — only the empty state. The App
  Group is what lets the extension read the app's database, and a free personal
  team cannot sign it (Gate 0). The empty state rendering correctly is the whole
  of what is provable here, and it is enough for this wave's claim.
- **The four inner `containerBackground` calls were left in place**
  (`OnyxTraining:61`, `OnyxVitals:62`, `OnyxLifestyle:116`, `:189`). They are
  redundant now and harmless — the screenshots show no double-application
  artefact. Removing them is cleanup with a regression risk and no user-visible
  gain; a later wave can do it if it is touching those files anyway.

### Close-out

| | |
|---|---|
| Version | **7.9.0** (70900), `version:check` in sync |
| Changelog | `docs/CHANGELOG.md` → `[7.9.0] — The widgets draw again` |
| Merged | `c1b3908e` → `main`, no-ff |
| Branch | `wave/1-foundations` deleted; `git branch -a` shows only `main` and `origin/main` |
| Cache purged | **24.58 GB freed** (4.7 G DerivedData + 20 G onyx-swift + 324 M SwiftPM → 0) |

**Cost the next wave inherits:** `~/Library/Caches/onyx-swift` is empty, so the
first `npm run check` in W2 or W3 is a full cold build of OnyxCore, OnyxData,
OnyxUI and the watch target. Budget for it rather than assuming a hung build.

---

## W2 — Watch IA rebuilt (7.10.0, Lane A)

### What shipped

The watch app's idle root is a **four-page vertical dashboard**. A live session
still roots at `SetView`, and W3's "it is the set, not a dashboard" comment is
rewritten rather than deleted — it holds *during* a workout and was always wrong
outside one.

| Page | Accent | Draws |
|---|---|---|
| 1 · **Onyx** | the split's own `Color.onyx.dayLabel` | split at `WatchType.figure`, a chip row (movements · battery · readiness), one large Start |
| 2 · **Today** | `OnyxDomain.recover` | `.recovery` (battery + readiness), `.sleep`, `.stress` |
| 3 · **Train** | `OnyxDomain.train` | `.volume`, `.weekRings`, `.steps` |
| 4 · **Fuel** | `OnyxDomain.fuel` | `.fuel`, `.water`, "+1 glass" |

- **The rest-day dead end is gone.** It was the word "Rest day" and nothing
  else. It is now "Rest day" in Lunar over the readiness score as the hero, with
  battery and last night's sleep beside it — and three pages of readings behind
  it, on a rest day like any other.
- **The colour is card chrome, not a rewritten face.** `AccessoryFace` is shared
  with the phone's Lock Screen and this watch's complications and must not
  change, so `DashboardCard` carries the page's accent as a 14 % fill, a 45 %
  hairline, and a two-style `foregroundStyle` hierarchy — which lands on the
  face's glyph and headline precisely because `AccessoryFace.rectangular` sets
  no style of its own and its caption sets `.secondary`. That is an environment
  value, not an edit.
- **`.train` came off the Train page**, because page one says the same thing at
  four times the size. **`.steps` moved off Fuel onto Train**, because three
  faces plus the water button hung 24.5 pt below even the 49 mm fold and the
  screenshot showed "Add a glass" cut through the middle.
- **`DashboardView(showsStart:)`** — `DeckView`'s in-session toolbar disc still
  pushes the dashboard, without the Start page. The disc on `StartView` is gone:
  a link from page one of a pager to the pager it is in does nothing.

### What the code falsified about the brief

1. **The re-root bought no height.** The whole plan for this wave assumed a root
   screen would have a smaller navigation bar than a pushed one — no back
   chevron, no toolbar item. The accessibility tree of the running root reads
   `{{0, 0}, {205, 64}}`, the same 64 the pushed bar measured. There is no
   `rootBar` constant because there is no second number.
2. **A 40 mm case had never been measured in this repository.** Every constant in
   `WatchPanel.swift` was read off the 49 mm Ultra 2 and used as a conservative
   proxy, and W1 created the first 40 mm simulator. The device says the bar is
   **47.5** and not 64, the page is **149.5** and not 133, a row is **46** and
   not 48.5, and the water button is **45** and not 54. So the suite's standing
   claim that "the third card hangs 20.5 pt below the 40 mm fold" was **false**:
   three rows are 146 of 149.5 and nothing scrolls. `OnyxWatchLayoutTests` now
   replays both the conservative budget and the measured device, and the 4 pt
   gap between them is asserted rather than smoothed away.
3. **watchOS does not tint an inline navigation title with `.tint`.** The page
   model relied on it. The 49 mm screenshots came back with the same
   `WatchInk.secondary` grey heading with and without the modifier.
   `.foregroundStyle` does not reach a navigation title either, and `.principal`
   is not a placement this app has ever proved on watchOS. The title stays grey,
   the colour lives in the cards, and the finding is recorded in
   `DashboardPages.swift` so the next wave does not re-spend the round.
4. **Clearing the schedule override does not make a rest day.**
   `Schedule.scheduleDayIn` falls back to a `ProgramDay`'s own `weekday`, so the
   first `restday` shot came back as the training hero with "Upper B" on it — a
   real screen under the wrong filename. A program with **no days** is the only
   seed `resolveDay` reads as nothing scheduled.

### Defects found and fixed that the brief did not name

- **`MirrorView` and `FinishView` held a full-width `WatchInk.commit` capsule at
  full brightness in the always-on state.** `SetView` applies
  `dimmedWhenLuminanceReduced` to its logger page and to nothing else, so the
  two live-session screens held longest were the two missing the burn-in call —
  the exact case `WatchInk`'s own header names.
- **The DEBUG widget harness grey-washed the face it exists to review.** The
  first version of the tinted card was reused in `LiveWidgetPreview` with
  `WatchInk.secondary` as its accent, which set a `foregroundStyle` that
  `LiveWorkoutFace`'s un-styled movement name inherited — so `widget.png`
  photographed it at white 0.62 while the real complication draws full ink.
  `DashboardCard.accent` is `Color?` now; nil draws the plain row and sets no
  style at all.
- **The DEBUG page hook could select a page that does not exist.** It wrote
  `page = .start` unconditionally, and `.start` is not in `pages` when
  `showsStart` is false — a `TabView` selection matching no tag draws nothing,
  silently and permanently. Clamped to `pages`, and the initial selection moved
  into `init(showsStart:)` so there is no `onAppear` ordering to get wrong.
- **The rest-day hero had no accessibility label.** VoiceOver read "81" then
  "Readiness" as two elements, and "—" on a day with no score. One grouped
  element now, with "not scored yet" as the value.

### Constants — measured vs decided

| Constant | Value | How |
|---|---|---|
| `WatchCase.navBar` | 64 | **measured**, 49 mm, root AND pushed |
| `WatchCase.navBar40mm` | 47.5 | **measured**, 40 mm root — new this wave |
| `WatchCase.content40mmHeight` | 149.5 | derived from the above (was 133, an estimate) |
| `WatchDashboard.rowHeight40mm` | 46 | **measured** — cards at y = 51.5 / 101.5 / 151.5 |
| `WatchDashboard.buttonHeight40mm` | 45 | **measured** — `{{9.5, 147.5}, {143, 45}}` |
| Hero chip row width | 121 pt of 146 | **measured**, 40 mm — x = 3.5 → 124.5 |
| `WatchDashboard.facesPerPage` | 3 | **decided** (unchanged) — and now it fits |
| Card fill `0.14` / hairline `0.45` | — | **decided**, with arithmetic: 0.14 × `LuminanceDim`'s 0.76 = 0.106, i.e. the dimmed card weighs what `WatchInk.fill` weighed. The always-on state costs the colour, not the layout |
| Page accents | `recover` / `train` / `fuel` / `dayLabel` | **decided** — existing tokens, no new palette |

### Verification

| Gate | Result |
|---|---|
| `npm run check` (incl. `check:watch`, `swift:ui`) | **PASSED**, exit 0 |
| `npm run swift:core` | **PASSED** — 708 tests, 136 suites (was 706; +2 this wave) |
| `npm run swift:data` | **PASSED** — 727 tests, 89 suites |
| Full `Onyx` scheme suite | **NOT RUN** — see below |

- **Screenshots on BOTH cases**, which is what this wave was asked for: five
  screens on `Apple Watch Ultra 2 (49mm)` and six on `Apple Watch SE 3 (40mm)`,
  the first watch screens ever photographed at 40 mm in this project. Every page
  fits both cases with no card and no button below the fold.
- **The in-session push was driven, not assumed** — `axe tap` on `DeckView`'s
  toolbar disc during a live session, photographed opening on Today with a back
  chevron and no Start page.
- **`OnyxDataTests` failed once and passes alone.** `W6 seam benchmarks` →
  "the nutrition day is one read, and it holds what seven held" is a **timing**
  test; it failed while a watch build was compiling on the same machine and
  passed on a clean re-run. **Do not run `swift:data` concurrently with a
  build** — it reads as a data defect and is not one.
- **The `Onyx` scheme suite was not run.** This wave changed no iOS app-target
  source; the one shared module it touched is `OnyxCore`, whose own 708 tests
  pass. W1's baseline (11 issues / 9 names) is therefore unchallenged rather
  than re-measured, and this is reported as *not run*, not as *passed*.

### Left open

- **`watch-shot.sh nophone` is only honest as the first screen of a run**, after
  an uninstall. It carries no launch environment, so it draws whatever
  `WatchContextCache` holds — and every other screen in the list seeds one. The
  script says so at the hook; `all` no longer includes it.
- **`WeekMarks` missed-day dots now resolve `.secondary` to `WatchInk.secondary`**
  rather than the system's, because the card sets a two-style hierarchy. Same
  family, visually correct in the Train screenshot on both cases, noted rather
  than worked around.
- **The page indicator dots sit slightly over the navigation heading** at both
  case sizes. System chrome on both counts; nothing in this app draws either.
- **The 49 mm pair is active again.** W2 activated `SE 3 40mm ↔ iPhone 15` to
  photograph 40 mm and restored `Ultra 2 ↔ iPhone 15` afterwards, so W4 finds
  the pair it needs. Only one pair is active at a time.

---

## W3 — Logger: Add Exercise, HR chart, Hevy (7.11.0, Lane B)

### What shipped

- **(a) Add a movement mid-session.**
  - **The picker.** `ExercisePickerSheet` is now its own file
    (`Features/Exercises/`). The routine builder and the live deck's new
    "Add a movement" row (live decks only) both call it.
  - **The card.** `LoggerModel.addExercise(named:exerciseId:)` places the new
    card at the bottom, and its plan is added to `day`. Its sets take the next
    `exercise_order`, and no other card is renumbered. It starts from
    `RoutineExercise.starting`, which is now the one place both callers get the
    3 × 8–12 / 120 s default from.
  - **"Last time" comes from a second, narrow lookup.**
    `AppDatabase.lastWorkingSet(named:userId:excludingSession:)` returns the
    last non-drop working set of the movement across every session and day key.
    It resolves the movement by canonical name under all of its ids, the way
    `PrRecorder.baselines` gathers `siblings`. It reads through `historySets`,
    folds pairs with the seed's own `collapsePairs`, and is limited to the
    current user.
  - **Only an added movement reads that lookup.** `LoggerModel.lastTimes` is
    read only when the day's seed has **no** entry for the movement.
  - **The seed is built from `programDay`**, the day as it was handed in, and
    never from the enlarged `day`.
  - **The added card gets a line of its own:** `last 25kg × 11 · Sat 19 Sept`.
- **(b) The heart-rate chart.**
  - **One colour.** `TelemetryCard` draws everything in
    `OnyxDomain.recover.accent`, with three opacity steps (1 / .75 / .55).
    `colour(for:)` and the `MuscleMap.movers` lookup behind it are deleted.
  - **Axes.** The x axis shows each movement's number at the middle of its
    first stretch. The y scale is hidden until the plot is tapped.
  - **Where it opens.** The chart is gone from both pages. It lives in
    `heartRatePanel`, a bottom sheet opened by tapping the Avg HR reading on
    `FinishSheet` or on `SessionDetailView`.
  - **Motion.** Spring 0.8 / 0.3 on an offset, so a tap mid-flight turns it
    around. It enters and leaves along the same path. Dragging down dismisses
    it, using the projected end point, and tapping the dimmed backdrop also
    dismisses it. Under Reduce Motion it cross-fades.
- **(c) Hevy.** The card is now one compact line: the source's initial, its
  name, and `128 bpm · 356 kcal`. Tapping it opens a sheet with the four-row
  comparison and a single "Use Hevy HR & calories". Skip and every `.skip`
  write are gone. Both callers hide the line only on `.use`, and nothing else
  reads `hevyDecision`.

### What the code falsified about the brief

1. **`OnyxDomain.recover.accent` is not red.**
   - **What it is.** It is Lunar lavender, `#A79FD6`, in the default theme.
     Founder decision 3 names the token *and* describes it as "red-family",
     and those two statements conflict.
   - **What was done.** The chart uses the token, because the decision names
     it.
   - **Why there is no red alternative.** There is no themed red:
     `Color.onyx.danger` is a literal hex and does not follow Appearance
     presets.
   - **Status.** This is left to the founder. The swap is a one-line change to
     `TelemetryCard.ink`.
2. **The deck had no "last time" line to populate.**
   - **What happened to it.** The founder removed it. The reason is still in
     the `ExerciseCardView` header comment: it repeated the first row's two
     numbers.
   - **What the brief's "last time" actually is.** It is `SetRow.previous`,
     which the Live Activity reads as `lastTime`.
   - **What was done.** Only an added card got a line back, because its
     numbers come from another split and the date is the one thing its rows
     cannot show. The cards the day opened with are unchanged.
3. **The picker was never parameterised on `ExerciseCatalogEntry`.**
   - **Why that type does not fit.** It is the Library's "movements with
     history" row. The picker lists every `Exercise` catalogue row and offers
     to create new ones.
   - **What the closure takes instead.** It hands back
     `(name, picked: Exercise?)`, where `nil` means a new name. The routine
     builder then creates the movement, and the logger records the picked
     catalogue id.
4. **Appending to `LoggerModel.exercises` is not enough.**
   - **Phase switch.** `rebuildForPhase` rebuilds the deck from `day.exercises`,
     so a card that lived only in the array disappeared on a phase switch.
   - **Relaunch.** `restoreLoggedSets` ignored `DeckRestore`'s `unmatched`
     rows, so an added movement's logged sets were not drawn after a relaunch.
   - **What was done.** The card now joins `day`. A relaunch rebuilds it from
     the `unmatched` rows, but only for ids the catalogue can name.
5. **"`ExerciseDetailView`'s history path" is `historySets(exerciseIds: [id])`,
   a single id.** For a lift logged on both clients that finds only half the
   history. The new lookup gathers every id by name first.
6. **The Avg HR cell on the finish sheet was already a tap target** that opened
   its stepper. With a heart-rate series present, the tap now opens the chart,
   and the stepper is reached through "Edit the average" inside the panel.
   With no series, the tap behaves as before.
7. **`.chartYAxis(.hidden)` shifts the plot.**
   - **The problem.** Revealing the labels takes a column of width, so every
     movement boundary moved sideways under the finger that tapped.
   - **Why a style toggle alone fails.** The axis is now always laid out and
     only its ink changes. But Swift Charts **caches axis labels**: a
     state-driven `foregroundStyle` or `opacity` inside `AxisValueLabel` never
     updated, even though the grid line did.
   - **The fix.** `.id(showScale)` on the chart.
   - **A second trap.** `value.as(Double.self)` is nil when a mark was plotted
     with an `Int` y, so every mark now plots a `Double`.
8. **"Only appears if detected" was verified, not rebuilt.** The chain is
   `AppEnvironment.foreignWorkout` → `liftingOverlap` → `WorkoutProvenance.pick`,
   which returns `.foreign` only for a lifting workout written by another
   bundle.

### Defects found and fixed that the brief did not name

- **The seed-widening trap.** A phase switch rebuilt the seed from the enlarged
  `day`. That gave the added movement a cold-start entry, which silently
  switched off its "last time" (the gate is `seeded == nil`). Code review caught
  it, and a test now pins it.
- **"Last time" could be a drop set.** A session that ended on a 15 kg drop set
  would have reported the drop as the last set. The lookup now takes the last
  set that is not a drop set.
- **Opening the chart stamped Duration as "edited".** The chart path now runs
  no `commitMetrics`.
- **Tapping "Use" cut the sheet's dismissal short.** It removed the view that
  presents the sheet while the sheet was still leaving. `onUse` now runs from
  `onDismiss`.
- **After Hevy's figures were adopted,** the finish sheet's caption credited
  "the watch's own workout". It now names Hevy.
- **The picker's muscle label read "Rear_Delts".**
- **The pinned Finish button drew through the panel.** On this SDK a
  `.safeAreaInset` draws above an overlay placed on the `NavigationStack`.
  The inset is now hidden while the panel is up, and opening the panel moves
  the sheet to `.large` so its title is not clipped on a small phone.
- **The shaded area under the chart filled from 0.** It ran below the plot to
  the card's edge, and now starts at the plot floor.
- **A `check:body` near-miss.** A store write in a `SessionDetailView` view
  builder had only ever passed the scanner because the Skip closure's `Task {`
  sat inside its six-line window. The write is now a method, `useHevy`.
- **AX5 (largest text size).**
  - The added card's `last` line truncated to `25kg… · Sat 1…`. At accessibility
    sizes the date now goes on its own line.
  - The Hevy line truncated its figures and squashed its monogram. The figures
    now go on their own lines, and the monogram has a minimum size instead of a
    fixed 24 pt.

### Verification

- `npm run check`: **PASSED** (exit 0). This includes `swift:ui` (42/42) and
  `check:watch`.
- `npm run swift:core`: **706/706**.
- `npm run swift:data`: **733/733** (727 plus 6 new) when run alone.
  - Under load it recorded one `SeamBenchmarkTests` timing issue. That is the
    known W7 flake, and it passed when re-run alone.
- **`Onyx` scheme tests.** No new failures.
  - **OnyxTests.** The failing names are exactly W1's nine. The `64 tests /
    11 issues` summary line comes from one parallel worker, and the new
    `Add exercise mid-session` suite (2 tests) passed in run 1.
  - **OnyxDataTests.** One issue: the Keychain `stores, retrieves and removes
    a session blob` test, which is Gate 0.
  - **OnyxCoreTests** 706/706, **OnyxUITests** 42/42.
- **invariant-auditor** was run after the seed change. It found one risk: an
  edit deck could draw a "last time" line through restore, because
  `lastWorkingSet` has no date bound. Fixed with an `isEditing` gate. Its
  other findings were OK.
- **code-reviewer, architect-reviewer and ui-ux-designer** were run on the full
  diff and on the screenshots. Every bug and risk they raised was fixed or is
  listed below.
- **Simulator, iPhone 15 on iOS 27.0, signed ad-hoc build.**
  - **The add path** was driven by hand on the new `logger-add` harness screen:
    Upper B deck, then "Add a movement", then Face Pull, which the store holds
    only on an Upper A session. The card was added as "9 OF 9" with
    `last 25kg × 11`, and its rows pre-filled with 25 × 11. Checked again at
    AX5.
  - **The finish sheet** was photographed with the chart hidden, then with it
    opened from Avg HR. After that: the scale revealed with no shift, drag to
    dismiss, tap on the dimmed backdrop to dismiss, and "Edit the average"
    handing off to the stepper.
  - **The session page** was photographed with the chart hidden and then open.
  - **Hevy:** the compact line, its sheet, and the result of "Use" (128 bpm and
    356 kcal adopted, the line gone, the caption naming Hevy). Also checked at
    AX5.
  - **Health permission.** Health read/write access was granted once, on the
    simulator only, for the harness's synthetic heart-rate seed (Past 30 Days).

### Left open

- **The watch cannot see a phone-added movement (W4).**
  - **Why.** `WatchModel.planDeck` drops sets that match no plan, so once a
    movement is added the two decks and their `setsPlanned` / `plannedSets`
    counts disagree.
  - **Suggested fix (architect).** Move the rule "unmatched logged keys become
    `RoutineExercise.starting` plans" into `DeckRestore` so both clients share
    it.
  - **A related gap.** A movement that was added but never logged is not kept
    across a relaunch. It has nothing in the log to rebuild from.
- **The colour decision above belongs to the founder.**
- **The Avg HR cell can show "—" while the chart's headline shows the series
  mean.** The cell reads the session row's stored average and the chart falls
  back to the trace. This predates W3: the inline card showed the same
  mismatch.
- **Earlier-wave issues seen during review:**
  - The open Avg HR stepper spills over its neighbouring cells, and its buttons
    are 30 pt.
  - At AX5 the logger's pinned header takes about 55 % of the screen.
  - "INTENSITY" hyphenates at AX5.
  - The "adopt only what is not measured" Hevy rule is written in three places.
- **The session page's navigation bar stays live above the dimmed backdrop.**
  The page is pushed and cannot overlay its parent's bar.
