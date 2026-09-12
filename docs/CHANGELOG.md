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

## [3.0.0] — 2026-09-12 · The Web App Is Gone

Onyx is one app now. The Helix web app — the Next.js dashboard, logger and
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
  `native/README.md` says where those files went. The load-bearing `helix`
  strings stay, on purpose: the `helix5-` exercise-id prefix, the `"helix"`
  era wire value, the `helix.week/1` schema tag, the legacy App Group and
  sqlite names the one-time store move reads, the `helix_*` preference
  fallbacks, the founder's plan and era labels in the golden fixtures, and the
  Netlify host name.
- `README.md` describes the native-only repo; the `native` and `ship` skills
  say the same.

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
  catalogue uuid from the web beside a `helix5-` slug from the phone, which
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
- Legacy `helix5-…` set ids resolve through `exercises.slug` (data), not through
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
  phone now counts towards its muscles. Phone-logged sets carry `helix5-` slug
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
  `helix5-treadmill`. `WarmupCardio` is deliberately outside `Program.onyx5`, so
  the slug the deck stamps on the bout was in no name table and the page fell
  back to printing the key. The same one-line miss meant a treadmill logged on
  the phone threw `unknownExercise` on push and could not be uploaded at all —
  the one movement the deck adds for you was the one the sync refused. The
  `helix5-` prefix itself stays: it is a key written into local rows, and
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
- Helix web app: dashboard, logger, nutrition, trends, reports, PWA.

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
