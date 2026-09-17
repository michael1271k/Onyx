# UX/UI Refinement Sprint — compaction, comparison, and the Library

**Status:** approved 2026-09-17 · step 0 done (this file). W1 next.
**From:** `main` @ 3.19.0 (`903e4181`).
**Ships as:** three sequential waves, 3.20.0 → 3.21.0 → 3.21.1. **W3 deletes this file.**
**Branches:** `onyx/refinement-ux-w<N>`, each cut from current `main` and merged `--no-ff`
back into it, then deleted. There is no long-lived sprint branch — `main` is the only
trunk (`docs/GIT.md`).
**Model for every wave:** Opus 5 (Extra High Effort). This is not optional and does not
change between waves.

---

## Context

Six briefs across three surfaces: the post-workout summary, the exercise card, and the
Train tab's Past Weeks list. The sprint exists because the session page has grown to
fourteen figures before the first exercise, and an exercise card spends ~74 pt on wrapped
chips against ~36 pt per set — the reader scrolls a screen per movement.

Exploration measured every brief against the source before this plan was written, and
**six of them name a symptom whose cause sits somewhere else.** The waves below are
written against what the code does.

| Brief | What is actually true |
|---|---|
| "Delta arrows sit BELOW the set metrics, creating an ugly empty row" | There is no row. `SessionDetailView.swift:2132` `column(_:)` is `VStack{ value; deltaLine }` — each delta is the second line **of its own column**, and three of them align into what looks like a row. The line is reserved on purpose (`Text("—").hidden()`, `:2185`) so a card cannot change height between sessions. The waste is 11 pt × N sets on cards with **no previous session at all**. |
| "Tags take up 3 cluttered rows" | They are already **one** `FlowRow` (`:1110`) — muscle chips then reading capsules. The three rows are wraps, and the wrap point moves with text size. Primary vs secondary is only tint/opacity (`:1203`); there is no grouping and nothing to collapse. |
| "Reduce the mini-graph height by a few pixels" | `Sparkline` is `40×16` (`:1071`) inside the header HStack beside the exercise name, whose line box is ~22 pt. 16 → 12 buys **0 pt**. |
| "Merge identical L/R sets into one row" | `SetPairLayout.resolve(weights:reps:rpes:)` already implements exactly the three cases asked for (`OnyxCore/Exercises/Unilateral.swift`). Only the **logger** consumes it, and `.unified` was deliberately killed for completed pairs on 2026-09-11 because a merged row left no way to rate one side. |
| "Sept 10 pushdown is missing the right-side RPE" | Not a bug — a reachable state. `workout_sets.rpe` is nullable by design (`AppDatabase.swift:598` — "an unrated set must stay distinguishable from a set rated zero"). `ExerciseCardView.swift:1803` `compactEffort` calls `onEffort([side])` with **one row**, and `SetPatch` cannot write null back (`SetEvent.swift:465`). Rate L, skip R, and R is null permanently. Nothing in the repo backfills it. |
| "Number past weeks correctly and colour them by phase" | Numbering already exists — `Week.label(ofWeekStart:anchor:phases:)` returns `"Week 3"`, and `Phases.enumerateWeeks(kinds:in:)` returns `[ProgramWeek]` newest-first with `n`, `label`, `eraTag`, `era`, `kind`. `WorkoutWeek.swift:816` never calls it, and hand-rolls `"Week of Sun 6 Sep"` instead. **Colours do not exist:** `Color.onyx.phase()` takes `ProgramPhase` (cut/bulk) while `PhaseKind` has four cases. |

Two more facts the waves are built on:

- The Train root has **no `.toolbar` at all** (`WorkoutTabView.swift:206` is
  `navigationTitle` + `navigationBarTitleDisplayMode` + a bottom `safeAreaInset`). The
  only `.toolbar` in that file lives inside the `$reviewing` sheet. The Library button is
  net-new chrome.
- `WeeklyWrapContent.stat()` (`WeeklyWrapView.swift:219`) and `SessionDetailView.cell()`
  (`:564`) are near-duplicate square primitives — micro label, `.display` numeral, delta
  line — differing only in whether they wear `.onyxGlass(.row)`.

### Founder decisions (2026-09-17)

1. **Deltas stay per-column.** The reserved blank line is dropped **at card level** when a
   card has no previous session; within a card the height still never changes. Moving the
   arrows to the row's right edge was rejected: a `+4` at the trailing edge cannot say
   whether load or reps moved.
2. **Tags swap in place.** Tapping the primary muscle turns row 2 into the secondary
   muscles; Volume/Top/RPE hide while open. The card height never changes.
3. **Volume becomes the hero.** It moves into `SessionHeaderCard`; the 3-up and 4-up grids
   collapse into one 3×2 grid of Duration · Sets · Difficulty · Records · Avg HR · Calories.
   One hero per screen, and the 3/4 column seam goes with it.
4. **Unilateral merge is ledger-only.** `SessionDetailView` honours all three
   `SetPairLayout` cases; the logger keeps its 2026-09-11 rule untouched, because the dead
   end that rule exists to prevent is an *editing* dead end and the ledger is read-only.
5. **`Color.onyx.phase` learns four cases** — cut = fuel accent, bulk = `good`,
   peak = `record`, deload = recover accent.
6. **Library is grouped by phase block**, one section header per `plan_phases` block,
   weeks newest-first inside it, no 8-week cap.
7. **Missing RPE: show it and stop the leak.** The ledger prints `L 8 · R —` in tertiary
   ink; in the logger, rating one side pre-fills the sibling side (editable), the way
   `splitSet` already copies `rpe` into both halves (`LoggerModel.swift:1355`). Sept 10's
   row stays null until it is edited by hand — **no historical write invents a rating**,
   and no DDL runs from this machine.
8. **Both extras ship** — the zoom transition out of the tapped card, and the
   sparkline-backed metric squares.

---

## Wave 1 — Train Library & unilateral logic (data & structure) · 3.20.0

**Branch:** `onyx/refinement-ux-w1`, cut from current `main`.

### Tasks

**A · `PhaseKind` gets a colour.** Add `Color.onyx.phase(_ kind: PhaseKind)` beside the
existing `phase(_ ProgramPhase)` in
`native/Packages/OnyxUI/Sources/OnyxUI/DesignSystem/OnyxTokens.swift:395` —
cut → `OnyxDomain.fuel.accent`, bulk → `good`, peak → `record`, deload →
`OnyxDomain.recover.accent`. Keep the two-case overload; nothing that calls it changes.
`TokenDisciplineTests` must stay green (no raw hex).

**B · The Library sheet.** New `native/Onyx/Features/Workout/PastWeeksLibrary.swift`:

- `PastWeeksLibrary` — `NavigationStack` + `.presentationDetents([.large])`, following the
  sheet template at `native/Onyx/Features/Logger/PhaseSheet.swift:24-51`.
- Sections from `Phases.enumerateWeeks(_:in:)` over `ctx.phases`, grouped by the
  `PhaseDef` block that owns each week; header = `eraTag` + phase name + date range.
- `WeekBannerCard` — built from `SessionHeaderCard`'s vocabulary
  (`native/Onyx/Features/History/SessionHeaderCard.swift:68`): hero week label + date
  range on one `Shoulders` baseline, `MuscleTagRow` of the week's families, a totals line,
  and the 22 %→0 / 72 pt top wash (`sessionDayWash`, `:332`) tinted by
  `Color.onyx.phase(week.kind)` instead of the day hue. `.onyxGlass(.tile)`,
  `.onyxPress(scale: 0.98)`.
- Tapping a banner opens the existing `WeeklyWrapView` sheet. Do **not** build a second
  week summary.

**C · Relocate it.** In `native/Onyx/Features/Workout/WorkoutTabView.swift`:

- Add the Train root's first `.toolbar` (`:206`) — a trailing `books.vertical.fill` button
  presenting `PastWeeksLibrary`.
- Delete `pastWeeksSection` (`:1119`), `pastWeekRow` (`:1140`), and the
  `expandedWeek`/`loadExpandedWeek` machinery that only served them (`:66`, `:1133`).
- `TrainLayout.pastWeeks` (`OnyxCore/Dashboard/TrainLayout.swift:41`) becomes the
  **button's** visibility gate so Customize keeps working; do not remove the case.

**D · Real week labels.** `native/Onyx/Features/Workout/WorkoutWeek.swift:803-827`:
replace `"Week of \(Swap.shortDayLabel(start))"` (`:816`) with
`Week.label(ofWeekStart:anchor:phases:)` and carry the date range as the subtitle. Drop
the `pastWeekCount = 8` cap (`:790`) for the library's query; keep the walk's
`Schedule.isPlannable` break, which is what stops it walking into pre-plan weeks.

**E · Unilateral merge, ledger only.** In
`native/Onyx/Features/History/SessionDetailView.swift`, `SetRow` (`:1687`):

- Call `SetPairLayout.resolve(weights:reps:rpes:)` per pair row instead of hardcoding two
  lines at `pairLines` (`:2202`).
- `.unified` → render as an ordinary `.loaded` row: no L/R, no `sideTrack`, one value
  line, one effort figure.
- `.valueSplit` with equal RPE → two value lines, **one** effort glyph vertically centred
  against the pair. The effort column is already a separate trailing view (`:1953`); it
  needs `.center` rather than inheriting the row's `.top`.
- `.valueSplit` / `.effortSplit` with differing RPE → `L 8 · R 9`.
- A nil side renders `—` in `Color.onyx.textTertiary`, never a blank: `L 8 · R —`.
- `SetRow.layout(_:)` (`:1857`) makes the whole card `.pair` if **any** row is a pair
  (`:1870`) — that stays; the merge decision is per row.
- Volume, set counts and `unitDelta` are untouched. `SessionVolume.sessionVolumeKg`
  already scores a pair once at the weaker side; nothing here may change a number.

**F · Stop the RPE leak.** `native/Onyx/Features/Logger/ExerciseCardView.swift:1783`
`effort(_:)` / `:1803` `compactEffort`: when a rating is written to one side of a pair and
the sibling row's `rpe` is nil, pre-fill the sibling with the same value and commit it
(`model.commitEdit`). It stays editable — this mirrors `splitSet`
(`LoggerModel.swift:1355`), which already copies `rpe` into both halves. **No historical
backfill, no SQL.** Sept 10's row is repaired by editing that session.

**G · Shots and tests.** New preview screens `train-library` and `train-library-open` in
`native/Onyx/App/PreviewCatalogue.swift` (+ the Workout previews file); new
`session-pairs-merged` in `native/Onyx/Features/History/HistoryPreviews.swift:83`. Extend
`native/OnyxTests/UnilateralAndQualityTests.swift` with the three-case ledger mapping and
the nil-side render, and `PreviewCatalogueTests.swift` with the new screens.

### The prompt to run Wave 1

```
Execute Wave 1 of docs/UX_UI_REFINEMENT_SPRINT.md — "Train Library & unilateral logic".
Model: Opus 5 (Extra High Effort). Auto Mode.

Read docs/UX_UI_REFINEMENT_SPRINT.md first and follow its Wave 1 section exactly,
including the founder decisions above it. Branch onyx/refinement-ux-w1 from current main.

GOAL
Move Past Weeks off the Train tab into a Library sheet of phase-tinted week banners, and
make the session ledger tell the truth about unilateral pairs — including the sides that
were never rated.

TASKS
A. Add Color.onyx.phase(_ kind: PhaseKind) to OnyxTokens.swift:395 (cut=fuel accent,
   bulk=good, peak=record, deload=recover accent). Keep the ProgramPhase overload.
B. New native/Onyx/Features/Workout/PastWeeksLibrary.swift — a .large sheet, sections from
   Phases.enumerateWeeks grouped by plan_phases block, each week a WeekBannerCard built
   from SessionHeaderCard's vocabulary (hero label, MuscleTagRow, totals line, 72pt top
   wash tinted by the phase). Tapping a banner opens the EXISTING WeeklyWrapView.
C. WorkoutTabView.swift: add the Train root's first .toolbar with a trailing
   books.vertical.fill button presenting the library; delete pastWeeksSection (:1119),
   pastWeekRow (:1140) and the expandedWeek machinery; repoint TrainLayout.pastWeeks at
   the button's visibility.
D. WorkoutWeek.swift:816 — use Week.label(ofWeekStart:anchor:phases:) instead of
   "Week of <shortDayLabel>"; drop the 8-week cap for the library query.
E. SessionDetailView SetRow: consume SetPairLayout.resolve and honour all three cases in
   the LEDGER ONLY (.unified = one ordinary row; .valueSplit with equal RPE = two value
   lines and ONE vertically centred effort glyph; differing RPE = "L 8 · R 9"). A nil side
   renders "—" in textTertiary. Do NOT change the logger's 2026-09-11 rule, and do not
   change any volume or set-count arithmetic.
F. ExerciseCardView effort(_:)/compactEffort: rating one side of a pair pre-fills the
   sibling side's nil rpe with the same value, editable, committed via model.commitEdit.
   No backfill, no SQL, no historical write.
G. Add preview screens train-library, train-library-open, session-pairs-merged; extend
   OnyxTests/UnilateralAndQualityTests.swift and PreviewCatalogueTests.swift.

SKILLS: native, apple-design, ui-design-system, supabase-postgres-best-practices, graphify
AGENTS: ios-developer, swift-expert, architect-reviewer, invariant-auditor, debugger

CONSTRAINTS
- Tokens only. TokenDisciplineTests fails the build on a raw hex.
- graphify query before grepping; graphify update . before the merge commit.
- Never hand-edit Onyx.xcodeproj — cd native && xcodegen generate.
- Pass SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-refinement-w1 on every shot run.

GATE (all of it, and paste the output)
  npm run check
  npm run check:swift && npm run swift:core && npm run swift:data
  cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-refinement-w1 \
    scripts/native-shot.sh "train train-library train-library-open session-pairs session-pairs-merged"
Review every screenshot before claiming the wave is done. OnyxTests has 4 pre-existing
failures on main — name them, do not fix them, do not let them hide a new one.

CLOSE
Bump package.json to 3.20.0, npm run version:sync, cd native && xcodegen generate, append
the 3.20.0 release section to docs/CHANGELOG.md, confirm npm run version:check passes.
Append a Wave Record to docs/UX_UI_REFINEMENT_SPRINT.md. Merge --no-ff to main, delete the
branch, push with [skip ci].
```

---

## Wave 2 — Exercise card compaction & post-workout polish · 3.21.0

**Branch:** `onyx/refinement-ux-w2`, cut from `main` **after** W1 merges.

### Tasks

**A · One grid, one hero.** `SessionDetailView.metrics(_:)` (`:461`): delete the 3-up
(`:464`) and 4-up (`:494`) grids and build a single `LazyVGrid(columns: columns(3))` of
Duration · Sets · Difficulty · Records · Avg HR · Calories. `columns(_:)` (`:533`) already
collapses to one column at accessibility sizes. Volume moves into `SessionHeaderCard`
(`SessionHeaderCard.swift:68`) as the hero figure with its delta —
`.onyxType(.hero).onyxNumeral()`, which already carries
`contentTransition(.numericText())`, so the number counts up on arrival.
`IntensityBar` (`:530`) stays, now under one grid instead of between two.

**B · Sparkline squares.** `cell(_:_:_:sub:tint:symbol:)` (`:564`): replace the reserved
second text line with an 8-week `Sparkline` (`OnyxPrimitives.swift:359`) behind the value
at low opacity, same cell height. Move the `basis` / `bpmBasis` restatements (`:679`,
`:688`) out of the visible line and into the `.accessibilityLabel`. `composition` (`:661`)
and `delta` (`:646`) keep their ink.

**C · Delete a duplicate.** `WeeklyWrapContent.stat()` (`WeeklyWrapView.swift:219`) and
`cell()` are the same primitive. Promote one into `OnyxUI` and delete the other.

**D · The muscle card says it once.** `muscles(_:)` (`:736`) encodes one fact three ways —
`AtlasFigure` (`:754`), the 100 % `ramp` (`:785`) and the top-4 `legend` (`:803`). Delete
the ramp; keep figure + legend.

**E · Tags become two deterministic rows.** `ledgerHeader` (`:996`): replace the `FlowRow`
(`:1110`) with a fixed two-row structure.

- Row 1: primary muscle chip (tappable, `+2` counter) · progression % · target goal.
- Row 2: Volume · Top · RPE.
- Tapping the primary muscle **swaps row 2 in place** for the secondary muscles —
  Volume/Top/RPE hide, the card height never changes. Animate with `OnyxMotion.move`; the
  disclosure idiom is the one at `WeeklyWrapView.swift:400` (label + "+N more" count,
  44 pt min height, `accessibilityHint`).
- **Token floor:** `OnyxType.micro` (11) forbids carrying a number in as many words, so
  chip *labels* may go `.micro` and values stay `.caption` (13). Do not invent a role.
- `MetaTagRow.Capsule` (`MetaTagRow.swift:86`) is the chip. `FlowRow`
  (`ExerciseDetailView.swift:445`) survives for its other callers.

**F · Deltas collapse per card.** `column(_:)` (`:2132`) / `deltaLine` (`:2154`): when no
row on the card has a previous set, reserve nothing. Within a card the reservation is
unchanged, so the height still cannot move between two sessions. `upIsGood: false` on RPE
(`:2101`) stays — up is harder, harder is not better.

**G · The sparkline earns its width.** `:1071` — `Sparkline` goes `40×16` → `56×16` and
moves to the trailing edge of tag row 1, off the name's line. The height does not change,
because it never cost anything.

**H · Zoom out of the card.** `WorkoutTabView.swift:611` done-card gets
`.matchedTransitionSource(id:in:)` and `SessionDetailView` gets
`.navigationTransition(.zoom(sourceID:in:))` — the pattern already shipping at
`MiniPlayerCard.swift:38`. Same treatment for a library banner opening its week. Enter and
exit travel the same path, which is the rule the sprint's spatial consistency rests on.

### The prompt to run Wave 2

```
Execute Wave 2 of docs/UX_UI_REFINEMENT_SPRINT.md — "Exercise card compaction &
post-workout polish". Model: Opus 5 (Extra High Effort). Auto Mode.

Read docs/UX_UI_REFINEMENT_SPRINT.md first and follow its Wave 2 section exactly.
Branch onyx/refinement-ux-w2 from current main (W1 must already be merged).

GOAL
Cut the session page from fourteen figures to seven, and the exercise card from ~74pt of
wrapped chips to two deterministic rows — without losing a single comparison.

TASKS
A. SessionDetailView.metrics(:461): delete the 3-up and 4-up grids, build ONE 3x2 grid
   (Duration, Sets, Difficulty, Records, Avg HR, Calories). Volume moves into
   SessionHeaderCard as the hero figure with its delta. IntensityBar stays under it.
B. cell(:564): replace the reserved second text line with a low-opacity 8-week Sparkline
   behind the value, same height. Move basis/bpmBasis (:679,:688) into accessibilityLabel.
C. WeeklyWrapContent.stat() (WeeklyWrapView.swift:219) and cell() are one primitive —
   promote one into OnyxUI and delete the other.
D. muscles(:736): delete the 100% ramp (:785). Keep AtlasFigure + legend.
E. ledgerHeader(:996): replace the FlowRow (:1110) with two fixed rows — row 1 primary
   muscle chip (tappable, +N counter) / progression % / target goal; row 2 Volume / Top /
   RPE. Tapping the primary muscle SWAPS ROW 2 IN PLACE for the secondary muscles; the
   card height must not change. OnyxMotion.move. Chip labels may be .micro; values stay
   .caption — OnyxType.micro may never carry a number.
F. column(:2132)/deltaLine(:2154): reserve NO delta line when no row on the card has a
   previous set. Unchanged within a card. RPE keeps upIsGood: false.
G. Sparkline at :1071 goes 40x16 -> 56x16 and moves to the trailing edge of tag row 1.
H. Add .matchedTransitionSource to the Train done-card (WorkoutTabView.swift:611) and
   .navigationTransition(.zoom) to SessionDetailView, the MiniPlayerCard.swift:38 pattern.
   Same for a library banner opening its week.

SKILLS: apple-design, frontend-design, ui-ux-pro-max, ui-design-system, native, graphify
AGENTS: ui-ux-designer, ios-developer, swift-expert, code-reviewer, architect-reviewer

CONSTRAINTS
- Tokens only; TokenDisciplineTests fails on raw hex. No new spacing or type values.
- Every layout claim is verified by a screenshot, not by reasoning. ViewThatFits cannot
  stack a flexible child; check AX5 on every screen you touch.
- graphify query before grepping; graphify update . before the merge commit.
- Pass SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-refinement-w2 on every shot run.

GATE (all of it, and paste the output)
  npm run check
  npm run check:swift && npm run swift:core && npm run swift:data
  cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-refinement-w2 \
    scripts/native-shot.sh "session session-ledger session-records session-pairs session-cardio train train-done"
Review every screenshot at default type AND at AX5 before claiming the wave is done.

CLOSE
Bump package.json to 3.21.0, npm run version:sync, cd native && xcodegen generate, append
the 3.21.0 release section to docs/CHANGELOG.md, confirm npm run version:check passes.
Append a Wave Record to docs/UX_UI_REFINEMENT_SPRINT.md. Merge --no-ff to main, delete the
branch, push with [skip ci].
```

---

## Wave 3 — Cleanup & execution protocol · 3.21.1

**Branch:** `onyx/refinement-ux-w3`, cut from `main` **after** W2 merges.

### Tasks

1. Merge any logic left open by W1/W2; close every `ponytail:` marker either wave left, or
   promote it into the changelog as a named ceiling.
2. Harvest both Wave Records into `docs/CHANGELOG.md` (3.21.1) and into a memory file at
   `~/.claude/projects/-Users-michael-Documents-PyCharmProjects-Onyx/memory/`, with a
   one-line pointer added to `MEMORY.md`. Record the six corrected premises, not the task
   list.
3. **Delete `docs/UX_UI_REFINEMENT_SPRINT.md`.**
4. Delete every `onyx/refinement-ux-*` branch, local and remote.
5. Purge the wave caches: `$HOME/Library/Caches/onyx-swift/shot-refinement-w1`, `…-w2`,
   `…-w3`, and any `.claude/worktrees/refinement-ux-*`.
   `native/__screenshots__/` is gitignored and no gate reads it — leave it.
6. `graphify update .`, then the full gate, then the version bump and push.

### The prompt to run Wave 3

```
Execute Wave 3 of docs/UX_UI_REFINEMENT_SPRINT.md — "Cleanup & execution protocol".
Model: Opus 5 (Extra High Effort). Auto Mode.

Read docs/UX_UI_REFINEMENT_SPRINT.md first. Branch onyx/refinement-ux-w3 from current main
(W1 and W2 must already be merged).

GOAL
Close the sprint: merge what is left, harvest the record, and leave no artefact behind.

TASKS
1. Merge any logic W1 or W2 left open. Grep for `ponytail:` markers added by either wave
   and either close them or move them into the changelog as known ceilings.
2. Harvest both Wave Records into docs/CHANGELOG.md as the 3.21.1 section, and into a new
   memory file under
   ~/.claude/projects/-Users-michael-Documents-PyCharmProjects-Onyx/memory/ with a
   one-line pointer in MEMORY.md. Record the six corrected premises, not the tasks.
3. Delete docs/UX_UI_REFINEMENT_SPRINT.md.
4. Delete all onyx/refinement-ux-* branches, local and remote.
5. Purge the wave caches:
     rm -rf "$HOME/Library/Caches/onyx-swift/shot-refinement-w1" \
            "$HOME/Library/Caches/onyx-swift/shot-refinement-w2" \
            "$HOME/Library/Caches/onyx-swift/shot-refinement-w3"
     rm -rf .claude/worktrees/refinement-ux-*
   Leave native/__screenshots__/ alone — it is gitignored and no gate reads it.
6. graphify update .

SKILLS: native, graphify, code-reviewer
AGENTS: architect-reviewer, code-reviewer, debugger

GATE (all of it, and paste the output)
  npm run check
  npm run check:swift && npm run swift:core && npm run swift:data
  cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

CLOSE
Bump package.json to 3.21.1, npm run version:sync, cd native && xcodegen generate, confirm
npm run version:check passes, then:

  git checkout main
  git merge --no-ff onyx/refinement-ux-w3 -m "chore(sprint): close the UX/UI refinement sprint — 3.21.1 [skip ci]"
  git branch -d onyx/refinement-ux-w1 onyx/refinement-ux-w2 onyx/refinement-ux-w3
  git push origin --delete onyx/refinement-ux-w1 onyx/refinement-ux-w2 onyx/refinement-ux-w3 2>/dev/null || true
  git add -A
  git commit -m "chore(sprint): purge the sprint plan and wave caches — 3.21.1 [skip ci]"
  git push origin main

Confirm `git status` is clean and `git branch -a` shows only main before reporting done.
```

---

## Verification — every wave, in this order

A green package build **hides a broken app target** (memory: `xcodeproj-drift-and-swift6`),
so the `xcodebuild` line is not optional.

```bash
npm run check                  # atlas + doms + mirror + version
npm run check:swift            # OnyxUI + OnyxCore cross-build
npm run swift:core             # golden vectors
npm run swift:data
cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-refinement-w<N> \
  scripts/native-shot.sh "<screens>"
```

Layout needs eyes. W1 shoots `train train-library train-library-open session-pairs
session-pairs-merged`; W2 shoots `session session-ledger session-records session-pairs
session-cardio train train-done`, **at default type and at AX5**.

**Known-bad baseline.** `OnyxTests` carries four pre-existing failures on `main`
(memory: `auto-fixes-w7`). Name them in each wave record; do not fix them in this sprint,
and do not let them mask a new one.

**Numbers that must not move.** `SessionVolume.sessionVolumeKg` scores a unilateral pair
once at the weaker side, `set_count` folds on `pair_id`, and the PR engine's golden
vectors are pinned. W1's merge is a rendering change only — if any total shifts, the merge
is wrong.

---

## Wave Records

_Each wave appends its record here before merging. W3 harvests them, then deletes this
file._

## W1 — Train Library & unilateral logic · 3.20.0

**Shipped:** 2026-09-17 · `<merge sha>`

**What changed.** A · `Color.onyx.phase(_ kind: PhaseKind)` beside the
`ProgramPhase` overload — cut/bulk keep their ink, `peak` takes `record`,
`deload` takes Recover's accent, no new hex. B · `PastWeeksLibrary.swift`: a
`.large` sheet of `WeekBannerCard`s, sections from `Phases.enumerateWeeks`
grouped by the `PhaseDef` that `Phases.span` says owns each week, each banner
built from `SessionHeaderCard`'s vocabulary and washed in its phase's colour.
Tapping one opens the existing `WeeklyWrapView`. C · The Train root's first
`.toolbar`, a trailing `books.vertical.fill` gated on `TrainSection.pastWeeks`;
`pastWeeksSection`, `pastWeekRow`, `expandedWeek`, `seedApplied`,
`pastSummaries`, `loadExpandedWeek` and `seededExpandedWeek` all deleted (108
lines). D · `PastWeek.label` is `Week.label(ofWeekStart:anchor:phases:)`, with
`WeekWindow.rangeLabel` as the subtitle; the 8-week cap is replaced by
`pastWeekCeiling = 520`, a loop guard rather than a window. E · `SetRow`
consumes `SetPairLayout.resolve` and honours all three cases in the ledger only.
F · `SetRowView.effortTargets(tapping:in:)` carries an unrated sibling into the
picker with the tapped side. G · `train-library`, `train-library-open`,
`session-pairs-merged`, five new tests.

**What the brief got wrong — and the four things it could not have known.**

1. **The Train tab already has a door called "Library" and it is the EXERCISE
   catalogue** (`ExerciseLibraryView`, in the doors row, under a
   `books.vertical` glyph). The sheet is titled **Past Weeks** for that reason.
   The `books.vertical.fill` button was built as the brief names it, but the
   two affordances now share a glyph family on one screen — **a founder call is
   open here**: keep the book, or give the toolbar `calendar` back.
2. **`resolve` never returns `.unified` for a two-row pair** — its own guard
   makes `.unified` the answer for a group of ONE. So the brief's ".unified →
   an ordinary row" is the one-sided pair, and the MERGE the brief is actually
   about is `.effortSplit` with both ratings equal. The ledger maps: values
   agree + ratings agree → one line, one word; values agree + ratings differ →
   one line, `L 8 · R 9`; values differ → two lines, with one centred glyph
   when the ratings agree.
3. **`resolve` cannot see a cardio pair.** It reads load, reps and effort, and
   two treadmill sides both store `weight_kg 0, reps 0` — so the rule alone
   would merge two bouts of different lengths into one line printing one of
   them. `SetRow.splitsValues` therefore also asks whether the two sides render
   the same string. Pinned by a test.
4. **The wrap-up sheet had its own `Week of Sun 16 Aug`**
   (`WeeklyWrapContent.title`), so a shelf saying `Week 5` opened a sheet that
   disagreed with it — the exact invariant `PastWeek.label`'s old comment
   existed to protect, one layer down. `WeeklyWrapView` took an optional
   `title:`; every other caller is byte-identical.
5. **The fixture could not photograph the wave.** Every pair in
   `HistoryPreviews` is `(5, r)` against `(5, r − 1)` with no rating at all —
   all `valueSplit`, none rated — so two of the three cases were unphotographable
   and editing a rep would have moved a tonnage three other shots are pictures
   of. A new session `s-2026-07-15` (`HistoryPreviews.pairShapes`) carries one
   of each shape. Dated inside `Week 0 · Transition` on purpose: before every
   other session, so no photographed week's totals move, and in a PEAK block, so
   the shelf has a second phase colour to prove its sections are sections.

**Numbers that did not move.** `SessionVolume.sessionVolumeKg`, `set_count` and
the PR golden vectors are untouched; the merge is a rendering change and a test
asserts the fixture's tonnage is scored once per pair at the weaker side.

**Seams left for W2.** (a) The `books.vertical.fill` collision above. (b) The
This-week tile and History still open the wrap-up under its date name — only the
shelf passes a `title:`; a wave that gives `WeeklyWrap.Summary` an anchor closes
it everywhere. (c) `session-pairs` is shot parked at the ledger HEAD, so its own
pair card is below the fold and always has been; the pair table is reviewed from
`session-pairs-merged`. (d) The block-header dot is `record` gold for peak and
`fuel` accent for cut, two warm hues a few degrees apart — legible as a grouping,
weak as a distinction.

**Gate.** `npm run check` ✔ · `check:swift` ✔ · `swift:core` 565 ✔ ·
`swift:data` 568 ✔ · `xcodebuild` app target ✔ · shots ✔ (reviewed at default
type and AX5; two AX5 defects found and fixed — the section header wrapped
`ONYX / CUT` beside a truncated range, now `Shoulders`; the totals line
truncated `5,350…`, now `lineLimit(2)`).

**OnyxTests: FIVE pre-existing failures, baselined on `main` at `903e4181` in a
throwaway worktree and identical there.** `HistoryWeeksTests` "Week 0 is the
week the block opened on" and "A capsule counts its week and marks the days that
were missed"; `SessionSummaryHotfixTests` "a treadmill logged on this phone is
titled Treadmill, not its slug"; `WorkoutWeekTests` "ready to progress fires only
after the ceiling is cleared twice"; `AppDatabaseTests` "stores, retrieves and
removes a session blob" (`Keychain error -34018: A required entitlement isn't
present` — environmental, the free team). The memory `auto-fixes-w7` names four;
the fifth is the Keychain one. None fixed, none new: the app suite went 53 → 58
tests with the same five failures.

---

<!--
## W<N> — <title> · <version>

**Shipped:** <date> · `<merge sha>`
**What changed:** …
**What the brief got wrong:** …
**Seams left for the next wave:** …
**Gate:** <which commands ran, which failed, the 4 baseline failures named>
-->
