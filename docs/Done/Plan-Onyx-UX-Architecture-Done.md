# Onyx UX/UI Architecture Sprint — the plan

**Status:** approved 2026-09-17 · step 0 done (this file). W1 next.

**From:** `main` @ `3.21.1` (`dba8f351`). **Ships as:** five sequential waves, `3.22.0 → 4.0.1`.
**Branches:** `onyx/w<N>-<slug>`, each cut from current `main`, merged `--no-ff` back into it,
then deleted (`docs/GIT.md`). One branch at a time — two sessions share the git index
(memory: `concurrent-waves-shared-checkout`).

---

## Context

Six briefs across five surfaces: an InBody form nobody wants to fill twice, a theme system
that can only turn a hue, a weekly report trapped in a 560 pt sheet behind a donut, three
live-logger defects that are one state-management bug wearing three hats, an edit deck with
no way out, and a supplement the app cannot yet describe.

Exploration measured every brief against the source and the **live** Supabase schema before
this plan was written. Four briefs name a symptom whose root cause sits elsewhere, and one
names work the data already supports.

| Brief | What is actually true |
|---|---|
| "Live PR cup only appears after finishing" | `LoggerModel.baselines:548` is snapshotted once at `attach()` and never rebuilt. Worse: the live candidate key comes from `storedId:2470` while the commit path uses `storedIdCreatingCatalogueRow:2502`, which **mints a catalogue row and rewrites `idByCanonicalName:2510`**. After the first set the candidate key flips slug→uuid while `baselines` is still slug-keyed, and `PrEngine.detectSetPrs:382` awards nothing against a missing index entry. |
| "Treadmill shows 0 kg × 0" | Literal. `withWarmupCardio:1033` mints the row with `weightKg: 0, reps: 0` — **non-nil**, so `if let kg, let reps` at `LiveActivityController.swift:149` succeeds. `ContentState` has **no** duration/distance/incline field at all (`OnyxWorkoutAttributes.swift:33`). |
| "Missing Cardio tag" | Two causes. `LoggerModel.setRow(SeedRow):1134` drops `durationSec/incline/distanceKm`, so a seeded treadmill card fails `isCardio`. And `Program.swift:121` reads `MuscleMap.movers`, never `cardioMovers:367`, so `plan.movers.primary` is empty for "Treadmill" and `family == nil`. |
| "18.75 renders smaller" | `ExerciseCardView.swift:2390` — `.minimumScaleFactor(0.6)`. `monospacedDigit()` equalises digit advance but **not** the decimal point, and the weight field sits in a flexible track whose leftover width is the real budget. |
| "Treadmill drops to the bottom on edit" | `SessionAnalysis.grouped:540` orders by `sets.compactMap(\.exerciseOrder).min()`, and nil sorts **after** everything placed (`:512-530`). Memory `hotfix-polish-sprint`: phone sessions upload no `exercise_order`. `editorDay:333-354` then reproduces that order. |
| "Records vanish to —" | `FinishSheet.swift:251` reads `model.recordCount` = `prsThisSession`, written only by `refreshLivePrs`. `attach(editing:):2204` **swallows** a failed baseline build in a bare `catch`, leaving `baselines == .empty` → 0 PRs → `"—"`. Same root cause as the live PR bug. |
| "Sets show 18/19" | `completedSets:646` counts working sets in the deck; `plannedSets:647` is `day.plannedSets(for:)` where `day` is `editorDay`'s synthetic day that appends **every unperformed plan movement** (`SessionDetailView.swift:356`). A finished session has no planned sets left to hit. |
| "Add Week 0" | Not missing data. Plan `onyx5` started `2026-07-15`, `user_goals.week_end_day = 6` → weeks start Sunday → anchor week = **`2026-07-12`**, which holds **two complete sessions** (17 and 19 sets). `Week.label:53` already returns `"Week 0"` for it. The backward walk in `WorkoutWeek.pastWeeks:890` `break`s below the anchor. |
| "Ugly bottom sheet" | `WeeklyWrapView.swift:40` is a `.sheet` with `PresentationDetent.height(560)`. Its body is already split into `WeeklyWrapContent:121` **so it can sit inline** — that is the seam a full page pushes through. |

### Live schema facts (introspected, not read from `types.ts`)

- The InBody reading writes to **`daily_logs`**, not `body_composition`. `body_composition` is the HealthKit-sourced twin.
- `daily_logs` has **no waist column** — only `estimated_waist_to_hip_ratio`. The `body_measurements` table **no longer exists** in the live database.
- `custom_supplements` has `micros jsonb`, `dose_amount`, `dose_unit`, `time text` — and **no macro columns**.
- `plan_phases` already carries `kind ∈ {bulk, cut, peak, deload}` and `era_tag` per block — the banner hue and the report's era capsule both have a real source.
- `lever_periods.profile_key` is the **nutrition** rung schedule (`baseline`, `lever-1`, `maintenance-week`), *not* the training phase. Do not conflate.

### Founder decisions (2026-09-17)

1. **InBody = Concept A.** Gradient hero (body-fat headline, weight + SMM satellites, deltas), then four accordions — Mass · Composition · Water & Protein · Minerals & Derived. Everything pre-filled on open; a per-row caption names the source.
2. **Themes gain a mood knob.** `OnyxThemeSpec` grows `chroma` and `lift` so a theme can read deep-and-muted or bright-and-vivid, not just rotated.
3. **Report hero = Phase Band + Three Rails.** Phase-hued gradient band with the week numeral, era capsule and date range; three horizontal rails (Training · Nutrition · Recovery) replace the donut.
4. **Psyllium macros live in `custom_supplements.micros`.** No DDL; the day total learns to fold supplement macros.
5. **Waist gets a real column.** `daily_logs.waist_cm`, and the three "no tape measurements, ever" comments are struck.
6. **Cancel Edit reverts via `set_events` replay.** A watermark at attach, compensating events on cancel, then reproject + rescore.
7. **Week 0 only.** Make the anchor week draw its banner; the PPL era (March–July) stays out of Past Weeks.
8. **Treadmill Live Activity shows the live bout** — elapsed · km · pace.

### One correction this plan makes on the founder's behalf

**Ion cannot be dropped.** `OnyxThemeSpec.default` is Ion, `AppearanceView.swift:65` says "Reset to Ion", and `SettingsTabView.swift:320-323` names the current theme by matching it against `presets`. Remove Ion and every default install reads "Custom". So: **Ion stays first, the other five are replaced by the eight new ones → nine presets.** Say so if you would rather rename Ion than keep it.

### A note on the skill list in the brief

`capacitor-apple-review-preflight`, `capacitor-offline-first`, `capacitor-performance`,
`capacitor-security`, `report`, `visual-check`, `tanstack-query`, `nextjs-best-practices`,
`react-best-practices` and `ux-researcher-desginer` **do not exist** — they are web-era names,
retired with the web app on 2026-09-12. Every wave prompt below names only skills and agents
that are installed.

---

## Waves

| Wave | Scope | Ships |
|---|---|---|
| W1 | Nutrition, Stack UI & Typography | `3.22.0` |
| W2 | Live Logger & Edit Mode core fixes | `3.23.0` |
| W3 | InBody & Appearance overhaul | `3.24.0` |
| W4 | Train tab & the weekly report | `4.0.0` — a removed screen is MAJOR here |
| W5 | The Great Purge & Merge | `4.0.1` |

**The gate, every wave.** There is no CI; these commands are the whole of it.

```bash
npm run check          # version + atlas + mirror + doms in sync
npm run check:swift    # OnyxCore + OnyxUI cross-build
npm run swift:core     # golden vectors + invariants
npm run swift:data     # store, sync, migrations
cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

A green `check:swift` hides a broken app target — run the `xcodebuild` line (memory:
`xcodeproj-drift-and-swift6`). **`OnyxTests` has five known baseline failures on `main`**
(memory: `refinement-ux-w1`): record the count before you start and compare after; a sixth
is yours.

---

# WAVE 1 — Nutrition, Stack UI & Typography

**Ships `3.22.0`. Branch `onyx/w1-nutrition-stack-type`.**

### The exact prompt

````
Execute Wave 1 of docs/Plan-Onyx-UX-Architecture-Done.md. Read that file first — the
Context table and the Founder decisions are binding.

Branch: cut `onyx/w1-nutrition-stack-type` from current `main`.

LOAD FIRST
  Skills:  native (the runbook — read before touching anything under native/ or scripts/src/)
           schema (introspect LIVE Supabase before any claim about a column)
           ponytail (the ladder: reuse before writing)
           apple-design, ui-ux-pro-max (the wheel and the row typography)
  Agents:  ios-developer or swift-expert for the SwiftUI work
           schema-truth-checker before writing the supplement row
           code-reviewer at the end, on the diff

GOAL 1 — The Stack time editor becomes a native clock.
  Today: `native/Onyx/Features/Pulse/StackView.swift:387-389` is a plain
  `TextField("Time", text: $time)` inside `SupplementEditSheet:315`.

  Replace it with a wheel `DatePicker`. The component to copy is
  `native/Onyx/Features/Logger/TimerSheet.swift:331-341` — `.datePickerStyle(.wheel)`,
  `displayedComponents: [.hourAndMinute]`, `.labelsHidden()`, a clamped height. The Sleep
  sheet's twin is `native/Onyx/Features/Pulse/SleepEditSheet.swift:350-364`; it carries
  `.date` as well because a night straddles midnight — a supplement dose does not, so take
  TimerSheet's shape, not SleepEditSheet's. Do NOT extract a shared component for two
  call sites that want different `displayedComponents`.

  THE TRAP THAT WILL BITE: `SupplementStack.customSlotsForDate:344-375` GROUPS BY THE TIME
  STRING and orders by it, with a "—" bucket first. The wheel must emit exactly zero-padded
  24-hour `HH:mm`. A `DateFormatter` on the user's locale emits "6:30 PM" and silently mints
  a new slot bucket. Use `Locale(identifier: "en_US_POSIX")` and `dateFormat = "HH:mm"`.

  Keep the "no set time" affordance the TextField had (blank → the "—" bucket). Clearing it
  must still clear server-side: `SupplementEditing.editCustomSupplement:111-141` uses `nulls:`
  for exactly this. Verify a cleared time round-trips.

GOAL 2 — Psyllium Husk, and supplement macros that reach the day total.
  Product: "Psyllium Husk Powder, by Now Foods". Base 9 g serving: 30 kcal, 0 g fat,
  10 mg sodium, 8 g carbs, 7 g fiber, 0 g protein, 1.5 mg iron, 90 mg potassium.
  The founder takes 5 g at 18:30. 5/9 = 0.5556, so the PER-DOSE payload is:

      kcal 16.7 · fat 0 · sodium 5.6 mg · carbs 4.4 g · fiber 3.9 g
      protein 0 · iron 0.83 mg · potassium 50.0 mg

  Store it in `custom_supplements.micros` (jsonb) alongside the existing micro keys — the
  decision is recorded in the plan. `dose_amount: 5`, `dose_unit: "g"`, `time: "18:30"`,
  `form: "powder"`. NOTE: `g` is not a count unit
  (`SupplementNutrients.countUnit:45-49`), so the payload is NOT multiplied — the numbers
  above are what gets stored, exactly as the existing caffeine row stores `200`.

  Then teach the day total to fold supplement MACROS, not just micros. Today
  `NutrientsView.swift:50,156-157,193` folds stack micros into the nutrient grid, but the
  macro ring reads `nutrition_entries` via `NutritionWeek`/`NutritionModel`. The fold belongs
  in `native/Packages/OnyxData/Sources/OnyxData/Day/StackCredit.swift` — the day-level credit
  resolver that already exists.

  TWO RULES, both testable:
    · Fold a dose's macros ONLY when `supplement_log.taken` is true. A planned dose must not
      inflate the total.
    · Fold exactly once. `sodium`, `iron` and `potassium` may already be nutrient-grid keys —
      adding `kcal/carbs/fiber/protein/fat` must not double-count anything already counted.

  Write the row with a small idempotent one-shot under `scripts/` using the service-role key
  from `.env.local`, keyed on `schedule.key = "psyllium"` so a re-run updates rather than
  duplicates. Run it once. Record the returned row id in the wave log.

GOAL 3 — Standardise the set-row numeral size.
  Symptom: typing `18.75` renders smaller than `17.5` or `20`. The founder wants everything
  at the size `20` renders at.

  Root cause: `native/Onyx/Features/Logger/ExerciseCardView.swift:2390` —
  `.minimumScaleFactor(0.6)` on `NumericField:2340`. `.onyxNumeral()`
  (`OnyxUI/DesignSystem/OnyxType.swift:167-172`) applies `monospacedDigit()`, which equalises
  DIGIT advance but leaves the decimal separator proportional. The weight field is inside a
  FLEXIBLE track (`fills: !typeSize.isAccessibilitySize`, `:1579-1592`), so its rendered width
  is the layout-pass leftover, and the scale factor then shrinks per-string.

  DO NOT just delete the scale factor. The comment at `:2376-2388` records why it is there:
  at 375 pt `11.25` and `13.75` both rendered `11…`. Fix the BUDGET, then the modifier:
    1. `SetColumn` is at `:990-1042`. `weightFloor = 56` claims to fit six glyphs (`123.75`);
       measure whether it actually does at 375 pt. Raise it, and/or trim `step = 32`, until
       the widest legal load string renders at full size.
    2. Only then raise `minimumScaleFactor` to 1.0 for the non-accessibility case. KEEP a
       scale factor at accessibility sizes — that is a different, legitimate squeeze.
    3. The column headers at `:875-933` must squeeze identically (the note at `:915-932`).

  Leave the other scale factors alone unless they show the same defect, but NAME them in the
  log: `SetBadge.swift:131` (0.5), `ExerciseCardView.swift:355`, `:591`, `:1900` (0.7).

VERIFICATION PROTOCOL — run all of it, read the counts, "no output" is not a pass.
  1. Record the OnyxTests baseline failure count BEFORE any edit (five are known on main).
  2. npm run check && npm run check:swift && npm run swift:core && npm run swift:data
  3. cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
       -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  4. New unit tests, all of which must fail before your change and pass after:
       · a wheel `Date` at 18:30 in a non-POSIX locale still serialises to "18:30"
       · a cleared time round-trips to NULL through `editCustomSupplement`
       · a taken 5 g psyllium dose adds 16.7 kcal / 4.4 g carbs / 3.9 g fiber to the day
       · an UNTAKEN dose adds nothing
       · sodium/iron/potassium are counted exactly once
  5. Screenshots — ALWAYS pass SHOT_DERIVED (memory: concurrent-waves-shared-checkout):
       SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w1 \
         scripts/native-shot.sh stack && … stack-add && … fuel && … nutrients \
         && … set-row && … set-row-cardio && … logger
     Shoot at BOTH sizes (the script does default + AX5). Look at them. The typography fix
     is only done when `18.75`, `17.5` and `20` are visibly the same size in `set-row.png`
     AND in `set-row-ax5.png`.
  6. Version: set package.json to 3.22.0, `npm run version:sync`,
     `cd native && xcodegen generate`, append the release section to docs/CHANGELOG.md,
     confirm `npm run version:check` passes.

DOCUMENTATION REQUIREMENT — before the merge commit, append a "Wave Record — W1" section to
docs/Plan-Onyx-UX-Architecture-Done.md with these exact four headings:
  · **What was done** — file:line for every change, and why that file and not another.
  · **Succeeded** — with the evidence: test names, counts, screenshot filenames.
  · **Failed** — anything you tried that did not work, and what you learned from it.
  · **Left open** — every seam W2+ inherits, named precisely. Include the founder's manual
    checklist (anything they must click or paste).

Then merge --no-ff into main, delete the branch, push with [skip ci] in the message.
````

---

# WAVE 2 — Live Logger & Edit Mode core fixes

**Ships `3.23.0`. Branch `onyx/w2-live-logger-edit`.** The heaviest wave; it is one
state-management bug wearing three hats plus two independent defects.

### The exact prompt

````
Execute Wave 2 of docs/Plan-Onyx-UX-Architecture-Done.md. Read that file first — the
Context table is binding, and its root-cause claims were measured against the source.

Branch: cut `onyx/w2-live-logger-edit` from current `main`.

LOAD FIRST
  Skills:  native, schema, ponytail
           superpowers:systematic-debugging — use it on GOAL 1 before you edit anything
           superpowers:test-driven-development — GOAL 1 and GOAL 5 get failing tests first
  Agents:  swift-expert (concurrency + the model), ios-developer (the SwiftUI + ActivityKit)
           invariant-auditor AFTER the PR change — it checks src domain math against the
             invariants each module states in its own header
           debugger if a symptom does not reproduce
           code-reviewer on the final diff

GOAL 1 — The live PR cup. ROOT CAUSE ONLY. No patches, no second code path.
  The chain: `LoggerModel.toggleDone:1435` → `appendInStore` → `refreshLivePrs:1470`.
  `refreshLivePrs:1560-1633` builds candidates keyed by `storedId(for:):2470` and runs
  `PrEngine.detectSessionPrs:1612` against `baselines`.

  THE BUG, in two parts:
    (a) `baselines:548` is built ONCE at `attach()` (`:2116`) / `attach(editing:)` (`:2201`)
        and is never rebuilt for the life of the model. The comment at `:534-548` says so.
    (b) The live candidate key comes from `storedId:2470` = `catalogueIndex()[canonicalKey]
        ?? ExerciseSlug.id(name)`. The COMMIT path uses
        `storedIdCreatingCatalogueRow:2502`, which MINTS a catalogue row and writes
        `idByCanonicalName[key] = created` at `:2510`. `catalogueIndex():2396` reads that same
        dictionary. So after the first append the candidate key flips slug → uuid while
        `baselines` is still slug-keyed, and `PrEngine.detectSetPrs:382` — which requires an
        EXISTING index entry for every axis — awards nothing.

  Also confirm and fix, in the same pass, because they are the same seam:
    (c) `attach():2092` calls `restoreLoggedSets()` before `buildLiveBaselines`, but it
        returns early when `sessionId == nil` (`:2218-2219`). On a fresh workout
        `storedExerciseId` is nil for every card, so the baseline id set is slugs only.
    (d) `rebuildForPhase:862` can replace `exercises` mid-session with no baseline rebuild
        and no `refreshLivePrs`.
    (e) `:1577` computes a rep-window `floor` and never passes it into the candidate.
        Decide deliberately: pass it or delete the dead local. Do NOT leave it.

  THE FIX SHAPE: resolve exercise identity ONCE, before the baselines are built, and make the
  live candidate key and the commit key the same value by construction. Then rebuild the
  baselines whenever the deck changes. One guard in the shared resolver beats a guard in every
  caller. Respect memory `exercise-identity-uuid` — the watch never mints an id, so the
  resolver must tolerate a row that has none.

  DO NOT touch these on-purpose asymmetries:
    · `PrEngine.buildBaselines:329-331` — a floor only RAISES keys already present in `rows`.
      A brand-new exercise gets no floor. That is deliberate (memory: auto-fixes-w7).
    · `PrRecorder.floors:264-290` `standingRecordFloors: true` is the LIVE tier only
      (`AppDatabase.livePrBaselines:599-614` is its one caller).
    · `SessionAnalysis:590,609` recomputes PRs from the ledger per session. It is allowed to
      be a second, independent answer — but after your fix the two MUST agree on the founder's
      history. Prove it.

GOAL 2 — Treadmill in the Dynamic Island and on the Lock Screen.
  Decision: show the live bout — `12:30 · 0.37 km · 5:42/km`.

  `native/Shared/OnyxWorkoutAttributes.swift:33` `ContentState` has no cardio field at all.
  THE RULE AT `:114-121` IS LOAD-BEARING: every field added after first release must be
  Optional, or a running Live Activity fails to decode and the user's in-flight workout dies.
  Add optionals only.

  Carry the two NUMBERS (`cardioElapsedSec: Int?`, `cardioDistanceKm: Double?`) and derive the
  pace string in the view — `native/Shared/WorkoutActivityCard.swift` is shared by the lock
  card (`:448-452`) and the watch card (`:160-161`), so one formatter serves both. Guard the
  divide: distance can be 0.

  `LiveActivityController.swift:147-156` is the only producer of `ContentState.load`. It reads
  `if let kg = row.weightKg, let reps = row.reps` — and the treadmill row has non-nil ZEROS
  (`LoggerModel.withWarmupCardio:1033-1048`), so the guard succeeds and the string is literally
  "0 kg × 0". Branch on `row.isCardio:241` FIRST, not on nil.

  `OnyxWidgets.swift:296` does
  `state.load.replacingOccurrences(of: " kg ", with: "")` for compactTrailing. That string hack
  cannot survive a cardio payload — give it a real field or a real branch.

GOAL 3 — The missing "Cardio" tag in-app. Two root causes, fix both.
  (a) `LoggerModel.setRow(SeedRow):1134-1143` constructs the row with no
      `durationSec/incline/distanceKm`, so a SEEDED treadmill card fails `isCardio:241`. The
      code already knows: see its own note at `:1013-1029`.
  (b) `Program.swift:121` does `movers ?? MuscleMap.movers(name) ?? MoverTokens(primary: [])`
      — it never consults `MuscleMap.cardioMovers:367`. So `plan.movers.primary` is empty for
      "Treadmill", `ExerciseCardView.family:520` is nil, and `LoggerModel.primaryMuscle:696-703`
      falls back to the row test that (a) just broke.

  ⚠️ `MuscleMap.dict` MUST NEVER LEARN A TREADMILL (memory: next-gen-w4-ledger). The cardio
  table at `MuscleMap.swift:345-401` is separate ON PURPOSE. Read `cardioDict`/`cardioMovers`
  as a FALLBACK; do not merge them into `dict`.

  Draw the tag at `ExerciseCardView.swift:467-475`. Do NOT un-gate the lift tagger there — the
  comment records that `ExerciseTags` labelled a treadmill "Isolation". Add an explicit Cardio
  tag in that branch. The Live Activity's own chip already resolves from the "cardio" token
  (`WorkoutActivityCard.swift:517-523`) and will light once (b) is fixed.

GOAL 4 — Edit mode keeps the performed order.
  `SessionAnalysis.grouped:531-552` DOES read `exercise_order` (`:540`), and nil sorts after
  everything placed (`:512-530`). `editorDay:333-354` then walks `report.exercises` in that
  order. Memory `hotfix-polish-sprint`: phone sessions upload no `exercise_order`.

  Two parts:
    (a) The warm-up/treadmill card must be written with an `exercise_order` like every other
        card. `snapshot:2426` writes `deckOrder(of:):2446-2458`; find why the cardio row misses it.
    (b) `withWarmupCardio` runs at `init` (`:930-931`) and PREPENDS the treadmill (`:1031,1050`);
        `attach(editing:):2176-2178` then deletes it only if it has no done rows. Skip the
        prepend entirely when the model is being built for an edit — one guard at construction
        beats a delete-after.

  A backfill for historical sessions with null `exercise_order` is IN SCOPE but OPTIONAL: use
  the `backfill` skill, scope it to the founder's user_id, dry-run it, and only run it if the
  dry run is clean. If you skip it, say so under "Left open".

GOAL 5 — The Finish tiles stop lying.
  (a) Records "—": `FinishSheet.swift:251` reads `model.recordCount:655` = `prsThisSession`,
      and `attach(editing:):2204` swallows a failed baseline build in a bare `catch`. GOAL 1
      fixes the cause; ALSO stop swallowing — surface the failure.
  (b) "18/19": `completedSets:646` counts working sets in the deck; `plannedSets:647` is
      `day.plannedSets(for:)` over `editorDay`'s synthetic day, which appends EVERY unperformed
      plan movement (`SessionDetailView.swift:356`). Fix at the TILE, not at the day: on an
      edit deck show the performed count alone ("18 sets"). A finished session has no planned
      sets left to hit, and `editorDay` keeps appending plan movements ON PURPOSE so a
      forgotten exercise can still be added.

GOAL 6 — Cancel Edit, via set_events replay.
  There is no discard path today, and `LiveLoggerView.swift:378-388` documents the refusal
  ("AND WHY EDIT MODE HAS NO TRASH"): every set edit already commits to `set_events` +
  projection + outbox before Save (`LoggerModel.swift:2543,2580,2622`;
  `SessionEditing.swift:552`).

  FIRST run `/schema` and introspect `set_events` live. Do not assume its columns.

  Build:
    · `attach(editing:):2144` stamps a watermark (the session's max event id / created_at) into
      `EditContext`. Persist it — a crash mid-edit must not lose the ability to revert.
    · A revert writer in `native/Packages/OnyxData/Sources/OnyxData/Training/SessionEditing.swift`,
      near `reproject:552` and `recount:561-586`. It appends COMPENSATING events back to the
      watermark, reprojects, recounts, and enqueues the outbox upsert. It does not DELETE
      history.
    · The button at `LiveLoggerView.swift:388` — open the `if !model.isEditing` gate, with a
      confirmation dialog modelled on `:228-240`. REWRITE the `:378-388` comment to explain the
      new revert; do not delete it silently.
    · Cancel then runs `requestRescore():722-726` with `.sessionEdit`, same as Save.
    · The chevron path keeps its current meaning — leave, keep changes
      (`:247 .onDisappear { requestRescore() }`, hint at `:372-376`).

VERIFICATION PROTOCOL
  1. Record the OnyxTests baseline failure count BEFORE any edit.
  2. The full gate: npm run check && check:swift && swift:core && swift:data && the xcodebuild line.
  3. `npm run swift:core` covers PrGoldenTests — the golden vectors are hand-maintained and
     MUST NOT be regenerated to make a test pass (memory: hotfix-live-state-3-10-0).
  4. Run the invariant-auditor agent on the PR diff.
  5. New tests, failing first:
       · a set that beats a standing record lights `isRecord` on the FIRST tick, with the
         catalogue row minted mid-session (the slug→uuid flip)
       · `rebuildForPhase` mid-session does not lose a already-awarded PR
       · an edit deck's `recordCount` matches `SessionAnalysis`'s `prCount` for the same session
       · a treadmill `ContentState` decodes in an activity built from the PREVIOUS schema
         (the Optional rule)
       · a seeded treadmill card reports `isCardio` and resolves a cardio mover
       · an edit deck preserves performed order with the treadmill in position 1
       · Cancel returns every aggregate to its pre-edit value; Save does not
  6. Screenshots, SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w2:
       logger, logger-finish, set-row, set-row-cardio, set-row-records, session-edit,
       session-cardio, widgets (the Live Activity faces)
     A simulator cannot photograph a real Dynamic Island — use the widget preview screens and
     say in the log which surfaces were verified by eye on a device and which were not.
  7. Version 3.23.0 + version:sync + xcodegen + CHANGELOG + version:check.

DOCUMENTATION REQUIREMENT — append "Wave Record — W2" to
docs/Plan-Onyx-UX-Architecture-Done.md with the four headings: What was done / Succeeded /
Failed / Left open. Under "Left open", state explicitly whether the live PR path and
SessionAnalysis now agree on the founder's full history, and whether the exercise_order
backfill ran.

Then merge --no-ff into main, delete the branch, push with [skip ci].
````

---

# WAVE 3 — InBody & Appearance overhaul

**Ships `3.24.0`. Branch `onyx/w3-inbody-appearance`.** Contains the one piece of DDL the
founder must paste.

### The exact prompt

````
Execute Wave 3 of docs/Plan-Onyx-UX-Architecture-Done.md. Read that file first.

Branch: cut `onyx/w3-inbody-appearance` from current `main`.

LOAD FIRST
  Skills:  native, schema, ponytail
           apple-design (the hero, the accordions, the motion)
           ui-ux-pro-max + ui-design-system (the palette work)
           frontend-design (visual direction — resist the templated default)
  Agents:  ios-developer, swift-expert
           schema-truth-checker BEFORE and AFTER the waist DDL
           ui-ux-designer on the screenshots
           code-reviewer on the diff

GOAL 1 — The theme spec grows a mood knob.
  Today `native/Packages/OnyxCore/Sources/OnyxCore/Design/OnyxThemeSpec.swift:9` is two
  UInt32s, and `OnyxTheme.init(spec:):26-52` derives the ENTIRE palette — four domain ramps,
  sixteen muscle hexes, ~1,250 static tokens — by OKLCH HUE ROTATION only. Lightness and
  chroma are pinned to the default literals, so every theme is Ion turned.

  Add: `chroma: Double` (0.6…1.0, a SCALE on the derived C) and `lift: Double` (−0.06…+0.06,
  an OFFSET on the derived L).

  ⚠️ TWO TRAPS, both silent:

  (a) DECODE. Swift's synthesized Decodable REQUIRES a key unless the property is Optional —
      a default value does not save it. Every existing install has a stored blob of
      `{"primary":…,"secondary":…}`, and `OnyxTheme.apply(json:):102` falls back to `.default`
      on a decode failure. Ship a custom `init(from:)` using `decodeIfPresent` with
      `chroma = 1.0, lift = 0.0`, or every user silently loses their theme. Test the old blob.

  (b) CONTRAST. `normalised():45-57` clamps L to 0.60…0.78 and C to ≤ 0.20 because THE ACCENT
      CARRIES TEXT at ≥ 4.5:1 on black — the header at `:26-44` shows the measurements and why
      a white-on-accent ceiling is arithmetically impossible. A negative `lift` applied to the
      accent is clamped straight back and does nothing.

      So: `lift` applies to the DERIVED stops — `end[domain]`, the washes, the surfaces — and
      NOT to `start[.train]` (the primary) or `start[.fuel]` (the secondary), which stay the
      chosen hexes. `chroma` scales DOWN only, so it can never break the ceiling. Document
      this in the file, in the register the existing comments use.

  The default spec (chroma 1.0, lift 0.0) must remain BIT-FOR-BIT identical to today —
  `OnyxThemeTests` already holds that line for the hue rotation; extend it.

  The spec rides to the widget and the watch automatically (`WatchPayloads.WatchContext:37`
  carries the whole spec; `OnyxProvider.theme():89-100` reloads per timeline). Verify — do not
  re-fix; the staleness bug is already solved there.

GOAL 2 — Eight new presets.
  `OnyxTheme.presets:121-128`. KEEP Ion first — it is `OnyxThemeSpec.default`,
  `AppearanceView.swift:65` says "Reset to Ion", and `SettingsTabView.swift:320-323` names the
  current theme by matching against this array. Drop it and every default install reads
  "Custom". Replace the other five with these eight → nine presets:

      Obsidian · Solstice · Meridian · Basalt · Aurora · Terracotta · Vesper · Halcyon

  Unisex, modern, no two adjacent in hue. Secondaries roughly 120° from their primaries, as
  the existing set does. SOLVE the hexes with `OKLCHConvert` inside the guard box — do not
  hand-pick literals and hope. `OnyxThemeTests` asserts `normalised()` is the IDENTITY on
  every preset; that assertion is your acceptance test. Give each a distinct `chroma`/`lift`
  so the mood knob earns its place — Obsidian deep and muted, Aurora vivid.

  ⚠️ `AppearanceView.swift:176-180` notes preset names are 3–5 characters and `.lineLimit(1)`
  is a tripwire, not a fix. "Terracotta" is ten. Re-lay-out the chip (the grid is
  `.adaptive(minimum: chipWidth = 100)` at `:111-117`) rather than truncating.

  Add two sliders for chroma and lift under the pickers at `:57-59`. They edit the DRAFT — the
  header at `:1-31` explains why nothing here writes live, and `commit():255-263` is the one
  writer. The `derived` preview at `:204-226` already renders from the uncommitted draft, so it
  shows the knobs working for free.

GOAL 3 — Waist. THE FOUNDER MUST PASTE THIS FIRST; the wave cannot run DDL from this machine.

      ALTER TABLE daily_logs ADD COLUMN waist_cm numeric;

  Then: add the column to `native/schema/supabase.json`, run `npm run mirror` (NEVER hand-edit
  `MirrorModels.swift` — it is generated), and confirm `npm run check:mirror` passes.

  Then strike the three places that say this is forbidden, replacing each with the new
  decision and its date — do not delete them silently:
      · `OnyxCore/Body/Composition.swift:10-13`  "NO TAPE MEASUREMENTS, EVER"
      · `native/schema/supabase.json:15-17`       "removed from the product twice"
      · `Onyx/Features/Settings/BodyTargetsView.swift:14-16`  "No waist, no hips, no limb girths"

GOAL 4 — InBody, Concept A.
  Screen: `native/Onyx/Features/Pulse/PulseScale.swift:96` `InBodyEntryView`. It writes to
  `daily_logs` (NOT `body_composition` — that is the HealthKit twin) via
  `PulseModel.saveBody:1089` → `DayEditing.saveBodyMetrics:85-97`.

  Build:
    · A gradient HERO card: body-fat % as the headline numeral, weight and skeletal muscle
      mass as satellites, each with a delta chip against `PulseModel.latestBodyReading:1096`.
    · FOUR accordions replacing the three-group grid. `FieldGroup:127-138` and the `Spec` table
      `:150-162` are the things to rework:
        Mass — weight, waist, fat mass, fat-free mass
        Composition — body fat %, muscle %, skeletal muscle mass, visceral fat
        Water & Protein — water %, water mass, protein %, protein mass
        Minerals & Derived — bone mineral, BMI, BMR, W:H ratio, and the read-only derived rows
      Fold `derivedSection:350-385` into the last one.
    · Keep `OnyxFieldCell` (`SettingsControls.swift:282`) as the cell. Its hint line is ALREADY
      reserved (`:308-321`) — put the provenance caption there, free: `Health` / `Last` / `You`.
    · DELETE `fillSection:282-310` and `fillFooter:336-346`. Fill on appear instead: seed every
      empty field from `latestBodyReading()`, then overlay `healthFillable:324-334` (Health
      offers only weight, bmi and bodyFat). Fine-tuning is typing over a filled field.

  ⚠️ THE TRAP: `DaySheet(… primary: ("Save", !edits.isEmpty, save))` at `:212` gates Save on
  `edits`. If auto-fill writes into `edits`, Save is live the instant the sheet opens and an
  untouched screen writes a duplicate reading. Keep the seeded values in a SEPARATE layer from
  user edits; Save stays disabled until the user actually changes something, or until there is
  no reading for today at all.

  `RowPush:104-121` pushes a merge with nil optionals omitted, so a HealthKit push cannot blank
  a hand-entered value. Do not break that.

VERIFICATION PROTOCOL
  1. OnyxTests baseline count before; the full gate after.
  2. schema-truth-checker BEFORE (confirm waist_cm absent) and AFTER (confirm present, numeric,
     nullable).
  3. New tests, failing first:
       · an old two-key theme JSON decodes to chroma 1.0 / lift 0.0, NOT to .default
       · the default spec renders bit-for-bit identical colours to today
       · every one of the nine presets is a `normalised()` fixed point
       · a lift of −0.06 never pushes an accent below L 0.60
       · opening the InBody sheet on a day with a reading leaves Save DISABLED
       · a waist value round-trips daily_logs → mirror → push
  4. Screenshots, SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w3:
       scale, scale-first, appearance, appearance-locked, day, body-trends
     AND every new theme through the theme harness, which already exists:
       SHOT_THEME=Obsidian scripts/native-shot.sh tabs
       … repeat for all nine, plus one `appearance` shot per theme.
     Check contrast BY EYE at AX5 as well as default. A theme that looks good at 17 pt and
     fails at AX5 is not done.
  5. Version 3.24.0 + sync + xcodegen + CHANGELOG + version:check.

DOCUMENTATION REQUIREMENT — append "Wave Record — W3" with the four headings. Under
"Left open", state whether the founder pasted the DDL and whether check:mirror is green.

Then merge --no-ff into main, delete the branch, push with [skip ci].
````

---

# WAVE 4 — Train tab & the weekly report

**Ships `4.0.0`.** MAJOR by this repo's own rule — the wrap sheet is a removed screen.
**Branch `onyx/w4-week-report`.**

### The exact prompt

````
Execute Wave 4 of docs/Plan-Onyx-UX-Architecture-Done.md. Read that file first.

Branch: cut `onyx/w4-week-report` from current `main`.

LOAD FIRST
  Skills:  native, ponytail, apple-design, ui-ux-pro-max, frontend-design
  Agents:  ios-developer, swift-expert, ui-ux-designer, code-reviewer
           architect-reviewer on the navigation change — four doors move at once

GOAL 1 — Week 0 draws its banner.
  DO NOT ASSUME IT IS BROKEN THE WAY YOU EXPECT. The data says it should already work:
  plan `onyx5` started 2026-07-15, `user_goals.week_end_day = 6` → weeks start Sunday →
  `weekZeroStart` = 2026-07-12, which holds two complete sessions (17 and 19 sets), and
  `Week.label:53` returns "Week 0" for n = 0.

  So: REPRODUCE FIRST. Write a failing test against
  `WorkoutWeek.pastWeeks:880` with anchor 2026-07-12 and two finished sessions in that week,
  asserting a `PastWeek(weekStart: "2026-07-12", label: "Week 0")` is emitted. Then find out
  why it is not, and fix THAT.

  The two candidates: `Schedule.isPlannable:191-194` is `dateISO >= ctx.weekZeroStart` and the
  walk `break`s below it (`WorkoutWeek.swift:890`) — an off-by-one there hides the anchor week
  itself; and `guard !finished.isEmpty else { continue }` at `:893`.

  DECISION: keep the break at the anchor. The PPL era (March–July, a different plan) stays out
  of Past Weeks.

GOAL 2 — Compact the banners and colour them by phase.
  `PastWeeksLibrary.banner(_:kind:):281` has NO fixed height — it is intrinsic, roughly
  120–140 pt at default type: hero label + date range, `MuscleTagRow`, then a two-line totals
  string, all at `.padding(OnyxSpace.l)`.

  Target ≤ 88 pt at default type. Collapse the totals to one line, tighten the tag row, keep
  the date range.

  The phase hue is ALREADY THERE and unused: `kind: PhaseKind?` is passed in at `:281` and
  resolved at `:180` via `Phases.span(for:in:)?.def`. Drive `.onyxTopWash(hue)` (`:314-320`)
  from it — cut, bulk, peak, deload each get their own. Use tokens only; `TokenDisciplineTests`
  fails the build on a raw hex outside the three token files.

  Respect the rules earlier waves discovered (memory: refinement-ux-sprint): one hero per
  screen, ZStack not `if` for a swap, and `.disabled()` greys ink — do not use it for state.

GOAL 3 — Destroy the bottom sheet. Build a pushed full-page report.
  `WeeklyWrapView.swift:40` is a `.sheet` with `PresentationDetent.height(560)` (`:47`),
  `.presentationDetents([reel, .large])` (`:94`) and its own NavigationStack (`:66`).

  THE SEAM IS ALREADY CUT: its body is split into `WeeklyWrapContent:121` precisely so it can
  sit inline (`:168-175` is a LazyVStack of headline / bestsCard / ringCard / topThree /
  breakdown / shareSection). Reuse that; do not rewrite it.

  New `WeeklyReportView`, pushed by `NavigationLink`, matching the pattern at
  `WeekDaysView.swift:12` (pushed from `HistoryView.swift:140-142`) — that is the closest
  existing full-page week screen, and the Train tab is already a
  `NavigationStack` (`RootView.swift:97-99`).

  ⚠️ ALL FOUR DOORS MOVE. Miss one and the sheet survives:
      · `WorkoutTabView.swift:319` (.sheet item: $wrapped) and its button at `:438`
      · `PastWeeksLibrary.swift:115`
      · `WeekDaysView.swift:158`
      · the Today tab, via `TodayFeedBuilder.weeklySummaryReady`

  ⚠️ THE LIST CONSTRAINT (`WeekDaysView.swift:148-153`): in a `.plain` List every presentation
  must hang off the LIST, not off a row — a lazy List tears rows down and takes the
  presentation with it. Any new destination obeys this.

  The zoom transition at `PastWeeksLibrary.swift:51/338/124` (`matchedTransitionSource` +
  `.navigationTransition(.zoom)`) was built for a push and keeps working. Keep it.

  DELETE `WeeklyMuscleRing.swift:41` and the `ringCard` at `WeeklyWrapView.swift:344-347`.
  The founder's words: "destroy the ugly Where-the-work-went ring."

GOAL 4 — The hero: Phase Band + Three Rails.
  BAND — full-bleed gradient in the phase hue, the week numeral large, the `era_tag` capsule
  (`PhaseDef.eraTag`, `Phases.swift:30`), and the date range. `Phases.weekPhase:113` is how a
  week knows its phase.

  RAILS — three horizontal progress rails with percentages, replacing the donut:
      Training · Nutrition · Recovery

  USE WHAT EXISTS. Do not invent a fourth score:
      Nutrition → `MacroAdherenceSeries.build:249` (Series.swift), verdicts hit/miss/
                  exception/ungraded/untracked, ±10 % tolerance at `:236`
      Training  → `WeeklyWrap.Summary.sessions` / `tonnageKg` / `tonnageDeltaKg`
      Recovery  → the readiness/sleep source already in the tree; read
                  docs/READINESS_MODEL.md and pick, do not define a new one

GOAL 5 — The report body. EVERY source already exists — reuse, do not re-query.
  The whole-week payload is ONE call: `WeeklyExportBuilder.input(weekStart:today:):57` returns
  `WeeklyExportInput` (`ExportTypes.swift:372`) with everything below. Build the page from
  that, not from six new queries.

      Metadata      — dates, era tag, phase, session count, duration
      Nutrition     — macros hit/missed via `MacroAdherenceSeries.build:249`;
                      water via `WaterTruth.ml(log:ledger:):32` — THE one rule reconciling
                      daily_logs.water_ml against the water_intake ledger; goal from
                      `user_goals.water_goal_ml`
      New PRs       — sorted BY EXERCISE. Range query already written at
                      `WeeklyExportBuilder.swift:536`
      Strongest     — `TopLifts.swift:13`, roles hardest / heaviest / oneRM
      Weight        — `Summary.bodyweightDeltaKg`, built at `WorkoutWeek.swift:1113-1116`

VERIFICATION PROTOCOL
  1. OnyxTests baseline count before; the full gate after.
  2. New tests, failing first:
       · pastWeeks emits Week 0 for the founder's anchor
       · pastWeeks still stops below the anchor (PPL stays hidden)
       · a banner's wash hue follows PhaseKind
       · every one of the four doors reaches WeeklyReportView and none opens a sheet
       · the three rails agree with the sources they claim to summarise
  3. `grep -rn "WeeklyWrapView\|WeeklyMuscleRing" native --include=*.swift` returns only the
     deletions you intended. A surviving reference is a surviving sheet.
  4. Screenshots, SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w4:
       train, train-past, train-past-open, train-wrap, train-wrap-large, train-wrap-deload,
       history-week, history-week-wrapped, history-week-wrap-open, session
     Add a harness case for the new report in `native/Onyx/App/PreviewHarness.swift` (the
     screen registry, `:360-500`) — a new screen with no shot case is a screen nobody reviewed.
     MEASURE the banner height in the screenshot; "looks shorter" is not ≤ 88 pt.
  5. Version 4.0.0 — MAJOR, because a screen was removed (docs/CHANGELOG.md's own rule).
     The changelog entry must tell the reader the wrap sheet is gone and what replaced it.
  6. version:sync + xcodegen + version:check.

DOCUMENTATION REQUIREMENT — append "Wave Record — W4" with the four headings.

Then merge --no-ff into main, delete the branch, push with [skip ci].
````

---

# WAVE 5 — The Great Purge & Merge

**Ships `4.0.1`. Branch `onyx/w5-purge-merge`.**

### The exact prompt

````
Execute Wave 5 — the final wave — of docs/Plan-Onyx-UX-Architecture-Done.md.

Branch: cut `onyx/w5-purge-merge` from current `main`.

LOAD FIRST
  Skills:  ship (the landing runbook), native, git-commit-helper, graphify
  Agents:  code-reviewer on the cumulative diff main…origin/main if anything is unmerged

CONTEXT YOU NEED
  · W1–W4 each already merged themselves into main and deleted their own branch. At the start
    of this wave `git branch -a` should list `main` and `origin/main` and nothing else. If it
    lists more, find out why BEFORE deleting anything.
  · There were no stale UI/UX branches when this sprint began — only `main` existed. "Delete
    all open UI/UX branches" therefore means: confirm each wave cleaned up after itself.

STEP 1 — Confirm the trunk is whole.
  git branch -a && git worktree list && git status
  Nothing uncommitted, no worktrees, no wave branches. Report what you find; do not
  force-delete a branch that still holds commits main does not.

STEP 2 — Purge derived data and caches.
  ⚠️ READ .gitignore:72-132 BEFORE DELETING. The DATED SNAPSHOTS and the cache are ignored,
  but the NINE LIVE FILES at the root of graphify-out/ ARE TRACKED (`.gitignore:83`). Deleting
  those is a tracked-file deletion, not a cache purge.

  Safe to remove outright:
      graphify-out/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/   (dated snapshots)
      graphify-out/cache/
      graphify-out/.rebuild.lock  graphify-out/.pending_changes
      native/graphify-out/
      native/__screenshots__/                 (63 MB, gitignored since 3.8.0; no gate reads
                                               them — memory: screenshots-untracked)
      $HOME/Library/Caches/onyx-swift/*       (all the wave scratch paths)
      Xcode DerivedData for this project

  Then REGENERATE rather than leave a hole:
      graphify update .       (AST-only, no API cost — rebuilds the tracked root files)

  Report the reclaimed megabytes. graphify-out was 134 MB and __screenshots__ 63 MB at the
  start of this sprint.

STEP 3 — The gate, in full. No commit before it is green.
  npm run check
  npm run check:swift
  npm run swift:core
  npm run swift:data
  cd native && xcodegen generate && xcodebuild -project Onyx.xcodeproj -scheme Onyx \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

  Compare the OnyxTests failure count against the five baseline failures recorded in W1's
  Wave Record. A sixth belongs to this sprint and must be fixed or named.

STEP 4 — Version and changelog.
  package.json → 4.0.1 (PATCH: a purge ships no capability).
  npm run version:sync && cd native && xcodegen generate
  Append the release section to docs/CHANGELOG.md using the template at the bottom of that
  file. Confirm `npm run version:check` passes — it is part of `npm run check`.

STEP 5 — Harvest, then land.
  · Harvest the four Wave Records into the CHANGELOG entries they belong to.
  · Write ONE memory file at
    /Users/michael/.claude/projects/-Users-michael-Documents-PyCharmProjects-Onyx/memory/
    covering what this sprint discovered that the code does not record — the PR identity flip,
    the Optional rule on ContentState, the theme decode trap, the Save-gate trap on the InBody
    sheet, the four doors into the report. Add its one-line pointer to MEMORY.md.
  · KEEP docs/Plan-Onyx-UX-Architecture-Done.md. Its name says Done; the Wave Records are the
    record of the sprint.
  · Merge --no-ff into main, delete the branch.
  · Push. The local push guard reads THE COMMAND, not the message (memory: next-gen-ux-sprint):
    put `[skip ci]` in the commit message or run `ONYX_DEPLOY=1 git push`. Netlify publishes
    site/ as-is with no build either way.

STEP 6 — The founder's checklist.
  End your final message with everything the founder must do by hand that no wave could —
  DDL they still need to paste, App Store Connect steps, Supabase settings, a device-only
  visual check. If the list is empty, say so explicitly.

DOCUMENTATION REQUIREMENT — append "Wave Record — W5" with the four headings: What was done /
Succeeded / Failed / Left open. "Left open" is the sprint's final state of the world; write it
for someone who was not here.
````

---

## Verification, end to end

After W5, the sprint is verified by doing these on a device, not in a test:

1. Start a workout, put the treadmill bout in — the Dynamic Island reads `mm:ss · km · pace`
   with a Cardio chip, never `0 kg × 0`.
2. Hit a PR mid-session — the cup appears on that tick, not after Finish.
3. Type `18.75`, `17.5`, `20` into a weight field — all three the same size, at 375 pt and at AX5.
4. Edit a finished workout with a treadmill in it — it stays in position 1; Records shows a
   number; Sets shows a count, not a fraction; Cancel returns everything to where it was.
5. Open Appearance, walk all nine themes — nothing unreadable, widget and watch follow.
6. Open the InBody sheet — already filled, Save disabled until you change something, waist in Mass.
7. Open Past Weeks — Week 0 is there, banners are short and phase-coloured, tapping one PUSHES
   a full page whose hero is a phase band over three rails, and there is no donut anywhere.
8. Tick the psyllium dose at 18:30 — the day gains 17 kcal, 4.4 g carbs, 3.9 g fiber, once.

---

# Wave Record — W1 · Nutrition, Stack UI & Typography

**Shipped `3.22.0` on 2026-09-17** from `onyx/w1-nutrition-stack-type`.

## What was done

**GOAL 1 — the Stack time editor is a wheel.**

| File:line | Change |
|---|---|
| `OnyxCore/Supplements/SupplementStack.swift:505-535` | New `Supplements.slotTime(from:calendar:now:)` and `slotTimeString(_:calendar:)`. They live in **OnyxCore**, beside `customSlotsForDate` which groups by the string they produce, because the spelling of `"HH:mm"` is domain and not presentation — and because a test for it then runs in `swift:core` without a simulator. |
| `Onyx/Features/Pulse/StackView.swift:390-440` | `timeRows` — a `Toggle("Set a time")` and, when it is on, a `.wheel` `DatePicker` at `[.hourAndMinute]`, clamped to 128 pt. Replaces the `TextField("Time", text: $time)` that was at `:387-389`. |
| `…/StackView.swift:333` | `Field.time` deleted from the focus enum. A wheel takes no keyboard. |

**Deviation from the brief, deliberately.** The prompt specified a
`DateFormatter` with `Locale(identifier: "en_US_POSIX")` and
`dateFormat = "HH:mm"`. `slotTimeString` uses `String(format: "%02d:%02d")` over
`Calendar.dateComponents` instead. Same output, one fewer object to
misconfigure: `%02d` is C-locale **by construction**, so there is no locale
property that a future edit could forget to set. The mutation test below shows
the difference is load-bearing, not cosmetic.

**GOAL 2 — supplements carry calories.**

| File:line | Change |
|---|---|
| `OnyxCore/Supplements/SupplementNutrients.swift:108-163` | New `StackMacros` and `macros(_:payloads:)` — same doses, same `credited` rule, same count multiplier as `credit`. |
| `OnyxData/Day/StackCredit.swift:19-42, 62-71` | `StackCredit.macros`, resolved from the same `payloads` dictionary in the same pass as `nutrients`. |
| `Onyx/Features/Nutrition/NutritionModel.swift:240-290` | `eaten` = food + credited stack. New private `eatenFood` holds the food-only sum; `macrosForEditing` reads **that**. |
| `scripts/add-supplement.mjs` | The seeder. Idempotent on `schedule->>key`, derives the per-dose payload from the label so the arithmetic is in the diff, and refuses to write without `ONYX_APPLY=1`. |

`custom_supplements` row **`b62dd39b-9006-4bbe-9c49-2832740feb2a`** — Psyllium
Husk Powder, `5 g` at `18:30`, `form: powder`, payload
`kcal 16.7 · carbs 4.4 · fiber 3.9 · protein 0 · fat 0 · sodium 5.6 · iron 0.83 · potassium 50`.
Verified back out of PostgREST after the write.

**Two judgement calls the brief did not settle:**

1. **The credit rule is `taken || due`, not `taken`.** The prompt said fold only
   on `supplement_log.taken`. The app's own rule — `SupplementDose.credited`,
   `SupplementStack.swift:245` — has always been `taken || due`, because the
   protocol is what happens unless you say otherwise. Using a stricter rule for
   macros than for micronutrients would let the nutrient grid credit a scoop's
   potassium while the ring refused its carbohydrate, for the same scoop, at the
   same minute. That is the shape of the water-has-two-truths bug this repo has
   already paid for once. The brief's actual intent — a planned dose must not
   inflate the total — is already served by `.later` never counting.
2. **`credit` was left unfiltered.** Its golden fixture (`stack-credit`, 40+
   cases) covers nine legacy payloads that carry no macro keys, so filtering
   would have changed nothing for them and risked a golden edit for no gain. The
   grid iterates `NutrientTargets.all`, so `kcal`/`carbs`/`fat` sitting in that
   dictionary are inert; `fiber` and `protein` **are** grid rows and are credited
   there on purpose. Documented at `SupplementNutrients.swift:142-148`.

**GOAL 3 — the numerals hold still.**

Root cause, and it was not the scale factor everyone would blame:
`SetColumn.weightFloor` was the constant `56`, which is six monospaced glyphs at
body's **17 pt and at no other size**. A `monospacedDigit` numeral advances at
~0.6 em and its decimal point at ~0.26, so `123.75` needs ~3.26 em — 55 pt at
17, 68 at Large, 76 at xxxLarge. Above the default the field ran out of room
between the fourth glyph and the fifth, and `.minimumScaleFactor(0.6)` shrank
exactly the strings that crossed it.

| File:line | Change |
|---|---|
| `Onyx/Features/Logger/ExerciseCardView.swift:1029-1048` | `weightFloor`'s doc rewritten; it is a BASE now. |
| `…:1056-1060` | `weightGroup` becomes `weightGroup(floor:)`. The unused constant is gone. |
| `…:41-44` and `…:1177-1181` | `@ScaledMetric(relativeTo: .body) private var loadFloor = SetColumn.weightFloor`, declared identically in `ExerciseCardView` (the header) and `SetRowView` (the rows). Same base, same text style, therefore the same number on both sides — which is the rule `columnHeaders:878-891` already depended on. |
| `…:911-915, 1617, 1699, 1731` | Six call sites repointed at the scaled floor. |
| `…:2408-2425` | `minimumScaleFactor(0.6)` **kept**, comment rewritten. |

**Second deviation, deliberately.** The brief's step 2 said to raise
`minimumScaleFactor` to 1.0 once the budget was fixed. It was conditional on
step 1, and step 1 makes it pointless: with the floor tracking the type, the
factor cannot fire on any load this app proposes, and raising it would only
bring the ellipsis back for a load typed past six glyphs — the case the comment
at `:2408` records as strictly worse than a small numeral. Smaller diff, same
outcome.

**Harness work this needed** (a control with no shot is a control nobody
reviewed):

| File:line | Change |
|---|---|
| `scripts/native-shot.sh:117-131` | New `SHOT_SIZE`. The default+AX5 pair **brackets** Dynamic Type and photographs neither of the four ordinary sizes between them — which is precisely where this defect lived, and why it survived a release. |
| `Onyx/Features/Pulse/PulsePreviews.swift:521-541` | New `stack-edit` case. `stack-add` opens on a new item, whose toggle is off, so it can only ever photograph the wheel's absence. |
| `Onyx/App/PreviewHarness.swift:436` | `stack-edit` registered. |
| `Onyx/Features/Logger/LoggerPreviews.swift:53-66` | `set-row` now seeds `20`, `17.5`, `18.75` on three adjacent rows — two, four and five glyphs, the founder's own three numbers. |

## Succeeded

**Package tests — every one green, and the new ones bite.**

| Suite | Before | After |
|---|---|---|
| `swift:core` | 565 tests / 118 suites | **575 / 119** |
| `swift:data` | 568 / 71 | **572 / 71** |
| `swift:ui` (inside `npm run check`) | 21 / 7 | 21 / 7 |

New: `SupplementMacroTests.swift` (10 tests) and four in `StackPushTests`.

**The new tests were mutation-tested, not just run.** Two mutations injected and
reverted:

- `slotTimeString` → a device-locale `DateFormatter`. Caught by four tests,
  including all five locales in `timeStringIsLocaleIndependent` and
  `sameMinuteIsOneSlot` (`slots.first?.time == "18:30"` failed — the exact
  second-slot bug the format exists to prevent).
- `macros` credit rule → `dose.state != .skipped`. Caught by
  `statesMatchTheMicroRule` at `SupplementMacroTests.swift:138`.

**The typography fix was photographed both ways, at the size that shows it.**
The bug does not appear at `medium` or at AX5 — the only two sizes the loop
shot. At `extra-extra-extra-large`:

- `scratchpad/before/set-row-extra-extra-extra-large.png` — floor reverted to the
  constant: `18.75` is visibly smaller than `20` and `17.5`.
- `native/__screenshots__/set-row-extra-extra-extra-large.png` — fixed: all three
  at one size, `KG` still centred over its column, `EFFORT` still fits
  "Very Hard" and "Max Effort".

Other shots read: `stack-edit.png` (wheel at 18:30, toggle on, dose `5 g`,
form Powder), `stack-add.png` (toggle off on a new item — correct),
`set-row-ax5.png` (stacked layout, all three loads full size),
`fuel.png` / `nutrients.png` (unchanged, as they should be — the preview stack
carries no macro payloads).

**Build:** `npm run check`, `check:swift`, `swift:core`, `swift:data` all green;
`xcodebuild -scheme Onyx -destination 'generic/platform=iOS'` **BUILD SUCCEEDED**.

## Failed

- **The OnyxTests baseline was measured late and imperfectly.** The background
  run was launched at the branch cut but `xcodebuild` reads the working tree at
  build time, so it compiled work in progress. It is therefore a POST-change
  run, not the baseline it was meant to be. Re-measuring cleanly costs a ~10
  minute run on `main`; it was not done.
- **The count in memory was wrong.** `refinement-ux-w1` records *five* baseline
  `OnyxTests` failures. This run shows **one**:
  `AppDatabaseTests.swift:254` — *"stores, retrieves and removes a session blob"*,
  `Keychain error -34018: A required entitlement isn't present`. That is the
  free-team constraint the runbook documents ("Keychain sharing… need the paid
  program"), not anything in this diff — but it was not proven against `main`,
  so it is asserted from the error text, not from a measurement.
- **The first screenshot attempt produced nothing.** Seven screens failed with
  `Unable to lookup in current state: Shutdown` because the background test run
  still held the simulator. Sequencing, not a defect — but a shot run launched
  beside a test run wastes ten minutes and, per the script's own header, can
  silently photograph the wrong build.
- **`set-row.png` at the default size cannot review this fix**, and neither can
  `set-row-ax5.png`. Both were re-shot and both look correct, but the claim they
  support is "nothing regressed", not "the bug is fixed". Only the `SHOT_SIZE`
  pass carries that.

## Left open

**For W2 and beyond:**

1. **The week strip does not know about the stack.** `NutritionModel.week` comes
   from `AppDatabase.nutritionWeekStream` (`OnyxData/Day/NutritionWeek.swift:53`),
   which reads `nutrition_entries` only. So today's ring now includes the
   psyllium while today's adherence dot and the seven-day strip do not. Closing
   it means resolving `stackCredit` for seven days inside that stream — real
   work, and **W4's weekly report will want exactly the same thing** for its
   Nutrition rail (`MacroAdherenceSeries.build`). Do it once, there.
2. **`WeeklyExportBuilder` has the same gap.** The exported week's macros are
   food-only for the same reason.
3. **`PulseModel.stackNutrients:786` has no consumer.** Dead since it was
   written. Left alone — deleting it is W5's kind of work, not W1's.
4. **W2's brief is confirmed by the compiler.** The app build warns
   `LoggerModel.swift:1577: initialization of immutable value 'floor' was never
   used` — divergence (e) in W2's GOAL 1, exactly as the plan predicted.
5. **`SHOT_SIZE` now exists and nothing else uses it.** Any wave touching a
   fixed width under a scaling font should shoot at
   `extra-extra-extra-large`, not trust the default+AX5 pair.

**Founder's manual checklist:**

- **Nothing is required to ship this wave.** No DDL, no Supabase setting, no App
  Store step.
- **Worth doing by eye on the phone:** open Pulse ▸ Stack ▸ Psyllium Husk Powder
  and confirm the wheel opens on 18:30; turn "Set a time" off and on and confirm
  the item moves to the top of the list and back. Then tick the 18:30 dose and
  confirm the Fuel tab's calorie ring moves by 17 kcal and the Nutrients grid's
  fibre row by 3.9 g.
- **W3 still needs its DDL** — `ALTER TABLE daily_logs ADD COLUMN waist_cm numeric;`
  — before that wave can run.

---

# Wave Record — W2

**Shipped `3.23.0` from `onyx/w2-live-logger-edit`, 2026-09-17.**

## What was done

**GOAL 1 — the live PR cup.** Root cause, as the brief framed it, plus two layers
under it that the brief could not have known about.

The identity a live candidate carries and the identity the bar is keyed on are now
the same value by construction. `LoggerModel.baselineIds()` resolves exactly ONE id
per card — `storedId(for:)`, the same call `refreshLivePrs` keys a candidate with —
and `rebuildBaselinesIfDeckMoved()` rebuilds the bar whenever that set moves. It is
called at the top of `refreshLivePrs`, which is the one place all eight tick paths
pass through. `buildLiveBaselines` lost its `excluding:`/`before:` parameters and
derives them from `sessionId` and `editing?.date`, which were the same two
expressions at both original call sites and are now correct at every later one.

Three things the brief asked about, answered:

- **(c)** `restoreLoggedSets` returning early on `sessionId == nil` is not a defect.
  A fresh workout has nothing logged to restore. Its real consequence — a slug-only
  baseline id set — is the same condition as (b) and the rebuild covers it.
- **(d)** `rebuildForPhase` now ends with `refreshLivePrs()`. It replaced `exercises`
  wholesale and recomputed neither the bar nor `prsThisSession`.
- **(e)** The rep-window `floor` local was **deleted**, not plumbed through.
  `PrCandidateSet` has no field to receive it, and passing this deck's phase would
  gate the e1RM axis by a different window than `PrRecorder.record` uses at close —
  a trophy the close path then refuses to file. The comment now says so.

**Two root causes the brief did not name, both found by making its own test pass:**

1. **Widening the baseline id set does not work, and would have looked like it did.**
   `PrRecorder.baselines:229` re-keys every gathered row to `keyByName[name(id)]`,
   built by uniquing on FIRST over a `Set` — whose iteration order is a hash. Hand it
   both the slug and the uuid for one movement and the bar lands under whichever the
   hash visited first. That is why the symptom came and went between launches. One
   resolved id per card is the fix; `baselines` gathers the movement's other ids by
   canonical name itself (`siblings`), so nothing narrowed.

2. **A minted catalogue row erased the movement's history.** `createExercise` wrote
   `slug: nil` on principle ("a row created now has no such history and never will").
   False for its one important caller: `storedIdCreatingCatalogueRow` mints EXACTLY
   when the catalogue has never heard of a movement, which is exactly when the deck
   has been writing that movement's sets under `ExerciseSlug.id(name)`. With the
   column nil, `nameBySlug` cannot resolve those rows, the sibling gather misses them
   by name, and the whole history drops out of the bar the instant the movement gets
   a row. `createExercise` now claims the slug **when, and only when, `workout_sets`
   already holds rows under it** (`slugWithHistory`).

**GOAL 2 — treadmill in the Dynamic Island and on the Lock Screen.** `ContentState`
gained `cardioElapsedSec: Int?` and `cardioDistanceKm: Double?` — optionals only, per
the load-bearing rule at `OnyxWorkoutAttributes.swift:114-121`. One formatter,
`cardioLine(sec:km:pace:)` in the shared `WorkoutActivityCard.swift`, serves the lock
card, the island and the watch; it reuses `SetFormat.cardio` and
`CardioMetrics.paceMinPerKm`, both of which already refuse zero, negative and
non-finite input, so there is no new divide to guard. `LiveActivityController` now
branches on `row.isCardio` BEFORE the `if let kg, let reps` that the treadmill's
non-nil zeros were satisfying. `OnyxWidgets.swift:296` got a real branch, not a real
field: the compact slot needs one number and the wire already carries it.

**GOAL 3 — the Cardio tag.** `SeedSet` and `SeedRow` gained `durationSec`/`incline`/`distanceKm`,
`SessionHistoryStore` fills them and `LoggerModel.setRow(SeedRow)` forwards them, so a
seeded bout is a bout — which is the fallback `LoggerModel.primaryMuscle` was always
waiting on. The card draws an explicit **Cardio** chip, and its rail tests `isCardio`
before `family`.

The brief's 3(b) — teach `Program.swift:121` to consult `MuscleMap.cardioMovers` — was
implemented, shipped into the first commit, and then **reverted**. See the review round
below; it was the one change in this wave that was actively wrong.

**GOAL 4 — performed order on an edit deck.** `LoggerModel.init` gained
`openingForEdit`, passed only by `SessionDetailView.openEditor`. An edit deck does not
read `storedDeckOrder` and does not prepend the warm-up bout; the `removeAll` in
`attach(editing:)` that used to undo the prepend is gone.

**GOAL 5 — the finish tiles.** Records is fixed by GOAL 1 and by the floor change
below. Sets reads the performed count alone on an edit deck.

**GOAL 6 — Cancel Edit.** A `session_edit_marks` table (migration `v29`) persists a
`(device_id, seq)` watermark stamped by `attach(editing:)`. `revertSessionEdits`
folds the session's events twice — once whole, once with this device's post-watermark
events excluded — diffs the two projections and appends compensating events, then
reprojects, replays the PR ledger and recounts. Nothing is deleted. Save and the
chevron both clear the mark.

## Succeeded

- **The live PR path and the ledger agree, three ways, across the flip.** A set that
  beats a standing record now lights `isRecord` on the FIRST tick with the catalogue
  row minted mid-session; the deck's `recordCount`, the `pr_count` `closeSession`
  writes, and the same session re-opened for editing all report the same number.
- A phase switch mid-session keeps every trophy already awarded.
- `npm run check`, `check:swift`, `swift:core` (575 tests, PR golden vectors
  **unchanged**), `swift:data` (581 tests) and the `xcodebuild` app/widget/watch build
  are all green.
- **OnyxTests is exactly at baseline.** Recorded before any edit: **10 issues across 4
  tests in 3 suites** — History weeks (3), Workout week (5), Session summary — the
  hotfix (2). After the wave: the same 10, same suites, nothing new. *(The plan's
  "five known baseline failures" undercounts: 5 is the issue count of two of the three
  suites. The number to compare against next wave is 10 issues / 4 tests.)*
- Verified by eye, simulator: `set-row-cardio` draws the **Cardio** chip, the cardio
  rail and `13:31 /km`; `widgets-activity` draws
  `Treadmill · 12:30 · 2.19 km · 5:42 /km` on the lock card.
- New tests, all failing first: `LivePrIdentityTests` (6), `LiveActivityCardioTests`
  (8), `SessionRevertTests` (9).

## Failed

- **Nothing was reverted, but one brief premise was wrong and is recorded as such.**
  GOAL 4(a) — "the warm-up/treadmill card must be written with an `exercise_order`
  like every other card; find why the cardio row misses it" — has no defect behind it.
  `snapshot` writes `deckOrder(of:)`, `SetEventFold` carries it, `SyncTranslation`
  sends it (`v16.exerciseOrder`), and the live table agrees: **of 8 cardio rows in
  Supabase, 8 carry `exercise_order = 0` and none is null.** The real cause of
  "treadmill drops to the bottom on edit" is `inDeckOrder` ranking the edited session
  against `deckOrder(dayKey:)` — the template left by the most recent session on that
  day key, which is almost never the one being edited — where an unranked movement
  sorts to `count + index`, i.e. last. Fixed there instead.
- The brief's example cardio line, `12:30 · 0.37 km · 5:42/km`, does not close
  arithmetically (750 s over 0.37 km is 33:47/km). The fixture uses 750 s over
  2.19 km, which is 5:42/km, so the shot can be checked against itself.

## Left open

- **Do the live PR path and `SessionAnalysis` agree on the founder's FULL history?
  Not proven, and not provable from here.** What is proven is the three-way agreement
  described above on a session constructed to contain the exact failure — slug
  history, empty-of-that-movement catalogue, a mint at the first commit — plus
  575 + 581 package tests including the hand-maintained PR golden vectors, which were
  not regenerated. A real answer needs `recomputeAllPrs` run against the founder's own
  store on the device and its output diffed against `personal_records`; that is a
  device-side write and was not run. **It is the first thing to do on the next
  device build.** Note the direction of the remaining risk is the safe one: the slug
  fix and the sibling gather can only widen a bar, and a wider bar removes false
  trophies rather than inventing them.
- **The `exercise_order` backfill was NOT run, deliberately.** The live database has
  **18 rows with a null `exercise_order`, all in one session** (`8a780ded…`,
  2026-09-06, `cb_a`), and **none of them is cardio**. An order is technically
  derivable from `created_at` (15 distinct instants, 7 distinct movements by first
  appearance) but the session interleaves — three movements recur later in the log —
  so any single `exercise_order` per movement is a reconstruction, not a record. With
  the reported symptom fixed at its real cause and no cardio row affected, writing
  invented history to production for one session is the worse trade.
- **`revertSessionEdits` has four named limitations**, all in the code: a restored set
  gets a new id and so moves to the end of its `setIndex` tie group (visible only for
  a split pair where one side was restored); the PR ledger returns in `replay`'s frame
  rather than `record`'s (pre-existing — the first `amendSet` of any sitting already
  does this); a permanently-poisoned void outbox item leaves both the old and the new
  server row (pre-existing for every void); and the watermark is per `(session,
  device)`, so a revert cannot and does not undo another device's edits.
- **The delete-on-reconcile claim behind Cancel is read from `SyncEngine:305-310` and
  `PostgRESTRemote:57-65`, not from Supabase.** Worth one manual check: edit a synced
  session, Cancel, drain, confirm the old `workout_sets` row is gone and the new id is
  present.
- **No Dynamic Island was photographed.** A simulator cannot render one. The lock card
  and the compact/expanded island were verified through the widget preview screens
  (`widgets-activity`, `widgets-island`); the real island, and the watch card at
  40 mm, want one device glance.
- `session-edit` is not a screen the shot harness knows. The edit deck was verified by
  test, not by pixel; the new Cancel button (`arrow.uturn.backward`, leading group,
  beside the chevron) has never been photographed at any text size.

## Review round — what the audit and the code review changed

Both ran against the committed wave. Neither found a defect in the PR/scoring path
itself; both found real defects around it, and one of them was a change the brief
had asked for.

**Reverted: the brief's GOAL 3(b).** `ProgramExercise.init` was taught to fall back to
`MuscleMap.cardioMovers`. It was wrong three ways:

- `LoggerModel.muscleSets` builds `MuscleCredit.weightedSets` — **the** accumulator —
  out of `plan.movers`. `cardioMovers`' own header states the invariant it broke:
  *"Nothing here reaches an accumulator."* A ticked warm-up walk began paying quad and
  calf credit into the distribution sheet and Live Stats. `MuscleMap.dict` stayed
  clean, so the rule everyone remembers was honoured and the leak went around it.
- `LoggerModel.primaryMuscle` **already** answers `"cardio"` for a bout by testing the
  rows. A non-nil `movers.primary` outranks that branch, so the Live Activity chip —
  the one the brief said "will light once (b) is fixed" — read **QUADS** on a
  treadmill. The first screenshot round photographed that and I read it as correct,
  because I had hand-written `primaryMuscle: "quadriceps"` into the fixture.
- It was not needed. The tag and the rail are `isCardio`-driven, and GOAL 3(a) is what
  makes `isCardio` true on a seeded bout.

The test written for it was asserting the bug (`#expect(bout.plan.movers.primary.isEmpty
== false)`). It is inverted now and ticks the bout to assert `model.muscleSets.isEmpty`.

**Fixed: `editWatermarked` was declared, written twice, and read nowhere.** Its own
header said the Cancel button reads it. The button was gated on `isEditing` alone, so a
session whose `markEditStart` had failed (busy store, unapplied migration) opened an
editor whose Discard button ran, reverted nothing, and dismissed reporting success —
after a dialog promising *"every set goes back to the way it was."* The button is gated
now, and `cancelEdit` treats `revertSessionEdits`' nil return as "nothing was undone"
rather than as success.

**Fixed: `cancelEdit` cleared the mark one line after the revert re-wrote it.**
`revertSessionEdits` re-marks deliberately, so a screen that stays open is still
cancellable. Clearing it made the second sitting silently un-revertable.

**Fixed: `cancelEdit` left ticked rows on a card the revert had emptied.**
`restoreLoggedSets` folds onto the deck and skips a card with no logged rows, so a
movement ADDED during the sitting kept rows describing sets that no longer existed —
and a tick on one would append behind a terminal tombstone and vanish. The deck is
blanked before it is rebuilt.

**Fixed: the bar was built twice per screen open, and the first one was unbounded.**
`rebuildBaselinesIfDeckMoved()` ran at the TOP of `refreshLivePrs`, which `init` now
reaches through `rebuildForPhase` — before `sessionId` or `editing` exist. That build
had no exclusion and no date bound, i.e. the edited session's own sets folded into the
bar it is judged against. Unreadable (candidates are empty there) and overwritten by
`attach`, but a loaded gun inside the one function whose invariant forbids exactly
that. The rebuild moved below the early return; the keys never came from the bar, so
the ordering was free.

**Fixed: an incline-only bout drew an empty slot.** `SetRow.isCardio` is true on an
incline alone, and the producer forwards only duration and distance — so typing the
incline first left the Lock Screen, the island and the wrist drawing nothing at all
where the set used to be.

**Fixed: `slugWithHistory` could let two catalogue rows claim one slug.**
`ExerciseSlug.id` is a lossy collapse — `Crunch Machine` and `Crunch (Machine)` give
the same slug — and `ExerciseIndex.bySlug` uniques on FIRST, which is the silent MERGE
that file exists to prevent. It now declines a slug another row already claims, which
is the same refusal `exerciseIds(byCanonicalNameIn:)` makes one file over.

**Fixed: three comment blocks that no longer described their code** — two in
`attach`/`attach(editing:)` still arguing for the id UNION that `baselineIds` now
exists to refuse (a reader trusting them would have reintroduced the hash-order
nondeterminism this wave removed), and two in `ExerciseCardView` crediting the reverted
cardio fallback.

**Left standing, with the reasoning recorded rather than changed:** if a
`personal_records` row owned by the judged session has a null `floor_value` (a web-written
row, or one predating `carryFloor`), excluding it drops the ledger tier for that axis and
the edit deck falls back to `workout_sets` — the tier that cannot see a movement whose
catalogue row has not been pulled. That is the 2026-09-14 false-trophy case the standing
-record tier was invented for. It now agrees with `record` and with a replay, both of
which read `workout_sets` only, so the behaviour is right and the gap is a documentation
item, not a code one.

---
# Wave Record — W3 · InBody & Appearance overhaul

**Shipped `3.24.0` from `onyx/w3-inbody-appearance`, 2026-09-17.**

## What was done

**GOAL 1 — the theme spec grew a mood knob.**

| File:line | Change |
|---|---|
| `OnyxCore/Design/OnyxThemeSpec.swift:24-26` | `chroma: Double` (a SCALE, 0.6…1.0) and `lift: Double` (an OFFSET, −0.06…+0.06). |
| `…/OnyxThemeSpec.swift:47-53` | A hand-written `init(from:)`, `decodeIfPresent` on the two new keys. **This is the wave's one silent-catastrophe guard** — see below. |
| `…/OnyxThemeSpec.swift:92-99, 121-128` | `normalised()` clamps the knobs too, through `bounded(_:_:fallback:)`, which refuses a non-finite value rather than clamping it. `clamp(_ hex:)` was renamed `guarded(_ hex:)` and made **public**: OnyxUI now derives two more accents and they must go through the same guard. |
| `OnyxCore/Design/OKLCH.swift:89-112` | `OKLCHConvert.mood(_:chroma:lift:)` — the whole knob, at fixed hue. Short-circuits to the same bits on a neutral knob, exactly as `rotate` does for a zero delta, which is what keeps the default palette bit-identical. |
| `OnyxUI/DesignSystem/OnyxTheme.swift:52-84` | The derivation. |

**Which colours the knob moves, and why not the others.** The brief said "the
derived stops — `end[domain]`, the washes, the surfaces". There are no tokens
actually named *wash* or *surface*; the derived set in `OnyxTheme` is the four
ends, the two derived starts, and the sixteen muscles. Each got a different rule,
and each rule came out of measurement rather than out of the brief:

- **The two chosen accents are untouched.** `start[.train]` is the primary and
  `start[.fuel]` is the secondary, exactly as picked. The Appearance swatch draws
  those two hexes, so a knob that moved them would make the control disagree with
  the screen.
- **The two derived accents** — `start[.body]`, `start[.recover]` — take the knob
  and then go back through `OnyxThemeSpec.guarded`. They tint section headers and
  gauges, so they carry text. Measured: Body sits at L 0.698 and Recover at
  0.729, so a −0.06 lift lands at 0.638 and 0.669 and the guard never bites; the
  guard is there for the theme nobody has picked yet.
- **The four ends take the knob and then `OnyxThemeSpec.floored`** — the L ≥ 0.60
  half of the guard and nothing else. This was "unguarded, they are gradient
  stops" until code review measured it, and the premise was false:
  `OnyxDomain.body.end` is the ink of the LEAN SOFT TISSUE numeral on two widget
  faces (`OnyxComposition.swift:157`, `OnyxLifestyle.swift:796`), a 12–14 pt
  figure on black. A primary of `0xE3A650` — the app's own Solar accent, on
  which `normalised()` is the identity — at chroma 1.0 and lift −0.06 put it at
  **4.46:1**. The floor and nothing more, because an end is also allowed to be
  *light*: `recover.end` sits at L 0.868 and the full `guarded` would crush it
  to the 0.78 saturation ceiling.
- **The sixteen muscles take the CHROMA SCALE ONLY.** This is a deviation from
  the brief and it is load-bearing. Measured, the palette's lightness ladder *is*
  the family ramp: the five legs run L 0.830 · 0.766 · 0.699 · 0.636 · 0.569 in
  even steps, and **Calves is already at 4.99:1 on black — 0.03 of L above AA**.
  A lift either flattens the ladder (if floored at 0.60) or drops Calves to about
  4.15:1 (if not). Muting or saturating the data palette is the whole mood the
  knob owes them, and chroma does that without touching a measured ordering.

**Why `lift` could not have been applied to the accents at all.** A negative lift
on an accent already at the 0.60 floor is clamped straight back by the contrast
guard and does nothing; a positive one caps at 0.78. The knob would have read as
dead on exactly the themes it was added for. Documented in the guard's own
header, in the register the existing comments use.

**The decode trap, measured rather than assumed.** Swift's synthesised
`Decodable` requires a key for every non-Optional property — a default value on
the property does not save it. Every install written before this wave holds
`{"primary":…,"secondary":…}` at `OnyxTheme.key`, and `OnyxTheme.apply(json:)`
falls back to `.default` on **any** decode failure, silently. With the
synthesised conformance, adding two stored properties would have reset every
themed install to Ion on the next launch, with no error and nothing to notice.
The test holds the literal old two-key blob.

**The widget and the watch were verified, not re-fixed.**
`WatchPayloads.WatchContext:52` carries `theme: OnyxThemeSpec?` whole, and
`OnyxProvider.theme():96-100` reloads from the App Group defaults on every
timeline build. Both already work, and the new `init(from:)` makes the cross-
version cases work in both directions: an old phone's two-key spec decodes on a
new watch as the neutral knob, and a new phone's four-key spec decodes on an old
watch because the old synthesised decoder ignores keys it does not know.

**GOAL 2 — eight new presets, nine in all.**

`OnyxTheme.presets:138-166`. Ion stays first and is still `OnyxThemeSpec.default`
(the plan's own correction on the founder's behalf, and it is right: `AppearanceView`
says "Reset to Ion" and `SettingsTabView` names the current theme by matching
against this array).

Every pair was **solved**, not picked. A throwaway test inside `OnyxCoreTests`
ran `OKLCHConvert.hex(from: OKLCH(l:c:h:))` over a chosen (L, C, h) inside the
guard box, put the secondary at h + 120°, and printed three things per candidate:
the round-tripped hex, whether `normalised()` was the identity on it, and its
contrast on black. The first hue table it produced was rejected by its own
pairwise-separation check — Ion vs Basalt came out 21° apart and Obsidian vs
Meridian 25° — so the hues were re-spread and re-solved. The scratch test was
deleted before the merge; `swift:core` is back to its 575.

| Theme | primary | secondary | h° | chroma | lift | on black |
|---|---|---|---|---|---|---|
| Ion | `0x6B78F0` | `0xE3A650` | 275.3 | 1.00 | 0.00 | 5.57 / 9.84 |
| Obsidian | `0x3C90B8` | `0xB46C8C` | 232.3 | 0.62 | −0.05 | 5.87 / 5.46 |
| Solstice | `0xE5A323` | `0x30C8CC` | 77.7 | 0.94 | +0.03 | 9.59 / 10.26 |
| Meridian | `0x19BCB9` | `0xC18BDE` | 192.7 | 0.86 | 0.00 | 8.94 / 8.02 |
| Basalt | `0xB58194` | `0x909866` | 355.5 | 0.66 | −0.03 | 6.53 / 6.87 |
| Aurora | `0x31D96D` | `0x9CB4FE` | 149.9 | 1.00 | +0.05 | 11.28 / 10.37 |
| Terracotta | `0xE57255` | `0x32B36E` | 40.3 | 0.80 | −0.02 | 6.87 / 7.81 |
| Vesper | `0xAA72C2` | `0xBA7F14` | 309.8 | 0.72 | −0.04 | 5.90 / 6.13 |
| Halcyon | `0xAAB354` | `0x51B7EB` | 113.8 | 0.88 | +0.04 | 9.29 / 9.32 |

Minimum pairwise separation across the nine primaries is **36°**, measured, not
assumed from list order. Every one is a `normalised()` fixed point, so the source
shows exactly what ships.

**The chip re-layout.** `AppearanceView.swift:43-57`. The brief flagged
`.lineLimit(1)` as a tripwire rather than a fix, and it was right: at `.caption`
semibold "Terracotta" is ~67 pt of text, and with the 22 pt swatch, its 8 pt gap
and 12 pt of padding each side the chip needs ~121 pt. Three columns cannot hold
that on a 393 pt phone, so `chipWidth` went 100 → **126** and the grid is two
columns and five rows — one column at the accessibility sizes, where the shot
shows every name in full.

**The sliders.** `AppearanceView.swift:196-263`. "Saturation" reads as a
percentage; "Lift" reads ×100 and signed, because the stored value is an OKLCH
lightness offset and `0.03` means nothing to anyone. They edit the draft like
every other control here, and the `derived` preview at `:271` already renders
from the uncommitted draft, so it shows the knobs working for free.

**GOAL 3 — the waist.**

**The founder had already pasted the DDL.** `schema-truth-checker` introspected
the live database before any edit: `daily_logs.waist_cm` **already exists** —
`numeric`, nullable, no default, 0 of 167 rows populated. `body_measurements`
does not exist. So the wave's one blocking dependency was never blocking.

| File:line | Change |
|---|---|
| `native/schema/supabase.json:55` | `waist_cm:numeric?` added to `daily_logs`, after `estimated_waist_to_hip_ratio`. |
| `OnyxData/Mirror/MirrorModels.swift` | **Regenerated** — `npm run mirror`, never hand-edited. `check:mirror` is green. |
| `OnyxData/Database/AppDatabase.swift:1265-1289` | `v30.waistCm` — the guarded ALTER for stores that already exist, the shape `v20.sleepInaccurate` uses. |
| `OnyxData/Day/DayEditing.swift:158-160` | `waist_cm` added to `latestBodyReading`'s `IS NOT NULL` list. Without it a waist-only day was invisible to the carry-forward and the next weigh-in would have opened blank. |

The three "never" comments were **replaced with the decision and its date**,
not deleted:

- `OnyxCore/Body/Composition.swift:10-21` — the rule is narrowed rather than
  reversed. Nothing in that file computes a girth, infers one, or turns one into
  a body-fat estimate; the waist is stored and shown and the arithmetic never
  reads it. In particular the W:H ratio is **not** recomputed from `waist_cm` —
  there is no hip measurement and there is not going to be one.
- `native/schema/supabase.json:15-21` — the tape TABLE stays out. A column on the
  day is not a tape table: there is one number, it sits in the reading it was
  taken with, and there is still nowhere for hips, thighs or arms to land.
- `Onyx/Features/Settings/BodyTargetsView.swift:14-21` — and the waist is
  deliberately still absent from *this* screen, which is about where the plan is
  going. A waist target is a number you cannot train toward directly, only
  arrive at.
- `OnyxData/Day/DayEditing.swift:83-90` — a fourth one the brief did not name,
  and the one that would actually have misled the next reader, since it sat on
  the write path. The waist rides the day row only: `body_composition` is the
  HealthKit twin and HealthKit has no waist type, so mirroring it there would
  invent a column the other writer could never fill.

**GOAL 4 — InBody, Concept A.** `native/Onyx/Features/Pulse/PulseScale.swift`.

- **The hero** (`:325-375`): body fat as the headline numeral, weight and
  skeletal muscle as satellites, each with a ▲/▼ against `latestBodyReading()`.
  The AX5 collapse is the `typeSize.isAccessibilitySize` switch `WeekHeroCard`
  uses and deliberately **not** `ViewThatFits` — both satellites carry
  `.frame(maxWidth: .infinity)`, which tells `ViewThatFits` the row fits any
  width, so the stacked branch would be dead code (the W4 defect).
- **Four accordions** (`:452-480`) replacing the three-group grid: Mass,
  Composition, Water & protein, Minerals & derived. A shut group still says
  "3 of 4", so nobody has to open all four to find the field the scale did not
  report.
- **`derivedSection` is gone.** All six derived masses now sit in the group each
  was computed inside — fat and fat-free under Mass, water and protein masses
  under Water & protein, bone mineral mass and lean soft tissue under Minerals.
- **`fillSection` and `fillFooter` are deleted** — two buttons, a disabled state
  and three sentences of footer copy spent asking a question with one sensible
  answer. The form arrives full: previous reading first, Apple Health over the
  top of it for the three fields Health can answer.
- **The provenance caption is free.** `OnyxFieldCell`'s hint line was already
  reserved, so `Health` / `Last` / `You` costs no layout. The old `= 12.4 kg`
  live-mass hint was retired with it, because the mass it named is now a visible
  row in the same accordion.

**The trap, and the state shape it forced.** `DaySheet(… primary: ("Save",
!pending.isEmpty, save))` gates Save on there being something to write. The seed
is therefore a **separate layer**: `draft` is what the day holds plus what the
user typed, `seed` is only what the sheet offered, and `touched` records the
fields the user has operated so that clearing a pre-filled field sticks. The rule
is lifted out of the view into `InBodySaveGate.pendingFields` (`:96-118`) — with
a reading on the day, only real edits count; with no reading, the seeded figures
are offered too, because there is nothing to duplicate and a weigh-in that needed
no corrections still has to be recorded.

`RowPush`'s nil-omitting merge is intact and now has a test that says so: a day
with no waist does not send the key at all.

## Succeeded

- **`npm run check`** green — version `3.24.0 (32400)` in sync, atlas, mirror and
  doms all up to date. **`check:swift`** green. **`swift:core`** 575 tests (same
  as W2 — the scratch solver was deleted). **`swift:data`** 583 tests (581 + the
  two new waist tests). **`swift:ui`** 27 tests (21 + six new).
- The **app / widget / watch** `xcodebuild` for `generic/platform=iOS`: **BUILD
  SUCCEEDED**, no new warnings.
- **OnyxTests is exactly at baseline.** Recorded from a clean `main` worktree
  before any edit: **10 issues across 4 tests in 3 suites** — History weeks (3),
  Workout week (5), Session summary — the hotfix (2). After the wave: the same
  10, the same suites, nothing new. This matches W2's recorded figure exactly.
- New tests, **all written to fail first**:
  - `OnyxThemeTests` (+6): an old two-key blob keeps its theme and lands on the
    neutral knob; the neutral knob is today's palette and a turned one is not;
    **no knob puts a themed ink under AA anywhere a user can go** — the hue
    circle at 10°, both corners of the guard box, four chroma values and five
    lifts, reporting the worst ink found; the sixteen muscles keep their
    lightness ladder under every knob; the knob is clamped on the way in, a NaN
    falls back and a slider's `-0.019999999999999997` lands on `-0.02`; every
    preset declares a knob inside the published ranges, with at least one preset
    each side of neutral.
  - `InBodySaveGateTests` (+9, `native/OnyxTests/`): the untouched-sheet case,
    the single-edit case, the fresh-day case, the cleared-seed case, the
    cleared-stored case, the typed-on-empty case, the re-typed-identical case,
    and the two that hold the mass rule — a seeded percentage never reaches a
    mass column, and a typed one overrides the day's own.
  - `RowPushTests` (+2): a waist lands on the day, survives the mirror and rides
    the push — and a day with no waist does not send the key.
  - `MirrorTests`: `daily_logs` is 52 columns, and the 52nd is `waist_cm`.
- **Two arithmetic slips were caught by the tests rather than by review.** The
  old-blob test was first written with a hand-converted decimal (`15036501` for
  `0xE57255`) and failed; the JSON now interpolates the hexes so the literal
  cannot drift from the theme it claims to assert. And the first preset hue table
  failed its own separation check before it was ever written to source.
- Screenshots, `SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w3`:
  `scale`, `scale-first`, `appearance`, `appearance-locked`, `day`,
  `body-trends`, each at the default size and at AX5, plus
  `scale-accessibility-extra-extra-extra-large` for the hero re-check. Nine
  per-theme sets (`day`, `train`, `appearance`) under `themes/<Name>/`.

**Three defects found by `code-reviewer`, all fixed, all now covered by a test
that fails without the fix:**

1. **[HIGH] The echo guard compared the wrong two values.** The guard added for
   defect 1 below was `new != value(spec)`. But `OnyxNumberField` does not echo
   the value — it echoes the value put through the FIELD's own precision:
   `format` uses `.fractionLength(0...fractionLength)` and `parse` reads that
   rounded text back. `DailyLogIngest.swift:154` writes `weight_kg` straight off
   HealthKit at full precision, so a seed of `64.8347` renders "64.8", echoes
   back `64.8`, fails the equality test and lands in `draft` — arming Save on an
   untouched sheet of a day that already holds a reading, which is the exact
   duplicate write the two-layer design exists to prevent. Both sides now go
   through the same rounding the field does (`PulseScale.swift:265-271`). The
   shot loop could not have caught this: every value in the preview fixture is
   exactly representable at its field's precision.
2. **[HIGH] `save()` wrote six mass columns the gate had refused.** `derived`
   reads `value(_:)`, which falls through to the seed, and `save()` wrote all
   six masses outside `patch`. On a day holding a weight and nothing else,
   correcting the WAIST and pressing Save wrote `fat_mass_kg`,
   `fat_free_mass_kg`, `muscle_mass_kg`, `water_mass_kg`, `bone_mineral_kg` and
   `protein_mass_kg` computed from LAST WEEK's percentages, while the percentage
   columns on that row stayed null — a composition point with nothing behind it,
   which Body trends and both `OnyxComposition` widget faces then draw. A W3
   regression: on `main` `derived` read `draft` only. The rule is now
   `InBodySaveGate.massInputs` — the day's own values with the fields actually
   being written laid over them, never the seed — and the screen keeps its own
   `derived` so the read-only rows still show what the numbers in front of you
   are worth.
3. **[MEDIUM] The contrast guarantee was false, and the test could not see it.**
   Covered above under GOAL 1. The test that missed it was wrong in three
   separate ways, all instructive: it pinned `chroma: 0.6` on the reasoning that
   the lowest saturation was the harshest case (measured, it is the SAFEST —
   lowering chroma at fixed L moves toward that lightness's neutral, 5.3:1 on
   black); it read only `theme.start`, never `theme.end`; and it swept the nine
   PRESET hues, while the failing band is 114°–160° of rotation where no preset
   sits — but the screen has a `ColorPicker`, so every hue in the guard box is
   reachable. The replacement sweeps the hue circle at 10°, both corners of the
   guard box, four chroma values and five lifts, and reports the worst ink it
   found. Verified failing-first by removing the floor.

Two lower findings were accepted as correct and deliberately not changed —
see **Left open**. One was fixed: the slider's own floating-point arithmetic
(`Slider(value:in:step:)` snaps to `lowerBound + n × step`, so the Terracotta
position on the lift slider is `-0.019999999999999997`, and `AppearanceView`
lights a chip by exact equality). `bounded` now rounds both knobs onto the
two-decimal grid every preset is written on.

**Four defects the brief did not name, all found by the shot loop:**

1. **`OnyxNumberField` writes back through its binding on the first frame.**
   `.onAppear` sets `text` from the value, and `.onChange(of: text)` writes the
   parsed result straight back out. For its other eleven callers that is a no-op
   — their binding *is* the source of truth. Here it collapsed the two layers on
   the first render: every seeded value moved into `draft`, the captions read
   "You" on numbers carried in from last week, and the save gate had become a
   function of a render. Fixed with an echo guard in the binding's setter
   (`PulseScale.swift:493-506`) — a write carrying the value the getter just
   produced is dropped, anything else is the user, including a clear to nil.
   Fixed in *this* binding rather than in the shared control, because the
   write-back is correct behaviour for a binding that owns its value.
2. **The derived masses rendered whole.** `OnyxHeldRow` hard-coded
   `fractionLength(0)`, so fat mass read "10 kg" where the figure is 10.2 and the
   week-to-week move is three or four hundred grams. It has a `fraction`
   parameter now, defaulting to 0 so the five levers rows are untouched.
3. **Three "level" chips on an untouched form.** A pre-filled field holds the
   previous reading itself, so a delta drawn against it is level *by
   construction* — the hero was announcing three times that a weigh-in which had
   not happened yet had changed nothing. The chip is now drawn only for a figure
   the day owns or the user has typed, and appears live as the numbers go in.
4. **Two AX5 defects in the hero.** "SKELETAL MUSCLE" truncated to "SKELETAL
   MUSC…" under `.lineLimit(1)` — a register label is uppercase and tracked out,
   and at AX5 it is wider than the phone even with the whole row to itself. And
   the blank line reserved to keep two side-by-side satellites the same height
   was still being reserved when they were stacked, putting 22 pt of nothing in
   the middle of the card. Both fixed at `PulseScale.swift:389-421`.

## Failed

- **The brief's screenshot command names a screen that does not exist.**
  `SHOT_THEME=Obsidian scripts/native-shot.sh tabs` — there is no `tabs` screen
  in `PreviewHarness.Screen`, and an unknown name renders a visible error rather
  than failing, so the run would have produced nine PNGs of an error message.
  Substituted `day train appearance`, which between them draw all four domain
  ramps, the muscle palette, the sparkline series and the preset chips.
- **The first attempt to record the OnyxTests baseline measured nothing.** The
  command was `xcodebuild … | tail -80 > file`, so the file held the last test
  bundle's summary and the pipeline's exit code was `tail`'s. Re-run properly in
  a `git worktree` at `main` with the full log captured — which then failed with
  `'Onyx.xcodeproj' does not exist`, because `xcodegen` refuses a worktree whose
  `native/Onyx/Support/Secrets.xcconfig` is absent (it is not tracked). Copying
  that one file in was enough. Worth knowing before the next wave cuts a
  worktree to measure something.
- **`InBodySaveGateTests` crashed with `signal trap` on its first run**, not a
  compile error — `Field` and the gate were nested inside `InBodyEntryView`, and
  a `View` is `@MainActor`-isolated along with everything declared in it,
  including a `CaseIterable` witness. This is the trap `w1a-week-wrapped`
  records. Both moved to file scope as `InBodyField` and `InBodySaveGate`, which
  is where the gate belonged anyway.

## Left open

**The founder's manual checklist — one item, and it is already done:**

- **The DDL was already pasted.** `ALTER TABLE daily_logs ADD COLUMN waist_cm
  numeric;` is live as of the introspection on 2026-09-17 — `numeric`, nullable,
  no default. **Nothing is required of the founder for this wave.**
- **`npm run check:mirror` is green**, and `MirrorModels.swift` was regenerated
  rather than hand-edited.

**Seams W4+ inherits:**

- **`daily_logs.hrv_overnight` is live but unmirrored.** The introspection turned
  up a 53rd column on the live table — `boolean NOT NULL DEFAULT false` — that
  `native/schema/supabase.json` does not list. Pre-existing drift, unrelated to
  this wave, and harmless while nothing reads it; but the fixture's claim to be a
  faithful introspection is now one column short. Add it or document why not.
- **The muscle palette takes chroma but not lift, and that asymmetry is not
  visible anywhere in the UI.** A user who drags Lift to −0.06 moves the ramps
  and the two derived accents and sees the sixteen data colours stay where they
  are. That is the right behaviour and it is documented in `OnyxTheme`'s header
  and defended by a test, but the Appearance footer does not say it. If W4 or W5
  touches that copy, it is one clause.
- **The `derived` preview shows ramps only.** It draws the four domain ramps from
  the uncommitted draft, which is what makes the knobs legible — but the muscle
  palette is sixteen of the twenty-six colours a theme moves and none of them is
  previewed. A sixteen-swatch row under the ramps would make Saturation's effect
  obvious; it was out of scope here.
- **Nothing in `npm run check` runs `OnyxTests`.** `scripts/swift-ui-test.sh`
  passes `-only-testing:OnyxUITests`, so `InBodySaveGateTests` — written
  precisely because there is no screenshot that can show the save gate is right
  — is executed by nothing in the gate. It was run by hand for this wave (9/9).
  Wiring it in is not a one-line change: the bundle carries the 10 baseline
  failures below, so adding it turns `npm run check` red on `main`. That is a
  sprint-level decision and W5's audit is where it belongs.
- **On a day that already holds a reading, a seeded field the athlete AGREES
  with cannot be committed.** Save only counts real edits, so the only way to
  accept a carried-forward figure is to type a different value and type it back.
  The `Last` caption is the only signal that the number on screen is not on the
  row. This is the specified behaviour — it is what stops the duplicate write —
  but a tap-to-accept affordance would close the gap honestly.
- **An install on Ember, Moss, Rose, Gold or Sea keeps its colours and loses its
  name.** The decode is correct and the hexes are untouched, but
  `SettingsTabView` matches by SPEC against `presets`, so the Settings row now
  reads "Custom" and no chip lights. There is no old-preset → new-preset
  mapping and this wave does not invent one; the release notes say so.
- **`OnyxTests` still has its 10 baseline issues** in History weeks (3), Workout
  week (5) and Session summary — the hotfix (2). Unchanged by this wave and still
  ungated. W5's audit inherits them.
- **One environment-only failure** shows up when the suites are run through
  `xcodebuild` rather than `swift test`: `AppDatabaseTests` "stores, retrieves
  and removes a session blob" throws a Keychain error in the simulator. It passes
  under `npm run swift:data`. Present on clean `main` too — recorded here so the
  next wave does not adopt it as new.

---

# Wave Record — W4 · Train tab & the weekly report

**Shipped `4.0.0`** — MAJOR, by `docs/CHANGELOG.md`'s own rule: a screen was
removed. Branch `onyx/w4-week-report`, cut from `main` at `1a856ce2`.

## What was done

### GOAL 1 — Week 0. The brief's premise was false, and the test is the proof.

The brief said "REPRODUCE FIRST" and named two candidates. Both were wrong, and
so was the symptom: **Week 0 already drew its banner.**

`WorkoutWeekTests.weekZeroIsAPastWeek` was written to fail against
`WorkoutWeek.pastWeeks` with the founder's own numbers — `onyx5` started
2026-07-15, `week_end_day = 6` (a SUNDAY-start week), anchor 2026-07-12, two
sessions inside it. It passed on the first run. So did the guard beneath it,
`theEraBeforeTheAnchorStaysHidden`: a session on 2026-07-08 and a PPL session in
May are both excluded, because the walk stops at the first week BELOW the anchor
and not at the anchor itself.

Neither candidate could have been the bug:

- `Schedule.isPlannable` is `dateISO >= ctx.weekZeroStart`, and the walk tests
  the week it is ABOUT to emit rather than the one it stepped off — so
  `2026-07-12 >= 2026-07-12` lets the anchor week through and `2026-07-05` ends
  the walk. There is no off-by-one.
- `guard !finished.isEmpty else { continue }` skips EMPTY weeks and continues; it
  cannot hide a week holding two sessions.

A third test was written for the half the brief did not name — the only place a
week the walk emitted could still fail to be drawn. `PastWeeksLibrary.blocks(_:)`
joins the walk's weeks against `Phases.enumerateWeeks`, and a week no
`plan_phases` block covers falls to the "Between blocks" bucket at the bottom of
the shelf, in grey, under a heading that reads like an error.
`WeeklyReportTests.weekZeroIsBanneredAndTinted` asserts the anchor week reaches a
block with a `kind` of its own and is not in that bucket. It passes, and the
screenshot agrees: `train-library` shows **Week 0 · 12 – 18 Jul** under its own
`ONYX · WEEK 0` heading in the peak hue.

`blocks(_:)` and `tint(_:)` were made `nonisolated static` and internal to be
asserted at all. That is the change GOAL 1 actually produced: no screenshot can
show that a week is missing from a list it was never in.

### GOAL 2 — 124.3 pt → 86.3 pt, measured.

The before and after were measured off the PNGs, not judged: a pure-Python PNG
decode of a column through the shelf, reading the glass edges. The tile was
**373 px = 124.3 pt**; it is **259 px = 86.3 pt**, with the 30 px (`OnyxSpace.grid`)
gutter between tiles unchanged in both. Five whole banners on a 402 × 874 screen
instead of three and a half.

Four cuts, no figure removed:

1. `.hero` → `.display`. W2 (refinement) wrote down **one hero per screen** and a
   shelf had one per ROW — eight 28 pt numerals arguing about which of them the
   screen was about. −8 pt, and the rule is now obeyed.
2. The totals are `.caption` on one line at every size that is not an
   accessibility size. Two lines were bought for AX5, where `Shoulders` already
   stacks and the tile is free to grow; a default-size banner paid 20 pt for a
   break it never took.
3. `OnyxSpace.xs` between the three rows rather than `s`. They are one thought.
4. `m` horizontal / `s` vertical padding rather than `l` all round.

The tag row was NOT folded onto the totals line: a muscle capsule cannot share a
row (W2 · live-ux), and a `FlowRow` beside a `Spacer` wraps to one tag per line
at the first long landmark name.

**The brief was wrong about the hue too, in the other direction.** It said the
phase colour was "ALREADY THERE and unused". It was already USED — `banner(_:kind:)`
took `tint(kind)` for both the label and `.onyxTopWash(hue)` before this wave.
What was missing was a test, and `bannerHueFollowsPhase` is it: four kinds, four
distinct inks from `Color.onyx.phase(_:)`, and `textTertiary` for the unclaimed
week — asserted to be none of the four, or "no phase" would read as one.

### GOAL 3 — the sheet is gone, and all four doors moved.

`WeeklyWrapView` is deleted. `WeeklyMuscleRing.swift` is deleted.
`WeeklyWrapView.swift` was `git mv`d to `WeeklyWrapContent.swift` and holds only
the reel, which is unchanged apart from losing three things that were the
sheet's: `showsLegend` (answered from a detent), `onNeedsHeight` (a page is
already at its height) and `ringCard`.

`WeeklyReportView` is pushed by every door:

| Door | Was | Is |
|---|---|---|
| `WorkoutTabView` This-week tile | `.sheet(item: $wrapped)` | `.navigationDestination(item: $wrapped)`, beside the session destination |
| `PastWeeksLibrary` banner | `.sheet(item: $opened)` on the sheet | `.navigationDestination(item: $opened)` **inside** its own `NavigationStack` |
| `WeekDaysView` Wrapped chip | `.sheet(item: $wrapDoor)` | `.navigationDestination(item: $wrapDoor)`, still hung off the LIST |
| `TodayTabView` week-complete banner | `.sheet(item: $wrapDoor)` | `.navigationDestination(item: $wrapDoor)` |

Every `WrapDoor` / `Door` box went from `Identifiable` to `Hashable`, which is
what `navigationDestination(item:)` wants — the same box `WeekDaysView.ReportDoor`
already was, keyed on the week start.

The shelf stays a sheet and that is not a contradiction: a SHELF is a thing you
open, scan and put down; the week you find in it is a place. The zoom transition
(`matchedTransitionSource` + `.navigationTransition(.zoom)`) was built for a push
in the first place and is unchanged.

`fourDoorsPushAndNonePresents` asserts it off the source — the four files, the
four bindings, `navigationDestination` present and `sheet(item:)` absent for each,
and no `WeeklyWrapView(` or `WeeklyMuscleRing(` anywhere. It cannot pass
vacuously (W8's trap): the first expectation on every file is that it was read
and is over a thousand characters.

`grep -rn "WeeklyWrapView\|WeeklyMuscleRing" native` now returns two prose lines
in the two files that explain what happened to them, plus the graph fixture and
three `OnyxMega`/`WeekDaysView` comments that cite the deleted ring as precedent.

### GOAL 4 — the band and the three rails.

`PhaseBand` is full-bleed: no gutter, no glass, a 28 %→0 wash in
`Color.onyx.phase(kind)` with the week numeral at `.clock` over it, the `era_tag`
capsule and the date range beneath. The numeral is the page's one hero, which is
what makes that rule checkable here rather than a sentiment — nothing else on
the screen is set at `.clock`. `Phases.weekPhase(weekStart:in:)` answers the kind
and the tag; a week no block covers falls back to the train accent, no capsule,
and prints its label whole under `BLOCK` rather than splitting a numeral out of it.

Three rails, reusing `OnyxProgressBar`:

| Rail | Source | Denominator |
|---|---|---|
| Training | `Summary.sessions` / `tonnageKg` / `tonnageDeltaKg` | `Schedule.sessionTargetIn` — the plan's own day count, which is the footer's "3/5" |
| Nutrition | `MacroAdherenceSeries.build`, ±10 %, graded against the rung in force ON EACH DATE (`targetPeriods`) | days graded hit-or-miss; exceptions and untracked days are neither |
| Recovery | the stored `battery_pct` (READINESS_MODEL §7) | the nights that have one |

No fourth score was invented, and bars were chosen over a donut deliberately:
these three are not parts of one whole, so part-to-whole is the wrong encoding.
A rail with no reading prints an em dash and not 0 %, because "no graded day" and
"missed every graded day" are different weeks.

### GOAL 5 — the body, off one call.

`WeekReport.build` is a fold over `WeeklyExportBuilder.input(weekStart:today:)` —
the same payload the weekly export renders — plus one `scheduleContext` read for
the phase table. Not six queries, and the page cannot disagree with the exported
document about the same week.

- **Nutrition** — the seven verdicts as dots, and water through
  `WaterTruth.ml(log:ledger:)`. The payload has already applied the half of that
  rule that needs two stores (`ExportDay.waterMl` is the ledger's sum where the
  ledger has rows); passing an empty ledger applies the other half — a stored
  zero is a day nobody measured — without a second copy of it.
- **New PRs** — `ExportSession.prs`, built off the range query at
  `WeeklyExportBuilder.swift:536`, sorted by exercise name.
- **Strongest** — `TopLifts.group` over the whole week's working sets, warm-ups
  and ghosts excluded. `previous: [:]`, because the arrow is a session-to-session
  comparison and there is no "last week's hardest set of the week" to point it at.
- **Weight** — `Summary.bodyweightKg` / `bodyweightDeltaKg`, signed.

The share control **left the reel** and is now the page's last block
(`WeeklyShareSection`). It was the final section of what used to be the whole
sheet; with four more sections under the reel it would have sat in the middle of
the page, above the macros and the weigh-in — a terminal action with a document
after it.

## Succeeded

- **OnyxTests: 10 baseline issues before, 10 after.** History weeks (3), Workout
  week (5), Session summary — the hotfix (2). Six new tests, all green, none of
  them in those three suites' failing cases.
- **`npm run swift:core` 575/575, `npm run swift:data` 583/583.**
- **The app target builds** — `xcodebuild -scheme Onyx -destination
  'generic/platform=iOS'`, which is the check a green `check:swift` can hide a
  failure behind (memory: `xcodeproj-drift-and-swift6`).
- **The banner is 86.3 pt, measured off the PNG.** Not "looks shorter".
- **Week 0 is on the shelf, in its own block, in the peak hue** — `train-library`.
- **All four doors push.** `history-week-wrap-open` photographs the History door
  end to end: a back chevron, the band, and Week 5's figures matching the Week 5
  banner on the shelf exactly (5 sessions, 7,872 kg).
- **Two public inits were added** — `AdherenceDay` and `ExportPr` — because a
  preview fixture in the app module cannot reach an internal memberwise init.
  Both are documented as preview-only; nothing else changed in OnyxCore.

## Failed

- **GOAL 1's premise.** Week 0 was never missing from `pastWeeks`. Three tests
  now say so, which is the whole of what the goal produced. If the founder is
  still not seeing it on the phone, the remaining explanation is the live
  `plan_phases` table having no block over 2026-07-12 — the week would then draw
  in grey under "No phase covers these weeks" at the bottom of the shelf, which
  the fixture cannot reproduce because `PreviewCatalogue` seeds a Week 0 block.
  **This is the one claim in this record that could not be checked against the
  live database from here.**
- **GOAL 2's "the phase hue is ALREADY THERE and unused".** It was already used.
  Only the test was missing.
- **`train-past` and `train-past-open` do not exist.** They were renamed
  `train-library` / `train-library-open` by W1 (refinement) when the section
  became a sheet; the brief's shot list is one wave stale. Those two were shot.
- **Two rounds of screenshots were needed, and the first round's defects were
  both in the harness rather than the page.** `AppEnvironment.userIdString` is the
  empty string when nothing is signed in, so the first `train-wrap` built its
  export for user `""` and drew a page with no nutrition, no battery, no records,
  no strongest and no phase capsule — over a store holding all five.
  `WeekReport.build` now falls back to `database.localUserId()`, which is what
  `WorkoutWeek.library()` and every other preview reader already did.
- **The first cut truncated its own rail detail at AX5** — `5 of 5 sessions ·
  42,180 kg · …`. `lineLimit(2)` is not enough for that string at an
  accessibility size; it is unlimited there now.

## Left open

**Nothing is required of the founder to ship this wave.** No DDL, no Supabase
setting, no App Store step.

- **The preview store seeds no `daily_logs` calories and no `battery_pct`.** So
  `train-wrap`, `train-wrap-large` and `train-wrap-deload` can only ever
  photograph the Nutrition and Recovery rails in their EMPTY state — "no day was
  graded", "no night was scored". `train-report` exists precisely for this and
  hands `WeekReport` over as a fixture, but the end-to-end shot cannot show a
  populated nutrition card. Seeding a week of `daily_logs` in
  `HistoryPreviews.environment()` would close it and is worth doing once, for
  every screen that reads nutrition and not only this one.
- **The band and the navigation title both say the week's name.** `Week 7` in the
  inline bar, `WEEK / 7` immediately under it. It is the standard arrangement —
  the bar title is what you see once the band has scrolled away — but it reads as
  a repeat on arrival.
- **A deload declared by the LEVER wears its block's colour, not the deload one.**
  `WorkoutWeek.wrap` sets `isDeload` for a phase-table deload OR a maintenance
  week (`Maintenance.isMaintenanceDate`), while the band takes
  `Phases.weekPhase(...).kind`. So a maintenance week inside a cut block shows the
  cut hue over a reel headed "Deload week — lighter by design". Both are correct
  about what they describe and the pair is visible in `train-wrap-deload`; a band
  that read `isDeload` instead would be a fourth opinion about what phase a week
  is in.
- **`Strongest` draws no arrows.** `TopLifts.group(sets, previous: [:])` — there
  is no week-over-week bar for a week-scoped role, and inventing one would mean
  deciding whether last week's "hardest" is the same question as this week's.
- **`WeekWindow(containing:startDay:)` has no anchor, so `number` is always 0.**
  `HistoryWeeksTests.weekZero` has failed on this since W2 made the anchor a
  parameter, and it is one of the ten baseline issues. It is a stale TEST, not a
  product bug — every real caller passes `weekZero` — but it sits directly on
  top of this wave's subject and should be either fixed or deleted by W5's audit.
- **`OnyxTests` is still run by nothing in `npm run check`.** Unchanged from W3.
  The six tests added here are as ungated as the ten that were already failing.
- **`train-wrap-large` is now "the bottom of the page" rather than "the `.large`
  detent".** It is shot with `.defaultScrollAnchor(.bottom)`. The name is kept so
  the pair with `train-wrap` still reads as one review, but it no longer means
  what it says.

---

# Wave Record — W5 · The Great Purge & Merge

**Ships `4.0.1`** — PATCH, because a purge ships no capability. Branch
`onyx/w5-purge-merge`, cut from `main` at `ba0c62fe`.

**Landed as `94e6fcf6` on `main`, branch deleted, pushed.** It landed in two
sittings: a second Claude session went live in a worktree partway through this
wave (see *Failed*) and the founder asked for a stable stopping point, so the
work was committed on the branch and held there until that session was idle. The
push needed `ONYX_DEPLOY=1` — the guard greps the COMMAND, and `git push` carries
neither `[skip ci]` nor the flag however the commit is worded.

## What was done

### STEP 1 — the trunk was whole, and then it was not alone.

At the branch cut (20:56): `git branch -a` listed `main` and `origin/main` and
nothing else, `git worktree list` held one entry — the primary checkout — and
`main` and `origin/main` were the same commit, 0 ahead and 0 behind. Every wave
had deleted its own branch. **Nothing was force-deleted, because there was
nothing to delete.** With no unmerged diff there was no cumulative
`main…origin/main` for `code-reviewer` to read, so that pass was skipped rather
than run against an empty range.

The one dirty thing was six tracked files under `graphify-out/` — `graph.json`,
`graph.html`, `GRAPH_REPORT.md`, `manifest.json` and the two label files — left
modified by the post-W4 graph rebuild. They were carried onto the wave branch
and are committed here, which is the only place they can land now that W4 is
merged.

**A correction to the brief: there are SEVEN tracked files at the root of
`graphify-out/`, not nine.** `git ls-files graphify-out` returns
`.graphify_labels.json`, `.graphify_labels.json.sig`, `.graphify_root`,
`GRAPH_REPORT.md`, `graph.html`, `graph.json` and `manifest.json`. The two the
count was presumably reaching for — `.rebuild.lock` and `.pending_changes` — are
named in `.gitignore:130-132` as machine-local scratch and were never tracked.
All four purge targets were confirmed untracked with `git ls-files` **before**
the `rm`, which is the check that separates a cache purge from a deletion.

### STEP 2 — 68.1 GB reclaimed.

Measured with `du -sk` across the five targets immediately before and after:
**71,470,956 KB → 21,432 KB, i.e. 69,774 MB ≈ 68.1 GB.**

| Target | Reclaimed | Note |
|---|---|---|
| `$HOME/Library/Caches/onyx-swift/*` | **~64 GB** | 27 directories — every wave's scratch and derived path back to `shot-w1`, plus `dd-w2`, `w4-base-derived`, `w6-main-derived`, `shots-w3`/`shots-w8`. This is the number the brief did not know about. |
| Xcode DerivedData for this project | 4.0 GB | `Onyx-fwuafknlmczojfefflrcfwbxhzaf` |
| `native/graphify-out/` | 93 MB | the duplicate graph `.gitignore:120` exists to refuse |
| `native/__screenshots__/` | 86 MB | not 63 — it has grown since 3.8.0 |
| `graphify-out/cache/` | 70 MB | stat index, rebuilt on demand |
| `graphify-out/2026-09-{15,16,17}/` | 58 MB | three dated snapshots, nothing reads them |

`graphify-out/.rebuild.lock` and `.pending_changes` were already absent.
The brief's figures were one wave stale in both directions: `graphify-out` was
150 MB rather than 134, `__screenshots__` 86 MB rather than 63.

Then `graphify update .` on a **cold cache** — 774 files re-extracted, 12,718
nodes, 34,608 edges, 484 communities — which reported *"No code-graph topology
changes detected; outputs left untouched."* That is the purge's own proof: the
seven tracked files regenerate to the same graph the repository already held.
`graphify-out/` now stands at 49 MB, of which 28 MB is the cache that regrew
during the rebuild and is ignored, and 20 MB is the tracked `graph.json`.

### STEP 3 — the whole gate, from cold caches.

Every scratch path had just been deleted, so nothing below was a warm rebuild.

| Gate | Result |
|---|---|
| `npm run check` | green — `4.0.1 (40001)` in sync, `tsc` clean, atlas / mirror / doms all matching |
| `swift:ui` (inside `check`) | **27 tests in 7 suites**, passed |
| `npm run check:swift` | green — project regenerated, OnyxUI + OnyxCore build for the iOS simulator |
| `npm run swift:core` | **575 tests in 119 suites**, passed — golden vectors unchanged |
| `npm run swift:data` | **583 tests in 72 suites**, passed |
| `xcodebuild -scheme Onyx -destination 'generic/platform=iOS'` | **BUILD SUCCEEDED** — app, widget and watch, 0 errors, 28 warnings, all pre-existing |

**`OnyxTests` is exactly at baseline: 10 issues, 4 tests, 3 suites.** No fifth
test, no sixth suite, nothing this sprint left behind:

- History weeks (3) — `weekZero` at `HistoryWeeksTests.swift:75`, and the capsule
  test's missed/rest counts at `:117-118`.
- Workout week (5) — "ready to progress fires only after the ceiling is cleared
  twice", `WorkoutWeekTests.swift:176-185`.
- Session summary — the hotfix (2) — the treadmill's canonical title,
  `SessionSummaryHotfixTests.swift:131-132`.

**Where "five baseline failures" came from.** The run's final line reads
`✘ Test run with 64 tests in 6 suites failed after 3.743 seconds with 5 issues` —
while the same log prints **24 suite results, 186 test results and ten issues**.
The roll-up line is not the run's total; the per-suite `✘ Suite … failed … with
N issues` lines are. Read those. The plan's "five" and W1's "one" are both
artefacts of trusting a summary line over the suites, and W2's 10 / 4 / 3 is the
figure that has now held across W2, W3, W4 and W5.

### STEP 4 — version and changelog.

`package.json` → **`4.0.1`**, `npm run version:sync` → `native/project.yml`
(`40001`, derived), `cd native && xcodegen generate`, and `npm run version:check`
green inside a re-run of `npm run check`.

`docs/CHANGELOG.md` gained **[4.0.1] — Putting The Tools Away**, written from the
template: what was removed, that the gate was re-run from source rather than from
a cache, and a note that `native/OnyxTests` is still ungated and still carries its
ten.

### STEP 5 — the harvest.

The four wave records were read against the four changelog entries they belong
to. **Three needed nothing** — `3.22.0`, `3.24.0` and `4.0.0` already carry their
wave's user-facing findings, including 3.24.0's "Note for anyone on an older
theme", which is the one consequence a reader could otherwise be surprised by.
`3.23.0` was one short and now carries **"What Cancel Edit does not cover"**: the
watermark is per `(session, device)`, so another device's edits are not this
device's to take back, and a restored set returns under a new id and therefore
moves to the end of its `setIndex` tie group. The entry promised "every set goes
back to the way it was"; those are the two ways that sentence is not literally
true.

One memory file was written —
`memory/ux-architecture-sprint.md`, pointer added to `MEMORY.md`. It carries the
five things the brief named and two the wave files did not already hold: that
every new `ContentState` field must be Optional (and why a nil-check is not a
zero-check for a cardio bout), and that adding a stored property to a persisted
`Codable` spec silently resets every install unless `init(from:)` is written by
hand. The per-wave detail stays in `live-logger-w2`,
`next-gen-w3-theme-inbody` and `w4-weekly-report` rather than being copied.

`docs/Plan-Onyx-UX-Architecture-Done.md` is **kept**, as instructed.

## Succeeded

- **68.1 GB reclaimed and nothing lost.** Every target was proven untracked
  before deletion, and the cold rebuild that followed reproduced the graph
  byte-for-byte as far as the topology check can see it.
- **The entire gate is green from cold caches** — which is a stronger claim than
  the one the waves made from warm ones, and it cost one afternoon of rebuild to
  earn.
- **`OnyxTests` did not move.** Four waves of feature work, and the failing set
  is the same four tests it was at W2.
- **The trunk was whole.** Four waves, four self-deleted branches, no orphan
  commits, `main` identical to `origin/main`.
- **The roll-up line was caught lying**, which retires a number that has been
  wrong in this plan since W1.

## Failed

- **The trunk did not stay alone, and this wave cannot close the way the brief
  imagined.** At 20:59 — three minutes after Step 1 measured the repository — a
  second Claude session created the worktree
  `.claude/worktrees/sprint-next-gen-w10` on a new branch
  `onyx/sprint-next-gen-w10`, and at 21:10 started an `xcodebuild test` in it.
  The branch is at `ba0c62fe`, **0 commits ahead of `main`**, so it holds nothing
  `main` does not — but it is a live session's workspace, not a stale one.
  Nothing of it was touched: not the branch, not the worktree, not the process.
  "Delete all open UI/UX branches" is satisfied by the four waves that cleaned up
  after themselves; `onyx/sprint-next-gen-w10` is not one of them and is not
  this wave's to remove.
- **The purge deleted a cache out from under that session.**
  `rm -rf $HOME/Library/Caches/onyx-swift/*` ran at ~20:57, a minute before the
  other worktree appeared, and `ui-test-derived` is a SHARED path —
  `scripts/swift-ui-test.sh` hardcodes it. No harm resulted (the other session
  rebuilt it, and its test run is what then held the lock), but a machine-wide
  cache purge is not a per-session operation and this one was run as if it were.
  **If a purge wave ever runs again, check for other worktrees and other
  `xcodebuild` processes first — `git worktree list` at the start of the wave is
  not enough, because a session can start after it.**
- **`npm run swift:ui` cannot run beside another session and failed here**:
  `error: unable to attach DB: … build.db: database is locked. Possibly there
  are two concurrent builds running in the same filesystem location.` The script
  offers no way to override its `-derivedDataPath`, so the suite was run by hand
  against `onyx-swift/w5-ui-test` — 27 tests in 7 suites, passed. Same for
  `OnyxTests`, run against `onyx-swift/w5-tests`. Teaching `swift-ui-test.sh` to
  honour a `UI_TEST_DERIVED` environment variable is a one-line change and the
  next wave that shares this machine will want it (memory:
  `concurrent-waves-shared-checkout`).
- **The brief's file count was wrong** (nine tracked root files; there are seven)
  and **its size figures were stale** (134 MB / 63 MB; measured 150 MB / 86 MB).
  Neither changed what was deleted, because the `git ls-files` check does not
  depend on knowing the number in advance.

## Left open

This is the sprint's final state of the world, for someone who was not here.

**The merge itself.** `onyx/w5-purge-merge` is committed and green but **not
merged, not deleted and not pushed** — paused at the founder's request while the
other session runs. Resuming is: `git checkout main && git merge --no-ff
onyx/w5-purge-merge`, delete the branch, push. The push guard reads the COMMAND
and not the message, so it is `[skip ci]` in the merge message **or**
`ONYX_DEPLOY=1 git push`; Netlify publishes `site/` as-is either way (memory:
`next-gen-ux-sprint`). Be aware that `onyx/sprint-next-gen-w10` was cut from
`ba0c62fe` and will therefore merge into a `main` that has moved — the collisions
to expect are `package.json`'s version, `docs/CHANGELOG.md`'s top entry and the
seven `graphify-out/` files, all of them semantic rather than textual (memory:
`hotfix-ui-data-sep11`).

**`native/OnyxTests` is run by nothing in `npm run check`.** Unchanged since W3
named it, and it is now three waves of new tests deep — `InBodySaveGateTests`,
`LivePrIdentityTests`, `LiveActivityCardioTests`, `SessionRevertTests` and W4's
six — all of them ungated. Wiring it in turns `npm run check` red on `main`
until the ten baseline issues are fixed, which is why no wave has done it. The
honest sequence is: fix or delete the four failing tests first, then add
`-only-testing:OnyxTests` to the gate. Two of the four are known to be stale
tests rather than product defects (`HistoryWeeksTests.weekZero` asserts against a
`WeekWindow` that has no anchor and whose `number` is therefore always 0; every
real caller passes `weekZero`).

**What is still unproven on a device, not in a test.** The end-to-end list at the
top of this document is the list, and none of it has been walked on hardware:
the Dynamic Island cannot be rendered by a simulator at all, the watch card at
40 mm was verified through previews, and `session-edit` is not a screen the shot
harness knows — the Cancel button has never been photographed at any text size.
The single highest-value one is W2's: run `recomputeAllPrs` against the founder's
own store and diff it against `personal_records`. The risk direction is the safe
one — the identity fix can only widen a bar, and a wider bar removes false
trophies rather than inventing them — but it is the one claim in this sprint
that was never checked against the founder's full history.

**Known and deliberately not fixed:**

- `daily_logs.hrv_overnight` is live (`boolean NOT NULL DEFAULT false`) and
  absent from `native/schema/supabase.json`. Pre-existing drift; harmless while
  nothing reads it, but the fixture is one column short of the introspection it
  claims to be.
- The preview store seeds no `daily_logs` calories and no `battery_pct`, so
  `train-wrap*` can only ever photograph the Nutrition and Recovery rails empty.
  Seeding a week in `HistoryPreviews.environment()` closes it for every screen
  that reads nutrition, not only that one.
- A maintenance week inside a cut block wears the cut hue under a reel headed
  "Deload week". Both halves are correct about what they describe.
- The muscle palette takes `chroma` but not `lift`, and no copy on the Appearance
  screen says so.
- An install on Ember, Moss, Rose, Gold or Sea keeps its colours and loses its
  name — Settings reads "Custom". The release note says so; there is no
  old-preset → new-preset mapping and this sprint did not invent one.
- `PulseModel.stackNutrients:786` still has no consumer. W1 left it for "W5's
  kind of work"; W5 did not delete it, because a purge wave that also removes
  live code is two waves wearing one commit.

**Founder's manual checklist: empty.** No DDL (W3's `waist_cm` was already
live), no Supabase setting, no App Store Connect step, nothing to paste. The
only outstanding actions are the merge above and the device walk-through.
