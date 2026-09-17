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
  `native/README.md` says where those files went. The remaining `helix`
  strings are load-bearing data, not branding: the `"helix"` era wire value,
  the `helix.week/1` schema tag, the legacy App Group and sqlite names the
  one-time store move reads, the `helix_*` preference fallbacks, and the
  founder's plan and era labels in the golden fixtures.

### One movement, one id

- **The logger writes the catalogue's id.** A set logged on the phone used to
  carry `helix5-<name-slug>` while the same movement pulled from the server
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
