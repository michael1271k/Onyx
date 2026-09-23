# Changelog

All notable changes to **Onyx** — the native iOS/watchOS app.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## How a version works here

`package.json` → `"version"` is the **single source of truth**. Nothing else is
hand-edited:

| Surface | Where the number comes from |
|---|---|
| Native app, widget extension, watch app | `MARKETING_VERSION` in `native/project.yml`, written by `scripts/sync-version.mjs` and read through `$(MARKETING_VERSION)` in each `Info.plist` |
| Settings → Version (native) | `Bundle.main.infoDictionary` at runtime — `OnyxLinks.versionString` |

```bash
# bump the SSoT, then push it everywhere
npm version 1.4.0 --no-git-tag-version   # or edit package.json by hand
npm run version:sync                     # writes native/project.yml
cd native && xcodegen generate           # regenerate, never hand-edit the .xcodeproj
```

`npm run version:check` fails when any surface has drifted, and `npm run check`
runs it. The build number (`CURRENT_PROJECT_VERSION`) is **derived**, not
stored: `1.3.0` → `10300`. It is monotonic for as long as the marketing version
is, which is all App Store Connect asks for, and there is no second field to rot
out of step with the first.

**Semver, as this project reads it**

- **MAJOR** — a migration the user has to be told about: a schema change that is
  not backward compatible, a plan/scoring model whose numbers move, a removed
  screen.
- **MINOR** — a wave, sprint, or engine lands. New surface, new capability.
- **PATCH** — a hotfix wave: defects, layout, copy. No new capability.

---

## [Unreleased]

_Nothing yet._

---

## [7.14.0] — 2026-09-23 · Start on one, the other follows

Wave 4 of the App Store sprint (Lane A). Planned as 7.12.0; W5 landed first as
7.13.0, and a lower number would give App Store Connect a lower build number
(71200 < 71300), which it refuses — so this is the next free minor, and W6/W7
move up one.

### Added
- **Start a workout on the phone and the watch follows** (watch app). Within
  seconds, and before any set is logged, the watch leaves its dashboard for
  the set screen and starts its workout session — which is what keeps the
  watch app on the wrist when you raise it. Nothing else was built for "stays
  awake", and `WKExtendedRuntimeSession` stays out.
- **Start on the watch and the phone follows** (phone). The Train tab opens
  the logger on the wrist's session, on the same clock.
- **Finish or discard on either device, and the other hears about it.** A
  workout finished on the watch is now closed on the phone — duration, set
  count, volume, PRs and the upload — from the wrist's own sets. Before this,
  a watch-finished workout stayed open on the phone for good.

### Changed
- **"Start workout" on the phone opens the session right away** instead of at
  the first ticked set, the way the watch's Start always has. Cancelling with
  nothing logged still leaves nothing behind.
- **Starting on both devices at once ends with one workout**, not two: the
  earlier start wins on both, and an empty duplicate is removed.
- **The watch's workout is not written to Health twice.** When the watch runs
  a phone-started workout it says so, and the phone skips writing its own.

### Fixed
- **Sets logged on one device never reached the other.** Every set names its
  session, and the other device had never been sent that session, so its
  database refused the set — silently, on the watch. The session now travels
  first.
- **The database would not open on the iOS/watchOS 26.5 simulators** ("Store
  unavailable — qualified table names are not allowed…"). Since 7.1.0 the
  rescore triggers used SQL that only the newer SQLite in the 27 runtimes
  accepts. Devices below 27 very likely carry the older SQLite (not checked on
  hardware); the app's minimums are iOS 18 / watchOS 11.
- A send made in the first moment after launch — the watch's Start among
  them — was dropped before the phone/watch link had finished starting. It
  now waits and goes out once the link is up.
- A discarded watch workout session's late failure could mark the next one as
  not running.

### Notes
- **Proved on paired simulators — iPhone 15 + Apple Watch Ultra 2 on the
  iOS/watchOS 26.5 runtimes — in both directions, with screenshots and the
  watch's own log** (`HKWorkoutSession started`, state `1 -> 2`). The iOS 27
  simulator runtime has no `appconduitd`, so WatchConnectivity cannot activate
  on the phone there at all.
- On those simulators only the immediate half of the link delivers; queued
  transfers never reached a running app. The finish/discard half and
  set-by-set sync are proved by tests (`SessionPulseTests`, 12), not on screen.
- A movement added on the phone mid-session is still not on the watch's deck
  (from W3): the watch has no catalogue row to name it by.

---

## [7.13.0] — 2026-09-23 · A dose change starts today

Wave 5 of the App Store sprint (Lane B). Changing a supplement's dose used to
rewrite every day you had ever taken it. It now starts on the day you change
it, and every past day keeps the dose it was actually taken at. The stack can
also remind you at each of its times.

### Added
- **Dose history** (phone, export). Changing a dose in the Stack editor keeps
  the old dose for every day before today. The Stack screen, the Pulse day and
  the weekly export all show the dose that was in force on the day they show,
  and a past day's Stack screen now names its date. Swiping back to a day
  before the change shows the old dose. For a counted dose ("2 caps"), that
  day's micronutrient credit on the Nutrition tab follows it too; a mass
  ("300 mg") is credited as the label, as before.
  - Changing the dose twice in one day keeps the first dose for the days
    before. Changing it back the same day is an undo, and leaves no trace.
  - Editing only the name, time, form or days of an item records nothing —
    including a row whose dose the editor merely re-spells ("2 Caps" saved
    back as "2 caps").
  - Archiving is unchanged: it still stops the item from its date forward and
    leaves its history alone.
- **Supplement reminders** (phone). Settings → Training → *Supplement
  reminders*. One notification per stack time, naming each dose still due then
  at that day's dose, for example *Before Bed · 22:00 — Magnesium Glycinate
  400 mg, L-Theanine 200 mg*. A dose you have already ticked or skipped is not
  reminded. Permission is asked for when you turn the switch on, never at
  launch. Reminders are armed a week ahead, on every foreground and after every
  tick, skip or stack edit. Signing out or deleting the account cancels them
  and turns both reminder switches off.
- **The export names the day a dose changed.** The day's row in the Markdown
  gets `dose change Magnesium Glycinate 300 mg → 400 mg`. In the JSON, each
  day's taken list carries the dose in force that day, and the day of a change
  carries a `supplementDoseChanges` list.
- **`docs/sql/w5-dose-periods.sql`** — adds the nullable `dose_periods` jsonb
  column to `custom_supplements`, for the founder to paste. It is a founder
  gate: this build must not reach the phone before it has run.

### Fixed
- **An archived supplement no longer stays in the export after its archive
  date.** The export read supplements through its own copy of the row mapper,
  which dropped `archived_at`, so an item archived on Wednesday was still
  listed as taken on Thursday to Saturday. It now uses the app's one mapper.

### Notes
- The export's golden fixtures did **not** move. None of them contains a dose
  change, and a day without one prints exactly what it printed before.
- The dose history is stored as `custom_supplements.dose_periods`, a list of the
  doses an item used to be taken at, each with the date it stopped. The row's
  own dose columns are still the current dose, so anything that does not know
  about the history still reads today's dose correctly.

---

## [7.11.0] — 2026-09-23 · Add a movement, see the heart rate when you ask

Wave 3 of the App Store sprint (Lane B). Three briefs on the logger's screen
family: a movement you did not plan can be added mid-session, the heart-rate
chart waits until you ask for it, and Hevy's record of the same workout is one
line instead of a question.

### Added
- **"Add a movement" at the bottom of the live deck** (phone). It opens the
  same searchable picker the routine builder uses — `ExercisePickerSheet`, now
  its own file, shared, not copied. The new card goes to the bottom, takes the
  next `exercise_order` without renumbering any other card, opens with the
  routine builder's default of 3 × 8–12, and joins the session's day, so
  switching between cut and bulk mid-session keeps it. Picking a movement
  that is already on the deck takes you to its card instead of adding a
  second one.
- **An added card opens with the movement's last working set from any split.**
  Its sets are pre-filled from that set, and a new line under the header reads
  `last 25kg × 11 · Sat 19 Sept`. Only added cards get this line; the cards
  the day opened with are unchanged. The lookup is a separate, narrow one
  (`AppDatabase.lastWorkingSet`). It matches the movement by name under every
  id it has been logged as, skips warm-ups and drop sets, counts a
  left/right pair once at its weaker side, and never looks at the session in
  progress. The day's own seed is not widened, so no existing card's numbers
  move.
- **An added movement survives a relaunch.** After the app is killed and
  reopened, the deck rebuilds from the routine, which does not list the added
  movement. Its logged sets used to be left off the screen: still in the log,
  still in the session totals, but not drawn. The card now comes back with
  its logged sets and the rest of its planned sets.

### Changed
- **The heart-rate chart is hidden until you tap Avg HR.** This applies on
  the finish sheet and on the session page. The chart slides up from the
  bottom as a sheet over a dimmed background, using the sheet spring
  (damping 0.8, response 0.3). It can be reversed mid-motion, closes the way
  it came, and can be dragged down or tapped away. With Reduce Motion on, it
  fades in and out instead of sliding.
  - When the watch recorded a heart-rate trace, the Avg HR cell's icon
    becomes a waveform.
  - On the finish sheet, tapping Avg HR used to open its number editor. That
    editor is now one tap further in, behind "Edit the average" inside the
    chart.
- **The chart is one colour.** Every movement uses `OnyxDomain.recover.accent`
  (founder decision 3), told apart by three opacity steps rather than by
  sixteen muscle colours that mean anatomy everywhere else in the app.
  - The x axis shows each movement's number, matching the legend, instead of
    clock times.
  - The bpm scale is hidden until you tap the chart. It has its space
    reserved, so the chart does not shift when the scale appears.
  - The shaded area under the line now stops at the bottom of the chart.
    Before, it ran down under the axis labels to the card's edge.
- **Hevy is one line, not a question** (finish sheet and session page). The
  line shows the source's initial, its name and `128 bpm · 356 kcal`. Tapping
  it opens the four-row comparison with a single "Use Hevy HR & calories"
  button.
  - Skip is gone, and so is every write of `HevyDecision.skip`.
  - The line disappears only once Hevy's figures have been used. An old
    `.skip` still loads and no longer hides anything.
  - The line still appears only when a lifting workout from another app
    overlaps the session. That condition already held and is unchanged.

### Fixed
- The picker labelled Face Pull's muscle "Rear_Delts". It now reads
  "Rear delts", the same name the deck's chip uses.
- Opening the heart-rate chart ran the finish sheet's save step. That marked
  the running clock's duration as "edited", turning a green dot blue.
- After Hevy's figures were used, the finish sheet credited them to "the
  watch's own workout". It now names Hevy.
- The session page wrote to the store inside a view body. The `check:body`
  test only let this through because of the Skip button's code nearby, and
  deleting Skip exposed it. The write is now a method.

### Notes
- **`OnyxDomain.recover.accent` is lavender in the default theme (`#A79FD6`),
  not red.** Founder decision 3 names this token and also calls it red. The
  token was used as named. The app has no themed red to swap to:
  `Color.onyx.danger` is a fixed hex. Changing it is a one-line edit to
  `TelemetryCard.ink`, and the founder should make that call.
- **A movement added on the phone is not on the watch's deck.**
  `WatchModel.planDeck` ignores sets that match no planned movement. This is
  left for W4 (session sync), which owns the watch deck.
- Tests added: `LastWorkingSetTests` (6) and `AddExerciseTests` (2). The
  `Onyx` scheme's failing tests are exactly W1's baseline list.

---

## [7.10.0] — 2026-09-22 · The watch gets a front door

Wave 2 of the App Store sprint (Lane A). The watch app opened on the word
"Rest day" over an empty screen, with everything the phone knows about you
hidden behind a toolbar disc. It opens on a four-page dashboard now, and the
pages have colour.

### Changed
- **The idle root is the dashboard, not `StartView`.** A live session still
  roots at `SetView` — W3's "it is the set, not a dashboard" argument holds
  *during* a workout and was always wrong outside one, and that comment is
  rewritten rather than deleted. Founder decision 2.
- **Four vertical pages, driven by the Crown as before.** Page one is the hero:
  today's split at `WatchType.figure` in the split's own colour, a chip row
  (movements · battery · readiness) and the one large Start button. Then
  **Today** (battery/readiness, sleep, stress), **Train** (week tonnage, week
  rings, steps) and **Fuel** (calories left, water, +1 glass).
- **A rest day is no longer a dead end.** It was the word "Rest day" and
  nothing else. It is now "Rest day" in Lunar over the readiness score as the
  hero, with battery and last night's sleep beside it — and the other three
  pages are there on a rest day like any other.
- **The pages have colour, from tokens that already existed.** Each page takes
  one `OnyxDomain` accent — Today → `recover`, Train → `train`, Fuel → `fuel`,
  page one → the split's `Color.onyx.dayLabel` — and the card carries it as a
  14 % fill, a 45 % hairline and the glyph and headline of the face inside it.
  No palette was invented and no hex is spelled in the watch app.
- **`.train` came off the Train page and `.steps` took its slot.** The `.train`
  face says "Upper B / due", which is what page one now says at four times the
  size. `.steps` moved off Fuel because three faces *and* the "+1 glass" button
  hung 24.5 pt below even the 49 mm fold — the button was photographed cut in
  half. Both are still complications.

### Fixed
- **`MirrorView` and `FinishView` held a full-width green capsule at full
  brightness in the always-on state.** `SetView` applies
  `dimmedWhenLuminanceReduced` to its logger page and to nothing else, so the
  two live-session screens that are held longest were the two missing the
  burn-in call. Both have it now.

### Added
- **`watch-shot.sh restday`** — the state the founder complained about by name
  had no shot hook, which is why nobody had looked at it. `seedDebugContext`
  gained a `restDay:` seed, and clearing the schedule override alone is *not*
  enough: `Schedule.scheduleDayIn` falls back to a day's own weekday, so the
  first rest-day shot came back as the training hero.
- **`watch-shot.sh nophone`** — the "Open Onyx on your iPhone" empty state,
  which `start` used to draw by accident. It is only honest as the first screen
  of a run after an uninstall, and the script says so.

### Notes
- **watchOS does not tint an inline navigation title with `.tint`.** The first
  version of the page model relied on it; the 49 mm screenshots came back with
  the same grey heading with and without the modifier. The title stays the
  system's grey, the colour lives in the cards, and the finding is recorded in
  `DashboardPages.swift` so the next wave does not re-spend the round.
- **A root navigation bar measures the same 64 pt as a pushed one.** Moving the
  dashboard up a level was expected to buy height back — no back chevron, no
  toolbar item. The accessibility tree of the running root says
  `{{0, 0}, {205, 64}}`, identical to the pushed bar `WatchCase.navBar` was
  measured against, so no budget in `WatchDashboard` changed and there is no
  second constant.
- Reviewed on **both** an Apple Watch Ultra 2 (49 mm) and an Apple Watch SE 3
  (40 mm), which is the first time any watch screen in this repository has been
  photographed at 40 mm.

## [7.9.0] — 2026-09-22 · The widgets draw again

Wave 1 of the App Store sprint. It owns `native/project.yml` alone so the two
later lanes can run in parallel worktrees without colliding on it, and it clears
the two things a reviewer or a Home Screen would have hit first.

### Fixed
- **Home Screen widgets rendered Apple's "Please adopt containerBackground API"
  placeholder instead of a tile.** Twelve of the twenty faces `OnyxTile.face`
  dispatches to never called `containerBackground`, and four more
  (`trajectory`, `consistency`, `deficit`, `fatigue`) carried it on a wrapper
  view that `face` goes around — as did `daily`. One call now sits at
  `TileFace`, the single widget root that draws a tile, rather than in twenty
  files: "each face remembers" is the rule that produced the bug. Verified by
  placing real medium and large widgets on a simulator Home Screen, not by
  reading the diff.

### Removed
- **Settings → "Reduce motion".** It wrote a column nothing native reads, and
  its own footer said so — while crediting "the web app", which was retired at
  3.0.0. The app already honours the system setting
  (`accessibilityReduceMotion`, read in eight places), and iOS keeps this switch
  at Settings → Accessibility → Motion. The row, its binding and
  `SettingsModel.setReduceMotion` are gone; the stored column is untouched.

### Added
- **Two parked entitlement blocks in `native/project.yml`** —
  `com.apple.developer.applesignin` and
  `com.apple.developer.healthkit.background-delivery`, commented in the same
  shape as the `associated-domains` block beside them, each naming exactly what
  to uncomment and what to enable in the developer portal. Both need the paid
  Developer Program; neither changes this binary.
- **An `Apple Watch SE 3 (40mm)` simulator**, paired to `iPhone 15`. 40 mm had
  been asserted by `OnyxWatchLayoutTests` and never once photographed, because
  no 40 mm device existed on this machine.

### Notes
- **The test baseline is now written down.** `OnyxTests` fails **11 issues
  across 9 test names**; `OnyxDataTests` fails **1**, the Keychain session-blob
  test, which is a free-team signing symptom (`-34018`) and passes on macOS via
  `npm run swift:data`. `OnyxCoreTests` (706) and `OnyxUITests` (42) are clean.
  Four documents in `docs/Done/` disagreed on this number; they should not be
  cited again.

---

## [7.8.1] — 2026-09-22 · The sprint leaves no residue

Wave 8, the close-out of the Onyx Expansion sprint. No feature, no schema, no
screen: this release is the eight waves' leftovers being taken out of the
repository and off the disk, and the sprint's record being put somewhere a
reader will find it.

### Removed
- **Ten merged branches** — `wave/3-watch-logger`, `wave/4-watch-dashboard`,
  `wave/6-lean`, `wave/7-ai-export`, and the six `onyx/sprint-widgets-*`
  branches that had outlived the widgets sprint. Every one was verified merged
  into `main` before deletion; none existed on `origin`.
- **`docs/sql/`** — `w1-onyx-wire.sql`, `w6-export-v6.sql` and `w7-exports.sql`,
  all three applied to the live database. Their text is preserved verbatim in
  this file under *Appendix — applied server migrations*, and the eleven places
  in the Swift and the MCP server that cited them by path now cite the
  appendix. That includes one reference to `w3-sleep-onset.sql`, a file the
  previous sprint's close-out deleted and left pointing at nothing.
- **95.8 GB of derived data** under `~/Library/Caches/onyx-swift/` — the
  thirty-three per-wave `SHOT_DERIVED` and test-scratch directories that had
  accumulated one per wave since the widgets sprint, largest 5.7 GB. The six
  the gates actually use are kept, and the directory is 103 GB → 7.2 GB.
- `native/__screenshots__/` (146 MB), `native/__store__/` (the App Store upload
  set, which `scripts/store-shots.sh` rebuilds in minutes),
  `native/graphify-out/` (108 MB, regrown since the last purge) and
  `tools/onyx-mcp/node_modules/`. All four are gitignored and all four
  regenerate.

### Changed
- **`docs/Plan-Onyx-Expansion-Done.md` moved to `docs/Done/`**, and its body is
  now the eight wave summaries. Each wave section reads goal → tasks → what
  actually happened; the eight prompts as they were handed to their agents are
  collapsed into *Appendix B — prompts as run*, kept because a summary says what
  happened and only the prompt says what was asked for.
- The plan's wave map now prints the versions each wave **shipped**. The
  "expected version" column had been wrong since W5 took 7.6.0.
- `docs/SIMULATORS.md` now says to delete a wave's `SHOT_DERIVED` directory when
  the wave closes. Thirty-three of them are what 95.8 GB looks like.

### Fixed
- **Pasting a coach's table with an absurdly long number no longer crashes the
  app.** `Settings → Prescriptions` parses the box on every keystroke, and a
  cell holding more than nineteen digits — the kind of thing a model emits when
  it loses the plot — went through `Int.init(Double)`, which *traps* past
  `Int.max` rather than failing. The app died on the keystroke that pasted it.
  The number is now refused and the field keeps its default, so the row is
  reported unread instead. The sprint had already fixed this exact trap in two
  other files and missed this one.
  (`OnyxCore/Training/PrescriptionPaste.swift`)
- **The apply-targets sheet and the write now round the same way.** On a target
  ending in an exact `.5` the preview rounded half-to-even and the write
  rounded half-away-from-zero: the sheet said `2,100 kcal` and `2101` was
  stored. Worse, when no other field had moved the diff row was suppressed as
  unchanged *while the write still happened* — a change the athlete approved
  without ever seeing it. (`OnyxData/Targets/TargetsApply.swift`)

---

## [7.8.0] — 2026-09-22 · One export, three ways to ask for it

Wave 7 of the Onyx Expansion sprint, and the one the app was originally for.
Getting a training week to an AI is one action from any surface; the extraction
that builds it exists in exactly one place; and the model's answer can write
next week's targets back.

### Added
- **History → a week → Export** now offers a RANGE, not a week: *Since last
  export* (the default), *This week so far*, *Last complete week*, *Last 7
  days*. Each carries the dates it resolves to, so you can see what you are
  about to hand over before you hand it over. The phone remembers how far it
  has exported, so "since last export" never shows a model the same days twice.
- **Shortcuts and Siri.** "Export my Onyx week" builds the document without
  opening the app and hands back two files — the Markdown for a chat window and
  the JSON envelope for anything that parses. The range is a parameter, so a
  Sunday-evening automation is four taps to set up.
- **`## 9 · PASTE-BACK`**, a new last section on every export. It tells the
  model how to answer in a form the app can read: a fenced `onyx-targets` block
  of JSON naming a rung, or calories, protein, carbs, fat, steps, water and
  sleep.
- **Apply targets.** Paste a report into Reports → a week, and if it carries
  that block, a button appears. It opens a diff — what each number is now, what
  it would become, and what will NOT change and why — and writes nothing until
  you confirm. A report dated to a week already past applies from today: days
  you have already logged keep the targets they were graded against.
- **`tools/onyx-mcp`** — a local MCP server for Claude Desktop and Claude Code.
  Five read-only tools: the exports your phone has filed, one envelope, the
  latest document, raw sets and raw daily scores. It serves what the app built
  and derives nothing, so a week read on the desktop and a week shared from the
  phone cannot disagree. Registration is two lines; see its README.
- **`docs/sql/w7-exports.sql`** — the `exports` table and its four RLS
  policies, for the founder to paste. Until it runs, the export still shares
  and the MCP server says exactly which table is missing.

### Changed
- **The export's complete-week lock is gone.** It used to refuse a week with
  days left in it. A span states its own two dates on the document's cover, so
  it cannot be mistaken for a week that has not finished — and asking on
  Thursday what Monday to Wednesday looked like is the ordinary use the lock
  was costing.
- **The weekly export is a SPAN, not a week.** Every figure is unchanged for a
  whole week; a partial or off-week span now renders exactly its own days.

### Fixed
- **A day was named by its position, not by what day it was.** The export's
  weekday column was the offset from the span's first day, so an athlete whose
  week starts on Monday has had every Monday labelled "Sun" for as long as the
  column has existed. It is read from the date now.

---

## [7.7.0] — 2026-09-22 · Measured, then cut

Wave 6 of the Onyx Expansion sprint. Every hot path has a signpost and a
number behind it; no view waits on the store; five tabs got denser rather than
shorter; and the app now knows when it is standing in a gym.

### The before/after table

Eight seams carry `os_signpost` intervals under the subsystem `app.onyx.perf`
(`Perf`, in OnyxCore) — `launch.firstFrame`, `tab.switch`, `logger.open`,
`set.tick`, `session.finish`, `export.build`, `watch.push`, `sync.foreground`
— joining `rescore.run`, which W2 left there.

The four seams that are pure store work are measured by
`SeamBenchmarkTests`, which runs the OLD shape and the NEW one in the same
process over the same deterministic account (`DenseSeed`, 141 days), so the
pair is one machine and one run rather than two branches. `ONYX_BENCH=1
npm run swift:data` reproduces it.

| Seam | Before | After | What changed |
|---|---|---|---|
| Battery stack (14 days) | 770 ms | **250 ms** | fourteen `ScoringWindow` loads, each reaching 48 days behind its own date, became one window over the whole span |
| Stress series (14 days) | 244 ms | **82 ms** | fourteen 49-day readiness reads became one 62-day read, sliced per day |
| Nutrition day (the Fuel tab's whole read) | 32 ms | **8 ms** | seven `ValueObservation`s plus two inline main-actor `stackCredit` reads became one observation, one transaction, one delivery |
| Watch context payload | 20,836 B | **7,040 B** | the whole deck catalogue rode along on every push; now the active program plus a name-deduplicated swap pool |
| `launch.firstFrame` | — | 661–776 ms | instrumented; measured cold on the iPhone 15 simulator, signed out (4 runs) |
| `tab.switch`, `logger.open`, `set.tick`, `session.finish`, `export.build`, `sync.foreground` | — | — | instrumented and **not measured here**: the simulator has no Supabase session, so there is no signed-in shell to switch tabs in, no deck to open and no sync to run. A device trace is the measurement. |

`export.build` has a second, larger number that is not a duration: the weekly
export used to be built on **every appearance** of a week page and is now
built when the share is actually performed — for most visits the cost went
from one whole-week read and a file write to nothing at all.

### Added
- **Gym mode** (§W6-B, decision 26). A workout already running, or a session
  due today with the clock inside the window this person usually trains in —
  the median of `workout_sessions.started_at` ± 90 minutes, and no window at
  all under eight logged starts — opens the app on Train with the tab bar out
  of the way. A **Leave** capsule in the navigation bar brings the tabs back,
  and finishing or cancelling ends it without anybody tapping anything.
  Settings → **Gym mode** turns it off; it is on by default.
- **Relevance ordering on Today** (§W6-B.3). The same cards, in the order the
  clock asks for: mornings lead with sleep, recovery and the session; evenings
  with fuel, water and tomorrow. Nothing is hidden, resized or removed — the
  hero moves. The first drag, resize or hide retires the ranking for good:
  a grid somebody arranged is never re-ordered again.
- **One "Log day" sheet** with three segments — stress, soreness, water —
  reached from Pulse and from Today's Quick Log. Soreness had no Quick Log
  spoke at all before; water was behind a long-press on a row whose tap did
  something else.
- **`docs/COMPACTION_AUDIT.md`** — every fact this app draws twice, which
  drawing is kept, and why. Ten rows resolved, ten recorded with their reason,
  and two rows the audit itself got wrong with the reason they are not
  duplicates.
- Three new gates: `scripts/check-body-reads.mjs` (no synchronous store read
  inside any SwiftUI view builder), `CardTextBudgetTests` (one hero and at most
  two captions per card, with a reasoned allowlist for registers), and
  `SeamBenchmarkTests`.

### Changed
- **Realtime survives a drop.** A failed channel join retries with exponential
  backoff and equal jitter (1 s floor, 60 s ceiling), and while the socket is
  down a 60 s poll delivers the same rows. The ladder resets on a successful
  join. Nothing retried at all before.
- **Keyset paging** replaces offset paging in `PostgRESTRemote`, keyed on each
  table's primary key — the only total order this schema has an index for.
  (`(updated_at, id)` as planned is not available: eleven of the mirrored
  tables have no `id` column and twelve carry no `updated_at`.)
- **The main-thread purge.** Reads that feed a view are off the main actor:
  the launch-time live-workout check, the routine builder's catalogue, the
  body-trends window and its ranged vitals read, the CSV importer's catalogue
  (which was re-read on every keystroke), and the watch-context push, which
  ran about thirty store reads on the main actor at sign-in, at midnight, on
  a theme pick and once every thirty seconds.
- Sleep durations print one way. `DayFormat.minutes` and `WeekDaysView.hours`
  are gone; `Format.sleep` is the one prose formatter, so an exact seven hours
  reads `7h` everywhere instead of `7h 0m` on one screen and `7h 00m` on
  another. Fixed-width tile faces keep `OnyxSnapshot.formatSleep`.
- Three duplicated helpers in OnyxUI collapsed to one each (the sessions
  fraction, the week-volume delta in tonnes), Today stopped drawing steps on
  two of its own sheets, and the Train tab's sections are `12` apart like
  Today's and Fuel's rather than `16`.

### Fixed
- `scripts/native-shot.sh` died with `seed[@]: unbound variable` on every
  screen that is not `telemetry-*`: bash 3.2, which is what macOS ships, reads
  an empty array as unset under `set -u`.

---

## [7.6.0] — 2026-09-21 · The session knows whose heart rate it is

Expansion W5. The post-workout summary shows the session's heart rate cut into
its movements; a Hevy log of the same hour is compared, never adopted; a
phone-only session leaves a workout in Health.

### Added
- **Heart-rate chart** on the finish sheet and the session page — one chart,
  the average as its hero, the peak and the burn as its two captions. Each
  movement's stretch is washed in that muscle's own colour and named at its
  boundary; rests after the last set and every paused interval are the thin
  grey line. Read from Apple Health at view time, cached locally after the
  first non-empty read (`session_telemetry`, never synced), and re-read once
  if the watch's samples land within ten minutes of a finish. At the
  accessibility sizes the card keeps the three numbers only.
- **"Hevy logged this too."** When a foreign strength workout overlaps a
  session, one card compares average HR, calories, duration and sets — Onyx
  vs Hevy — with **Skip** as the primary answer. "Use Hevy HR/kcal" adopts the
  two figures as your own answer. Neither button touches Health, and the
  answer is remembered so the summary page does not ask again.
- **The phone writes an `HKWorkout`** for a session the watch did not run —
  only when no own workout and no foreign strength workout already overlaps
  it — carrying the session's active energy when Health holds none for the
  interval (flagged estimated when `Estimates` produced it). iOS now asks for
  workout and active-energy write access alongside the reads.
- Harness: `telemetry-finish` and `telemetry-detail` seed the simulator's own
  Health store (`--onyx-telemetry-seed`) so the chart is a real read;
  `hevy-card` is the fixture-driven compare card.

### Fixed
- **A Hevy workout was adopted as the watch's measurement.** `SessionMetrics`
  took the first lifting workout overlapping a session and stamped its heart
  rate and energy MEASURED, whoever wrote it. Workouts now carry their source;
  only Onyx's own (phone or watch) is a measurement, and a workout with no
  source at all classifies as foreign, never own. Golden vectors:
  `workout-origin`, `workout-pick`, `hr-segments`.

## [7.5.0] — 2026-09-20 · The export prints the instruction you are actually working to

The coach's second audit, closed. The document stopped comparing this week's
lifts against a July blueprint, stopped presenting an import timestamp as the
moment a walk began, and stopped throwing out the one HRV reading worth having.

### Added
- **Prescriptions.** You → Prescriptions takes a pasted block from the weekly
  audit — a markdown table or one movement a line — shows you everything it
  read, every field it could not find and every line it refused, and appends a
  new version per movement. Nothing is ever overwritten: the day a load moved
  stays in the record. The export renders `prescribed` from the version in
  force on each session's own day.
- **Per-movement deltas against that instruction.** Each movement now prints
  `vs prescribed load +2.00 kg · reps in window`, and names by ordinal any set
  rated above the prescription's RPE cap. A rep delta is measured against the
  WINDOW: `8–12` means any of those five answers met it.
- **Insomnia tracker**, in §2 of the export. Every night over 45 minutes to
  onset, over 60 minutes awake, or tagged as trouble falling asleep, with its
  onset clock, awake total and duration — and a running count over the trailing
  eight weeks.
- **Log reminders** (You → Training). Local notifications for the day's
  unanswered fatigue slots and for the Thursday waist, armed a week ahead and
  re-armed on every foreground. A slot you have already answered is not asked.
- **Set-quality tally** in each session's header — `tagged_sets 3 (momentum 2,
  cold 1)`. The tokens have ridden on the set lines since 7.4.0; the session now
  says how many there are without your having to count them.
- **Waist Δ** column in the body-composition table, against the previous WAISTED
  scan, plus the week's own change on the clean-scan means line.
- **SpO₂ below 95 %** is flagged on the day and named in the anomalies.

### Fixed
- **A walk's start time.** `cardio_logs` has only ever had `created_at`, and on
  a row imported before `hk_uuid` existed that is the instant of the IMPORT, not
  the bout — so a Tuesday walk taken at 18:58 exported as `from 21:11`. Such a
  row now prints `imported 21:11` and is named in the anomalies, and a backfill
  sync walks back 90 days repairing the stamp from Apple Health's own record.
- **Duplicate bouts that agreed on everything but their calories.** The dedupe
  key was exact and included energy — the one figure Health revises as later
  samples arrive — so two copies of one walk both reached the document. It now
  matches on the day, the kind, the duration to within a minute and the distance
  to within a hundred metres, and keeps the earliest.
- **The Friday HRV that was never wrong.** `daily_logs.hrv_ms` holds two
  different measurements — the mean inside the night's bed window when it
  resolves, the calendar day's when it does not — and overnight SDNN runs far
  above the waking figure. The artifact gate was judging one against a history
  of the other and declining the good nights. The provenance is stored now
  (`hrv_overnight`, a column Postgres has had all along), the gate compares like
  with like, and a flagged reading prints its raw value, which window it came
  from and when the row was written.
- **Calcium, magnesium and vitamin D.** A food logger that re-syncs writes the
  same meal twice — same app, same instant, same amount — and Apple's dedupe is
  between DEVICES. Dietary totals are now re-summed without the re-filed
  entries, so calcium stopped reading 3,142 mg against a 1,000 mg target. And
  magnesium, vitamin D and vitamin C are marked as stack-sourced, which is where
  they have always come from: the export no longer reports them as missing from
  the food log every week.
- **One PR line per movement.** A lift PRd twice in a week was listed twice; the
  best is listed once and says `(2 sessions)`.
- The DOMS legend said 0–5 for a scale that has always been 0–3, and never said
  that a bare muscle name means both sides.

### Removed
- `actual rest` is withheld from the document until it is a rest interval. It
  was the gap between two log commits — 1 s when the next set was entered while
  it was under way, 304 s after a phone call — and neither figure is a choice
  anyone made.

---

## [7.4.0] — 2026-09-20 · The weekly export stops losing the week

The Markdown weekly export — Settings → the week's **Export** — had been
dropping or duplicating what it was built to report. Eight defects, and the
eight things the document now carries that it was already holding in memory.

### Fixed
- **Cardio is counted once.** A re-imported HealthKit bout carries the instant
  of the import, not its start, and the export's duplicate rule keyed on that
  instant — so a week with a handful of walks reported **228 bouts and
  40,559 kcal**. Bouts are now identified by `hk_uuid`, or by what the bout
  physically was, and the week-over-week ledger is deduped the same way.
- **The treadmill stops labelling the next exercise.** An exercise whose every
  set is a warm-up printed a bare **Treadmill** immediately above the first real
  movement. An exercise with nothing to list now prints no heading; the bout is
  under `warm-ups` and on the day's own cardio row.
- **Set qualities render.** Cold, Momentum, Short ROM, Form broke, Assisted and
  Cut short reach the set line for the first time — the export was writing a
  null for the column and the reader could not parse a set tagged with two of
  them at once.
- **A timed lift keeps its load.** A set that recorded a duration was rendered
  as a cardio bout, and `100 × 5` was replaced by `2:00`. The duration is now a
  token beside the set; only distance, incline, or a duration with no lift under
  it makes a bout.
- **A second weigh-in no longer erases the first.** Two scans on one date merge
  field by field, so an afternoon re-weigh cannot delete that morning's visceral
  fat and bone mass. Masses the scan did not store are derived from its own
  percentages — the same arithmetic the InBody sheet shows live.
- **Supplements count toward the day.** Psyllium husk's fibre, calories and
  carbohydrate were reaching the weekly mean and not the daily row. The day's
  totals now include the stack and name what it contributed.

### Added
- **Waist in the Body Composition table**, beside the weight it was taken with —
  and the columns are spelled as the InBody sheet spells them (Body fat,
  Skeletal muscle, Bone mineral, W:H ratio), reported figures first and derived
  masses after.
- **Rest, planned and measured**, on every exercise.
- **Per-day cardio**, on every day, including the days that had none. A bout is
  a thing a day contains, not part of whichever session shared its date.
- **A vitals row per day** — REM, awake, bed and wake times, respiratory rate,
  blood oxygen, wrist temperature, VO2max, daylight, stand hours, walking
  distance, active and BMR calories.
- **Session heart rate and energy**, each flagged when estimated.
- **Which record a PR was** — weight, reps, volume or e1RM — and the estimated
  1RM behind it.
- **Tonnage per muscle** beside the set counts in Sets by Muscle.
- **§8 · Legend** — the scales the rows are on (DOMS, fatigue, stress, RPE), the
  set-line grammar, and what an absence means.

### Changed
- **Sessions read as a ledger.** Two heading lines instead of one eight-field
  run, a blank line between movements, sets indented under the movement they
  belong to.
- **`target` and `prescribed` are one field.** Both came from the same plan row.
  The prescription prints when the plan names the movement; the bare rep window
  prints only when it does not.

## [7.3.0] — 2026-09-20 · The wrist reads the day, and both screens read your heart

The Watch stops needing the phone to answer "how am I doing". Three pages of
the same faces your complications draw, a live-workout card that surfaces
itself in the Smart Stack while you train, and a heart rate on the Lock Screen
and in the Dynamic Island on the phone in your pocket.

### Added
- **Watch dashboard — Today, Train, Fuel** — three vertical pages, turned with
  the Crown, reached from the Start screen's chart button before a session and
  from the deck's during one. Every reading is the SAME accessory face your
  watch face and your iPhone Lock Screen draw, so a number cannot say one
  thing in a corner of a clock and another on a page. Today is battery and
  readiness, last night's sleep and today's stress; Train is the session due,
  the week's tonnage and sets, and seven days of marks; Fuel is calories left,
  water and steps.
- **A glass of water from the wrist** — a button under the water face on the
  Fuel page. The wrist has no water ledger, so the glass is posted to the
  iPhone and lands in the same mailbox Control Centre's button uses, written
  by the same code that writes a tap on the Pulse tab — one row, whichever
  device you tapped. The reading moves on the wrist immediately and settles
  when the phone confirms.
- **Live workout in the Smart Stack** — a card that raises itself while a
  session is running: the movement, sets done against the deck, your heart
  rate, and the rest counting down. It ranks through watchOS 11's own
  workout-in-progress relevance and stands down when the session ends. Nothing
  was given up for it — the ten complications are all still there.
- **Heart rate on the watch face** — the same card as a circular complication,
  for a corner of the clock during a workout.
- **Heart rate on the iPhone's Live Activity** — the wrist's reading on the
  rest band of the Lock Screen card and in the Dynamic Island's compact slot
  while you work. It disappears when the watch goes quiet rather than freezing
  at the last number it sent — a stale rate presented as live is the one thing
  this reading must never do.

### Changed
- **The Fuel complication's second line is protein left** where it used to
  repeat the calories the line above had already subtracted.
- **`WatchTiles` carries four more readings** — the week's sets and tonnage,
  and today's protein against its target. Optional and last, so a watch on
  this build and a phone on the last one still understand each other.

### Fixed
- **The Lock Screen could keep drawing a heart rate from a watch that had come
  off your wrist.** The reading was aged at two minutes but nothing woke to
  apply the expiry, so the last number the watch sent stayed on the card until
  something else happened to refresh it. Both devices now age a reading over
  the same two minutes, from one constant.
- **The Dynamic Island's compact slot was drawn twice** — once by the widget
  and once by the app's own contact sheet, which is the only thing that
  photographs it. The copy had already drifted. One view now, in `Shared/`.
- The `dashboard` screenshot the shot loop has refused by name since 7.0.0 now
  has a launch hook, along with `train`, `fuel` and the live widget's faces.
- **The first screenshot of every shot run could come back solid black.** The
  loop waited eight seconds after installing a fresh binary, which is enough
  for a warm launch and not for the first one; it now takes a throwaway launch
  before it photographs anything.

---

## [7.2.0] — 2026-09-20 · The wrist logs the whole workout

The Watch stops being a place to tick a set and becomes the place to run a
session: pause it, throw it away, reorder it, describe what you just lifted,
and watch your heart come back down — none of it needing the phone out of your
pocket.

### Added
- **Set Quality panel on the Watch** — scroll down from the set screen for a
  second page: what the set WAS (warm-up, failure, drop, ghost), which side it
  was on a one-limb movement, and how it went (the six technique tags, several
  at once). Every tap writes immediately; there is no Save button. Same four
  kinds, same six tags and the same words the phone's set-options sheet uses.
- **Pause and discard on the Watch** — tap the session clock to stop and start
  it; hold it to discard the workout. The clock takes the pauses off itself, a
  paused session stops feeding the Activity rings, and a discarded one takes
  its `HKWorkout` with it.
- **A deck you can rearrange from the wrist** — tap a movement to jump to it,
  swipe right for "Do next" or "Add set", swipe left to skip it (skipped
  movements sink to the bottom and come back with a tap) or to swap it for a
  same-muscle movement from your own plan.
- **Edit the set you just logged** — tap the receipt on the rest screen and
  correct the load and the reps on the Crown.
- **Heart rate where you are looking** — the current rate on the set screen,
  and on the rest screen a sparkline of the last sixty readings with how far
  the rate has come down since you racked the bar.

### Changed
- The phone's set kinds and set-quality tags now read one table in the domain
  instead of their own copies of it. One visible consequence: the quality chip
  that said **"Cold start"** now says **"Cold"** — which is what the weekly
  export has always called it.
- Reordering the deck is one piece of arithmetic on both devices, so a session
  rearranged on the wrist groups on the phone exactly the way it was performed.

### Fixed
- Starting a workout session on the Watch could build a second `HKWorkoutSession`
  over the top of a paused one, orphaning the first one's energy.

---

## [7.1.0] — 2026-09-19 · Logging the past scores the past

Anything logged for a day that has already happened — a glass of water, a
night, a set, a whole workout — now produces correct daily scores, correct
records and correct server rows, from either device, without any screen
having to remember to ask. No server change; nothing to paste.

### Added
- **Log a workout here** (History → a past day → Pulse). A session is created
  on that date, born closed, and opens on the edit deck: no clock, no rest
  timer, no Live Activity, no watch mirror. Every set goes through the same
  door as a correction, so the PR ledger replays and the day rescores.
- **Rescore at the door.** Every committed write to a date-bearing table —
  including a delete — reports the earliest past date it touched, and the
  cascade runs from there when it is within 120 days. The per-screen calls in
  the logger, the finish sheet, the sleep editor, the water drain and Pulse are
  gone: no screen has to remember. Rows the mirror pulls, the seeds it writes
  and the sync's own acknowledgements are exempt — the device that made the
  edit already cascaded and pushed its scores.
- **Settings → Recompute history.** An edit older than 120 days marks the
  history stale instead of cascading; the row says so, and the button rewrites
  every stored day from the earliest owed date to today.
- **Sync doctor → Rescores.** The last six cascades: why, the dates reached,
  how many days written.

### Changed
- **The cascade is one read, one compute, one write.** Forty-nine days used to
  be forty-nine transactions of ~15 queries each; `ScoringWindow` reads the
  range once, computes every day in memory with the same domain functions, and
  writes all rows in one transaction. A sixty-day parity vector pins the
  output to the old path's, row for row. `rescore.run` is a signpost.
- **Watch sets reach the server.** A set logged on the wrist was marked synced
  on the phone and never queued, so it reached Supabase only if the phone later
  touched the same session. The phone now queues the wrist's events through
  its own outbox.

### Fixed
- **Pinned by test:** a heavier set logged a week late removes the interim
  record and files the right one, and the server hears the delete as well as
  the upsert. The replay existed; the proof did not.
- Apple Health no longer re-saves an unchanged day, night or water total on
  every foreground.

## [7.0.0] — 2026-09-19 · The predecessor's name leaves the data

The web app Onyx replaced was retired a year ago, but its name was still a
stored **value**: the era on every plan phase, and the prefix on every exercise
id this phone stamps. This release renames both, in the app and on the server,
and deletes the last code that existed only to recognise the old spelling.

**Run `docs/sql/w1-onyx-wire.sql` in the Supabase SQL editor BEFORE installing
this build.** The app migrates its own copy; that file migrates the server's.
Order matters and the file says so too: `v32.onyxWire` is a GRDB migration, so
the migrator records it by name and never runs it again. A `set_events` row
pulled after it has run keeps the old stamp permanently, and that movement's
history splits in two. The file is one transaction, prints a before/after count
per table, and re-running it is a no-op.

It also drops and recreates one CHECK constraint: `plan_phases.era` was pinned
to the old value and refused the new one outright (`23514`). That is the only
schema change, and it puts back a constraint of the same shape naming the two
values `PhaseEra` can actually encode.

### Changed
- **`plan_phases.era`** — the current era's wire value is now `"onyx"`.
  Migration `v32.onyxWire` rewrites the local rows; the SQL file rewrites the
  4 live ones. `PhaseEra` has exactly two cases, so both halves find their rows
  by excluding `ppl` rather than by naming what they replace.
- **Exercise id prefix** — `ExerciseSlug.id` now stamps `onyx-`. Because that
  id is a KEY and not a brand, the same migration moves all four places one is
  stored — the `workout_sets` projection, the `set_events` append log, the
  `exercises.slug` alias column and the shadow rows whose `id` *is* a slug — in
  one transaction. Moving a subset would file one movement under two identities
  and split its history and PR baselines in silence. `personal_records` is
  deliberately untouched: its `exercise_key` is a display name, not an id.
- **A straggler under the old stamp still resolves.** A migration runs once, so
  an id that arrives afterwards — from a pull that beat the server UPDATE, or
  from a watch still on 6.8.1, which updates independently of the phone —
  would otherwise match nothing and throw `unknownExercise`, stranding the set
  and naming a movement that does not exist. `ExerciseIndex.id(forSlug:)` now
  re-stamps it first, through the same predicate the migration uses.
- **Reports parse by position, not by brand.** `fmtV2.parseHeader` takes a
  report's title from the first non-box preamble line. The seven reports
  already stored under the old masthead keep rendering with a title, and §5 of
  the SQL file makes re-branding them opt-in — they are documents, not keys.
- **Docs** name the retired app "the predecessor web app" throughout.

### Added
- **`scripts/watch-shot.sh`** — the watch half of the screenshot loop, on the
  paired Ultra 2. It refuses an unpaired simulator and refuses by name the
  three screens that have no launch hook yet, rather than photographing
  `StartView` under someone else's filename.
- **`npm run check:watch`** — builds the `OnyxWatch` target for the watchOS
  simulator. `check:swift` never covered it. Wired into `npm run check`.
- **`npm run check:report`** — the first runnable check the report parsers have
  ever had. `fmtV2.ts` claimed a test file that went with the web app, so 945
  lines feeding the in-app renderer were unguarded. Six asserts, imported
  straight from the TypeScript via Node 24's native type stripping, so no test
  framework was added for it.
- **`docs/SIMULATORS.md`** — the pair, both shot scripts, the `SHOT_DERIVED`
  rule, and the 40 mm floor a 49 mm screenshot cannot prove.
- **`OnyxWireMigrationTests`** — the fold golden: a session's sets are compared
  field by field before and after the rewrite, then reprojected from their own
  event log to prove the table and the log still agree.

### Fixed
- **`npm run check` was exiting 1 with no output, and had been.**
  `scripts/swift-ui-test.sh` defaulted to an `iPhone 17 Pro` simulator that is
  not installed, and its UDID lookup is a pipeline under `set -e`: a
  non-matching `grep` killed the script before its own error message could
  print. So the gate failed silently and the 40 OnyxUI tests had not run. The
  default is now the paired `iPhone 15`, the lookup cannot abort, and a missing
  device prints what IS installed. Reproduced on `6.8.1` before the fix.
- **`scripts/watch-shot.sh` could photograph the wrong screen.** A failed
  `simctl launch` or screenshot inside a function called as `shoot … || status=1`
  runs with `errexit` disabled, so the script printed a success line and exited
  0 over a stale PNG. Both commands are now checked explicitly.

### Removed
- **The legacy store adoption.** `AppDatabase` no longer looks for a database
  under the predecessor's container, folder and file names. It had never fired:
  its App Group id was not in `Onyx.entitlements`, so `containerURL` answered
  nil, and its Application Support half looked for a folder no shipped build
  ever wrote. `moveStoreIfNeeded` — the Application Support → App Group half,
  with the WAL/SHM and never-overwrite rules — stays.
- **`OnyxCore/Sync/RealtimeKeys.swift`**, its golden and its fixture; the
  `rebranded` test shim, which had become an identity function;
  `scripts/add-supplement.mjs`; `.agents/skills/` (five web-era skills);
  `.claude/settings.json.graphify-bak`; `native/graphify-out/`.
- `docs/LIVE_UX_SPRINT_PLAN.md` and `docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md`
  moved to `docs/Done/`.

---

## [6.8.1] — 2026-09-19 · The sprint leaves no residue

The close-out of the Widgets · Sleep v2 · Themes sprint — eleven waves,
5.0.1 → 6.8.0, now 6.8.1. Nothing new to use; two things the sprint promised
to finish, finished.

### Removed
- **The six shell widget kinds are gone.** Fuel, Training, Body, Progress,
  Daily and Vitals each had their own Home Screen gallery entry and their own
  focus picker. 6.2.0 replaced all six with one "Onyx" entry whose picker is
  the tile itself, and kept the six as shells for a release so nothing already
  placed went blank. That release has been and gone. **If a widget is still
  placed under one of the six, it disappears on this upgrade — add it again
  from the single "Onyx" entry, which draws the same faces.** The faces
  themselves are untouched; they are the dashboard's own tiles and always were.
  The Lock Screen accessory, the Control Center controls and the running
  workout's Live Activity are unaffected.
- `docs/sql/w3-sleep-onset.sql`, applied on the live database, deleted with the
  founder's confirmation. `docs/sql/` is empty again, as it was before the
  sprint.
- Five dead focus accessors on `OnyxTileEntry` that existed only for the six
  deleted kinds.

### Changed
- The sprint plan is retired to `docs/Done/WIDGETS_SLEEP_THEMES_SPRINT.md` with
  its twelve Wave Records intact — the written account of what each wave
  actually found, including where it contradicts its own brief.

---

## [6.8.0] — 2026-09-19 · One screen for the stress log

Four surfaces that had grown taller than what they were asking for. The Stress
log wanted a mood, a minute and a couple of tags and took a full-height form
over three sections to collect them; it is now one half-height screen. The
cardio sheet and the Stress index sheet were shouting at 20 and 34 points for
things that are not headings. The Fuel tab's day picker was building two
calendars to decide whether it needed one.

### Changed
- **The Stress log writes in one screen.** "Log stress" opens at half height
  with everything on it at once: the five words in a row, the time as a compact
  control with the part of the day it files under stated under it, the seven
  tags as chips that pack at their own widths, and a one-line note. The note is
  no longer folded behind a disclosure and the sheet no longer opens full
  height. At an accessibility text size it still opens tall, because there it
  genuinely is.
- **The Stress index sheet.** The index reads at the size of a heading rather
  than at the size of the live workout timer, so the number and its word —
  "59 Elevated" — sit on one line as one phrase.
- **The cardio sheet.** The glyph on each Apple Health bout and its add button
  are icons again rather than headings; the one figure left at heading size is
  the last bout's distance, time and pace.
- **The Fuel tab's day picker** is its own screen now, scrolls once, and is in
  the screenshot loop for the first time.

### Fixed
- **The stress sheet's two captions no longer truncate at the largest text
  size.** "Relaxed = nothing…" and "Files un…" both wrap.

### Removed
- Nothing a reader can see. `SessionDetailView.swift` — 3,026 lines, the
  longest file in the app — became three files under `Features/History/
  SessionDetail/`: the page, the ledger (its movement header and its set row)
  and its chart. Not one pixel moved. `FlowRow`, the wrapping chip layout ten
  screens reach for, moved from the exercise page into the design system where
  a widget or a watch face can use it.

---

## [6.7.0] — 2026-09-18 · The numbers the logger already had

Everything here was already being measured, computed or sent, and none of it
was being drawn. The rest between your sets was clocked and stored and never
shown. The coach worked out which lifts are one session away from a heavier
load and published the answer to nobody. A record knew what it beat for exactly
as long as it took to file it. The watch has had your heart rate on your wrist
the whole time and the phone has never once asked for it.

### Added
- **Rest, on the session ledger.** Each set's row carries the rest taken before
  it under its ordinal, with an arrow when it moved by fifteen seconds or more
  against the set before. VoiceOver says it in words on every row, at every
  type size.
- **A rest bar on the exercise card.** While a movement is resting, its header
  carries a bar that drains against the rest the plan prescribed — and against
  the new total when you nudge it by ±15 s, not the old one.
- **The `1 more @ 12` cue.** A movement whose last two sessions have it one
  session away from a load bump now says so on its card, beside the rep
  window, while you are still standing in front of it. The `↗ 42.5 kg` chip
  that means "the load goes up today" is unchanged and still wins the slot.
- **What the trophy was worth.** A record row on the session summary shows its
  margin — `+2.5 kg`, `+2` — beside the trophy for two seconds as the page
  lands, then gets out of the way. The long press still opens the full sheet.
- **The finish sheet has a shape.** One sparkline of this session's tonnage
  against the last few of its own split, with a per-cent against their mean,
  and the intensity gradient that was only on the summary page — the two
  questions you actually ask between the last set and the locker.
- **Live heart rate on the phone.** The watch puts its current reading on the
  rest pulse and answers a phone-driven rest with one echo carrying it. The
  logger's header shows it beside the clock; the Live Stats Effort card shows
  it in place of an average that does not exist until the next morning's sync.
  It ages out after two minutes rather than going stale on screen.
- **The sparkline on a movement's ledger header is a door** — tap it and the
  same estimated-1RM chart the exercise's own page draws opens on this
  movement, with the dates the sparkline could not carry. From three sessions
  up; below that the trail is what it was.

### Changed
- **`RestPulse` carries `bpm`** — optional and last, so a phone or a watch on
  an older build neither throws nor stops seeing the rest clock.
- **`IntensityBar` and `OnyxFormat` moved into OnyxUI** so the finish sheet and
  the session page draw one bar and print numbers one way. No drawing changed.

---

## [6.6.0] — 2026-09-18 · Pulse, six squares, your order

Nothing on Pulse scrolls sideways any more. The two-page carousel that held
Fatigue and the Stress log is gone; they are squares now, in the same grid as
the stress index, soreness, the scale and the stack — a 2 × 3 the reader can
rearrange exactly like the Today tab, with the order kept on the same row the
dashboard and the Train tab already share.

### Added
- **Pulse → Edit.** A word in the toolbar puts the six squares in the Today
  tab's jiggle; drag one onto another's place and the rest close up. Done
  ends it. The order syncs with the dashboard row (`dashboard_layouts`,
  under a new `pulse` key), so a second device draws the same grid, and a
  reader who has turned motion off sees the squares stand still rather than
  wobble.
- **A Fatigue square** — the latest word, which slot it came from, the session
  cost, one dot per slot the day has, and the slot the day is asking for now.
  The square is the door to the rating sheet.
- **A Stress log square** — the last two stamped readings, the ones before
  them behind an "earlier" marker that opens the whole day's log, and the
  door to logging one more.
- **At the accessibility sizes** the six fall to rows in the same stored
  order, and the rows rearrange too.

### Changed
- **Pulse grid** — 2 × 3 in the stored order; the default puts the stress
  index and the log on one row, soreness and fatigue on the next, the scale
  and the stack last.
- **Today tab** — the jiggle and the drag are now the shared `Jiggle` and
  `Arrangeable` in OnyxUI; the tiles move as they did.

### Removed
- **The Pulse carousel** and its page dots. Delete-from-the-face on a stress
  reading went with it; the full log's rows still swipe to delete.

---

## [6.5.0] — 2026-09-18 · The week, anywhere

The weekly report leaves the Train tab. It is its own screen now, reachable
from the Dashboard's Week Rings tile as well as from History, the Past Weeks
shelf and Train — and it reports the whole week, not just the training in it:
sleep, battery, adherence, body composition, muscle coverage, macros,
micronutrients, cardio and records, one chart a section.

### Added
- **The Week Rings tile is a door.** Tapping it on the Dashboard pushes the
  report for the week happening now — a Tuesday included, where the three
  other doors only ever opened a week that had closed.
- **Three verdict capsules at the head of the page** — Sleep · Battery ·
  Adherence — each the mean of what the week actually stored, coloured by
  whether that reading is good. A week with no reading says so rather than
  printing a zero.
- **A Body section**: the week's last believed scan, with body fat and muscle
  mass beside the weigh-in and the date it was taken.
- **A Training section that shows where the work went** — the four muscles the
  week went into, then all sixteen against the plan's own weekly set targets,
  with a pip under every muscle past its target.
- **Nutrition as a chart**: calories a day against the target the week was
  actually eating to, a macro table of daily means, and the micronutrients
  worth acting on — a floor missed, a ceiling passed, or a reading the app does
  not believe.
- **Recovery as a chart**: hours asleep a night against the sleep goal, the
  week's battery as a trail, the mean stress reading and the week's worst
  soreness.
- **A Cardio section** — the week's bouts, minutes, distance and calories.

### Changed
- **Records stop at three**, with the rest one tap away. A good week set
  eleven, and eleven trophy rows pushed the share control off the page.
- **Three rails became three figures.** Sessions, tonnage and PR count now sit
  together as one row with the tonnage's own trailing-week trail behind it;
  "training 100 % / nutrition 67 % / recovery 74 %" invited a comparison
  between three percentages of three different things.
- **An untracked section is one line, not an empty chart.** A week nobody
  logged used to draw two full-height cards saying "No data".

### Fixed
- The weekly report's arithmetic is now testable, and tested. `WeekReport`
  moved out of the app target into `OnyxData`, where the package suite
  `npm run check` runs asserts every figure against the payload it folds.

---

## [6.4.0] — 2026-09-18 · Complications

The watch gets real WidgetKit. Ten of the dashboard tiles are now complications
on the watch face — circular, rectangular, inline and corner — drawn by the
SAME view the phone's Lock Screen draws, from the same numbers the Home Screen
widgets read. One face, both devices.

### Added
- **Ten complications on the watch** (`OnyxWatchWidgets`, a new watchOS widget
  extension): Battery, Workout, Fuel, Water, Steps, Sleep, Bedtime, Stress,
  Soreness and Week Rings, each at every accessory family the watch offers.
  A gauge where there is a goal (water against its target, steps, calories
  left, the battery, the sleep score), a glyph and a number where there is
  not (today's split, last night's bedtime, how many muscles are sore), and
  three rows of seven marks for the week.
- **The phone now sends the wrist its numbers.** `WatchTiles` (≤ 2 KB) rides
  inside the application context beside the schedule and the theme — cut from
  the same snapshot builder the widgets use, so the watch face and the Lock
  Screen never disagree. Pushed on sign-in, at midnight, on a theme pick, and
  after every local write on a 30 s trailing throttle.

### Changed
- **The Lock Screen faces are the watch's faces.** `LockView` delegates to the
  new `OnyxUI/Accessory/` drawing; its five focuses map onto the same ten ids.
  The rectangular Week face reads "Week · 5 trained / 5 fuelled · 6 slept" and
  the Stress inline names its band.
- **The watch app's cached context moved into the App Group suite**
  (`group.app.onyx.health.watch`), where the complication extension can read
  it. A context cached by an earlier build is refetched on the next push.
- `npm run check:swift` now cross-builds OnyxUI for the watchOS simulator too,
  so a system family used in an unfenced face fails on the command line.

### Founder
- Xcode → `OnyxWatch` and `OnyxWatchWidgets` → App Groups capability
  (`group.app.onyx.health.watch`). Needs the paid program: without it the free
  team strips the entitlement at signing (verified on the watch simulator) and
  the complications stay "—" on the wrist — Gate 0, same as the phone.

---

## [6.3.0] — 2026-09-18 · One Figure a Tile

Ten tile faces redrawn so a glance answers the question the tile is named for.
Every one of them had the number already; what most of them did not have was a
shape you could read without reading. The same faces are the Home Screen
widgets, so this is the widget refresh too — and the Water tile now has a
button on it.

### Added
- **+250 ml on the Water widget.** The Water tile at every size draws the day
  as `goal ÷ 250 ml` segments around an arc — seven of twelve glasses, not
  "63 %" — with a `+250` button beside it on the Home Screen. It lands
  immediately (the figure includes the tap before the app has seen it) and the
  app folds it into the ledger the next time you open it, through the same
  water row the Pulse tab uses.
- **A record now says what it beat.** The Latest PR tile is one trophy: the
  lift, the figure, and the margin over the bar it cleared — "32.5 kg, +2.5 kg,
  past 30.0 kg on the book". A first record on a lift says "first on the
  board" rather than inventing a gain. The Medium stacks three; the Large's
  ledger gained the same column.
- **The next session wears its own muscles.** The Today tile washes its top in
  the first two muscles the day's deck trains — the same gradient the Pulse tab
  has drawn on a session card since W2 — and the Medium and Large name the tap:
  **START**, which opens the deck.
- **Sixteen muscles on the Tonnage tile.** A ladder of sixteen cells ordered by
  how much of each muscle's target the week has covered, with the tail named in
  words ("Side delts is furthest behind — 3 of 9"). The per-landmark reading
  has been in the payload since W3 and no face had ever shown it.
- **Seven days of energy balance on the Deficit tile**, one signed bar a day
  around a zero line. A day missing intake or expenditure draws no bar at all
  rather than a bar at zero.

### Changed
- **Recovery leads with a charge arc** whose fill begins at last night's
  bedtime, the score in the middle and the day's verdict — "Ready to train" —
  as the only words under it. The second ring (the battery) became a figure
  beside the verdict; two gauges on one face was two claims about one morning.
- **Sleep is a depth strip**: the four stages as blocks at their own depth,
  widths in proportion to the night. It is captioned *share of night* and is
  not a hypnogram — the app stores four stage totals and no timestamps, so
  nothing here is drawn against a clock. The Medium gained the seven-night
  chart; the Large keeps the stage rows.
- **Vitals leads with whatever actually moved.** The reading furthest from its
  own normal — measured in its own scale, so 0.3 °C and 12 ms are comparable —
  takes the figure, and three chips carry the rest. Picking Temperature or
  Breathing still pins that reading; it is the two "show me the readings"
  focuses that now choose.
- **Fuel is framed on what is left.** Every macro on every Fuel and Macros face
  reads "42 g left" / "met" / "+12 g over" instead of "128 / 165 g", in one
  wording. The bar still carries the proportion.
- **Consistency leads with this week** — "2 of 3 planned" — over a four-week
  dot grid instead of eight. Eight columns on a Small put the dots three points
  apart, which shows that something was missed and not which day. The
  eight-week rate is still on the face, as a caption.
- **Fatigue is a battery line** over a fortnight, shaded by how much each day
  drained, with the biggest drain you can do something about named beside the
  figure. The five-band stack said where one day went, fourteen times at once.

### Fixed
- A macro remainder and a record margin no longer paint green in the Lock
  Screen's tinted rendering, where every tile is one colour and a green figure
  reads as a fault rather than as a verdict.
- The Vitals Large drew a band of nothing above its first row and below its
  last; three things were claiming the same leftover height.

---

## [6.2.0] — 2026-09-18 · One Tile, Three Buttons

The Home Screen gallery now has ONE Onyx entry that draws any dashboard tile,
and Control Center has three Onyx buttons. The six family widgets you may
already have placed keep working for this release and then go.

### Added
- **The Onyx tile** (Home Screen, Small/Medium/Large) — one widget kind whose
  "Edit Widget" picker lists every tile the Today dashboard can draw, under the
  same names, in the same order. The gallery offers each one. A tile placed at
  a size it has no body for draws the largest size it does have (a Medium
  inside a Large); a tile with nothing at or below that size — Day Rings at
  Small — says "Needs a larger widget" instead of drawing half of itself.
- **Control Center: Start session, +250 ml, Log stress.** The first and last
  open the app on the Train and Pulse tabs through the same `onyx://` deep
  links the widgets use. The water button adds a glass WITHOUT opening the
  app: every water face shows the new figure at once, and the glass lands in
  the day's ledger — the same row a tap on the Pulse water row writes — the
  next time the app is in front, and the day is rescored.
- **Lock Screen: Bedtime** — a fifth accessory focus: last night's bedtime in
  the ring, on the two-line face, and beside the clock.

### Changed
- **Fuel, Training, Body, Progress, Daily and Vitals are shells.** Same faces,
  same placement, now described "Moved to the Onyx tile" in the gallery. They
  are removed in the release after this one; re-place them as the Onyx tile
  before then.

---

## [6.1.0] — 2026-09-18 · Four More Faces

Four new tiles join the Today dashboard — and, because a dashboard tile IS the
Home Screen face, they arrive on both at once. Nothing has to be re-arranged:
they are appended to the end of the grid above Day Rings, and a layout you have
already tuned keeps every slot where you put it.

### Added
- **Week Rings** (Today, Small/Medium) — three rows of seven: did you train,
  did you eat to target, did you sleep to goal, for each of the last seven
  days. The tally beside each row is out of seven; the weekday letters come out
  of the dates, so the columns are labelled however the week falls. A day with
  nothing logged counts as a miss, which is what the row is asking.
- **Soreness** (Today, Small/Medium/Large) — today's DOMS painted on the body,
  the same figure Muscle Focus uses for the week's work. One rating covers the
  anatomy the word covers: a sore shoulder lights all three delts. The Large
  lists every sore region with its severity in the words you tapped; the Medium
  lists four and the Small names the worst one.
- **Stress** (Today, Small/Medium) — the stress index and the fortnight behind
  it, read against the scale's own centre of 50 rather than against its own
  average, so a fortnight that is high stays high.
- **Bedtime** (Today, Small) — when you went to bed, when you got up, and the
  usual bedtime underneath. Sleep v2 grades regularity against the median of
  the previous fortnight and until now that baseline was a number you were
  marked on and could not see. It appears after five nights; under five,
  "usual" would be a guess.

### Changed
- **Day Rings wears the theme.** The three arcs are stroked with each domain's
  full gradient instead of a single flat colour, so the tile moves with the
  palette you picked in Appearance instead of sitting slightly outside it.

---

## [6.0.0] — 2026-09-18 · A Night Is More Than Its Length

**MAJOR: every stored sleep score is rewritten.** The first launch on this build
rescores the whole history in the background (the "rescoring" hint on Pulse and
History while it runs). A night that took three hours to fall asleep no longer
scores 100.

**Before installing:** paste `docs/sql/w3-sleep-onset.sql` in the Supabase SQL
editor as `postgres`. Until the two columns exist the server rejects every
night the phone syncs.

### Changed
- **Sleep score v2 — five terms.** Duration (40, the old curve) · Efficiency
  (20, asleep ÷ in bed, full credit at 100 %, none at 75 %) · Latency (15, none
  at 90 min) · Fragmentation (10, awake minutes after falling asleep and
  awakenings of five minutes or more) · Regularity (15, tonight's bedtime
  against the median of the last fourteen, none at two hours off). A term the
  night cannot answer drops and the rest renormalise, so a night synced before
  this build scores on duration and regularity alone. The deep and REM bonuses
  and the illness/travel/emergency relaxations still apply. The battery, the
  recovery term and the short-night cap on the day score are untouched.
  (`Score.swift`; golden fixture `sleep-score-v2.json`, hand-computed, replaces
  `sleep-score.json`.)
- **Sleep sheet (Pulse → Sleep)** — the window is three wheels: **In bed**,
  **Fell asleep**, **Awake at**. The closed row now says how long you took to
  fall asleep. An onset outside the window is refused by the store, not just
  the wheel.

### Added
- **`sleep_sessions.onset_time` and `awakenings`** — when sleep began (the
  first asleep sample Apple Health recorded) and how many times it broke,
  written by every sync and by the sleep sheet, on the phone and the server.

---

## [5.2.0] — 2026-09-18 · The Palette Reads The Block

### Added
- **Nine themes in a 3 × 3 of live palettes** (Settings → Appearance). Each
  swatch is a mesh of the four accents that theme actually resolves to —
  training, nutrition, body and recovery — with the theme's name and its mood in
  one word under it. Four new themes: **Ember**, **Glacier**, **Verdigris** and
  **Nocturne**. Every pair was re-solved in OKLCH inside the contrast guard,
  each secondary at h + 120°, and the nine primaries are now held ≥ 35° apart by
  a test rather than by a comment.
- **The training block tints the app.** A cut reads quieter and deeper, a bulk a
  shade brighter, a deload drops the whole palette to one fixed low saturation —
  and it all shifts back when the block ends. It reaches every screen, the
  widgets and the watch; the two accents the theme is named for never move.
- **Custom routines get real day colours.** A deck built in the app spreads the
  Train mesh over its own days instead of drawing every training day in the grey
  that means "rest".

### Changed
- **Water, deep sleep, REM and awake follow the theme.** They were the last four
  fixed hexes in the palette, so they stayed the same blue, indigo, pink and
  grey under every theme. Water is now Tide's far stop, the three sleeping
  stages are three separated stops of Lunar in the order the night runs, and
  awake is secondary ink — it is not a kind of sleep.

### Removed
- **The colour pickers and the two mood sliders.** A hand-picked pair of hues was
  a palette nothing had been measured against, and the one hue band the contrast
  sweep found under AA was reachable only through a picker. The nine presets are
  each solved inside the guard; picking one of them is now the whole screen.
- The derived-ramp preview and "Reset to Ion" went with them — every swatch in
  the grid *is* that preview, and Ion is the first chip in it.

---

## [5.1.0] — 2026-09-18 · Nobody Else's Numbers

The founder's own figures had been shipping inside the app bundle and compiled
into the domain — his starting loads, his calorie targets, his treadmill, his
July. Every one of them now comes from the reader's own rows, or does not come
at all.

### Changed
- **The warm-up the logger opens with is yours.** It used to be a fixed five
  minutes at 2 % over 0.37 km on a movement called Treadmill, prepended to the
  first session of every account that ever opened the app. The deck now repeats
  the athlete's OWN last cardio bout — the walk, ride or row in `cardio_logs`,
  by its own name, cut to warm-up length (ten minutes) with its distance cut to
  match so the pace on the card is the pace that was run. Somebody who has never
  logged cardio gets no card, instead of somebody else's.
- **"Scheduled rest" no longer names a plan you are not on.** The coach headline
  on Today reads the plan that owns today out of `plans`, and has dropped the
  "150–250 kcal" Zone-2 dose — how much a rest day is worth is a function of
  your own targets.
- **Re-entry is a date you mark, not a fortnight in 2026.** The "go light, no
  PRs" headline was hardcoded to 19 July – 1 August. It now reads a `reentry`
  override in `schedule_overrides`, so anybody can mark their own days back
  after a break — and marking them moves no session: the week's training days
  and rest days stay exactly as the plan authored them.

### Fixed
- **"Trouble falling asleep" now moves the numbers it is an input to.** The flag
  feeds both the stress index and the battery's wellness drain, but ticking it
  wrote the row and stopped — so the stored score for that night, and every day
  in the readiness window after it, went on describing the un-flagged version.
  It runs the same rescore cascade a sleep-window edit does.

### Removed
- **Starting loads and phase goals are out of the bundled plan templates.** The
  three decks a new account can pick from carried a `wk1Kg` per exercise (one
  athlete's week-1 load) and a `phaseGoals` block per plan (his calories, his
  macros, his target weight, his rate band). The templates describe the DECK
  now; a new account's targets have been its own arithmetic since W5, and the
  screenshot harness carries the numbers it needs to draw a plausible screen.
- **`PreviewCatalogue` cannot ship.** The screenshot harness's seeded account is
  `#if DEBUG` like every other harness file, rather than a convention that held
  until somebody forgot.

---

## [5.0.1] — 2026-09-17 · The Sprint Leaves No Residue

**PATCH: nothing in the app changed.** The closing wave of the Next-Gen UX
sprint — twelve waves that ran from `3.10.1` to `5.0.0` — which was housekeeping
by design: the plan retired, the migrations put away, the caches purged, the
gate re-run on a cold cache.

### The sprint this closes

Twelve strictly sequential waves, each cut from `main`, merged `--no-ff` and
bumped on its own branch. What they shipped, in order:

| | | |
|---|---|---|
| `3.10.1` | Apple Health Tells The Truth | a walk imports once; the water row stops reading `—` |
| `3.11.0` | The Night Leads | the sleep hero, eight sidekick vitals, and a vital that can take the lead |
| `3.12.0` | Four Squares | Pulse's 2 × 2 grid — stress, soreness, scale, stack |
| `3.13.0` | The Ledger Stops Shouting | RPE inverts, the em-dash goes, unilateral sets get a comparison |
| `3.14.0` | Cardio and the Banners | the bout card, and the placeholder that stops being a grey box |
| `3.15.0` | Train Tells the Truth About the Week | day-matched trends, past weeks, Customize Train |
| `3.16.0` | The Dashboard Grows a Face | Day Rings, the rule-based sentence, connected stacks, the jiggle |
| `3.17.0` | Appearance, Everywhere | the tab tint, the App Group accessor, 105 hardcoded inks tokenised |
| `3.18.0`–`.2` | The Body Has Two Sides | tap the side you mean; `doms_logs` learns left from right |
| `4.1.0` | Fatigue Reads The Clock | the card asks the question the time of day makes sense of |
| `5.0.0` | One Store, One User | RLS on all 34 tables, every read scoped, account-switch erase |

Each has its own entry below, and each says what a user can now do. This entry
exists so the twelve read as one arc.

### Changed
- **The sprint's three migrations are applied and their files are gone.**
  `w1-hk-uuid.sql` (pasted 2026-09-15), `w9-doms-laterality.sql` (2026-09-16)
  and `w11-isolation-rls.sql` (2026-09-17) have all landed in Postgres, so
  `docs/sql/` is empty again, as it was before the sprint. The guarded local
  `ALTER TABLE`s that shipped beside them stay — they are for a store older than
  the migration, not for a server that lacks the column — and the comments that
  described the waiting window now say when it closed instead of naming a file
  that no longer exists.
- **The plan is retired to `docs/Done/`,** joining `EPIC_SPRINT_PLAN.md` and
  `Plan-Onyx-UX-Architecture-Done.md`. Its eleven Wave Records — the drift taken
  on purpose, the root causes that were not where the plan guessed, the
  constraints each wave left for the next, and the seams held open deliberately —
  were harvested first into this changelog and into the project's memory, so
  nothing in them depends on the file to survive.
- **The regenerable data is off this machine again**, none of it tracked and
  none of it read by any gate: each wave's Swift scratch paths and screenshot
  derived-data directories, `native/.build`, and the Xcode derived data for this
  project. The whole gate — `check`, `check:swift`, `swift:core`, `swift:data`
  and the app / widget / watch build — was then re-run from a cold cache, which
  is what makes the green a green from source.

### Note
`native/OnyxTests` is still executed by nothing in `npm run check`
(`scripts/swift-ui-test.sh` passes `-only-testing:OnyxUITests`, so the bundle is
compiled by the gate and run by no one) and still carries the baseline it
carried at the start of the sprint. Recorded rather than fixed, for the third
sprint running: turning that bundle on is a sprint of its own.

---

## [5.0.0] — 2026-09-17 · One Store, One User

**A MAJOR release: the founder must paste one SQL file, and signing into a
second account on a device now erases the first account's local data before the
first sync.**

### Added
- **Row Level Security for all 34 tables (`docs/sql/w11-isolation-rls.sql`).**
  Until now no policy was checked into the repo — isolation was asserted in
  prose only, and the live database granted every table to the anonymous role
  `to public`. This file, generated from a live introspection and proved on a
  throwaway Postgres 17 cluster, enables RLS on every table and gives each four
  policies on `(select auth.uid()) = user_id` — the initplan form, evaluated
  once per query. `workout_sets` and `set_events` are additionally checked on
  write against their session's owner; `set_events` is append-only, so it has
  no update policy; the founder's admin reads are preserved; `profiles.role`
  becomes read-only to the user (a column grant replaces the table UPDATE that
  let any account promote itself to admin); TRUNCATE is revoked from the API
  roles. **The founder pastes this once in the Supabase SQL editor — nothing in
  the app can apply it.**
- **`TwoUserIsolationTests`.** Two accounts seeded into one store, with every
  scoped reader asserted to return one account's rows and never the other's —
  sessions, sets, the ledger, records, cardio, bodyweight, reports, the weekly
  export, the scorer and the widget snapshot. The exhaustive proof of the wave.

### Changed
- **Signing into a different account erases the previous one's data first.**
  A sign-in whose user differs from the store's owner now clears the local
  store before the first sync, using the same erase sign-out runs, and reports
  the previous account's unsynced-change count exactly as sign-out does.
  Before this a sign-in with no sign-out before it inherited the previous
  account's rows until its own sync landed — and the widget kept drawing them.
- **Every local read is scoped to its user.** The personal-record engine, the
  session history, the weekly export, the day scorer, the widget builder, the
  live/finished session readers, the session editors, the event reprojection,
  cardio, bodyweight and the training puller all now filter on `user_id`
  (through the session join where the row carries none). The store was already
  one user's mirror; this is the second lock, so a row that outlives its owner
  is never handed to the next account.

### Fixed
- **A new account can no longer land on a configured app.** Onboarding stopped
  being offered whenever the local `exercises` catalogue held any row — but
  that table has no `user_id`, so one leftover row from a previous account
  suppressed onboarding for a brand-new one. The catalogue check is deleted:
  local `exercises` proves a catalogue was pulled, not that this account was
  set up.

### Unchanged, on purpose
- **No score, record or golden vector moves.** Scoping a single-user store's
  reads by that user returns exactly the same rows; all 591 OnyxData, 581
  OnyxCore and every UI test pass byte-for-byte.

---

## [4.1.0] — 2026-09-17 · Fatigue Reads The Clock

### Changed
- **The fatigue card asks one question at a time.** On the Pulse tab the card's
  verb now names the slot the day is asking for — **Rate before training** until
  the session ends and **Rate after training** from the minute it does (or from
  18:30 on a training day with no session logged); **Rate waking · midday ·
  night** at 11:00 and 18:30 on a rest day, which never asks the pre-session
  question. The empty dot for that slot is drawn in the Recover accent. The
  fatigue sheet opens on the same slot, so the question on the card and the
  segment under the five words agree. A day already over asks its last slot.
- **A session cost is never printed against a blank.** `post − pre` still shows
  only when both ends exist; with exactly one end logged the card now says
  **Pre not rated** or **Post not rated** instead of nothing, so "no cost" and
  "no cost yet" stop looking the same. VoiceOver reads the same words.
- **The clock is read from one place.** The card, the sheet and the stack's
  Due/Later split all read `DayModel.clock` — pinned in the screenshot loop —
  and the session's end from the stored row, never the wall clock. The `day`,
  `day-rows`, `day-past` and `day-session` shot screens are pinned to 13:00.

### Unchanged, on purpose
- **The stress index's self-report input did not move.** `Fatigue.dayMean` is
  still the mean of every slot the day holds (`STRESS_MODEL.md` §2); the
  battery still reads the latest slot. `FatigueClockTests` asserts the mean
  over two slots is the same whichever slot is being asked for, and every
  battery, readiness and stress golden vector is byte-identical.

---

## [4.0.1] — 2026-09-17 · Putting The Tools Away

**PATCH: nothing in the app changed.** The closing wave of the UX/UI
architecture sprint — `3.22.0` A Powder Is Food, `3.23.0` The Trophy Lights On
The First Tick, `3.24.0` Nine Moods And A Form That Arrives Full, `4.0.0` The
Week Is A Place — which was housekeeping by design: the trunk confirmed whole,
the derived data purged, the gate re-run on a cold cache.

### Changed
- **68 GB of regenerable data removed from this machine**, none of it tracked
  and none of it read by any gate: the graph's dated snapshots and its stat
  cache, a duplicate graph under `native/`, the screenshot archive (untracked
  since `3.8.0`), every wave's Swift scratch path, and the Xcode derived data
  for this project. The code graph was then rebuilt from a cold cache, which is
  also the proof that the purge left nothing that could not be rebuilt.
- The whole gate — `check`, `check:swift`, `swift:core`, `swift:data`, and the
  app / widget / watch build — was re-run from scratch rather than from a warm
  cache, so the green it reports is a green from source.

### Note
`native/OnyxTests` is still executed by nothing in `npm run check`, and still
carries the ten baseline issues it carried at the start of the sprint. Both
facts are recorded in the sprint's Wave Records rather than fixed here: turning
that bundle on is a sprint of its own, not the tail of this one.

---

## [4.0.0] — 2026-09-17 · The Week Is A Place

**MAJOR because a screen was removed.** The weekly wrap-up sheet is gone. Every
door that opened it now pushes a full-page **Weekly Report** instead, and the
"Where the work went" ring has been deleted rather than moved.

### Added
- **The Weekly Report — a page, not a sheet.** Open a week from the Train tab's
  This-week tile, from the Past Weeks shelf, from a week's **Wrapped** chip in
  History, or from the Today tab's "week is complete" banner: all four now push
  the same screen, with a back button and no fold. It opens on a **phase band** —
  the week's numeral over a full-bleed wash in its block's own colour, with the
  block's tag and the dates beside it — and then three **rails**: Training,
  Nutrition, Recovery, each a percentage with the figures behind it written
  underneath.
- **The report says what the week ate, drank, lifted and weighed.** Under the
  reel that was the sheet's whole content you now get the seven days graded hit
  / miss / exception against the calorie rung that was in force **on each date**;
  the week's water as a daily mean against your goal; every personal record the
  week set, sorted by exercise; the week's Hardest, Heaviest and best estimated
  1RM; and the weigh-in with its change across the week. All of it comes from
  the one call the weekly export already makes, so the page and the exported
  document cannot disagree about the same week.

### Changed
- **Past Weeks banners are a third shorter and coloured by phase.** A banner was
  ~124 pt; it is now under 88 pt at the default text size, which is five weeks
  on a screen instead of three. The label is a card title rather than a second
  hero, the totals are one line, and the tile's wash takes its block's colour —
  cut, bulk, peak and deload each have their own.

### Removed
- **The wrap-up sheet.** `WeeklyWrapView`, its 560 pt detent and its drag
  indicator. The reel it carried is unchanged and is now the middle of the
  report page.
- **The "Where the work went" ring.** `WeeklyMuscleRing` is deleted. Where the
  week's work landed is the Training rail at the top of the page and the
  movement breakdown below it; a third answer drawn as a donut of sixteen
  landmarks was one too many.

---

## [3.24.0] — 2026-09-17 · Nine Moods, And A Form That Arrives Full

### Added
- **Appearance — a mood, not just a hue.** A theme was two colours and every
  other colour in the app was one of them turned: lightness and chroma were
  pinned to Ion's, so Obsidian and Aurora were the same palette at different
  angles. Two sliders under the pickers now set **Saturation** and **Lift**, and
  they reach all twenty-four derived colours — the four domain ramps, the washes
  and the sixteen muscles. The two accents you pick stay exactly as you picked
  them, so the swatch never disagrees with the screen.
- **Eight new themes — nine in all.** Ion, Obsidian, Solstice, Meridian, Basalt,
  Aurora, Terracotta, Vesper, Halcyon. Every pair was solved in OKLCH inside the
  contrast guard rather than picked by eye, the nine primaries are at least 35°
  apart around the hue circle, and each carries its own mood: Obsidian and
  Basalt deep and grey, Aurora and Halcyon lifted and vivid. Widgets and the
  watch follow on their next refresh.
- **The waist has a column.** `daily_logs.waist_cm`, entered in the InBody sheet
  beside the weight it was taken with, synced like every other figure and
  carried forward into the next reading. Three comments that said this would
  never happen have been replaced with the decision and its date rather than
  quietly deleted — there is still no table of girths, and no hips, thighs or
  arms.

### Changed
- **The InBody sheet is a hero and four accordions.** Body fat is the headline;
  weight and skeletal muscle sit under it, each gaining a live ▲/▼ against your
  last reading as you type. Below it the scale's own four registers — Mass,
  Composition, Water & protein, Minerals & derived — each collapsible and each
  saying how many of its fields are filled while it is shut. The five derived
  masses are no longer a section at the bottom: each now sits one row under the
  percentage it was computed from, and to one decimal, so a three-hundred-gram
  move in fat mass is visible instead of rounded away.
- **The form arrives full.** "Fill from last time" and "Fill from Apple Health"
  are gone. Every empty field is seeded from your previous reading, with Apple
  Health over the top of it where Health has something, and a caption under each
  field names the source — **Health**, **Last** or **You**. Fine-tuning is
  typing over a filled field.
- **Save still waits for you.** On a day that already holds a reading, opening
  the sheet and closing it writes nothing, however much arrived pre-filled. On a
  day with no reading yet, the carried figures are offered for saving — because
  a weigh-in that needed no corrections still has to be recorded.

### Fixed
- A theme saved before this release keeps it. The stored blob has two keys and
  the spec now has four; a missing key reads as the neutral mood instead of
  failing to decode and silently resetting the app to Ion.
- The preset chips name their themes. The grid was built for five-character
  names and "Terracotta" is ten — it is two columns now, and one at the
  accessibility sizes, rather than a row of truncated words.
- The InBody hero at the largest accessibility size: "Skeletal muscle" is no
  longer cut to "SKELETAL MUSC…", and the blank line reserved to align two
  side-by-side figures no longer sits in the middle of the stacked card.
- A saved weigh-in can no longer gain body-composition masses computed from last
  week's percentages. Correcting one field on a day that holds a partial reading
  writes that field and the masses it feeds, and nothing else.
- No theme can put a number under the 4.5:1 contrast floor. The lift used to
  reach the ramp ENDS unguarded, and `Lean soft tissue` on the composition
  widgets is drawn in one of them.

### Note for anyone on an older theme
Ember, Moss, Rose, Gold and Sea are no longer in the preset list. **Your colours
are unchanged** — the app keeps the exact two hues you were on — but Settings
now names the theme "Custom" and no chip is lit, because a theme is identified
by its colours and those five are no longer in the table. Pick any of the nine
to adopt a name again.

---

## [3.23.0] — 2026-09-17 · The Trophy Lights On The First Tick

### Fixed
- **The live PR cup appears the moment you earn it.** The logger built its
  record bar once, when the screen opened, and then quietly changed the key it
  judged sets under: the first set of a movement the catalogue had not heard of
  mints a catalogue row, and the key flipped from a slug to a uuid while the bar
  stayed on the slug. A record needs an existing bar to beat, so the deck awarded
  nothing — on sets whose own session page, one screen later, showed two. The
  deck now resolves one identity per card, rebuilds the bar whenever that
  identity moves, and a set that beats a standing record lights gold on the tick
  that logs it.
- **A phase switch mid-session no longer drops the trophies you already won.**
- **Records stop vanishing to "—" on a re-opened session.** An edit deck was
  measuring a workout against the personal records that same workout had set, so
  a session with three PRs reported none of them. The standing-record floor now
  excludes the session being corrected.
- **A movement's history survives getting a catalogue row.** The row minted for a
  lift you have been logging under a legacy id now claims that id, so the sets
  behind it stay part of the bar instead of dropping out of it.
- **The treadmill reads as a treadmill on the Lock Screen and in the Dynamic
  Island.** It said `0 kg × 0` — literally, because a bout's load and reps are
  real zeros and the producer only checked for nil. The running-workout card now
  shows the live bout on the phone and the watch: `12:30 · 2.19 km · 5:42 /km`,
  and the compact island shows the bout's clock instead of a barbell.
- **The Cardio tag is back on the exercise card**, with the bout's pace beside
  it. A seeded treadmill card now carries its minutes, incline and distance, so
  the card knows it is a bout — and the muscle dictionary still refuses to learn
  a treadmill, which is what keeps walking out of your weekly volume.
- **An edit deck opens in the order you trained in.** A re-opened session was
  being re-ranked against a different session's running order, which sent the
  treadmill to the bottom every time, and the deck offered a warm-up bout nobody
  had walked. Both decisions now happen when the deck is built.
- **The finish sheet stops claiming a finished session is unfinished.** Editing a
  complete workout read "18/19 sets"; it now reads "18 sets", because a session
  that has ended has no target left to hit.

### Added
- **Cancel Edit.** Re-opening a finished workout now has a way out. Every set
  edit commits as you make it — that has not changed — so cancelling is a real
  undo: the deck marks where your log stood when the editor opened and writes the
  events that get back to it, restoring the sets, the tonnage, the set count and
  the PR ledger. Nothing is deleted; the undo is itself history, so it survives a
  sync and a crash mid-edit. Leaving by the chevron still means "keep my
  changes", and it still says so.
- A seeded bout carries its minutes, incline and distance, so a treadmill card
  built from history is a bout rather than a lift of nothing.

### What Cancel Edit does not cover
It undoes **this phone's** edits to that session, from the moment the editor
opened. Another device's edits to the same session are not this device's to
take back, and a set that was deleted and then restored comes back under a new
id — so if you restore one half of a split pair, that half moves to the end of
its position group. The figures are all correct; only the order inside a tie
changes.

---

## [3.22.0] — 2026-09-17 · A Powder Is Food

Wave 1 of the UX/UI architecture sprint: the Stack editor, the day's calorie
ring, and the one numeral in the logger that would not hold still.

### Added
- **A supplement's time is set on a clock, not typed.** The Stack editor's time
  row was a free-text field asking for "22:00" in words. It is a wheel now —
  the same `.wheel` `DatePicker` the rest timer uses, hour and minute only — and
  a "Set a time" toggle beside it, because a wheel cannot express *no time* and
  an item without one is a real state that sorts to the top of the day.
- **Supplements carry calories, and the day's ring counts them.** A row's
  `micros` payload may now name `kcal`, `carbs`, `fat` and `protein`, and
  `StackCredit` resolves them from the same doses, under the same credit rule,
  as the micronutrients it already resolved. Five grams of psyllium husk is
  17 kcal and 4.4 g of carbohydrate; until now the tab showed the fibre arriving
  and pretended the scoop had not happened.
- **Psyllium Husk Powder** (Now Foods), 5 g at 18:30, seeded with its label
  payload — and `scripts/add-supplement.mjs`, which writes a row like it
  idempotently, keyed on the log key so a re-run can never mint a twin.

### Fixed
- **`18.75` is the same size as `20`.** A load rendered smaller than its
  neighbours the moment it reached five glyphs, on any text size above the
  default. The scale factor everyone would blame was not the cause: the load
  column's floor was the constant `56`, which is six monospaced glyphs at body's
  17 pt **and at no other size**, so above the default the field ran out of room
  mid-string and shrank the strings that crossed it. The floor now scales with
  the body text style, in the row and in the column header alike, so the table
  stays a table and the numerals stay one size.

### Changed
- The Nutrition tab's `eaten` total is food plus the credited stack. The edit
  sheet still opens on **food alone** — seeded from a stack-inclusive figure, a
  save would have written the supplement's calories into a food row and counted
  the same scoop twice from then on.

---

## [3.21.1] — 2026-09-17 · One Week, One Name

Closes the UX/UI refinement sprint (3.20.0 → 3.21.0 → 3.21.1).

### Fixed
- **A week is called the same thing by every door that opens it.** Four screens
  open a week's wrap-up in a sheet — the This-week tile, History, the Today tab
  and the Past Weeks shelf — and three of them headed it `Week of Sun 16 Aug`
  while every other surface in the app called that week `Week 5`. The sheet
  could not do better: naming a week needs the phase table and the plan's
  week-zero anchor, and a view holding a `WeeklyWrap.Summary` has neither. The
  BUILDER has both, so the summary now carries its own label and the four doors
  agree. A summary assembled by hand in a preview still falls back to the date.

### Removed
- `WeeklyWrapView(title:)`, the per-call-site override W1 added to make the
  shelf and its sheet agree. One name on the summary makes it unnecessary, and
  an override that only one of four callers passed was the disagreement waiting
  to come back.

---

## The sprint's six corrected premises

Six briefs opened this sprint and **all six named a symptom whose cause sat
somewhere else.** Kept here because the plan that recorded them is deleted with
this release, and the corrections are the part worth keeping.

1. **"Delta arrows sit BELOW the set metrics, creating an ugly empty row."**
   There was no row. Each delta is the second line of its OWN column, and three
   of them align into what looks like one. The line is reserved on purpose so a
   card cannot change height between two sessions. The real waste was a card
   with **no previous session at all**, reserving a comparison that cannot
   exist — fixed in 3.21.0 as a card's decision, not a row's.
2. **"Tags take up 3 cluttered rows."** They were already ONE `FlowRow`. The
   three rows were wraps, and the wrap point moved with the text size. The fix
   was not fewer tags but a fixed ROW ASSIGNMENT: what was asked of the movement
   on row 1, what it produced on row 2.
3. **"Reduce the mini-graph height by a few pixels."** The sparkline was 40×16
   inside a header line whose box is ~22 pt. Shrinking it bought **0 pt**. It
   was the WIDTH that was wrong, and the line it was on: it went to 56×16 on the
   row below, off the movement's name.
4. **"Merge identical L/R sets into one row."** `SetPairLayout.resolve` had
   implemented exactly that for a year. Only the LOGGER consumed it, and
   `.unified` was deliberately killed there on 2026-09-11 because a merged row
   left no way to rate one side. That dead end is an EDITING dead end; the
   ledger is read-only, so the ledger merges and the deck still does not.
5. **"Sept 10 pushdown is missing the right-side RPE."** Not a bug — a reachable
   state. `workout_sets.rpe` is nullable by design and `SetPatch` cannot write a
   null back, so rating one side and skipping the other left the second side
   null permanently. Nothing backfills it. 3.20.0 stopped the leak (rating one
   arm seeds the other) and made the ledger say so (`L 8 · R —`); the row
   already in the log is still repaired by editing that session.
6. **"Number past weeks correctly and colour them by phase."** The numbering
   already existed — `Week.label(ofWeekStart:anchor:phases:)` — and the Train
   tab simply never called it. The COLOURS did not exist: `Color.onyx.phase`
   took `ProgramPhase` (two cases) while `PhaseKind` has four. Both landed in
   3.20.0; this release finished the numbering at the last three doors.

---

## [3.21.0] — 2026-09-17 · Seven Figures, Two Rows

### Changed
- **The session page has one hero and one grid.** Volume was the first of seven
  equal figures in a 3-up over a 4-up — two tables about one workout, with the
  four narrow cells breaking their own labels. It is the masthead's hero figure
  now, with its arrow and its delta, and the six that are left (Duration · Sets ·
  Difficulty · Records · Avg HR · Calories) sit in one 3×2 grid at one column
  width. Fourteen figures down to seven.
- **Every metric cell carries eight weeks of itself.** A low-opacity trail of the
  split's own history sits behind each figure, in the space the number was
  already using. The two cells whose second line said "measured" or "estimated"
  — a restatement, not a comparison — say it to VoiceOver now and show the
  trail instead.
- **The exercise card is two rows that never move.** The header was one flowing
  line of muscle chips and readings, so the wrap point moved with the text size
  and no reading had a place. Row 1 is the movement's muscle, how it went, what
  was asked and the cue; row 2 is what it produced. Tapping the muscle chip
  swaps row 2 **in place** for the assisting muscles — the card does not change
  height, at any text size — and `+2` on the chip is both the count and the
  affordance. The assists are reachable at the accessibility sizes for the first
  time; they used to be capped away there.
- **The trail beside a movement's name moved and grew.** 40×16 on the title line,
  competing with the movement's own name, to 56×16 at the trailing edge of row 1.
  The height never changed, which is why it never cost anything.
- **The muscle card says it once.** The 100 % ramp is gone. It restated the
  legend's numbers as lengths in 6 pt of stacked capsule, where 4.5 and 4.0 are
  a pixel apart. The body figure is the shape; the legend is the reading.
- **The Train tab's finished card grows into the session page.** Both open with
  the same masthead, so the push was an identical band sliding over an identical
  band. A zoom says what happened, and the exit travels the same path. A Past
  Weeks banner opens its wrap-up the same way.
- **One square, not two.** `SessionDetailView.cell` and
  `WeeklyWrapContent.stat` were the same object drawn twice in two files, drifted
  apart by a type size and a scale floor. `OnyxStatCell` in the design system is
  the one drawing.

### Fixed
- **A first-ever movement reserves no delta line.** The rule that keeps a row
  from changing height between two sessions was being applied to a card that has
  no previous session and never had one — three columns of guaranteed blank on
  every row. It is a card's decision now; within a card nothing changed.
- **A session that lifted nothing has no volume hero.** `0.0 kg` at 28 pt over a
  treadmill-only day is the same category error the tonnage capsule already
  refuses: the work carried no load, so there is no tonnage to be zero of.

---

## [3.20.0] — 2026-09-17 · The Shelf, and Both Arms

### Added
- **Past Weeks is a shelf, behind a button.** The Train tab has its first
  toolbar: a books button at the trailing edge opens every closed week of the
  plan as a sheet of banners — the week's number, its dates, what it trained and
  what it weighed — grouped under the `plan_phases` block that owns it and
  tinted by that block's phase. Tapping one opens the wrap-up the This-week tile
  and History already open. The eight-week cap is gone: the shelf walks back to
  the week the plan started in.
- **`Color.onyx.phase` answers for a plan block.** The token took cut and bulk
  and the table stores four — so `peak` takes the app's record gold and `deload`
  takes Recover's accent, with no new hex. The two directions keep their ink.

### Changed
- **A week is called `Week 5` everywhere.** The Train tab hand-rolled
  `Week of Sun 16 Aug` while History, the session masthead and the weekly export
  all used the programme's own counter. The shelf, and the wrap-up sheet a
  banner opens, now both take `Week.label(ofWeekStart:anchor:phases:)`. The date
  is still there, as the subtitle it always should have been.
- **A unilateral set that agreed with itself is one row.** The session ledger
  drew every pair as two lines, so both arms pressing `5kg × 12` printed
  `5kg × 12` twice to say nothing twice. It now consumes `SetPairLayout` — the
  rule that has defined the three shapes since it was written — and merges the
  sides that agree, splits the ones that do not, and centres a single effort
  reading against a pair rather than parking it on the left arm's line. The
  LOGGER is untouched: merging there is an editing dead end, and the ledger is
  read-only. No tonnage, set count or record moves.
- **The Train tab stopped paying for a list nobody had opened.** The eight past
  weeks were walked on every refresh — a week query plus a read per session
  inside them. They are read when the shelf opens.

### Fixed
- **Rating one arm no longer strands the other.** `workout_sets.rpe` is nullable
  and `SetPatch` cannot write a null back, so rating the left side and walking
  away left the right side unrated permanently. The picker now carries an
  unrated sibling with the tapped side and seeds it with the same value —
  editable, and exactly what splitting a set already did. Nothing historical is
  written; a session already logged is repaired by editing that session.
- **An unrated side says so.** The ledger prints `L 8 · R —` in tertiary ink
  rather than a lone `L 8` that reads as the set's own rating.

---

## [3.19.0] — 2026-09-16 · A Walk Knows When It Happened

### Fixed
- **An auto-logged cardio bout keeps the time it actually started.** Every
  automatic pass already read `HKWorkout.startDate` and wrote it when it created
  a row — and then never looked at it again. A bout whose start had been
  replaced by the moment of the import (a row pulled back from the web era, one
  written before that rule existed, one whose timestamp did not survive a round
  trip) was matched by its key on every later pass and left exactly as it was.
  The walk you took at 07:50 kept printing 22:47 — the moment the app was opened
  — on the Workout tab and in the weekly export. The ingest now corrects the
  start it is holding, so every wrong row repairs itself on the next sync. A
  bout you typed by hand still keeps the moment you typed it: that is not a
  start, and nothing here invents one for it.
- **"Weigh-in landed" stops asking once you have answered it.** The banner was
  a predicate with no memory — "the row has a weight and neither InBody column"
  — re-evaluated on every yield of a stream this app does not fully control.
  A sync rewrites the day's `body_composition` row, a pull replaces it with the
  server's, so two columns filled in at 09:00 could read as blank again at 09:05
  and the question came back for the rest of the day. Saving the InBody form now
  answers it for that date, whatever a later sync does. Tomorrow's weigh-in asks
  again, which is the point of the banner.
- **The HealthKit ingest writes to the row every reader reads.** It picked the
  day's `body_composition` row with an unordered `fetchOne`; the stream, the
  InBody save and the vitals history all take the newest `measured_at`. On a day
  that ended up with two rows the weight went to one row and the reading came
  from the other, which is how a typed InBody number appeared to vanish.

### Changed
- **The dashboard jiggle is the Home Screen's, not a shake.** It ran every tile
  at one rate on rotation alone, which reads as a hinge and re-synchronises into
  a single pulse however the phases start offset. Each tile now leans ±1.1° —
  iOS's own amplitude — slides a little over half a point as it leans, and runs
  at its own rate within ten percent of the beat, so the grid never comes back
  into step. Reduce Motion still gets the accent hairline instead of all of it.
- **The Sleep sheet leads with the two questions only you can answer.** It is
  titled "Sleep" rather than "Sleep window"; the two flags sit at the top where
  a thumb lands; the night's gauge sits under them; and the window — two 128 pt
  wheels that used to push everything else past the fold — is last, shut on
  arrival, with its span on the closed row. It opens itself when there is
  something wrong with the window to say.
- **The Stack square says what the evening contained.** Once nothing is still
  ahead, the row of dots — whose whole job is "how much is left" — gives way to
  the doses themselves: up to five overlapping discs in each supplement's own
  colour, newest first, with the rest as `+N`. A stack of three or fewer names
  its last dose; a longer one gives the time.
- **The Soreness square always draws the body.** With nothing sore it was a
  caption over an empty box, which reads as a square that failed to load. The
  anatomy figure is now the square's own mark, always drawn, on the side that
  carries the soreness — and when there is any, the same figure paints it at
  severity.

---

## [3.18.2] — 2026-09-16 · The Database Had Already Decided

A second hotfix for 3.18.0, and the one that settles what a whole-muscle
soreness rating is stored as.

### Changed
- **A rating of a whole muscle is now stored as `both` / `''`, not as an absent
  value.** `doms_logs` declares both columns NOT NULL — the old web app made
  them that way and filled them with those words — so 3.18.0's design was not a
  second spelling of the same thing, it was a value the table refuses. The app
  now writes what the table requires, which means one spelling in Postgres, in
  the phone's local store and on the wire.
- The weekly export is unaffected and pinned by its golden document: a bilateral
  rating is still the bare muscle name, with no marker of any kind.

### Fixed
- `docs/sql/w9-doms-laterality.sql` now normalises the column values rather than
  trying to empty them, and sets the defaults that let a bilateral rating be
  pushed without naming either column. It no longer requires Postgres 15.

---

## [3.18.1] — 2026-09-16 · Two Spellings, One Meaning

A hotfix for 3.18.0, found while applying its migration.

### Fixed
- **A soreness rating the old web app wrote is now re-rated, not duplicated.**
  That app spelled "the whole muscle, both sides" as `side = 'both'` /
  `sub_region = ''`; the native app spells it as an absent column. A rating
  carrying the older spelling was invisible to the newer lookup, so re-rating
  that muscle minted a second row beside the first. Both spellings now answer
  the same question the same way, in the store, on the Soreness map and in the
  weekly export — whose token for such a rating is unchanged either way.
- `docs/sql/w9-doms-laterality.sql` normalises the older spelling once, on the
  server, and reports what it collapsed. It also no longer fails on a catalog
  type mismatch when it looks for the key it has to replace.

### Changed
- The migration refuses to delete anything on its own: if two ratings would
  collapse onto one key it stops, rolls back and prints the query that shows
  what is involved.

---

## [3.18.0] — 2026-09-16 · The Body Has Two Sides

Soreness stops being a thing you have and starts being a thing you have on one
side. The atlas has drawn a left and a right path per bilateral muscle since it
was first drawn, and the hit test has always known which one a finger was in —
this is the release where the answer stops being thrown away.

### Added
- **Rate one side of a muscle.** Tap the right glute and rate the right glute.
  The severity popover opens with a **Both · L · R** segment pre-selected to the
  side you touched, so the common case is still one tap and the correction is
  always there. Muscles the body draws as one shape — the traps, the erectors,
  a midsection — are still rated whole, because they have no side to choose.
  (Pulse ▸ Soreness)
- **`doms_logs` carries `side` and `sub_region`**, both optional. A left and a
  right rating of one muscle now coexist on one day.
- **The weekly export finally writes the laterality grammar it has always
  known**: `muscle[/subRegion][@L|@R]:severity` — `Glutes@R 3`, `Back/Erectors 2`.

### Changed
- **VoiceOver walks the body by side.** Touch-explore lands on "Glutes, left"
  rather than one element spanning the whole pelvis, and the rotor still offers
  the ten whole muscles so nobody has to scroll past thirty.
- The Soreness square counts a one-sided rating **once**. A sore right glute is
  one sore muscle.

### Fixed
- The soreness summary takes the **worst** of a muscle's sides rather than
  whichever row was read last — the fold the battery has always used.

**Unchanged on purpose:** every battery and stress number. The scoring fold
takes the max within a muscle, so splitting a rating into a left and a right
cannot move a score that a single rating at the same severity did not move.

**Requires the founder to paste `docs/sql/w9-doms-laterality.sql`.** Until then,
one-sided ratings queue in the outbox and land on the first sync after; whole-
muscle ratings are unaffected.

---

## [3.17.0] — 2026-09-16 · Appearance, Everywhere

### Added
- **The tab bar knows which tab it is on.** The selected item now wears its
  domain's accent — Today in Lunar, Train in Ion, Nutrition in Solar, Pulse in
  Tide — and moves with the theme, because every one of those is derived from
  your two colours by hue rotation rather than written down. Settings stays
  neutral: it belongs to no domain, and colouring it would say the tab is about
  one. (`native/Onyx/Features/Shell/RootView.swift`)
- **`AppearanceCoverageTests`**, a sibling to `TokenDisciplineTests`. Every root
  screen must stand on `.onyxScreen` or `.onyxFormBackground`, or be allowlisted
  in the test **with a written reason**. A screen with no ground is a screen with
  no domain mesh, and until now that was invisible in a diff, in a build and in
  a default-theme screenshot alike.
- `Color.onyx.ink(_:)` — the one name for ink that is a fill or a stroke rather
  than type.

### Fixed
- **Widgets follow a theme change.** The four places that read the theme suite
  each wrote `UserDefaults(suiteName:) ?? .standard`, and `.standard` is the
  *calling process's own* domain — so under the fallback the app wrote its theme
  to the app's plist while the extension read the extension's, and a widget
  never saw the change at all. They now go through one accessor,
  `AppDatabase.appGroupDefaults()`, which says what the fallback costs and, in
  DEBUG, prints once when the App Group container is missing instead of failing
  in silence on the device.
- **The widget faces move with the theme.** Roughly a hundred ink reads across
  the eleven tile files and the Live Activity card were spelled `.white` or
  `.black` by hand — the only surfaces in the app that did not resolve through
  `Color.onyx.*`. They now read `textPrimary`, `base` and `ink(_:)`. The
  accessory rendering's `mono ? .white` branch is deliberately left: there the
  white is the rendering mode's ink, not the theme's.
- `OnyxThemeTests` now holds **each shipped preset** to sixteen distinct muscle
  hues, not only the four quarter turns of the rotation.

---

## [3.16.0] — 2026-09-16 · The Dashboard Grows a Face

### Added
- **Day Rings, a twentieth dashboard tile.** Three concentric arcs — the night
  against its goal, the day's movement, the food against its target — a battery
  percentage in the hole, and one sentence underneath. Large only, and it is on
  the grid already: a device that has been carrying its arrangement since Wave 5
  finds it appended at the end rather than in place of anything.
- **The sentence is a rule table, not a model call.** Battery band, training
  load (ACWR), stress band and the sleep-debt bank, read in that order, first
  match wins. It works with the phone in aeroplane mode in a basement, which is
  where an offline gym app has to be able to say "rest day needed". Nineteen
  fixtures pin it, one per branch, including the day a new account has: "Nothing
  is known about today yet."
- **Connected stacks.** Edit Stack has a *Connected* switch. Connected stacks
  share one window: they all turn over on the same beat instead of drifting
  apart, so the grid shows page one of everything and then page two of
  everything. Off by default, and every stack you already have stays as it was.

### Changed
- **Edit mode wobbles properly.** The jiggle was ±0.8° on an ease curve, which
  read as a shimmer from more than arm's length — and since the long press
  started opening a menu instead, the jiggle is the only thing that says which
  mode you are in. It is ±1.2° on a spring now.
- **Edit mode says so without moving, when you have asked it not to move.** With
  Reduce Motion on, every editable tile wears a hairline in its own accent
  instead of wobbling. It used to get the two corner badges and nothing else.

### Fixed
- **The dashboard stops forgetting its arrangement.** The layout was never lost
  — `dashboard_layouts` has been synced both ways all along. It was *overwritten*:
  the grid draws the default arrangement for the fraction of a second before the
  stored one arrives, and a drag made in that window saved the default over the
  real row and pushed it to every other device. An edit before the first read is
  now refused outright; nothing is written and nothing is queued.

---

## [3.15.0] — 2026-09-16 · Train Tells the Truth About the Week

### Fixed
- **The Trends door no longer says you are thirty tonnes down on a Sunday
  morning.** It was subtracting a *full* previous calendar week from however
  much of the current one had happened — two different quantities, with the
  answer presented as a comparison. Both sides now run from the week's own start
  to the same ordinal day, so Wednesday compares three days against three and
  the first morning of a week compares one against one. The rule, its windows
  and every case in which it must say nothing at all now live in `OnyxCore`
  (`WeekPace`) with fourteen tests on them.
- A door with **nothing to compare** shows `—` and says "nothing to compare
  yet", never a signed zero. Zero is the claim that two weeks matched; two weeks
  in which nothing has yet happened have not matched.

### Added
- **On pace.** Under the delta, the Trends door now projects where the week
  lands if the rest of it goes like the part that has: `vs same point last week ·
  on pace 32 t`. The denominator is the training days the plan *asked for* that
  have already passed, not the days you turned up — so a skipped session pulls
  the projection down instead of leaving it flat.
- **Past weeks.** Every closed week behind this one is now a collapsed row at the
  bottom of the Train tab — its date, its sessions and its tonnage — expanding in
  place into the same wrap-up banner the Sunday-night door opens, reel, rings,
  movement breakdown and share card included. Reaching the week before last used
  to mean leaving Train for History, finding the row and opening its chip. A week
  that missed a planned day now summarises too: "is the week finished" is a
  question about the *current* week, and a week that has ended has ended.
- **Customize Train.** A long press anywhere on the tab opens a sheet with a
  switch for each of Library · History · Trends, the Trends door, Cardio, Ready
  to Progress and Past Weeks. The week strip and today's session carry no switch
  — they are what the tab is for. The arrangement is stored in the
  `dashboard_layouts` row you already have, so it syncs across devices with no
  new table and no migration.
- Three screenshot screens: `train-monday` (the morning the old delta lied),
  `train-past` (the tab parked on its closed weeks) and `train-customize`.

### Changed
- The wrap-up's content is now a view of its own (`WeeklyWrapContent`), so the
  sheet and an expanded Past Weeks row draw the same figures from the same
  summary rather than two screens that could drift apart.

---

## [3.14.0] — 2026-09-16 · Cardio and the Banners

### Added
- **The cardio card says when the bout was.** The last bout on the Train tab
  now prints its day and, for a bout Apple Health filed, the clock time it
  actually started at — alongside its duration, distance, pace and average
  heart rate, and an **Automatically logged** badge. A bout typed in by hand
  shows no time, because the column that carries the start on an imported row
  carries the moment of typing on a hand-entered one, and 21:00 is not when the
  walk happened.
- The bout's readings are now the **same four capsules, the same glyphs and the
  same colour** the post-workout ledger draws for the same row, so the two
  screens describing one walk can no longer come to disagree about it.
- Two screenshot screens: `train-cardio`, which parks the tab at the bottom so
  the card is reviewable at an accessibility text size for the first time, and
  `train-pending`, which holds the done card on its stand-in.

### Changed
- **The Zone-2 rail is gone.** A filled bar drawn one line under the last bout's
  average heart rate reads as a heart-rate bar — and it was not one, nor could
  it ever be: the app stores a bout's average heart rate and no zone at all. The
  fraction behind it was sound (bouts this week over twenty minutes, against a
  target of two); drawing it as a gauge there was not. The count survives as a
  caption on the section's own title, where a count of sessions belongs.
- **Both grey session banners joined the app.** The stand-in the Train tab and
  the Pulse day draw while a finished session's masthead loads was a title and a
  line of numbers on plain glass. It is now one shared card wearing the day's
  own wash, the day's own ink and the session's muscle capsules — so it differs
  from the real masthead in what it says (no career number, no plan tags) and
  not in how it looks, and nothing jumps when the read lands.

### Fixed
- **A chip wider than its row was drawn off the edge of the card.** The wrapping
  chip layout measured every chip unconstrained, so one whose ideal width
  exceeded the container was placed at that width and clipped mid-word — its own
  wrapping and scaling rules never consulted. At an accessibility text size the
  bout's **Automatically logged** badge read "Automatically lo" and ran past the
  glass, on the ledger as well as on the Train tab. Chips that already fitted are
  unchanged.

---

## [3.13.0] — 2026-09-16 · The Ledger Stops Shouting

### Added
- **The post-workout ledger finally compares a unilateral set.** A movement
  trained one arm at a time was the only kind on the page carrying no arrow at
  all. It now draws as `L 22 × 10` over `R 22 × 9` under one set badge, with one
  verdict beneath the pair — scored the way every other tonnage in the app is,
  at the weaker side, so the row and the card's own kilogram capsule can never
  disagree about what a pair is worth. A bilateral warm-up on the same card
  keeps its own line and its own verdict.
- **The treadmill card says something.** A bout's card prints its distance, its
  pace, its average heart rate and an **Automatically logged** badge when Apple
  Health filed it — where, before, all five of the strength readings were
  correctly suppressed and nothing took their place, so the card drew an empty
  row. It also names the muscles a walk actually uses, which no surface in the
  app had ever been able to say.
- Two screenshot screens, `session-pairs` and `session-cardio`, and a fixture
  day that is **only** a bout — the one shape that shows a cardio card with no
  lift beside it to lend the page its colour.

### Changed
- **A harder set is no longer good news.** The RPE column painted a rise green,
  like every other column, so three sets that went from an 8 to a 9.5 — the
  textbook picture of accumulated fatigue — read as progress. A rise in effort
  is now red. The arrow still points where the number went; only the verdict
  inverts.
- **Every exercise header is a line shorter.** The muscle chips and the movement's
  readings were two stacked flow rows, so a two-mover lift spent a whole line
  saying "Chest · Triceps" and the numbers began underneath it however much room
  was left. They are one row now — muscles first, the against-last-time verdict
  last, after the evidence it is drawn from.
- A bout's row centres against its set badge instead of hanging from the top of
  a taller row's height.

### Removed
- **Fifteen em-dashes a card.** The line under each reading is still reserved —
  that is what stops a card changing height between two sessions — but it is now
  blank rather than a dash. A page with no previous session to compare against no
  longer says so fifteen times.

---

## [3.12.0] — 2026-09-16 · Four Squares

### Added
- **Pulse: a 2 × 2 square grid** under the carousel — Stress index, Soreness,
  Scale and Stack, side by side. The stress index keeps its number, its band
  word and its fortnight against your own 50; soreness says how much of you is
  sore and opens the body map; **the scale gains a trace it never had room for**
  — the weigh-ins across the whole window, so what you weigh now has a direction
  as well as a value; and the stack shows the day's dose dots — counted, still
  ahead, said no to — beside what has counted so far.
- **Pulse: a shot of a day with two sessions** (`day-two` in the screenshot
  harness). The session cards are the only part of this screen whose count is
  not fixed, and nothing photographed a second one before.

### Changed
- **Pulse reads top to bottom as one argument**: how you are (the Now strip),
  what the night did (the sleep hero and the eight vitals), **what you say**
  (the carousel), **what was measured** (the four squares), and what you did
  (the session cards). The stress index stays below the stress log that feeds
  it, which is why the squares are not in the strip.
- **The carousel is two pages, not three** — Fatigue and the stress log, each
  keeping its verb button. Soreness had spent a whole page restating a list and
  handing you to a sheet; it is now a square that opens the same sheet. Nothing
  about rating a muscle changed: the severity popover has always lived on the
  map itself.
- **A page is ~130 pt instead of 196.** The floor was measured from three cards
  and was 66 pt of empty glass on every one of them; it is now the height the
  content actually needs, and the cap at the accessibility sizes came down with
  it.
- **Logging stress is one screen again.** The five words and the clock share a
  section — they are one act — the tag grid packs four chips to a row instead of
  three, and the note folds behind a disclosure that still shows what you typed.
  Every control keeps its 44 pt.
- At the accessibility sizes the four squares become four rows, the way the
  vitals grid above them already did: half a phone is 171 pt wide, so a square
  of it is 171 pt tall, and four of those stop being a compaction.

### Fixed
- **The screenshot fixture had a supplement skip with no stack behind it.** The
  preview day has written "caffeine: skipped" since the stack tracker shipped
  and never seeded a stack for it to land on, so the write went to a key with no
  dose. Pulse's fixtures now seed the nine-item protocol — and a fortnight of
  weigh-ins, for the same reason: a fixture thin in one column photographs an
  empty square and calls it neutral.
- **Every Pulse screenshot now has one clock.** The due/later split is a
  question about the time of day, so an unpinned fixture counted three doses at
  lunchtime and nine after ten; the committed PNG would have changed by the
  hour.

---

## [3.11.0] — 2026-09-15 · The Night Leads

### Added
- **Pulse · a dynamic hero vital.** The night now leads the vitals block at full
  width — the duration, a 44 pt stage bar, the sleep bank, and the same tap into
  the sleep window it always had. When a vital has gone far enough wrong it takes
  that slot instead and the night drops into the grid, keeping its own door.
  "Far enough wrong" is the readiness engine's own verdict and no new one: a
  seven-day rolling mean against the forty-two days before it, dead-banded at
  half a standard deviation, and it has to cross a full SD in the direction that
  is bad **for that reading** — a resting heart rate above your normal, an HRV
  below it. The dead band is why the lead does not change every morning.

### Changed
- **Pulse · the vitals stop being a horizontal scroller.** Nine chips in a
  sideways strip — about 1,010 pt of content in a 375 pt window, eight of the
  nine reachable only by swiping — are now one lead and eight cells that are all
  on screen at once. Nothing is behind a swipe and nothing is behind a
  disclosure. At accessibility sizes the eight are still rows, and the night is
  still a row you can open.
- **Pulse · the Now strip.** The day's fuel was a right-aligned tail squeezed
  beside two 28 pt numerals, breaking to two lines and truncating first at any
  size above default. It now has its own full-width line. The score keeps the
  screen's one hero numeral and the battery sits at display size beside its own
  ring, which is the rule the type scale has always stated.

### Fixed
- **Pulse · the sleep bank is on the screen again.** The decayed sleep debt and
  the nights behind it were readable nowhere on Pulse after the sleep tile left;
  they are the hero cell's last line.

---

## [3.10.1] — 2026-09-15 · Apple Health Tells The Truth

### Fixed
- **Train · Apple Health import** — a walk imports **once**. Every cardio bout
  now carries `HKWorkout.uuid`, the identity Apple already assigns it, and the
  duplicate rule matches on that before it falls back to guessing from a start
  time. The old rule asked whether a stored row's `created_at` fell within five
  minutes of the incoming bout — a table with no start column, a heuristic, and
  it missed outright whenever `created_at` did not survive the round trip. Every
  sync then re-inserted: one Friday held twenty-three copies of one walk.
- **Train · the bouts already duplicated** — collapsed once, on the same key the
  weekly export has deduped at render time ever since it found them. The row
  kept is the one carrying the most measurements, and the deletions reach the
  server rather than coming back on the next pull. Weekly cardio totals, minutes
  and kilocalories stop being multiplied by however many times the import ran.
- **Train · a bout that crosses midnight** is filed under the day it STARTED in.
  It used to be returned by both days' queries and inserted under each.
- **The "synced from Apple Health" notice** counts only bouts the ledger had
  never seen. A row that merely gained the new key says nothing.
- **Nutrition · the water row** stops reading `— / 3.0 L`. The tab and the
  widget now read one rule (`WaterTruth`): the intake ledger when it has rows,
  the day's flat figure otherwise. They used to read two and could print
  different litres for the same day.
- **Nutrition · "Use Apple Health"** clears the hand-entered figure and nothing
  else. It used to delete the whole day's ledger — Apple's own row and every
  glass tapped on the tab — and blank the column, so the day read as untracked
  until the next successful sync, which on a phone where the water read is
  denied is never.
- **Nutrition · an unmeasured day** says "Waiting for Apple Health" instead of a
  dash, but only inside the window the sync actually scans. An old day with no
  water keeps its dash, because that is true.

### Changed
- `cardio_logs` gains `hk_uuid`. **Paste `docs/sql/w1-hk-uuid.sql`** — until you
  do, an imported bout's upload is rejected for an unknown column and retries in
  the outbox. Nothing is lost while you wait; nothing new reaches the server.

---

## [3.10.0] — 2026-09-15 · The Deck Tells The Truth

A hotfix wave for one Delts & Arms session that crashed, came back on the
dashboard with a stopped clock, and then grew sets nobody performed.

### Fixed
- **Sets you never did no longer appear when a session is reopened.** A
  movement trained one side at a time is two rows per set, and the deck was
  counting the shortfall in rows while spending it in sets — so a Single Arm
  Lateral Raise prescribed four sets, with two logged, reopened showing six.
  The two extra sets were real, tickable rows. Every reopen added them again,
  which is why tapping Edit did it a second time.
- **The treadmill warm-up is drawn once.** Reopening a session that began with
  a walk put the bout at the top of the deck AND at the bottom, both ticked,
  both counted — a session's set total and its "20/21 completed" line both
  inflated by it, and the two cards wrote over each other's set.
- **A workout in progress survives being killed.** Relaunching mid-session used
  to land on Today with no sign of the deck you were holding; the app now opens
  on Train when a workout is actually running.
- **The timer no longer resets to 0:00.** A session the phone terminated while
  the clock was stopped came back claiming hours of rest against a ninety-minute
  workout, and the elapsed reading collapsed to zero. A pause the app never got
  to close is now worth at most fifteen minutes, the ledger can never claim more
  time than has passed, and the deck says so in the header when it has had to
  repair one.
- **The clock survives a termination before your first set.** Open the deck,
  warm up for eleven minutes, get killed — those eleven minutes used to vanish,
  because the start instant only reached storage when the first set was logged.
- **A phase switch on a deck holding two cards for one movement crashed
  outright.** It cannot hold two any more, and a card's identity is no longer
  its name, so a namesake can never take the screen down again.

### Changed
- **Estimated 1RM is Brzycki — `weight × 36 / (37 − reps)`.** It was Epley, and
  Onyx was the only app reporting that number, so a set that read 30.86 kg
  everywhere else read something lower here. Every stored estimate on this
  device is re-derived and the record ledger is replayed against it, so history
  and new sets are judged on the same formula.
- **A hard set below your programmed rep window can win Best 1RM again.** The
  engine refused the estimated-1RM record to any set under the day's rep floor,
  unexplained and invisible: Hammer Curl at 25 kg × 8 took Heaviest and nothing
  else where two records were earned. The bound is now the formula's own — above
  sixteen reps there is no estimate to compare, which is past every window the
  programme prescribes.
- **A split set shows both arms, always.** Left and right each get their own
  line inside one set box, with one checkmark that completes the pair. Loads and
  reps can now differ between arms — before, the only control on the row wrote
  to both sides at once, so there was no way to enter two different weights at
  all.

---

## [3.9.0] — 2026-09-15 · Your Two Colours

### Added
- **Settings → Appearance: pick the two colours the whole app is built from.**
  Six presets — Ion, Ember, Moss, Rose, Gold, Sea — or your own primary and
  secondary through the system colour picker, with a preview of the four ramps
  the app derives from them. Primary is the training accent and also rotates
  body, recovery and all sixteen muscle colours; secondary is nutrition's. Text,
  ground, glass, danger, good and record gold never move. "Reset to Ion" puts
  every colour back exactly as it shipped. Widgets and the Lock Screen card
  recolour on their next refresh; the watch on its next context.
- A colour too dark to read on black, or louder than the muscle palette, is
  pulled back to the nearest one that is not — so no theme can make the app
  unreadable.

### Changed
- **The Smart Stack turns over more easily.** A tile now takes the drag after
  10 pt instead of 16, and commits on a quarter of a face travelled as well as
  on a flick — so a finger that drags a face most of the way, stops to look and
  lets go gets the face it was reaching for instead of the one it started on.
  A drag that is more sideways than vertical is left to the dashboard under it.
- Appearance refuses to change colours while a workout is running, and says so.
  Applying a theme rebuilds every screen, and the live session's clock, rest
  timer and deck position are held in memory.
- The tab you are on now survives a colour change. It did not: picking a theme
  answered you with the dashboard.

### Fixed
- **The water row no longer crashes the app.** One tap on the Nutrition tab, on
  any day that already had an entry, killed the app outright — and never logged
  the glass. The same defect was in the Pulse day's water row. Both are fixed,
  and a test now stands behind them.
- A widget could redraw with the previous palette after a theme change,
  depending on whether its process happened to be running.
- A sideways drag across a stacked tile could still turn it over on release,
  having shown no sign of doing so.
- A colour picked and then left by backgrounding the app is no longer lost.

---

## [3.8.0] — 2026-09-15 · The Day's Three Questions

### Added
- **Pulse asks three questions on a pager.** Fatigue, stress and soreness were
  three tiles stacked down a screen you had to scroll to answer, and the third
  one lived below the fold on every phone. They are three pages of one carousel
  now, each carrying its own control, and the day reads in order: the Now strip,
  the vitals chips, the three questions, the scale and the stack, the stress
  index, then the session you did. The whole day fits a phone.
- **Stress is a log, not a number.** The old Head tile held one reading per slot
  and quietly overwrote it, so a morning you logged at 06:12 disappeared when
  you logged again at 07:40. Every reading is kept: the card draws the day as a
  strip of clock-stamped capsules — the most recent three, with "+N earlier"
  standing where the older ones are — and the full-day sheet carries the tags,
  the notes and a swipe to delete. A reading can be backdated to any minute of
  the day that has already happened. The weekly export prints each one with its
  clock, so two readings in one slot both survive the round trip.
- **A vitals chip row.** The night's sleep and eight readings are one 44 pt
  scroller where a 168 pt sleep tile and an always-open 192 pt grid used to sit.
  Sleep leads it and opens the edit sheet; the rest expand the full grid.
- **Pulse draws `SessionHeaderCard`.** The Pulse door, the Train done card and
  the session page are finally one card — with the career number, the plan and
  phase tags, the clock and the muscles trained. (3.7.0 joined the first two.)

### Changed
- **Pulse prints tonnage the way the rest of the app does.** It alone used the
  formatter that always writes a tenth, so the session Train called "13,005 kg"
  read "13,005.0 kg" one tab over.
- **"Head" is gone from every surface.** The tile is the Stress index, the card
  is the Stress log, and the Quick Log spoke is `stress`.
- **Screenshots are no longer committed.** 220 phone screens had reached
  144 MiB, turned over on every layout edit, and were read by nothing in
  `npm run check`. `scripts/native-shot.sh` still renders any of them offline in
  a couple of minutes; git history keeps every one ever committed.

### Fixed
- **A session card could be stranded on its placeholder for good.** The
  career-wide masthead load was not a cancellation point, so stepping days
  faster than it completed left the card that was mid-flight showing a
  placeholder until the screen was rebuilt.
- **A stress reading begun before a slot boundary saved into the next one.** The
  sheet re-derived "now" on every keystroke, so a reading started at 17:58 under
  "Files under midday" saved as evening.
- **Six accessibility-size defects found in the shot loop** — a truncated verb
  on each carousel page, `"Okay Before t…"` on the fatigue reading, `"Wak… Pre
  Post"` on its slot row, a soreness capsule cut by the card's own edge, a
  carousel that showed page one while its dots said page two, and a chip row
  whose one-row collapse took the night's only door off the screen.

### Removed
- `SleepTile` (280 lines), `FatigueSummaryRow`, `SorenessRow`,
  `WorkoutSummaryCard` and `HeadSheet` — nothing constructs them after the
  reorder. Every part of the sleep tile survives in the edit sheet the night's
  chip opens, or in the chip's own two lines.

---

## [3.7.0] — 2026-09-15 · One Session, One Header

### Added
- **Top Lifts groups by the movement.** A session carried by one lift printed
  that lift's name three times — once as the hardest set, once as the heaviest,
  once as the best estimated single, each at body weight and each telling the
  reader a name they had read on the row above. The movement is a heading now
  and the roles sit under it, with an arrow against the same movement's last
  session and a flame when the set took a record. The three maxima, the tie
  rule and the deltas moved into `TopLifts` (OnyxCore) where they are tested
  against vectors rather than re-derived in a view.
- **One `SessionHeaderCard` for a finished session.** The Train tab's done card
  and the session page's title band were two renderings of one workout that
  disagreed about which facts mattered — and about the day's NAME: Train read
  "Upper A" while the page it opened read "Cb A", because the page resolved the
  label through whichever plan is selected today rather than through the deck
  that owned the session's date. One card now, one loader behind it, and the
  Train card gained the career number, the plan and phase tags, the clock and
  the muscles it trained. (Pulse joins them in the next wave.)

### Changed
- **The Live Stats timeline is coloured by the muscle, not the day.** Every row
  drew the split's one hue, so colour said only "this is a Legs day" — which the
  title two cards up had already said. Each movement's dots now carry the
  landmark colour the Lock Screen, the deck's rail and the body figure use.
- **A finished treadmill bout fills its dot.** The opening bout is logged as a
  warm-up on purpose — it stays out of tonnage, out of the working-set count and
  out of the PR engine — and the timeline's numerator was the working-set count,
  so the one row that could never be filled was the one you had definitely done.
  A cardio-only movement is counted in rows ticked.
- **The Live Stats rest bar and its countdown carry the whole rest.** Both were
  still calling the timer helper without a total, so the bar snapped back to
  full on every +15 s — the same defect 3.6.0 fixed on the Lock Screen, in the
  last two callers.

### Fixed
- **The session page and the Train card name the same session the same way.**
  The label resolves through the session's own deck on both.

---

## [3.6.0] — 2026-09-15 · The Minimised Workout

### Added
- **Mini Player on Train.** A running workout no longer hides behind a "Resume
  workout" button. A 64 pt card above the tab bar carries the session's name and
  its elapsed clock, the movement you are walking to next, and sets, tonnage and
  records — read from the live session rather than re-queried from the ledger,
  so the numbers match the logger exactly. Tapping it zooms into the deck, and
  the logger can now be dragged down to minimise back to it.
- **The Lock Screen and the Dynamic Island say what is next, truthfully.**
  "NEXT" used to be a label in front of the lift you were already doing. It
  names the real next movement in the deck now, on its own line under the
  current one, and only at a movement boundary — so the name and the load under
  it are never two different lifts.
- **Load × reps and RPE on the watch's rest screen**, under the countdown, for
  the set that earned the rest. Both watch screens also carry a session clock.

### Changed
- **The rest bar drains instead of snapping back.** It never had a denominator:
  the range was recomputed from "now" on every redraw, so the fill was
  elapsed-since-render over time-remaining and +15 s sent it back to full. It
  now measures the whole rest, and +15 s moves the fill *down* a little, which
  is what adding time to a rest actually does.
- **The rest timer wears the movement's colour** — the same muscle hue the deck,
  the body figure and the card's own tag are drawn in — rather than the split's,
  which was the same colour for all twenty of a session's rests.
- **The muscle tag moved up beside the session title** on the Lock Screen and
  into the Island's trailing slot, which had been printing the set count that
  the row below it already printed.
- **The watch's rest screen lost its countdown ring.** It was hidden in the
  always-on state and under Reduce Motion — the two states it was most needed
  in — and it was the only thing reading a total that could disagree with the
  clock after a nudge. The digits took the space.

### Fixed
- ±15 s on the watch no longer leaves the rest's stated length behind its own
  countdown.
- The watch's rest screen lays out inside a 40 mm case: the RPE ladder is on
  screen without scrolling, and the set position no longer truncates to
  "Set 1 of".

---


## [3.5.0] — 2026-09-14 · The Engines Under the Live UX Sprint

The first of six waves. On the default theme nothing is recoloured and no
layout changes — this release is the maths and the seams the next waves draw
on. Three small things do move, all forced by the rewiring; they are listed
under Changed.

### Added
- **A theme engine, waiting for its switch.** Every colour the app draws now
  resolves through one runtime theme (`OnyxTheme`): primary and secondary hues,
  with the four domains, the 16 muscle colours, the macro rails, the chart
  series and the day colours derived from them by hue rotation in OKLCH. The
  default theme reproduces today's palette bit for bit. Six presets are
  defined; the Appearance screen that picks one lands in wave 5. Widgets read
  the same spec at launch; the watch receives it with the next context send
  (sign-in, midnight, a plan change).
- **Stress is an event log.** `stress_logs` gains `logged_at`; a day can hold
  any number of entries, each with a time, instead of one per slot. The weekly
  export prints an event as `14:32 3` (older rows keep `evening 3`). The Stress
  index is unchanged: it was already the mean of the day's entries. The founder
  pastes `docs/sql/w1-stress-events.sql` before logging the first event.
- **Holiday** as a one-day context, next to Event, in the day's target sheet.
- **Top Lifts engine** (`TopLifts.group`): one block per movement with its
  Hardest, Heaviest and 1RM, an arrow against the last time you did it, and a
  record flag. The Live Stats screen switches to it in wave 3.
- **Timeline dots engine** (`dotProgress`): a ticked cardio bout counts for its
  dot without ever entering working sets, tonnage or the PR engine.
- **Token discipline is a gate again.** `npm run check` runs the OnyxUI tests
  (`npm run swift:ui`), which fail on any raw colour literal outside the token
  table. The check now needs a bootable iPhone simulator and takes about two
  minutes longer.
- **A rest range with a denominator.** `restCountdown` takes the rest total, so
  a countdown bar can be built as elapsed over total. No surface passes the
  total yet — the Live Activity bar still behaves as in 3.4.0 until wave 2
  wires it.

### Fixed
- **"Next" on the Lock Screen and Dynamic Island names the next movement** —
  only at a movement boundary, so the name and the load under it always agree.
  Between sets of the same movement the card keeps the current lift and its
  set count.

### Changed
- **The Head sheet opens blank and logs a fresh entry** each time it is saved;
  "Clear this reading" became "Remove the last entry" and removes the day's
  latest event. Its summary line counts the slots answered, not the rows. The
  Stress card and sheet are redesigned in wave 4.
- **Holiday** appears in the exception-reason menu of the day's target sheet.
- Wave branches are `onyx/sprint-live-ux-w<N>`; the integration branch is
  `onyx/sprint-live-ux`.

---

## [3.4.0] — 2026-09-14 · The Clock Survives, the Trophy Has to Earn It

### Fixed
- **The session clock survives the app being killed.** iOS suspending and then
  terminating a workout used to bring the deck back with every set restored and
  the timer at zero — forty minutes of training reported as seconds. Rejoining
  a live session now reads the start instant the session row has held all
  along, so the elapsed time, the Live Activity and the recorded duration all
  count from when you actually started. An explicit pause is still the only
  thing taken off the clock; a workout the phone slept through still happened.
- **Phantom records on the Live Logger.** A movement whose history is filed
  under a catalogue id this device had not pulled yet was measured against half
  its own history — a bar low enough to light a trophy the next launch quietly
  took away (a 47.5 kg × 13 seated leg curl reading as 617.5 kg "was 550"). The
  deck now reads `personal_records` as a floor, so the live bar can never sit
  below the record the ledger already holds. The bar can only rise, so this
  removes false trophies and cannot hide a real one.

### Changed
- **Two tags, the same two everywhere.** The Live Logger showed `Cut` and
  `Week 9` while the session's own summary showed `Onyx-5` and `Cut W9` — four
  strings for two facts. Every session surface now carries exactly the plan
  (`Onyx-5`) and the phase with its week (`Cut W9`), read from one place. The
  phase picker moved onto the combined tag rather than disappearing with the
  chip that used to carry it.
- The logger's week is now cut on the athlete's own week-end day. It defaulted
  to Sunday, so anyone on a different week could see a session numbered one week
  on the deck and another on its summary page.

### Added
- **Settings › Training › Warm-up calculator** — off by default. The
  "WARM-UP FROM … KG" line and its ramp-up chips now appear only when it is on,
  and the row reclaims its space when it is off.

---

## [3.3.0] — 2026-09-14 · The Session, Read as a Table

The post-workout summary stops being a list of sentences and becomes a page you
can scan: a masthead that names the session, one row of anatomy, one row of
performance, and a real table under every movement. Plus the badge-centering
defect that had been off by four points in both the live deck and the ledger
since the badge was shared.

### Added
- **Columns.** Every movement's sets are now a table — `KG · REPS · RPE` under
  a heading, three equal tracks, one shape for the whole card. Under each
  reading is a reserved line carrying the change against the SAME SET NUMBER
  the last time the movement was trained: a green or red triangle and the
  amount. A set added this week has no counterpart and says so with a dash
  rather than inventing a verdict.
- **A treadmill reads like a lift.** A bout gets `MIN · KM · PACE` in the same
  table, in the cardio colour. The pace is derived from the distance and the
  duration and is never stored. Incline and total ascent are no longer drawn —
  they describe the bout rather than the set, and VoiceOver still speaks them.
- **The session's ordinal, in the masthead.** `#45` sits at the right-hand end
  of the title row, in the split's own colour — and in record gold, with a soft
  bloom, on any session that set one. Same condition the trophies below it are
  drawn on.
- **The prescription beside the movement.** `@ 10–12` now follows the exercise
  name in that movement's own hue, set one step down and rounded so it reads as
  a brief rather than as part of the name. How much of it landed (`2/3 @ 10–12`)
  stays with the results, where it belongs.

### Changed
- **The page header is three rows and a remark.** Name and session number;
  plan, phase week and lever on the left with the start date and time on the
  right; then the primary muscles. The verdict sentence closes the band under
  them, set as a quiet italic aside rather than as another heading.
- **Muscles are ranked by the work, not by the credit.** The header row sorts on
  the raw count of working sets whose movement names the muscle as a PRIMARY
  mover, with the tonnage behind them breaking the ties — so twelve leg sets
  always precede four core sets, and no muscle climbs the list on work it only
  assisted with. Computed in the loader, off the main actor. The Muscle focus
  card keeps the weighted share it was always right to draw.
- **The exercise header separates anatomy from arithmetic.** The chip row now
  carries muscles and nothing else; the row beneath it carries the whole of the
  performance — the session-on-session percentage, top set, tonnage, RPE and
  the ceiling count.
- **That row is no longer grey.** Each capsule takes the token that already
  means its reading: the verdict and the tonnage take green or red, the top set
  takes the movement's muscle hue, the RPE takes the effort ramp. Glyphs render
  `.hierarchical`, and each capsule is washed in 12 % of its own ink.
- **The `vs 30 Aug` capsule is now `▲ +7%`.** The date was the half of the fact
  a reader could not use thirty seconds after finishing the session.
- **The effort column is a number.** `8.5` in the effort ramp's own colour,
  which is what bought the width for a third track. The word comes back at the
  accessibility sizes, where the rows stop being a table.

### Fixed
- **Set badges were not centred.** `SetBadge` stacked its surface and its
  content `.bottomTrailing` so that the failure pip could reach the corner — but
  a `ZStack`'s alignment applies to every child, and only the surface fills. The
  ordinal, the tick and the trophy were therefore pinned low and right in every
  badge in the app, on the live deck and in the ledger both. The stack is
  centred and the pip has moved to an overlay of its own, where it now carries a
  1 pt ring of the page's base colour so it separates from the badge under it.
- **The rep window clashed on every card.** It was drawn in the domain accent,
  which folds sixteen landmarks onto four hues — so a chest movement's brief
  came out violet beside a red rail, red chips and a red trail. It takes the
  movement's own colour, like the other five surfaces on the card.

---

## [3.2.0] — 2026-09-13 · One Language for a Set

Two waves of UI and mechanics. The live deck and the session page had been
drawing the same objects in two different languages; they speak one now, and
four things that were quietly wrong underneath them are fixed.

### Added
- **The Sunday banner opens the week.** "Week N is complete" on Today now opens
  the Weekly Wrap reel — the same one the Train tab and History open. It used to
  select the Settings tab.
- **A door to every trophy.** Double-tapping a gold set badge in the live logger
  opens the record sheet: which axes it won, and by how much. Attached only to
  rows that hold a record, so every other set keeps an instant tap.
- **The session page says one sentence.** "Heaviest Upper A in 6 weeks", under
  the title, when the session has earned it — silent otherwise.
- **Intensity.** A single bar on the session page, one stop per set in the
  effort ramp: the shape of how hard the session got, from the first set to the
  last.
- **A muscle on the Lock Screen.** The running-workout card and the Dynamic
  Island now name the primary muscle of the set you are on, in that muscle's own
  colour.
- **Pace, derived.** A cardio card computes its own pace from the duration and
  distance actually entered.
- **Weight and reps as columns** in the session ledger, each with a green or red
  arrow against the same set number the last time that movement was trained.

### Changed
- **A record badge is the movement's colour with a gold trophy in it**, on both
  screens, with a soft glow behind the glyph. It used to be solid gold on the
  deck and a grey circle in the ledger.
- **The session ledger draws the deck's badge.** Same shape, same states, same
  hue — `SetBadge` is now the only place a set's box is drawn.
- **Header metrics are colour-coded and carry SF Symbols** — a flame on
  calories, a red heart on average HR, a trophy on records, an arrow on volume,
  the effort ramp on difficulty.
- **Only primary muscles in the session header.** The assisting ones stay on the
  movement cards, where they carry a share; as flat capsules in the header they
  made a chest day look like a six-muscle day.
- **Per-exercise trails are the movement's own hue and curve** (Catmull-Rom)
  rather than a four-colour domain accent and a polyline.
- **Pulse carries the day's muscles**: a wash at the top of the screen that
  fades as you scroll, and a session card washed in the muscles it trained
  rather than in the split's colour.
- **Cardio is an ordinary movement.** No `W` badge, no lift-only tags, no rep
  window, and a colour of its own instead of the day's accent on one screen and
  Core's lavender on the other.
- The lock-screen and Dynamic Island **sparkline is gone**; the exercise name is
  the headline, with the load and the rating under it.

### Fixed
- **Sets no longer jump by 2** on unilateral movements after a session is
  reopened. The pair's two rows were folded only under the local spelling of a
  side, so a restored `L`/`R` drew one set as two — and weighed the arm twice.
- **A weight hold steps by 1.25 kg.** It took the 2.5 kg tap step and then
  ramped; it now hands that plate back the moment the hold engages, with a
  haptic at the swap and one per tick.
- **PRs show up live.** The bar the live deck measured against was built before
  the session's own rows were read, so a movement whose catalogue row the deck
  could not resolve was measured against nothing — and nothing is never a
  record. The trophies matched the summary page's afterwards; they match it
  during the workout now.
- The founder's hardcoded treadmill note ("Pace rising 4.3 to 5.0") is gone from
  every deck.

---

## [3.1.0] — 2026-09-13 · The Export Answers to the Audit

The weekly export is rebuilt from the ground up for the coaching audit that
reads it. **The document format is replaced wholesale** — nothing that parsed
export v4 will parse v5. There is no data migration; every past week re-renders
in the new shape from the rows it already had.

### Changed
- **History → Export week** now writes **export v5**: seven fixed sections —
  `WEEK`, `WEEK AGGREGATES`, `BODY COMPOSITION`, `DAILY ROWS`, `SESSIONS`,
  `SETS BY MUSCLE`, `ANOMALIES` — and nothing between them. A field with nothing
  behind it prints nothing at all rather than a dash, except the handful where
  the absence is itself the finding. A normal week is about 120 lines, down
  from roughly 700.
- Gone with v4: the legend, the four standing closing notes, the per-day
  `Not recorded:` line, the energy-balance paragraph, the micronutrient and
  stack sections, and every prose sentence. The audit writes the prose now.
- **No Score and no Battery figures anywhere.** Both were this app's opinion of
  the week; the audit forms its own, and a test bans the words.
- **Body composition** no longer compares the week's first weigh-in to its last
  — that read `61.7 → 61.7 (+0.00)` for a week that moved. It reports the
  **trailing-four weigh-in mean** and the sample centre that says which part of
  the week those four came from.
- A scan whose bone mass sits more than 0.10 kg, or whose body water sits more
  than 0.6 kg, from the fortnight's median is printed **ANOMALOUS** and excluded
  from every mean.
- **Sessions** print in the order the movements were **performed**, taken from
  the set event log, rather than in deck order. Where the log cannot answer —
  a session pulled from another device, or one whose log was back-filled by an
  edit — the fallback is named in `ANOMALIES` rather than presented as a record.
- **Sets by muscle** is graded the way `VolumeZone` has always stated it: a
  muscle is UNDER only if even its total, assistance included, falls short, and
  only DIRECT work can earn an OVER. A muscle that reached its number purely by
  assisting other movements no longer reads OVER.
- `nights_deep_ge_60` carries the nights that measured deep sleep as its
  denominator — 4 of 7 and 4 of 4 are different weeks.

### Fixed
- **Every timestamp is the phone's own wall clock.** Bed and wake times, session
  starts and ends and cardio starts were all rendered in UTC — a 19:00 session
  read 16:00, and a night in Asia/Jerusalem read three hours early.
- **Session start and end are the first and last set**, from the event log, not
  when the logger screen was opened and the finish button tapped. A workout
  performed at 19:00 exported as 10:46–17:12.
- **Sets to failure** are counted from set-level **RPE 10** as well as the
  failure tick. A session with six sets rated 10 reported `0`, directly above
  the list of them. A unilateral pair is examined per side and counted once.
- **Duplicate cardio** is removed on start, duration and distance — one walk had
  been importing as 23 rows on a Friday and 8 on a Saturday, multiplying the
  week's bouts, minutes and calories.
- **Sleep duration** falls back to the sleep session's own figure and then to
  deep + REM + core when `daily_logs` carries none. Most nights had none, so the
  week's average was a mean of one night.
- **Treadmill warm-ups** carry their duration, distance, incline and a derived
  speed instead of rendering as `W 0 reps`. The export's own set query had never
  selected the four cardio columns, all of which are `Optional`, so the omission
  was silent.
- **The supplement stack's micronutrients** — vitamin C, B12, D and magnesium —
  are credited again. A `custom_supplements.micros` payload that was present but
  empty short-circuited the fallback table, and the item silently credited
  nothing; the two are merged now, per micronutrient.
- **HRV readings** are run through `VitalsGate` — the same gate every ingest path
  already used — and a doubted night is named, excluded from a second mean, and
  listed in `ANOMALIES`.
- **The lever line carries a 1,935 kcal baseline.** The ladder has no rungs to
  answer with (nothing writes `target_profiles.kind`, so every profile resolves
  to `Custom`), and a daily target with no anchor behind it cannot be read as a
  deficit.
- A micronutrient the week doubted on **every** day still has a row, reading
  `no plausible reading (0 of 7 d)`. Dropping it made a week of implausible
  calcium read exactly like a week where calcium was never logged at all.
- A micronutrient the food source never reported on a day with food logged is
  named in `ANOMALIES`, so a gap in what MyFitnessPal wrote to Apple Health no
  longer reads as a low intake. There is no food database in Onyx to fix — every
  food micronutrient arrives as a daily total from Apple Health.

---

## [3.0.0] — 2026-09-13 · The Web App Is Gone

Onyx is one app now. The predecessor web app — the Next.js dashboard, logger and
PWA that Onyx grew up beside and shared a database with — is retired, along
with the Capacitor shell that wrapped it, the old watch app inside that shell,
the Playwright and Vitest suites that tested it, and every web build config.
Nothing the phone does changed; what changed is that nothing else is running.

MAJOR because a surface was removed: anyone still opening the web dashboard
gets a two-page static site instead. Its data is untouched — every row it wrote
is in the same Supabase the phone reads.

### Removed

- **The web app** (`src/`, 600 files), the Capacitor iOS shell (`ios/`), the
  PWA assets (`public/`), the end-to-end suite (`e2e/`), the Netlify keep-alive
  function, and ten web build configs. The web-only maintenance scripts that
  imported from `src/` (`backfill-prs`, `backfill-notion-sets`,
  `backfill-supplement-log`, `rebuild-routine-templates`, `seed-demo-account`,
  `sync-pr-truth`, `reseed-muscle-groups`) went with it — they cannot run
  without the modules they imported. All of it is in git history before this
  commit.
- **The completed migration plans** (`NATIVE_MIGRATION_PLAN`,
  `NATIVE_PHASE_2_PLAN`, `PHASE_2_POLISH_PLAN`, `PHASE_3_PLAN`) — done, and
  written in the vocabulary of the app they retired.
- `package.json` shrinks from 25 dependencies + 23 dev to six dev
  dependencies: `vite`, `micromark` and `micromark-extension-gfm` (the report
  renderer bundle), `typescript` (the generator sources are still typechecked,
  `npm run check:types`), `sharp` (icons) and `@supabase/supabase-js` (the
  service-role scripts). The package is named `onyx`.
- **The Supabase keep-alive is gone with the Netlify function that ran it.**
  Daily use of the phone makes the same calls; a week without opening the app
  can let the free-tier project pause, after which the next sign-in fails until
  it is resumed in the Supabase dashboard. If that bites, a Supabase cron or a
  scheduled GitHub Action is the ten-line replacement.
- `scripts/recompute-scores.mjs` — it POSTed to the web app's compute-score
  route. The phone's rescore cascade owns re-scoring now.

### Changed

- **The Netlify site is static.** `site/` holds the privacy policy, the
  support page and the Apple App Site Association file; `netlify.toml`
  publishes it with no build command. The AASA file now names only the native
  App ID. Settings → About links the same two pages at the same domain, with a
  trailing slash.
- **The generators read `scripts/src/`.** The body atlas, the soreness
  vocabularies and the report renderer's TypeScript moved out of the web tree
  into `scripts/src/{atlas,soreness,subRegions}.ts` and
  `scripts/src/report/*`; `npm run atlas`, `doms` and `report:bundle` produce
  byte-identical Swift and a re-bundled `ReportRenderer.html` from there.
  `sync-version.mjs` writes only `native/project.yml` now.
- **`npm run check`** is the version check, a `tsc` pass over `scripts/src/`,
  and the three generator checks. There is no lint step because there is no
  TypeScript app to lint; the Swift gates
  (`check:swift`, `swift:core`, `swift:data`, the `xcodebuild` line) are
  unchanged.
- **Native comments no longer point at `src/`.** Every "a port of
  `src/lib/…`" note now reads "a port of the web app's `lib/…`", and
  `native/README.md` says where those files went. The remaining predecessor
  strings are load-bearing data, not branding: the era wire value, the
  schema tag, the legacy App Group and sqlite names the
  one-time store move reads, the preference fallbacks, and the
  founder's plan and era labels in the golden fixtures.

### One movement, one id

- **The logger writes the catalogue's id.** A set logged on the phone used to
  carry the predecessor's `<brand>5-<name-slug>` stamp while the same movement pulled from the server
  carried the catalogue's uuid — one movement under two identities, which the
  session summary drew twice, the volume fold split, and a PR could be
  measured against half of. `storedId` now resolves the local catalogue by
  canonical name; the commit path alone
  (`storedIdCreatingCatalogueRow`) may create the row when nothing answers.
  Opening a screen never mints one. Two refusals guard it: an EMPTY catalogue
  is treated as "not pulled yet" rather than "new movement", because minting
  there would queue rows the server already holds under other ids and
  `UNIQUE (user_id, name)` would reject them on every retry; and a name two
  rows answer to is left to the slug, which `ExerciseIndex` refuses out loud
  at push time instead of being guessed at silently.
- **The watch resolves but never mints**, and `#if !os(watchOS)` now makes
  breaking that a compile error rather than a code review. Its store is its
  own, so a row created there would carry an id no other client had seen. It
  writes the routine payload's id when there is one and the legacy slug
  otherwise, which `ExerciseIndex` has resolved at push time since W2.
- **`v23.catalogueIds` remaps the event log, then the projection.**
  `workout_sets` is a projection of `set_events`, and `reproject` rebuilds it
  from the append bodies — so a migration that touched only the table would be
  undone by the first edit to a session, and half-undone at that: the deck
  would already hold the migrated id while the fold restored the rest under
  the old one. Both are remapped, with one map, built only from slugs exactly
  one catalogue row answers for. A slug two rows share is left alone —
  `Crunch Machine` and `Crunch (Machine)` slug identically and disagree about
  `is_bodyweight`. A slug that answers to nothing keeps its id: it is still a
  logged rep. Personal records are untouched either way — the ledger keys on
  the movement's name, on both sides of the wire.

### Removed, second pass

- **`docs/sql/`** — fifteen applied migrations. The live database is the
  schema of record and `native/schema/supabase.json` is what the mirror
  generator reads; the DDL is in git history. The fifteen Swift comments that
  cited a file by path now cite it by name.
- **Six service-role scripts** (`backfill-treadmill-sets`, `repair-calcium`,
  `repair-sep-2026-data`, `split-exercise-by-day`, `merge-exercise`,
  `reconcile-pr-counts`) — one-off fixes, already run.
- `docs/UX_WEEKLY_NUTRITION_WIDGETS_PLAN.md`, `docs/SECURITY_SWEEP_2026-09.md`,
  `docs/superpowers/`, `design-system/`. `READINESS_MODEL.md` and
  `STRESS_MODEL.md` stay — they are the stated model behind `Readiness`,
  `Stress` and `Battery`.

### Changed, second pass

- **The Netlify site is `onyx-health-fitness.netlify.app`.** `OnyxLinks.host`,
  both App Store URLs and the AASA all follow it. The old host dies with the
  rename.
- **`README.md` is rewritten** for the App Store: the pitch, the Train /
  Recover / Fuel philosophy, an architecture diagram, the offline-first and
  two-client stories, the HealthKit read-write split, and getting-started
  paths for an athlete and for a developer.

---

## [2.7.0] — 2026-09-12 · Stacking, Said Out Loud

Tiles on the Today grid have always been stackable — two same-size widgets
sharing one square, turning over every nine seconds like a Smart Stack. Almost
nobody found out, because the only way in was to long-press into edit mode, drag
a tile onto a same-size neighbour, hold there for six hundred milliseconds and
let go. Five hundred milliseconds got you a move instead, silently, and the only
thing on screen that ever mentioned any of it was a two-point border.

A long press now opens a menu that uses the words. And the carousel behind it
was rebuilt: it owns its gesture instead of borrowing a `TabView` turned on its
side, so swiping a stack no longer fights the dashboard it sits on.

### Added

- **A long-press menu on every tile** (Today). *Stack With* — or *Add to Stack*
  once there is one — lists the tiles this one can absorb, each named by the
  face it is currently showing. *Unstack Sleep* names the face that is up rather
  than asking you to know the word "face". *Edit Stack* reaches the reordering
  sheet, which until now could only be opened from inside the jiggle. *Edit
  Dashboard* is the old long-press, now a row with a name on it.
  The drag-and-hold still works; it is no longer the only door.
- **A row that says why, when there is no partner.** A tile with nothing its own
  size shows *No Same-Size Widget to Stack With*, greyed. A feature that vanishes
  when it is unavailable is one nobody learns exists.
- **VoiceOver can work a stack.** The tile announces the face that is up and then
  its depth — "Vitals. Stack of 2." — instead of reading every face with nothing
  to say which is on screen. *Next widget in stack*, *Unstack*, *Edit Stack* and
  each stacking target are rotor actions.

### Changed

- **The stack is a carousel now, not a rotated `TabView`.** It tracks the finger
  one-to-one, resists past the first and last face, and lands where the throw
  was going rather than where the finger stopped.
- **The page dots are on the tile.** Under the rotated `TabView` the rail was
  aligned in the rotated view's coordinate space and did not appear on a large
  tile at all. It rides in the tile's own padding gutter, clear of the numbers.

### Fixed

- **Swiping a stack no longer scrolls the dashboard with it** (Today). Both page
  vertically, and the nested `TabView` gave no way to tell them apart. The
  carousel takes the drag only past sixteen points of vertical travel — short
  drags still scroll the screen — and holds the screen still for the rest of it.
- **A stack coming back from the background rotates within nine seconds**, not
  nine plus up to seven more. The clock was a countdown that restarted whenever
  the stack paused — every trip to the background, every visit to edit mode. The
  beats are now read off the wall clock, so a stack rejoins the rhythm it would
  have been on had it never stopped, and the grid stays spread out instead of
  every stack re-phasing onto the moment you unlocked the phone.
- **Reordering a stack no longer changes what it is showing.** Faces were
  identified by position while a stack may legitimately hold the same widget
  twice; sorting them in the Edit Stack sheet left the tile pointing at a
  position that now held something else.
- **Unstacking lifts the face it named.** On a stack the web made from a mix of
  widgets the phone can and cannot draw, the menu's index and the stored index
  were two different things — so it removed the wrong face, or appeared to do
  nothing at all.
- **A tile being dragged onto a stack brightens in the colour of the face that
  is up**, not the colour of the first face in the slot.
- **A tile that stops being a stack forgets which face was up**, so stacking
  something onto it later opens on the top face rather than on whatever index
  the old stack left behind.

### Notes

- `today.png` and the `today-sheet-*` screenshots photograph a stack that is
  genuinely rotating, so the stacked tile may show either of its faces from run
  to run. That is the subject moving, not the layout changing.
- The four behaviours this wave is judged on — a stack made from a long press, a
  swipe that pages without scrolling, a resume that rotates on time, and a
  reorder that holds its face — are covered by unit tests and a build, but were
  not driven by hand on a device: this machine has no way to send touches to the
  Simulator. They need one pass on hardware before the wave is called done.

## [2.6.0] — 2026-09-12 · The Week, In Colour

The week detail was black on black. Eight small numbers, seven grey rows, and
the only colour on the screen was an 8 × 8 pt dot — while a 16-hue muscle
palette and a five-colour split palette sat in the design system, unused by this
screen. It now opens with the four figures a week is actually opened for, every
day you trained wears its own split's colour, and the actions are chips instead
of list rows.

And the wrap-up stopped expiring. A week that closed a month ago opens the same
highlight reel the Train tab shows on the Sunday night — the screen is a
permanent door to it rather than a notification you had to catch.

### Added

- **A hero on the week detail.** Tonnage as the screen's one 28 pt figure, then
  average bodyweight, training strain and the fat delta beneath it. The existing
  eight-cell register is unchanged underneath: the hero answers "what was this
  week", the register is still there to be scanned.
- **Weekly training load, from the battery's own series.** Foster's weekly
  strain with the acute:chronic ratio as its sub-caption — one cell, two
  figures, the way tonnage already carries its delta. Read through
  `Readiness.loadSignal`, the public path, against the same 49-day series the
  battery is scored from, so the two cannot disagree.
- **The week's mean bodyweight**, which existed nowhere before — in Swift or in
  the web app. The delta beside it says which way; the mean says where.
- **Every logged day wears its split's colour.** The house muscle wash, on the
  row rather than in it, so the tint spans the whole row including the chevron.
  A rest day, a missed day and a day from a routine this build does not know all
  get no wash — a grey rail says nothing, and on a logged day it would be a lie.
- **A wrap door on any week that wrapped** (founder decision 8). The chip opens
  the same detent sheet the Train tab opens, built from that week's own rows.
- **Three new screenshot fixtures**: a week that wrapped, a live week with the
  export locked, and the wrap door open on a three-week-old week.

### Changed

- **The week's actions are a chip row**, not `LabeledContent` rows in a list
  section. Report · Wrapped · Export, under the hero.
- **The locked export states its own date.** On a running week the chip stays,
  wears a lock, reads `Export opens Sun 13 Sept` and refuses the tap. A control
  that vanishes reads as a bug; the answer to "where did the button go" is a
  date, so the control carries it.
- **`OnyxChip` gained a disabled state** — outline without fill, full-strength
  label. Greying the label would have said "broken"; this says "not yet".
- **`OnyxChipRow.face(_:)` is public**, so the one control in the row that
  cannot be a `Button` — a `ShareLink`, which is a view and needs its item up
  front — wears the row's real capsule instead of a copy that drifts.
- **`WorkoutWeek.wrap` is callable for any week**, through one entry point that
  assembles its arguments. Its body was already week-agnostic; only the
  assembly and its visibility were not. The Train tab's own path is untouched.

### Fixed

- **The wrap's two "best" cells could never stack.** W1a used `ViewThatFits`
  over cells that declare `.frame(maxWidth: .infinity)`, which tells the
  container the row fits any width — so it took the horizontal branch at every
  size including AX5, and the stacked branch was dead code no screenshot could
  reach. It asks the type size now, like every other collapse in the app.
- **A live week no longer fabricates a detraining signal.** The load series is
  clamped to today rather than run to the week's future end, where days that
  have not happened would have entered as real zeros and decayed the acute side
  of the ratio. The hero says so, on the live week only, in one line.

## [2.5.0] — 2026-09-12 · Five Seconds Of The Week

The Week Wrapped screen used to be a document: a navigation push carrying every
movement of the week, one row each, thirty rows on a full week. Nobody reads a
document on the evening they finished the work it describes. It is a sheet now,
and the first thing in it is a reel you can read before the phone goes back in
your pocket. Nothing was deleted — the document is one drag and one tap away.

### Added
- **Where the work went** — the Week Wrapped sheet draws the week's weighted
  sets as a ring of eight muscle families, and names any family that got nothing
  rather than drawing it as an invisible sliver. Dragging the sheet up breaks it
  out into all sixteen landmarks with their set counts. The numbers come from
  the same accumulator the Today tile, the muscle focus sheet and the Trends
  atlas already share, so all four surfaces count a week the same way.
- **Best e1RM, beside the heaviest set.** They are different questions and the
  answers diverge constantly — 80 kg for four is the heaviest set of a week
  whose best estimated max came off 70 for fifteen. The reel prints both, under
  labels that say which is a fact and which is an inference.
- **The biggest session of the week**, under the ring, by the same volume rule
  the week's own tonnage uses — every non-ghost set, warm-ups included.
- **"Show all 16 muscles"** under the ring. The legend is otherwise behind a
  drag, and a drag is not a gesture VoiceOver or Switch Control can perform.

### Changed
- **Week Wrapped opens as a bottom sheet, not a screen.** The tile on the Train
  tab is still the door and still permanent; tapping it now lifts a sheet to
  560 pt with the tab visible behind it, instead of replacing the tab and
  charging a back tap to leave. Drag up for the full breakdown.
- **The three movement lists moved below the fold**, into one disclosure that
  says how many rows it is holding. The top of the sheet is the Top 3
  progressions; the disclosure carries every movement of the week, including
  the ones that simply held — which the old screen never showed at all.
- The share card is now rendered when you scroll to it rather than when the
  sheet opens, and is not re-rendered on every re-open.

### Fixed
- The Week Wrapped stat row broke `SESSIONS` across three lines and printed the
  week's tonnage as `42,…` at the largest accessibility size. It collapses to
  one column now, the way the History week's vitals row already did.
- `WeeklyMuscleRing`'s arc arithmetic crashed rather than failed when called off
  the main actor: conforming to `View` infers `@MainActor` onto a type's static
  constants too, and reading them from a `map` closure trips Swift 6's isolation
  check. The geometry is `nonisolated`, where it always belonged.

---

## [2.4.0] — 2026-09-12 · What Actually Happened

An audit of the Week 7 export found the document confidently stating things the
database did not say. Exercises came out in the wrong order. A supplement the
wearer had explicitly refused was reported as taken. Every lifting session
claimed no heart rate and no calories beside a day whose activity ring was full.
None of it was a rendering bug: the renderer printed exactly what it was handed,
and what it was handed was assembled wrong.

### Fixed
- **Exercises are printed in the order they were performed.** The native builder
  never read `workout_sets.exercise_order` — it grouped by first appearance in
  `fold_order`, which for a session pulled from the server is the *puller's*
  arrival order. Upper A exported with Face Pull first and Chest Press last.
  `SessionHistoryStore` was fixed for this in §U4.5; the export was the last
  reader still grouping the wrong way. A session with no index falls back to
  logged sequence and now SAYS so — `*(order: logged sequence)*` — rather than
  presenting a guess as a record. The web had the same defect from the other
  end: `(exercise_order ?? 0)` collapsed to a single key on legacy rows and
  interleaved every exercise's first set. (`WeeklyExportBuilder.swift`,
  `useWeeklyLoop.ts`)
- **A skipped dose can no longer vanish.** Both builders wrote
  `scheduled.filter(i => skipped.has(i.key))` — filtering the wearer's own
  answer through a projection of today's protocol. When the two drift, which a
  day swapped Train↔Rest or an item archived mid-week guarantees, the evidence
  was deleted rather than reported. That is how Friday 2026-09-04 exported as
  *9 of 9 — skipped: none logged* after L-Citrulline was declined. A refusal
  the day's schedule does not name is now printed under its own label.
- **Session heart rate and calories are read instead of nulled.**
  `WeeklyExportBuilder` hardcoded `avgBpm` and `caloriesBurned` to null on the
  reasoning that the columns are "not mirrored". True of the pull; irrelevant
  here — `HealthSync.syncSessionMetrics` writes both on this device from the
  overlapping `HKWorkout`, and has since Phase 3.
- **`archived_at` is honoured.** `Supplements.active(_:on:)` and its TS twin
  `activeOn` existed and were called by neither builder, so an item archived on
  Wednesday stayed "scheduled" — and "taken" — through Saturday.
- **A night the watch missed keeps its self-reported flags.** Both sleep toggles
  live inside the Sleep row, which was gated on a duration existing, so ticking
  *trouble falling asleep* on a night with no HealthKit data erased it.
- **A retroactive edit reaches the document.** `['weekly_export']` hung off four
  tables out of a dozen, so logging water or correcting a weigh-in for an
  earlier day invalidated nothing and `staleTime: 60_000` served stale markdown.
  Natively, the `.md` file was rebuilt only when a rescore cascade bumped
  `rescoreGeneration` — so a supplement tick, a cardio bout or a sync pull left
  the previous file in the temporary directory to be shared again.

### Added
- **Measured rest.** `workout_sets.actual_rest_sec` — the elapsed gap between
  committing one set and the next of the same movement, written by the native
  logger. The plan could always say what you were aiming for; it could never say
  whether you held it. A block prescribed at 135 s and trained at 90 s is a
  different block. Renders as `rest 135 s plan (avg 141 s actual)`, and as the
  plan alone wherever nothing was measured. NOT the rest timer, which is a
  countdown you can skip; and not the dead `rest_sec`, whose name still carries
  the old semantics. Local-first: `docs/sql/actual-rest.sql` is the Postgres
  half and the push waits on it, so a workout cannot fail to sync over a column
  the server has not grown yet.
- **Muscle tags on every session.** `Session #41 · Legs & Core A · [Quads,
  Calves, Abs/core, *Hamstrings*, *Glutes*]` — direct work upright, indirect in
  italics, because a bench press *trains* chest and *involves* triceps. Resolved
  in the builders so `exercises.muscle_groups` overrides are honoured, and
  repeated once at the top as a `**Sessions**` index, so the shape of the week
  is legible before descending into any day.
- **An implausible reading names the app that wrote it.** HealthKit dietary
  queries now ask for `.separateBySource` in the same pass that computes the
  total, and the ingest records the split beside the figure. Calcium arriving at
  ~3,100 mg could be doubted but never traced, because `nutrition_entries`
  stores a daily aggregate with no item breakdown. Future spikes read
  `Calcium ⚠ 3,074 / 1,000 mg — implausible, mostly from <app> (3,100)`.

### Changed
- **"Head" is now "Stress".** The row is the Pulse Head control, but the
  document is read by people who never saw that screen.
- **The stack is three lines, not one.** The count, what was taken and what was
  skipped each get a row, and the skipped row says which kind of refusal each
  was — `(planned)` or `(not scheduled this day — logged anyway)`. The count
  states the real four states: `7 of 9 scheduled · 1 still ahead · 1 skipped`.
- **An implausible day is excluded from the weekly average.** It used to be
  flagged AND counted, so the week's calcium mean read 2,012 mg against a
  1,000 mg target — a figure produced almost entirely by days the same document
  says not to believe. The Days column states the exclusion: `4 of 6 ⚠`.
- **Sleep onset prints only when it is true.** `?? false` rendered "fell asleep
  easily" for every night nobody was asked about.

### Removed
- **The week-over-week table and the "vs the previous week" paragraph.** Both
  were correct; `trendLedger` and its vectors are deleted with them. This
  document has one consumer — a person pasting a week into a chat window — and a
  comparison table invites every reading of that week to be a reading of the
  trend instead. A −40 % volume line at the top of a deload reads as a collapse;
  the same week read alone reads as the deload it was planned to be. The ledger
  stays on the payload: `derived.ts` needs the previous week for the energy
  balance, which is a calculation and not a table. Four tables became three.

---

## [2.3.0] — 2026-09-12 · The Week, Written Down

The weekly export stops being a payload and becomes a document. The native
**Export week** button shared a `JSONEncoder` dump; the web's **Copy raw data**
shared markdown that read like a spreadsheet — `## DAYS` was forty columns
joined by ` · `, one line per day, and answering "what happened on Monday" meant
visiting four sections and counting dots. Both are now the same day-major
document, byte for byte, in both languages.

### Added
- **The week is written day by day.** Everything Onyx knows about Monday sits
  under `## DAY 2 · Mon · 2026-08-31` — sleep, vitals, body, readiness, head,
  intake, micronutrients, the stack, activity, the shape it was given, its
  sessions, its cardio, and the figures Onyx computed from it. One place per
  day. (`src/lib/reports/weeklyExport.ts`, `OnyxCore/Reports/WeeklyExport.swift`)
- **Sets you can read.** `` `S1` 75 kg × 12 @ 8.5 Hard `` rather than
  `75×12@8.5` — the effort carries its word from the logger's own ladder, and a
  unilateral pair states what it scored: `L 5 kg × 15 · R 5 kg × 17 → scores
  5 kg × 15`.
- **The Head row reaches a report for the first time.** `stress_logs` shipped
  with the Pulse Head row and was read by nothing. Every day now names its slot,
  its level with the word, what it was about and the note:
  `morning 2 Okay · evening 4 Strained — work, money`. The web gained the same
  reader, so both surfaces render the same week. (`src/lib/recovery/psychStress.ts`)
- **Four tables, each a real grid** — the programme ledger, sets by muscle vs
  target, body composition, and the weekly micronutrient average against every
  target. Everything else stays prose, because a markdown table collapses into
  one paragraph in Apple Notes.
- **The four closing notes are back**, verbatim and last: the unilateral scoring
  rule, the Epley estimate, the Apple Watch caveat, and the Week 7 reference.
  Above them, a legend that explains every convention the document uses.
- **The native app shares a real file.** `onyx-week-2026-08-30.md` reaches Files,
  Mail and Notes with a name, rather than arriving as loose text.
  (`native/Onyx/Features/History/WeekDaysView.swift`)

### Changed
- **A gap is named, never a blank.** A missing reading says `no data`, an empty
  list says `none`, a skipped weigh-in says the reason the protocol recorded
  (`no weigh-in — As Planned`). A row states what it has and names the rest
  after `— not measured:`; a row with nothing at all is dropped and listed in
  that day's closing `Not recorded:` line, so a blank Saturday costs one line
  instead of twelve that all say the same thing.
- **Computed figures are labelled where they sit.** v3 kept a document-level
  fence with every derived figure below it. A day-major document has no fence,
  so the marker travels with the number: `**Derived** *(computed by Onyx, not
  measured)*`, and the energy balance says it is an estimate on its own line.
- **A day's micronutrients print the exceptions only** — a floor missed, a
  ceiling exceeded, a reading the document doubts. The full picture moved to the
  weekly table, which is where an average belongs.
- **Supplements are named, not keyed.** A day's taken list said `d3k2@07:00`; it
  now says `Vitamin D3 + K2 07:00`. An item the protocol no longer names still
  appears, under its key.
- **Session counts are read off the rows the document prints**, not off the
  stored `set_count`. Where the two disagreed the document stated one total and
  then showed another.

### Fixed
- **A session dated outside the week's day rows no longer vanishes.** Nesting
  sessions under days created a way to drop a whole workout that the old flat
  section could not have; stranded work is printed under its own date and
  counted in every total.
- **A note keeps its own punctuation.** `;` and `:` were stripped because the
  token grammar reserved them, so "barely slept; deadline" reached the document
  as "barely slept deadline".
- **The stand ring, the bed and wake times, and a hand-typed cardio start** all
  read as what they are rather than as raw column values.

### Removed
- `weekJson.ts` / `WeekJson.swift` — the machine-readable half. It was fully
  written, documented and tested, and called by nothing: this export has one
  consumer and it is a person pasting into a chat window.
- v3's token grammar. `line.split(' · ')` is no longer a complete parser, and
  `export-recoverable.test.ts` now proves the obligation underneath it instead:
  every set that went in comes back out of the document alone.

---

## [2.2.0] — 2026-09-12 · The Week Bends, The Bout Arrives By Itself

### Added
- **Move a whole week without touching the plan.** Tapping "This week" on Train
  opens all seven days at once — reassign any of them, take a rest day, and
  next week goes back to normal. Every consequence is stated before you
  confirm: what changes, what goes back to the plan, and which session has been
  left with nowhere to go. A day you have already logged says so and cannot be
  moved. (`WeekOverrideSheet`)
- **Cardio arrives on its own.** Walks, runs, rides, rows, elliptical and HIIT
  are read out of Apple Health on every sync and filed without you opening
  anything — with their start time, heart rate, ascent and total energy. Train
  and Pulse say briefly what landed. Nothing you typed is ever overwritten: an
  import only ever fills a blank. (`HealthSync.syncCardioBouts`)
- **The week, wrapped.** When the last planned session of the week is logged —
  Friday, if that is when your plan finishes — the This-week tile becomes a
  summary: sessions, tonnage and its change, PRs, the heaviest set you lifted,
  and every movement that progressed or regressed against the same split last
  week. A deload week says so and relabels its drops rather than filing them in
  red. Shareable as a card, with bodyweight off unless you ask for it.
  (`WeeklyWrapView`)
- **The Pulse body now draws two things at once.** The fill is what the ledger
  implies you are still carrying, muscle by muscle, decaying at a rate that
  differs between a quad and a side delt. The ring over it is what you reported.
  A muscle filled with no ring is loaded and not complaining; a ring with no
  fill is complaining about work the ledger has no record of. (`MuscleRecovery`)
- **Warm-up rungs in the Live Logger.** A row of chips under every loaded
  movement — 40% · 15, 50% · 20, 75% · 30 — each one a tap that adds that set,
  rounded to the increment the weight in front of you is already using. Build
  the ladder you want; it is saved into the routine for next time.
- **`start_time`, `elev_m` and `source` in the weekly export's CARDIO block.**
  All three were already on the row and none of them reached the document, so a
  week of walks read as a list of durations.

### Changed
- **Export is a closing ritual on the phone too.** "Export week" no longer
  appears on a week with days left to log, and says which date it opens on. The
  web has worked this way since the report loop was built.

### Fixed
- The Pulse review shot photographed a body with no training behind it, so half
  of what the soreness tile draws was invisible in its own screenshot.

---

## [2.1.0] — 2026-09-12 · Which Side, Which Part, Which Joint

Soreness stops being ten numbers. You can now say WHICH part of a muscle is
sore, WHICH side, and that the complaint is a joint and not a muscle at all —
and none of it changes what the battery reads, because one muscle still
contributes exactly one number however many ways you describe it.

### Added
- **Day → Soreness** — a Left / Both / Right control in the rating sheet, and
  sub-region rows under the four groups that have them: Back splits into traps,
  rhomboids, lats and erectors; Shoulders into the three delt heads; Arms into
  biceps, triceps and forearms; Inner thighs into adductors and **abductors**.
  Rating a muscle whole stays a complete answer — the parent and its parts are
  different rows, not alternatives.
- **Day → Soreness → Joints & tendons** — flag a knee, hip, ankle, wrist, elbow,
  AC joint, lumbar junction or neck, with an optional note. Presence is the
  whole datum: there is no severity, and nothing about it reaches your readiness
  score or gates a workout. It is history, and it is in the export.
- **The figure** — joint rings on the body, filled when flagged, and sixteen new
  tendon, fibre and seam lines in ivory. The rings never take a tap and never
  add a keyboard stop; a joint is chosen in the sheet, on a full-size row.
- **Weekly export** — every side and sub-region is serialised. A whole-muscle,
  both-sides rating is spelled exactly as it always was, so old weeks re-export
  unchanged; a qualified one reads `Arms/Biceps@L:3` or
  `Inner thighs/Abductors@R:1:Legs & Core B:2026-09-02`. Flagged joints get
  their own `joints` column: `Knee@L;Wrist@R:tight after pressing`.

### Fixed
- **Readiness** — a day's soreness is now the mean over distinct RECOGNISED
  muscles, taking the worst of a muscle's sides and sub-regions, where it was
  the mean over rows present. Two consequences, both real: rating both biceps
  no longer moves a score that rating one did, and rows whose muscle name is not
  one of the ten — the demo account has been writing `Quadriceps` and `Lats` —
  stop counting toward a number they could never be read back into. Historical
  batteries change only for accounts that hold such rows.
- **Day → Soreness** — the tracker's own description had listed nine muscles
  since `Inner thighs` became the tenth on 2026-09-08.

### Changed
- `npm run check` now runs `check:atlas`, `check:mirror` and the new
  `check:doms`. The first two existed and were never in the gate, so a
  hand-edited generated file could ship green. `DomsMap.swift` is generated from
  the TypeScript vocabulary and can no longer drift from it — before this, a new
  soreness muscle could land on the web, be invisible on iOS, and leave both
  test suites passing.

### Migration
- Run `docs/sql/soreness-v2.sql` in the Supabase SQL editor. Until it is run the
  app degrades quietly: ratings still save, they just cannot carry a side or a
  sub-region.

---

## [2.0.1] — 2026-09-11 · The Ceiling That Was the Wrong Muscle

### Fixed

- **Native · InBody sheet.** A muscle-mass percentage above 70 % was refused
  with *"muscle 80.2 is outside 10–70%"*, and the reading could not be saved.
  The ceiling was the one for SKELETAL muscle applied to the column that holds
  the scale's MUSCLE MASS percentage — lean soft tissue over bodyweight, which
  on a lean athlete reads high-70s to low-80s on every InBody. The gate
  (`VitalsGate.musclePercentRange`) now runs 10–85 %, wide enough for a real
  reading and still narrow enough to catch a kilogram typed into a percent
  field. Nothing about the number changed: the same value, the same derived
  muscle mass, the same ledger row — it just lands now.
  The app's own preview fixtures used 77.6 %, a value the old gate would have
  refused, so this was never only about one reading.
  Skeletal muscle (kg) and fat-free mass (kg) are unaffected and were already
  loggable; neither is derived from this percentage.

---

## [2.0.0] — 2026-09-11 · Somebody Else's First Day

Onyx has had one user, and every screen quietly assumed it. Sign-up asked for an
e-mail and a password and then dropped you into somebody else's training plan,
somebody else's calorie target, and a five-minute treadmill warm-up with a note
about a pace rising from 4.3 to 5.0. This wave is the other person's first
launch: a new account now sets itself up, writes its own routine, and brings its
own movements.

**MAJOR because the new-user path is new.** Nothing about an existing account
changes — the founder's plan, deck, targets, levers and history are untouched,
and onboarding is never offered to an account that has any of them.

### Added
- **Onboarding** — eight steps after sign-up: bodyweight, week start, goal,
  daily macros, weekly sets per muscle, optional one-rep maxes, and a routine.
  Every step opens with a working answer already in it, and the two that ask for
  something optional say so in a button. Nothing is written until the last tap,
  so quitting halfway leaves an account that is still, correctly, brand new.
- **Your targets, from your bodyweight** — calories, protein, carbohydrate, fat
  and fibre worked out from what you weigh and what you are training for, and
  editable on the spot. The four numbers always add up to each other, so the
  app's own consistency warning cannot fire on the numbers it just produced.
  It does not ask for your sex, age or height, and does not need them.
- **Weekly set targets from published volume landmarks** — a starting point for
  all sixteen muscles rather than the founder's own tuned numbers. A cut holds
  at the minimum effective volume; a bulk reaches for the productive middle.
- **A routine builder** (Settings → Plan → Routines) — days you can add,
  rename, reorder, duplicate and delete, and inside each one the movements with
  their sets, cut sets, rest, rep window and starting load. The movement picker
  doubles as the new-movement field, so a machine Onyx has never heard of is one
  line of typing rather than a dead end.
- **Import exercises from a CSV** (Settings → Plan) — from Hevy, Strong or a
  spreadsheet, by file or paste. It shows you what it read before it writes
  anything: what will be added, what you already have, and — the one that
  matters — which movements it could not work out a muscle for, because those
  log fine but count towards nothing until you tell it.
- **Optional one-rep maxes at setup** — so the first month of sessions does not
  read as a personal record every week.

### Changed
- **The cardio sheet fills itself in.** Opening it on a day Apple Health has a
  single bout fills the whole form from it — distance, duration, active energy,
  **total energy** (active plus resting, the figure your watch and every
  treadmill console show), **ascent** and average heart rate. Tapping a bout no
  longer logs it: it fills the form, and Save is a second, deliberate tap on
  figures you have actually looked at. Ascent and total energy are now stored.
- **The weigh-in sheet fills itself in** — "Fill from Apple Health" takes your
  latest weight, BMI and body fat into the empty fields, never over something
  you have typed. Every percentage now prints its own **"= xx.x kg"** live as
  you type the weight, because 18.4 % of a body is not a quantity anyone can
  reason about and 14.2 kg is.

### Fixed
- **Quick Log's cardio sheet offered no Health import at all.** It never passed
  the day's bouts, and because that screen looks identical on a day Health has
  nothing, nobody noticed. Every route into the sheet now reads Health.
- **A flat bench press counted towards nothing.** The muscle dictionary grew
  around a training plan that presses on an incline and on machines and never
  once wrote the words "Bench Press", so the most common barbell lift in the
  world resolved to no muscle at all.
- **Resting energy came back as a raw count, not kilocalories** — it was
  authorised to be read and had no unit, so any sum of it was silently wrong by
  a factor nobody could see.
- **The treadmill opener is no longer prescribed to everyone.** It is one
  person's Zone-2 warm-up — a named machine, a distance, an incline and a pace
  note — and it was prepended to every session of every account.

### Removed
- Nothing. Every existing screen, number and row is where it was.

## [1.10.0] — 2026-09-11 · What You Say About the Day

Five of the six things this app asks you about yourself were behind a form. A
fatigue reading took nine taps and a scroll; a weigh-in was on another tab; a
glass of water was on a third; there was nowhere at all to say that the week was
stressful, or that you slept badly because of a flight. This wave is the typed
half of the app — the words, where they are said, and how long it takes.

### Added
- **Fatigue in five plain words** — **Amazing · Good · Okay · Tired ·
  Exhausted** (Pulse). They were Fresh / Fine / Worn / Heavy / Empty, which are
  precise and which nobody feels instantly at 7 a.m. The sheet is one row of
  five equal targets on the slot the clock picks, one tap, and it closes. Stored
  values are unchanged (1–5), so every reading you have ever logged still means
  what it meant; the weekly export's battery notes print the new words.
- **Head** — a new row beside Fatigue that asks what is on your mind, 1–5:
  **Relaxed · Okay · Tense · Strained · Swamped**, with optional tags (work,
  study, family, money, health, travel, other) and a note. It files under the
  part of the day the clock is in, so a day can carry up to three answers, and
  it feeds the Stress index's self-report term beside fatigue — the breakdown
  sheet now names both inputs (`fatigue 2.5 of 5 · head 3.0 of 5`). It is
  **not** a battery input and moves no score, like the index it feeds.
- **Quick Log** behind the Onyx mark on the dashboard (top right). Six spokes on
  a ring — water, weigh-in, fatigue, head, cardio, note — each opening the sheet
  that already existed, each showing what the day says so far. Water is the one
  that does not open anything: a tap is a 250 ml glass, added to the ledger, and
  the ring stays up for the second one. "Done" still owns that slot while the
  dashboard is in edit mode.
- **A note on the day** (Quick Log → Note). `daily_logs.journal_md` has been in
  the schema since the beginning with no way to write it. Nothing scores it,
  nothing exports it and nothing reads it back at you — which is the point.
- **The phone writes reports.** The Reports screen is now a list of WEEKS rather
  than of rows: every week back to your oldest report, never fewer than a
  quarter, each either a report to read or an **Add report** to paste one into
  ("Paste your AI coach reports…"). Saving an empty body takes a report back,
  which is the only way to undo a paste that went to the wrong week. Until now
  the web was the only writer.
- **Export PDF** from a report, next to Share text, straight into Files or Mail.
  It renders the same bundled document the reader draws, on demand — the render
  happens when you tap share, not every time a report opens.
- **The stack knows what a thing IS** — pill, capsule, powder, liquid or gummy,
  drawn as its own silhouette beside the name in your own item colour, and a
  dose that is an **amount and a unit** (mg, g, mcg, IU, ml, tab, cap, scoop)
  instead of free text. The editor says what the row will read before you save
  it, and whether its micronutrients count once or per unit.

### Fixed
- **The stack editor could not reach half the row.** Add could set the weekdays
  and "training days only"; Edit could not — so the only way to change an item's
  schedule was to delete it and add it again, which takes the row's log key with
  it and silently orphans every dose you have ever ticked for it. Edit reaches
  every field now, and the schedule is **merged** rather than replaced, so the
  key, the slot name, the notes and the per-day doses survive an edit.
- **A training day logged off-plan asked the wrong questions** (Pulse). The
  scorer has counted a day as training when a session exists OR the calendar
  says so since 1.6.0; this screen still read the calendar alone. A session
  trained on a scheduled rest day therefore offered Waking · Midday · Night
  while the arithmetic behind your score folded Waking · Before · After — and
  the stack dropped its training-only items out from under a session in
  progress. Both now ask the same question, and they ask it mid-session rather
  than at the end.
- **A refused body reading said the phone was broken.** Typing 855 into the body
  fat field produced "That change could not be saved on this device", which is
  useless and untrue. It now says which field, what value, and what is wrong
  with it.

## [1.9.0] — 2026-09-11 · Before, During and After the Workout

A hotfix sprint against one real session (Legs & Core B, 11 Sep). Three screens
— the plan card you read before a workout, the deck you log it on, and the
summary you read after — plus the two numbers that turned out to be wrong
underneath them.

### Added
- **The plan card shows LAST TIME, not the rep window** (Train tab). Every
  movement's row printed `3 × 10-15`, which is the prescription and has not
  moved in eight weeks. It now prints the top set from the last session of the
  same split — `Last: 72.5 kg × 15 @ 8.5` — heaviest working set, ties broken
  by reps, a unilateral pair scored at its weaker side, a hold in seconds. A
  movement that was not in that session prints nothing rather than a number
  from some other day.
- **"Open last · Thu 4 Sep"** on the same card opens that whole session's
  summary in a sheet, over the plan you are about to perform.
- **A set stopwatch** in the logger's timer sheet (tap the elapsed reading).
  Start / Stop / Lap / Reset, for timing a plank or a hollow hold; read it and
  type the number into the set. It is anchored to a date rather than driven by
  a repeating timer, so it is the system clock the phone and the watch already
  share — it cannot drift, and it survives the screen locking.
- **Muscle tags on the session summary header**, derived from the muscle credit
  the session actually earned. A Legs & Core B holding a Side Plank and a
  Hanging Knee Raise was missing its Abs/core tag; nothing up there had ever
  asked what was trained, only what the calendar said. Nothing is truncated —
  core work is always the smallest share, so any "top four" drops exactly the
  tag this fixes.
- **The trophy is the set's badge on the summary**, and long-pressing a record
  row opens the record sheet the live deck has had since E4 — which axis, the
  new figure, and what it beat. VoiceOver reaches it through a "What it beat"
  rotor action.

### Fixed
- **One session, one tonnage.** 11 Sep read **8,815 kg** on the Train tab and
  the Pulse card, and **9,715 kg** on its own summary page — the gap was a
  single 60 kg × 15 warm-up on the leg press. `SessionVolume`'s rule is one
  sentence ("a ghost weighs nothing; a warm-up still counts") and five call
  sites in three files were filtering warm-ups out before calling it. They no
  longer do, so every surface now agrees with `workout_sessions.total_volume_kg`
  and with the close path. Set COUNTS still exclude warm-ups, deliberately —
  that is a different question. `src/tests/session-tonnage-discipline.test.ts`
  fails the next call site that re-adds the filter.
- **Records that never got filed.** 11 Sep stored `pr_count = 1` where a replay
  of the whole ledger finds five: Leg Press volume (72.5 × 15), Calf Press
  volume and 1RM (70 × 15), Hanging Knee Raise reps (18), Side Plank duration
  (66 s). `PrRecorder.baselines` gathered the bar under the session's OWN
  exercise ids, so a movement whose history sits under a second id — a
  catalogue uuid from the web beside a predecessor-stamped slug from the phone, which
  `nameResolver` calls routine — was judged against an empty bar, and an empty
  bar awards nothing at all. The bar is now gathered under every id that
  resolves to the same canonical name. It can only ever raise a bar or fill an
  empty one, so it removes false positives and cannot invent a record; the
  ledger's filing key is unchanged.
- **A split set was scored twice.** The PR engine folds an L/R pair on `L`/`R`,
  and the phone's own rows spell the sides `left`/`right` — so `volumeCredits`
  saw no pair and credited each arm its own tonnage, both at close and on the
  live deck (which was not passing `pair_id` or `side` at all). An asymmetric
  pair could take a volume record the same work logged unsided never would.
- **Splitting a set now does something visible.** A pair whose two sides agreed
  drew as the single row it replaced, and the one effort control wrote to both
  of them — so "split the Side Plank, rate the left arm harder" was a dead end
  with no way out of it. A completed pair now always draws its two efforts
  (`L 8 · R 9`) over one value line, which is what the web has always done.
- **"Fin…"** — the Finish button truncated in the navigation bar. The word is
  incompressible now.
- **Dead space on unloaded movements.** With no kg column, the reps/time track
  kept its floor beside the badge and the effort word stayed pinned right,
  leaving ~90 pt of nothing between them on Side Plank and Hanging Knee Raise.
  The surviving track takes the vacated width, in the row and in its header.
- **A split set kept its measurements.** `splitSet` copied load, reps and effort
  to both halves and dropped `duration_sec`, `incline`, `distance_km` and
  `elevation_m`; `mergeSet` dropped them the other way.
- **`scripts/backfill-prs.mjs` could not run at all.** `workout_sets` passed
  1,000 rows, PostgREST truncated the read silently, and the script's own
  preflight — correctly — refused to proceed, because a truncated read prunes
  the ledger of every session it cannot see. The read is paged now.

### Data
- The record book was replayed over the full ledger (`backfill-prs.mjs`):
  120 rows written, 3 superseded rows pruned, 9 `is_pr` flags and 3 `pr_count`s
  corrected — 11 Sep from 1 to 5, 10 Sep from 10 to 5, 8 Sep from 4 to 1.

---

## [1.8.0] — 2026-09-11 · Sixteen Muscles, One Count

Every muscle has its own colour, and the week is counted once.

### Added
- **Muscle focus on Trends** — a new card at the top of the Trends screen: the
  body front and back with every landmark tinted by what landed on it, and a
  ranked list of all sixteen under it. It carries its own window — **Week**,
  **30 d**, **All** or the current programme — where Week respects the week
  start you chose (`user_goals.week_end_day`) rather than assuming Sunday.
- **The widget's Muscle Focus tile grades against your targets.** It used to
  rank families against the week's own busiest family, which told you where the
  week went and never whether it was enough. It now reads "Legs 24/32" with a
  rail, the same question the sheet it opens has always answered.

### Changed
- **Sixteen muscle colours, in eight families.** Chest, Back, Shoulders,
  Biceps, Triceps, Forearms, Legs and Core each have a hue; the landmarks inside
  a family step light to dark, so three back muscles read as three shades of one
  teal. Before this, chest, all three delt heads and all three arm muscles drew
  the same indigo — "Side delts 0/7" looked exactly like "Chest 18/18". Measured:
  any two muscles of different families sit at least ΔE 22.8 apart, and the
  dimmest clears 4.99:1 on black.
- **Biceps and triceps are separate families.** They always had separate weekly
  set targets; now they have separate bars, separate colours and separate rows.
  Weekly set volume in Settings is grouped the same way.
- **The week is counted in one place.** The widget tile, the Today sheet and the
  Trends card each used to count muscle work for themselves — six families or
  sixteen, with or without credit for assistance, from a Sunday or from your own
  week start — so the same session could read three ways. All three now call one
  accumulator: direct work 1.0, assistance 0.5, warm-ups counted, ghost sets not.
- The muscle atlas legend keeps its colour bar at accessibility text sizes
  instead of dropping it, and its colour dot scales with the type.

### Fixed
- **A phone-logged set is credited on Trends too.** Sets logged on the phone
  carry a slug id rather than a catalogue uuid; the Trends reader named only the
  catalogue, so those sets silently credited no muscle at all — the same defect
  that produced "Side delts 0/7" on the tile and the sheet, on the one surface
  W1 did not reach.
- A week with no per-muscle targets set — a new account, or a phase never given
  volume rows — drew an empty body on the tile and the sheet even with work
  logged. With no target to grade against, the figure now grades against the
  busiest muscle.

### Removed
- `MuscleAggregator` and `WidgetDerive.volumeByFamily`, the two accumulators the
  single one replaced, with their fixtures.
- `OnyxDomain.forMuscle` and `OnyxDomain.forFamily` — the four-accent collapse.

## [1.7.0] — 2026-09-11 · The Generic Model

W2 of the epic sprint (`docs/EPIC_SPRINT_PLAN.md` D1–D6). No new screens; the
app stops being one athlete's plan compiled into a binary. Every reader —
the logger deck, the muscle targets, the phase label, the nutrition lever, the
supplement stack, the PR floors — now takes rows, and a second account starts
empty instead of inheriting the founder's.

### Added
- **Four tables** (`docs/sql/w2-generic-model.sql`, founder pastes): `routines`
  (one row per program day, exercises in a jsonb payload), `plan_phases` (the
  dated blocks), `lever_periods` (when each nutrition rung came into force),
  `stress_logs` (the psych self-report W4 writes). Columns W4/W5 need on
  `exercises` (`slug`, `secondary_muscles`, `rep_floor`, `rep_ceiling`,
  `archived_at`), `custom_supplements` (`dose_amount`, `dose_unit`,
  `sort_order`, `archived_at`), `cardio_logs.elevation_m`, `plans` (`blurb`,
  `is_legacy`, `sort`), `plan_phase_goals` (`label`, `fiber_g`,
  `body_fat_ceiling_pct`), `target_profiles.kind`. The schema is frozen from
  here to W5.
- **The founder's seed** (`docs/sql/w2-seed-founder.sql`), generated from the
  constants before they were deleted — 3 plans, 14 routine rows with catalogue
  uuids, 8 phases, 4 rungs, 5 lever periods, 6 phase-goal rows, 96 weekly set
  targets, the netted PR floors — scoped to one account and never overwriting
  an edit.
- **Stress index** — the `self` term reads the day's `stress_logs` mean beside
  the fatigue mean (mean of the two that answered, weights unchanged);
  `docs/STRESS_MODEL.md` §2.3.
- **Levers screen** — changing the rung records a `lever_periods` row, so the
  schedule of rungs maintains itself from now on.
- `plan-templates.json` in the app bundle: the same three decks as the
  template W5's onboarding seeds a new account from.

### Changed
- `ScheduleContext` carries the decks, the plan entries and the phases; the
  plan that owns a date is the one whose block covers it, else the latest
  `started_on` before it (the compiled era boundary is gone). The watch reads
  the deck from the context the phone sends.
- Legacy predecessor-stamped set ids resolve through `exercises.slug` (data), not through
  the deck; new sets carry the catalogue uuid from the routine payload.
- PR floors are `personal_records` rows with no session; a replay never
  deletes them. A record that beats a floor carries it in `floor_value`
  (`docs/sql/w2-pr-floor-value.sql`, founder pastes third), and deleting
  that session hands the axis back to the floor instead of emptying it.
- The weekly export's programme line names the plan from its row
  ("Onyx-5 Cut").

### Removed
- From OnyxCore: `Program.onyx5/onyx4/pplLegacy`, `Programs.all/goals/
  weeklySetTargets`, `PhaseGoals.cut/bulk`, `NutritionPresets`, `Phases.all`,
  `Levers.all/schedule`, `LeverId`, `PrSeed`, `PrTruth.book`,
  `Supplements.protocolSeed`, `TargetProfiles.builtin`, `Week.week0Start`,
  `Era`, and the golden fixtures that pinned them.

---

## [1.6.0] — 2026-09-10 · The Truth Wave

W1 of the epic sprint (`docs/EPIC_SPRINT_PLAN.md`). No new screens; six things
the numbers were quietly getting wrong stop being wrong.

### Fixed
- **Muscle focus (dashboard sheet, Trends, widget tile)** — a set logged on the
  phone now counts towards its muscles. Phone-logged sets carry predecessor-stamped slug
  ids, not catalogue uuids, and the one map both readers share only knew the
  catalogue: "Side delts 0/7" after an Upper B was every lateral raise dropped.
- **Sync** — a PostgREST schema-cache miss (`PGRST205`/`PGRST204`/`42703`) is
  held and retried, never acknowledged; only Postgres's own `42P01` is
  permanent. The retry now jitters by up to a quarter-step so two devices
  that failed together do not knock again together.
- **Stress index, battery wellness, weekly export** — a day's fatigue folds by
  the day the athlete HAD: a session logged on a scheduled rest day makes it a
  training day, so a `noon` reading is "before training" and a stale legacy
  row can no longer merge away the answer actually given.
- **Set quality** — one parser in OnyxCore for the `+` grammar
  (`momentum+partial_rom`); the logger's typed view delegates to it, and the
  guard refuses exactly what the CHECK constraint refuses.
- **Session duration** — a session pulled from the server and finished on the
  phone is timed by its sets. Seeded events carry the server's `created_at`
  instead of the seed's clock; the 2-minute Pec Deck session cannot recur.
- **HealthKit ingest** — an HRV reading beyond the athlete's own 42-night band
  (median ± max(3.5 MAD, half the median)) or outside 5–300 ms is declined and
  reported, not stored. Body fat outside 2–70 %, muscle 10–70 %, visceral fat
  1–30 are refused on ingest and on the InBody sheet.

### Changed
- **Golden fixtures are Swift-owned.** `npm run golden` and the TypeScript
  generator are gone; `Fixtures/*.json` are frozen test resources with
  hand-computed cases.

### Removed
- `docs/sql/w1-cleanup.sql` (founder pastes) drops `widget_tokens`,
  `notion_credentials`, `notion_exports`, `body_measurements`,
  the `_bak_20260723` backup schema and the `exercise_history()` RPC.

---

## [1.5.0] — 2026-09-10 · One Set, One Box

The live logger stops disagreeing with the rest of the app about what a set is.
A movement trained one arm at a time is one row per set, the treadmill asks for
the two numbers a walk actually has, and the trophy finally says what it beat.

### Added
- **A pair is one set box** (native logger). L and R share a set number, a
  checkmark and a trophy. How much of the box splits depends on how much the two
  sides disagree: nothing when they match, the effort alone when only the rating
  differs (`L 9.5 · R 8.5`), and two value lines under one badge when the load
  or the reps do. The rule is `SetPairLayout` in OnyxCore, with vectors.
- **Duration and distance on a cardio set** (native logger). The treadmill block
  asked for kilograms and reps and showed `0 kg × 0`; it now shows minutes and
  kilometres, with the same coarse/fine stepper grammar as a load (1 min / 30 s,
  100 m / 50 m) — and it can be ticked, which a zero-rep row could not.
- **The record sheet, on the phone** (native logger). Tapping a set that holds a
  record slides up what it won, by how much, and what it beat — the web's
  `PrRecordSheet`, one for one.
- **Add set on a unilateral movement adds a pair**, so the fourth set is the
  same shape as the three the deck seeded.

### Changed
- **The PRs card groups by movement** (native Live Stats). One sub-card per
  lift, its name once at the top, a count of the claims it is carrying, and the
  axes underneath — instead of a flat list repeating the same exercise name on
  every row.
- **The Finish button lost its box** (native logger). Built against the iOS 26
  SDK a toolbar item is given a glass capsule of its own, under the filled one
  this item draws; the item now declares its own background.

### Fixed
- **A set list that read `1, L, R, 4`** (native logger). The deck numbered rows;
  it numbers sets.
- **Half-empty completion dots** (native Live Stats). A three-set unilateral
  movement counted six rows against three ticks and reported a finished lift as
  half done.
- **The rest timer survived an untick** (native logger + watch). Ticking the
  wrong set and immediately unticking it left the countdown running on the deck
  and a full-screen rest cover on the wrist. The phone now also *mirrors* its
  rest clock to the watch at all — `PhoneWatchBridge.send(rest:)` had no caller
  since Wave 10, so a phone-started rest never reached the wrist either.
- **A tap into a load selects it** (native logger). The caret used to land
  behind the number, so changing 40 to 47 meant tap, Done, tap, backspace twice.
- **The steppers stepped twice on a fast tap** (native logger). Touch-down and
  touch-up inside one frame delivered the button's action before the press edge,
  and both applied the step: reps by 2 where the control says 1, load by 5 where
  it says 2.5. The coarse step is now idempotent within one activation instead
  of dependent on a delivery order SwiftUI does not promise.

---

## [1.4.1] — 2026-09-10 · What The Summary Says Happened

Four defects on the post-workout page, and every one of them turned out to be
about something other than what it looked like. A grayed-out Edit button that
had nothing to do with dates, a duration delta that was a claim about a
different workout, an internal key printed as a movement's name, and half of
every set row belonging to another day.

### Fixed
- **Any past session can be edited again** (native, History → session → Edit).
  The button was disabled for every session containing a unilateral L/R pair —
  which is every Delts & Arms day — so the whole split had been uncorrectable
  and the symptom read as a date lock. The gate was written when the logger
  could not carry a `side`; it has carried one for some time
  (`restoreLoggedSets`, `snapshot`, and `ExerciseState.volumeKg` all handle a
  pair), and the gate was never lifted with it. Sessions with no `day_key` — the
  74 Notion-era workouts — are editable now too: the deck is built from the
  session's own movements when the program cannot name the day.
- **"74 min, +72" is gone** (native, session summary). The 2026-09-03 Upper B
  session recorded twelve sets as two minutes, and the page printed the
  difference as if it were a fact about Thursday. The stored figure is repaired
  and, so the next corrupt clock cannot do it again, a duration delta is now
  suppressed when the session it is measured against recorded less than 20
  seconds per set — a reserved blank line rather than an invented number.
- **The treadmill is called Treadmill** (native, session summary), not
  the predecessor's treadmill slug. `WarmupCardio` is deliberately outside `Program.onyx5`, so
  the slug the deck stamps on the bout was in no name table and the page fell
  back to printing the key. The same one-line miss meant a treadmill logged on
  the phone threw `unknownExercise` on push and could not be uploaded at all —
  the one movement the deck adds for you was the one the sync refused. The
  predecessor prefix itself stays: it is a key written into local rows, and
  renaming it would file every unsynced set under a second identity.
- **The summary shows only the sets you just did** (native, session ledger).
  Each row carried the positionally-matched set from the last time that
  movement was trained, so a four-set Single Arm Lateral Raise drew eight
  numbers. The comparison stays where it means something — the header's
  `vs 30 Aug` capsule, which reads the previous session whole rather than
  row by row.
- **2026-09-08 "Delts & Arms" now reads 3,680.75 kg**, reconciled set by set
  against the Hevy record: one rep on Seated Incline DB Curl (16 × 13 → 16 × 12,
  which was the entire tonnage gap), the treadmill's distance (0.370 → 0.4 km),
  and a scrambled `exercise_order` that had been drawing two cards each for the
  curl and the lateral raise. Ratings, quality flags and PR marks untouched.
  `docs/sql/hotfix-data-ui.sql` and `scripts/repair-sep-2026-data.mjs`.

---

## [1.4.0] — 2026-09-10 · Submittable

The wave that makes the binary uploadable. Two pages App Review opens before it
installs anything, the rows in the app that point at them, and the three sync
and scoring defects the Phase 3 ship gate left open.

### Added
- **Privacy policy** at `/privacy` and **support** at `/support` — public,
  prerendered, and written in the same vocabulary as the app's privacy manifest
  so the policy, the manifest and the App Store questionnaire cannot disagree.
  Both were 404s, which is the one thing that stops a HealthKit app being
  reviewed at all (5.1.1(i), 1.5).
- **Settings → About → Support**, beside the existing Privacy Policy row.
  `OnyxLinks` now states the host once and derives both urls from it.
- **Associated Domains** (`webcredentials:`) in the app's entitlements, matching
  the `apple-app-site-association` file already served. iOS Password AutoFill
  can now offer the credential the browser holds for the site. Needs the
  capability enabled on the App ID in the developer portal.
- App Store metadata in `docs/APP_STORE.md` §2 is written, not `⟨…⟩`.

### Changed
- **`/privacy`, `/support` and `/delete-account` are public.** `AuthGate` used
  to redirect everything that was not `/auth` to the sign-in page, so all three
  were a login form wearing a URL. One `PUBLIC_ROUTES` list now serves the gate
  and both navigation bars.
- **Sign-up's Close button is a toolbar item.** As a floating overlay the form
  scrolled underneath it, and a `.footnote` label is a ~30 pt hit target where
  the minimum is 44.

### Fixed
- **A set event is no longer lost to a transient failure.** `SyncEngine` used to
  acknowledge an outbox item after a push whose error it had swallowed, so one
  503 dropped the event permanently and two devices never converged again. The
  item is now held and retried; a genuinely missing `set_events` table is still
  swallowed, because no retry creates a table.
- **Set quality tags reach the server.** `Cheated`, `Short ROM` and the rest
  were held on the phone and never sent. The batch is split so the tagged rows
  carry the column and the untagged ones omit it — which is what stops a device
  that was never asked about a set nulling the tag the web app recorded.
- **A rest day no longer folds its fatigue as a training day.** On a day mixing
  a legacy slot key with a modern one this counted a superseded reading as a
  slot of its own, adding several points of Stress to a day that had none. It
  now resolves the day the way the scorer does.
- **`npm run build` passes again.** Every table in the generated Supabase types
  was missing `Relationships`, so the schema stopped satisfying postgrest-js's
  `GenericSchema` and every `.update()` argument collapsed to `never` — which
  had failed each deploy from `main` since 2026-09-08. Sixteen live columns
  missing from `daily_logs` and `user_goals` are restored with it.

---

## [1.3.0] — 2026-09-08 · UI/UX Pro-Max Polish

The polish wave. Nothing new to learn, several things that had been quietly
wrong for a wave or four.

### Added
- **Unilateral sets.** A set can be two sides, carry several tags, and own its
  own clock — the logger no longer forces a per-limb lift into one row that
  averages both. (`feat(logger,widgets)`)
- **Inner Thighs in the body atlas.** The adductors were the only landmark the
  atlas could not draw; the quad gives up two units at the hip and two at the
  knee and the adductor takes the strip it vacates. Web and Swift atlas
  regenerate from the one definition (`src/lib/body/atlas.ts`).
- **About → Version** on the web settings page, and `version` in
  `/api/version`. The app had shipped four waves without saying which build you
  were looking at.

### Changed
- **Dashboard widgets open the face you are looking at.** Tapping a tile used
  to route by widget id, which sent you to the wrong screen for any tile whose
  face had been rebound. (`feat(dashboard,atlas)`)
- Six dashboard tiles draw a **series** instead of a single reading, and one era
  window replaced three separate range controls (W11/W12 carried forward).
- The progression chip leaves the logger header while the clock runs, instead
  of fighting the timer for the same row.

### Fixed
- The session page stopped disagreeing with the session it was showing.
- Four 40 mm watch layout defects the screenshot loop found.
- The set-close stopped being undone by a late sync write, and the stepper
  stopped counting a single press twice.

---

## [1.2.0] — 2026-09-08 · Mathematical Engines

Two engines that turn raw signal into a number the rest of the app can grade
against. Both are **report-only and computed on read** — neither writes a score
row, so neither can corrupt history.

### Added
- **E2 — Sleep trim engine.** Strategy A/B trimming over asleep minutes, a
  night sentinel for the zero-minute case, and id-keyed edits so correcting one
  night never silently re-attributes another. (`feat(sleep)`)
- **E3 — Stress index v1.** A z-scored composite over the recovery inputs, with
  the flat-baseline case handled explicitly rather than dividing by a zero
  standard deviation. Surfaced as the Pulse stress tile and the stress series
  in Trends (U5). (`feat(scoring)`, `feat(pulse,trends)`)
- Sleep edit sheet — a night you know is wrong can be corrected in place.

### Fixed
- What the Phase 3 ship gate found across the gate, sleep, scoring and watch
  code paths.

---

## [1.1.0] — 2026-09-08 · Onyx on the Wrist

Wave 10. The watch stops being a viewer and becomes a logger, and two devices
logging the same session stop overwriting each other.

### Added
- **watchOS logging client** (`OnyxWatch`) — a single modern watchOS app target,
  budgeted for the 40 mm case throughout, with an `HKWorkoutSession` keeping it
  alive between sets.
- **Double-pinch to log a set.** `.handGestureShortcut(.primaryAction)` on the
  set view and the root — the wrist's actual advantage over a phone is logging
  without your other hand. (`native/OnyxWatch/Views/SetView.swift`)
- Heart rate and active energy read live during a set; the finished workout is
  written back to Apple Health.

### Changed
- **Supabase finally merges two devices.** Appending to a session pulled from
  another device no longer replaces its sets. (`feat(watch,sync)`)

### Fixed
- The four 40 mm layout defects found by the shot loop before the wave shipped.

---

## [1.0.0] — 2026-09-07 · Initial Launch

Everything up to and including Phase 3's truth waves — the point at which the
native app stopped being a port of the web app and became the product.

### Added
- **Onyx native iOS app** — Today, Logger, Pulse, Nutrition, Workout, History,
  Exercises, Stack, Settings. Domain in `OnyxCore`, GRDB store and sync in
  `OnyxData`, design system and tiles in `OnyxUI`.
- **Widget extension** — five Home Screen families, a Lock Screen accessory and
  the running-workout Live Activity, reading `onyx.sqlite` straight out of the
  App Group container.
- **The Great Sync** — `SyncEngine`, `MirrorPuller`, `MirrorRealtime`, the
  outbox, and a Sync Doctor that answers with the server's own count.
- **Readiness v9** — the battery reads six weeks of you.
- **Phase 3 truth waves** — rescore on edit, PR engine, export v3, auth both
  ways, the logger engine, and the edit deck.
- The predecessor web app: dashboard, logger, nutrition, trends, reports, PWA.

### Changed
- The app is **Onyx**, all the way down — `apex51`/`axis4` became `onyx5`/`onyx4`.

---

<!--
── ADDING A RELEASE ─────────────────────────────────────────────────────────
Copy this block under [Unreleased], newest first. Keep the one-line theme after
the date — the table of contents a reader actually uses is the list of themes.

## [X.Y.Z] — YYYY-MM-DD · Theme

### Added / Changed / Fixed / Removed
- What a user can now do, or what stopped being wrong. Name the surface.

Omit any section with nothing in it. Then:
  1. set `"version"` in package.json
  2. npm run version:sync
  3. cd native && xcodegen generate
-->

---

# Appendix — applied server migrations

Three files under `docs/sql/` carried the Supabase half of this codebase's
migrations. Every one of them was pasted into the SQL editor and run by the
founder; none can be run again, and none is read by any build. They were
deleted at the Onyx Expansion close-out and their text moved here, because the
record of what the server's schema became — and why — is worth more than three
files nothing executes.

They are reproduced verbatim, newest first. Nothing below is meant to be run.


## w7-exports.sql — the `exports` drop-box (Onyx Expansion W7, 7.8.0)

```sql
-- ════════════════════════════════════════════════════════════════════════════
-- w7-exports.sql — the drop-box the Onyx MCP server reads (Onyx Expansion, W7)
--
-- Paste into the Supabase SQL editor and run the whole file.
--
-- ── RUN THIS BEFORE THE BUILD REACHES THE PHONE ────────────────────────────
-- Same rule as `w1-onyx-wire.sql` and `w6-export-v6.sql`, and for w6's reason:
-- nothing here rewrites history, so a late run costs no data — but the app
-- POSTs an `exports` row the first time the export chip is tapped, and
-- PostgREST rejects an insert into a table it cannot find. Unlike the outbox's
-- rows this one is NOT retried (`ExportService.upload` is one best-effort
-- request, documented as such in its own header), so a week exported before
-- this file runs never reaches the server at all. The markdown still reaches
-- you through the share sheet; only the MCP server's copy is lost.
--
-- ── WHAT IT DOES ───────────────────────────────────────────────────────────
-- §1  creates `public.exports` — one row per (athlete, span), holding the
--     whole `ExportEnvelope` as `jsonb`.
-- §2  gives it RLS in the `(select auth.uid()) = user_id` INITPLAN form every
--     other table here uses, `to authenticated` and never `to public`.
-- §3  reports the result.
--
-- ── WHY THE DOCUMENT IS STORED AND NOT RE-DERIVED ──────────────────────────
-- The MCP server is Node, it has a service key, and it could in principle read
-- `workout_sets` and build a week itself. It must not. The extraction lives in
-- ONE place (`WeeklyExportBuilder` → `WeeklyExport.build`), and a second
-- implementation in a second language is how two surfaces come to disagree
-- about the same week — which is the exact failure this sprint's W7 exists to
-- prevent. So the phone builds the document and files it here, and the server
-- serves what it finds. The server's other tools are raw rows and say so.
--
-- ── AND WHY THE THREE COLUMNS BESIDE THE JSON ──────────────────────────────
-- `range_start`, `range_end` and `version` are copies of fields inside the
-- envelope. Duplicated deliberately: they are the only things anything filters
-- or orders on, and an index on a `date` column is a different conversation
-- from an index on a `jsonb` path. The envelope remains the source of truth;
-- if they ever disagree, the envelope is right.
--
-- ── THE KEY IS THE SPAN, SO A RE-EXPORT REPLACES ───────────────────────────
-- `(user_id, range_start, range_end)`. Exporting the same span twice — sharing
-- "last complete week" on Monday and again on Tuesday — must leave one row, not
-- two documents differing only by their timestamp. `ExportService.conflict` is
-- this same tuple, spelled in Swift.
--
-- ── WHAT THIS FILE COULD NOT VERIFY, AND YOU SHOULD ────────────────────────
-- Introspected live on 2026-09-22 through PostgREST's OpenAPI document:
-- `exports` does not exist (35 tables, none of them this one); every table
-- that carries `user_id` declares it `uuid NOT NULL`; `created_at` is
-- `timestamptz DEFAULT now()` on all 21 tables that have one; and both
-- `gen_random_uuid()` and `extensions.uuid_generate_v4()` are live column
-- defaults elsewhere in this schema. What could NOT be read from this machine
-- is the BODY of any existing RLS policy — `pg_policies` is not reachable
-- through PostgREST and there is no database password here. §2 below is
-- therefore written to match `w6-export-v6.sql`, which you ran, rather than to
-- match an introspection. §3 prints the policies it created; compare them with
-- another table's before you trust them.
--
-- ── EXPECTED COUNTS ────────────────────────────────────────────────────────
-- Before: `exports` does not exist. After: 0 rows. The first row arrives the
-- first time the export chip's share sheet is actually completed.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 0 · Before ──────────────────────────────────────────────────────────────
-- If `exists` is already true the table is in place and §1 is a no-op.
SELECT to_regclass('public.exports') IS NOT NULL AS exports_exists;

-- ── 1 · The table ───────────────────────────────────────────────────────────
-- NOT mirrored into the phone's GRDB store, and deliberately: the app never
-- reads this table. Mirroring it would mean carrying every document ever
-- exported in the local store, for no reader. So it is absent from
-- `native/schema/supabase.json` on purpose, and `npm run check:mirror` is not
-- wrong about it.
--
-- `gen_random_uuid()` and not `extensions.uuid_generate_v4()`: both are live in
-- this schema, and the newer tables (`cardio_logs`, `stress_logs`, `plans`,
-- `doms_logs`, …) all use the former.
CREATE TABLE IF NOT EXISTS public.exports (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    range_start date NOT NULL,
    range_end   date NOT NULL,
    version     integer NOT NULL,
    envelope    jsonb NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- A span ends no earlier than it starts, and is no longer than the app's own
-- cap. `ExportRange.maxDays` is 28 and `ExportRange.clamp` enforces it on the
-- phone; the constraint is here so a client that forgot cannot file a document
-- covering a year. 31 rather than 28 — the column should refuse an ABSURD span,
-- not police a product decision that may be widened next week.
ALTER TABLE public.exports DROP CONSTRAINT IF EXISTS exports_range_check;
ALTER TABLE public.exports
  ADD CONSTRAINT exports_range_check
  CHECK (range_end >= range_start AND range_end - range_start <= 31);

-- ONE DOCUMENT PER SPAN PER ATHLETE. This is what makes the phone's upsert an
-- upsert: `ExportService.conflict` names this tuple, and without the unique
-- index PostgREST's `on_conflict` has nothing to resolve against and the
-- request fails.
CREATE UNIQUE INDEX IF NOT EXISTS exports_user_range
  ON public.exports (user_id, range_start, range_end);

-- The read the MCP server's `list_exports` makes: this athlete's documents,
-- newest span first.
CREATE INDEX IF NOT EXISTS exports_user_recent
  ON public.exports (user_id, range_end DESC);

-- ── AND WHY THERE IS NO `updated_at` ───────────────────────────────────────
-- Every other table here has one, and this one had one too until it was read
-- properly: `DEFAULT now()` fires on INSERT only, and
-- `PostgRESTMirrorRemote.upsertRow` STRIPS both timestamp columns from every
-- body it sends. A re-export of the same span would therefore leave the column
-- frozen at the first insert while the envelope beside it carried a newer
-- `generatedAt` — a column that is permanently a lie. The envelope's own
-- `generatedAt` is the freshness figure, and it is the one the writer actually
-- sets.

-- ── 2 · Row level security ──────────────────────────────────────────────────
-- The `(select auth.uid()) = user_id` INITPLAN form, so the check is evaluated
-- once per query rather than once per row, and `TO authenticated` — never
-- `TO public`, which is the shape that leaked in W11.
--
-- The MCP server reads this table with the SERVICE key, which bypasses RLS by
-- design. That is the founder's own key on the founder's own machine, reading
-- the founder's own rows; it is never shipped and never given to a client.
--
-- Every statement re-runnable: `drop policy if exists` before each `create`.
ALTER TABLE public.exports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS exports_select_own ON public.exports;
CREATE POLICY exports_select_own ON public.exports
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS exports_insert_own ON public.exports;
CREATE POLICY exports_insert_own ON public.exports
  FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS exports_update_own ON public.exports;
CREATE POLICY exports_update_own ON public.exports
  FOR UPDATE TO authenticated
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS exports_delete_own ON public.exports;
CREATE POLICY exports_delete_own ON public.exports
  FOR DELETE TO authenticated
  USING ((select auth.uid()) = user_id);

-- ── 3 · After ───────────────────────────────────────────────────────────────
-- `exports_exists` must be true, `rls_enabled` must be true, and there must be
-- exactly FOUR policies, all of them `authenticated`. If any row below comes
-- back wrong, ROLLBACK rather than COMMIT.
SELECT to_regclass('public.exports') IS NOT NULL AS exports_exists;

SELECT relrowsecurity AS rls_enabled
  FROM pg_class WHERE oid = 'public.exports'::regclass;

SELECT policyname, cmd, roles::text, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'exports'
 ORDER BY policyname;

-- The columns, for comparison against `ExportService.Row` in
-- `native/Packages/OnyxData/Sources/OnyxData/History/ExportService.swift`.
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'exports'
 ORDER BY ordinal_position;

COMMIT;
-- ROLLBACK;   -- swap for COMMIT above if anything in §3 came back wrong
```

## w6-export-v6.sql — `prescriptions` and the `hrv_overnight` audit (export v6, 7.5.0)

```sql
-- ════════════════════════════════════════════════════════════════════════════
-- w6-export-v6.sql — the server half of `v33.prescriptions` (export v6)
--
-- Paste into the Supabase SQL editor and run the whole file.
--
-- ── RUN THIS *BEFORE* THE BUILD REACHES THE PHONE ──────────────────────────
-- Same rule as `w1-onyx-wire.sql`, for a different reason. Nothing here
-- rewrites history, so a late run costs no data — but the outbox pushes a
-- `prescriptions` row the moment the first block is pasted, and PostgREST
-- rejects an INSERT into a table it cannot find. The row would sit in the
-- outbox retrying until the table existed. Run it first and there is no
-- window.
--
-- ── WHAT IT DOES ───────────────────────────────────────────────────────────
-- §1  creates `public.prescriptions` — the CURRENT instruction per movement,
--     appended and never overwritten.
-- §2  gives it RLS in the `(select auth.uid()) = user_id` INITPLAN form every
--     other table here uses, `to authenticated` and never `to public`.
-- §3  reports what `daily_logs.hrv_overnight` already is. It is NOT created:
--     introspected live on 2026-09-20, the column exists and is `boolean`,
--     nullable, no default. It has been there since readiness v9 and was
--     missing from `native/schema/supabase.json`, which is why nothing on the
--     phone could read or write it. §3 exists so a founder running this file
--     against a database that somehow lacks it finds out here rather than from
--     a rejected push.
--
-- ── WHY `prescriptions` IS ITS OWN TABLE AND NOT A COLUMN ──────────────────
-- The export printed `ProgramExercise.wk1Kg` as `prescribed` — the load the
-- program was COMPILED with in July — while the coach moved Incline DB Press
-- 32 → 34, Lat Pulldown 45 → 50 and the RDL 30 → 40. Every `load Δ` in the
-- document was drawn against a number nobody had worked to since the block
-- began.
--
-- A prescription is an instruction with a DATE on it, and its history is the
-- argument a progression review is made of: "the top set went 34 → 36 on the
-- 14th" cannot be said by a row that is UPDATEd in place. So `version` is
-- per-movement and append-only, and `effective_from` is what decides which
-- version was in force on a given session's day.
--
-- ── AND WHY `exercise_key` IS A DISPLAY NAME ───────────────────────────────
-- Because `personal_records.exercise_key` is (introspected 2026-09-19: 81
-- rows, every one a canonical display name — "Seated Cable Row (V-Grip)",
-- never a slug). One movement, one key, across both tables, and no second
-- dictionary between them. `ExerciseAliases.canonicalName` is what produces
-- it on the phone.
--
-- ── EXPECTED COUNTS ────────────────────────────────────────────────────────
-- Before: `prescriptions` does not exist (introspected 2026-09-20 — 34 tables,
-- none of them this one). After: 0 rows. The first row arrives when the
-- founder pastes a block into You → Prescriptions.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 0 · Before ──────────────────────────────────────────────────────────────
-- If `exists` is already true the table is in place and §1 is a no-op.
SELECT to_regclass('public.prescriptions') IS NOT NULL AS prescriptions_exists;

-- ── 1 · The table ───────────────────────────────────────────────────────────
-- Column for column with `native/schema/supabase.json`, which generates the
-- GRDB mirror. The two must agree or `npm run check:mirror` is checking the
-- wrong shape.
--
-- NULLABILITY IS THE CONTRACT. A prescription that states a load and leaves
-- the count to the plan is a real prescription, and a fabricated `3` is a
-- claim — so everything but the identity, the version, the day and the two
-- enumerated words is nullable. `structure` and `lead_rule` are NOT NULL with
-- defaults because they have a meaningful default (`STRAIGHT`, `NONE`) and an
-- absent one would be indistinguishable from it.
CREATE TABLE IF NOT EXISTS public.prescriptions (
    id             uuid PRIMARY KEY,
    user_id        uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    exercise_key   text NOT NULL,
    version        integer NOT NULL,
    effective_from date NOT NULL,
    load_kg        numeric,
    sets           integer,
    rep_range      text,
    rpe_cap        numeric,
    structure      text NOT NULL DEFAULT 'STRAIGHT',
    set_loads      numeric[],
    lead_rule      text NOT NULL DEFAULT 'NONE',
    notes          text,
    created_at     timestamptz NOT NULL DEFAULT now()
);

-- The two enumerated columns, as CHECKs. `Prescription.Structure` and
-- `Prescription.LeadRule` are the Swift half; a value either side cannot
-- encode is a value that survives a round trip as something else.
ALTER TABLE public.prescriptions DROP CONSTRAINT IF EXISTS prescriptions_structure_check;
ALTER TABLE public.prescriptions
  ADD CONSTRAINT prescriptions_structure_check
  CHECK (structure IN ('STRAIGHT', 'TOPSET_BACKOFF'));

ALTER TABLE public.prescriptions DROP CONSTRAINT IF EXISTS prescriptions_lead_rule_check;
ALTER TABLE public.prescriptions
  ADD CONSTRAINT prescriptions_lead_rule_check
  CHECK (lead_rule IN ('ALTERNATE', 'LEFT', 'RIGHT', 'NONE'));

-- ONE VERSION PER MOVEMENT PER ATHLETE. This is what makes the append-only
-- rule enforceable rather than merely intended: a second `v3` for one movement
-- is refused by the database, so a client that lost track of the ladder cannot
-- write a duplicate ordinal and make "which instruction was in force"
-- ambiguous forever.
CREATE UNIQUE INDEX IF NOT EXISTS prescriptions_user_exercise_version
  ON public.prescriptions (user_id, exercise_key, version);

-- The read the resolver makes: every version of one movement, newest first.
CREATE INDEX IF NOT EXISTS prescriptions_user_exercise
  ON public.prescriptions (user_id, exercise_key, effective_from DESC, version DESC);

-- ── 2 · Row level security ──────────────────────────────────────────────────
-- The `(select auth.uid()) = user_id` INITPLAN form, so the check is evaluated
-- once per query rather than once per row, and `TO authenticated` — never
-- `TO public`, which is the shape that leaked in W11 and is the reason this
-- comment exists.
--
-- Every statement re-runnable: `drop policy if exists` before each `create`.
ALTER TABLE public.prescriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prescriptions_select_own ON public.prescriptions;
CREATE POLICY prescriptions_select_own ON public.prescriptions
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS prescriptions_insert_own ON public.prescriptions;
CREATE POLICY prescriptions_insert_own ON public.prescriptions
  FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS prescriptions_update_own ON public.prescriptions;
CREATE POLICY prescriptions_update_own ON public.prescriptions
  FOR UPDATE TO authenticated
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS prescriptions_delete_own ON public.prescriptions;
CREATE POLICY prescriptions_delete_own ON public.prescriptions
  FOR DELETE TO authenticated
  USING ((select auth.uid()) = user_id);

-- ── 3 · `daily_logs.hrv_overnight` — REPORTED, not created ──────────────────
-- Introspected live on 2026-09-20: it is already there, `boolean`, nullable,
-- no default. `v33.prescriptions` adds the local half. If the row below comes
-- back empty this database is not the one that was introspected — stop, and
-- say so, before the phone starts writing a column that does not exist.
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'daily_logs' AND column_name = 'hrv_overnight';

-- ── 4 · After ───────────────────────────────────────────────────────────────
-- `prescriptions_exists` must be true, `rls_enabled` must be true, and there
-- must be exactly FOUR policies, all of them `authenticated`.
SELECT to_regclass('public.prescriptions') IS NOT NULL AS prescriptions_exists;

SELECT relrowsecurity AS rls_enabled
  FROM pg_class WHERE oid = 'public.prescriptions'::regclass;

SELECT policyname, cmd, roles::text, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'prescriptions'
 ORDER BY policyname;

COMMIT;
-- ROLLBACK;   -- swap for COMMIT above if anything in §3 or §4 came back wrong
```

## w1-onyx-wire.sql — the server half of `v32.onyxWire` (Onyx Expansion W1, 7.0.0)

```sql
-- ════════════════════════════════════════════════════════════════════════════
-- w1-onyx-wire.sql — the server half of `v32.onyxWire` (Onyx Expansion, W1)
--
-- Paste into the Supabase SQL editor and run the whole file.
--
-- ── RUN THIS *BEFORE* 7.0.0 REACHES ANY DEVICE ─────────────────────────────
-- Not "either order". `v32.onyxWire` is a GRDB migration: the migrator records
-- it by name and NEVER runs it again. Nothing rewrites a row that arrives
-- afterwards. So if 7.0.0 installs and syncs before this file has run, every
-- `set_events` row pulled in that window keeps the old stamp permanently, and
-- that movement's history splits in two — which is the whole failure this
-- migration exists to prevent. (7.0.0 also strips an unrecognised stamp when
-- it resolves a slug, so a straggler degrades instead of jamming the outbox;
-- that is a safety net, not a substitute for running this first.)
--
-- ── v2 — WHAT CHANGED AFTER THE FIRST ATTEMPT ──────────────────────────────
-- The founder ran v1 and Postgres refused it:
--
--   ERROR: 23514: new row for relation "plan_phases" violates check
--   constraint "plan_phases_era_check"
--
-- `plan_phases.era` carries a CHECK constraint that allows `ppl` and the
-- predecessor's value and nothing else. The UPDATE was correct; the column
-- would not accept it. §1 now drops that constraint, rewrites the rows, and
-- puts an equivalent constraint back naming the two values `PhaseEra`
-- actually has. That is DDL, so §1 is the only part of this file that changes
-- the schema, and it changes it back to the same SHAPE it had.
--
-- The seven stored reports (§5) are now part of the transaction too, at the
-- founder's instruction: zero trace of the old name anywhere.
--
-- ── WHY NOTHING BELOW SPELLS THE OLD NAME ──────────────────────────────────
-- The point of the wave is that the predecessor's name is gone from every byte
-- of the repository, and this file lives in it. It does not need the name:
--   · `plan_phases.era` has exactly TWO values in the domain (`PhaseEra`), so
--     "not ppl" names the rows exactly.
--   · an exercise slug was stamped `<word><digit>-<kebab-name>`, so
--     `^[a-z]+[0-9]-` matches the old stamp, and a migrated slug already
--     starts `onyx-`.
--   · the reports' masthead is `⬢ <word> OS ·`, so the word between is
--     replaced by position.
-- The BODY after the first hyphen is never touched, so every movement keeps
-- its identity and only the stamp in front of it changes.
--
-- ── AND WHY A uuid IS EXCLUDED BY NAME, NOT BY ARGUMENT ────────────────────
-- A uuid's first hyphen is at position nine, so any uuid whose first seven hex
-- characters are all letters a–f and whose eighth is a digit — `abcdefa1-…` —
-- matches `^[a-z]+[0-9]-`. About one in 1,500, and `set_events.body` holds a
-- MIX of resolved uuids and unresolved slugs, so it is not a theoretical
-- column. Re-stamping one would point a synced set at a catalogue row that
-- does not exist.
--
-- ── THE TWO HALVES MUST DECIDE IDENTICALLY ─────────────────────────────────
-- `AppDatabase.onyxWireId` answers the same question on the phone. If these
-- two predicates disagree about one id, that movement is renamed on one
-- machine and not the other. Change one, change both;
-- `OnyxWireMigrationTests.matchesThePostgresPredicate` pins the Swift side to
-- the regex below, case for case.
--
-- ── WHAT IS DELIBERATELY NOT HERE ──────────────────────────────────────────
-- Introspected from the live database on 2026-09-19, before a line was written:
--
--   workout_sets.exercise_id     uuid, 2500 rows, 0 matches — a uuid column
--                                CANNOT hold a slug. The slug reaches the
--                                server only inside `set_events.body`, and
--                                `ExerciseIndex` resolves it to a uuid on push.
--   personal_records.exercise_key  text, 81 rows, 0 matches — it holds a
--                                canonical DISPLAY NAME ("Seated Cable Row
--                                (V-Grip)"), never an id. Renaming keys here
--                                would invent a second history per lift.
--   plan_phases.era_tag          text, 8 rows, 0 matches — re-read live on
--                                2026-09-19: already "Onyx Cut", "Onyx · Week
--                                0", "PPL Bulk". The app renders THIS column,
--                                not `era`, so it was worth checking twice.
--                                It needs nothing.
--
-- Expected row counts, same introspection:
--   plan_phases.era      4 of 8
--   exercises.slug      46 of 46   (every row)
--   set_events.body    116 of 787
--   reports.content_md   7 of 17
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 0 · Before ──────────────────────────────────────────────────────────────
-- Read these. If every "rows_to_change" is 0 the work is already done.
SELECT 'plan_phases.era'  AS target, count(*) AS rows_to_change
  FROM plan_phases WHERE era IS NOT NULL AND era NOT IN ('ppl', 'onyx')
UNION ALL
SELECT 'exercises.slug',   count(*)
  FROM exercises   WHERE slug ~ '^[a-z]+[0-9]-'
   AND slug !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
UNION ALL
SELECT 'set_events.body',  count(*)
  FROM set_events  WHERE body->'payload'->>'exercise_id' ~ '^[a-z]+[0-9]-'
   AND body->'payload'->>'exercise_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
UNION ALL
SELECT 'reports.content_md', count(*)
  FROM reports     WHERE content_md ~ '⬢\s*\w+\s+OS\s*·';

-- Every CHECK constraint on the four tables, so a second refusal like the one
-- that stopped v1 is visible here rather than as an aborted transaction.
SELECT conrelid::regclass AS "table", conname, pg_get_constraintdef(oid) AS definition
  FROM pg_constraint
 WHERE contype = 'c'
   AND conrelid IN ('public.plan_phases'::regclass, 'public.exercises'::regclass,
                    'public.set_events'::regclass,  'public.reports'::regclass)
 ORDER BY 1, 2;

-- ── 1 · plan_phases.era — the constraint, then the rows, then the constraint ─
-- THE ONLY DDL IN THIS FILE, and it is a replacement in kind: the column keeps
-- a CHECK that admits exactly the values `PhaseEra` can encode. `era` is
-- nullable and `PhaseDef.era` is Optional, so NULL stays admissible — absent
-- is not the same as an era, and rows that never claimed one must keep saying
-- so.
--
-- `IF EXISTS` so a re-run after a partial attempt does not fail on the drop.
ALTER TABLE plan_phases DROP CONSTRAINT IF EXISTS plan_phases_era_check;

UPDATE plan_phases
   SET era = 'onyx'
 WHERE era IS NOT NULL
   AND era NOT IN ('ppl', 'onyx');

ALTER TABLE plan_phases
  ADD CONSTRAINT plan_phases_era_check
  CHECK (era IS NULL OR era IN ('ppl', 'onyx'));

-- ── 2 · exercises.slug ──────────────────────────────────────────────────────
-- The catalogue's alias column — the map `ExerciseIndex.id(forSlug:)` resolves
-- a phone-stamped set through. All 46 rows carry the old stamp. This must
-- land, or a set logged on 7.0.0 finds no catalogue row.
UPDATE exercises
   SET slug = 'onyx-' || substring(slug from position('-' in slug) + 1)
 WHERE slug ~ '^[a-z]+[0-9]-'
   AND slug !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- ── 3 · set_events.body → payload → exercise_id ─────────────────────────────
-- The append log. The id is nested at `body.payload.exercise_id`; there is no
-- top-level `payload` column on this table (`routines.payload` and
-- `routine_templates.payload` are different tables and are not touched).
--
-- This cannot be skipped if §2 ran: any edit to a session reprojects it FROM
-- THIS LOG, so a log left on the old stamp would undo the projection and file
-- half a session under each name.
UPDATE set_events
   SET body = jsonb_set(
         body,
         '{payload,exercise_id}',
         to_jsonb('onyx-' || substring(
             body->'payload'->>'exercise_id'
             from position('-' in body->'payload'->>'exercise_id') + 1
         ))
       )
 WHERE body->'payload'->>'exercise_id' ~ '^[a-z]+[0-9]-'
   AND body->'payload'->>'exercise_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- ── 4 · reports.content_md — the seven stored reports ───────────────────────
-- Included at the founder's instruction (2026-09-19): zero trace anywhere.
--
-- These are DOCUMENTS, not identity values — nothing keys on them, and
-- `fmtV2.parseHeader` takes a report's title by POSITION, so they rendered
-- correctly either way. This is an archive decision, not a correctness fix,
-- and it rewrites seven historical documents to say something they did not say
-- when they were generated.
--
-- Structural, like everything above: it replaces the word between `⬢ ` and
-- ` OS ·` on the masthead, whatever that word is, and touches nothing else in
-- the body. `\w+` cannot cross the spaces around it, so a report body that
-- happens to contain the word elsewhere is untouched — only the masthead
-- matches the full `⬢ … OS ·` shape.
UPDATE reports
   SET content_md = regexp_replace(content_md, '(⬢\s*)\w+(\s+OS\s*·)', '\1ONYX\2', 'g')
 WHERE content_md ~ '⬢\s*\w+\s+OS\s*·';

-- ── 5 · AFTER ───────────────────────────────────────────────────────────────
-- Every number must be 0. If one is not, do NOT commit — ROLLBACK and say so.
SELECT 'plan_phases.era'  AS target, count(*) AS rows_left
  FROM plan_phases WHERE era IS NOT NULL AND era NOT IN ('ppl', 'onyx')
UNION ALL
SELECT 'exercises.slug',   count(*)
  FROM exercises   WHERE slug ~ '^[a-z]+[0-9]-'
   AND slug !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
UNION ALL
SELECT 'set_events.body',  count(*)
  FROM set_events  WHERE body->'payload'->>'exercise_id' ~ '^[a-z]+[0-9]-'
   AND body->'payload'->>'exercise_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
UNION ALL
SELECT 'reports.content_md', count(*)
  FROM reports     WHERE content_md ~ '⬢\s*\w+\s+OS\s*·'
   AND content_md !~ '⬢\s*ONYX\s+OS\s*·';

-- And the constraint is back, admitting exactly the two values and NULL.
SELECT conname, pg_get_constraintdef(oid) AS definition
  FROM pg_constraint
 WHERE conrelid = 'public.plan_phases'::regclass AND conname = 'plan_phases_era_check';

COMMIT;
-- ROLLBACK;   -- swap for COMMIT above if any "rows_left" came back non-zero
```
