# Compaction audit — every fact this app draws more than once

> (Gym mode was deleted in overhaul W0, 2026-09-23; the app always opens on Today.)
> Onyx Expansion **W6**, decision 24: *keep five tabs and gym mode; solve bloat
> by density and de-duplication, not by hiding.* Decision 25: *no
> hide-until-data.* Nothing in this document removes a fact from the app. Every
> row either deletes a SECOND DRAWING of a fact that is still on screen
> somewhere, or makes two drawings agree.
>
> Paths are relative to `native/`.

## How a row was decided

**Keep the surface that owns the question.** Pulse owns "how is my body",
Fuel owns "what have I eaten and drunk", Train owns "what am I lifting and what
have I lifted", History owns "what happened". A fact drawn on the surface that
owns its question is the one that stays; the same fact restated on a surface
that merely passes by is the one that goes — *unless* it is the same shared
`OnyxUI` component in both places, in which case there is only one drawing and
nothing to delete.

**A duplicated FORMATTER is worse than a duplicated drawing**, because two
formatters over one number make the app contradict itself. Those are collapsed
even when both drawings survive.

---

## 1. Facts drawn more than once

| # | Fact | Where it is drawn | Same component? | Keep | Resolution |
|---|---|---|---|---|---|
| 1 | Sleep duration | `Onyx/Features/Pulse/PulseSleep.swift:117`, `Onyx/Features/Pulse/PulseTabView.swift:831` (`DayFormat.minutes`), `Onyx/Features/History/WeekDaysView.swift:758` (`hours`), `Onyx/Features/Today/DomainSheets.swift:248`, `Packages/OnyxCore/.../Snapshot.swift:968` (`formatSleep`) | No — **four formatters**, four outputs for 457 min (`7h37m` / `7h 37m` / `7h 00m` / `7h`) | `Format.sleep` (OnyxCore) for prose; `formatSleep` only inside fixed-width tile faces | **RESOLVED** — `DayFormat.minutes` and `WeekDaysView.hours` deleted, callers repointed. `DomainSheets` had already made this choice by hand in a comment; it is a rule now. |
| 2 | Sessions this week / target | `Packages/OnyxUI/.../OnyxTraining.swift:291` (`weekText`), `:1150` (`sessionsText`), `Packages/OnyxUI/.../OnyxPerformance.swift:410` (`sessions`) | No — **the same three-line function written three times in one module** | one helper | **RESOLVED** — collapsed to one. |
| 3 | Week-volume delta in tonnes | `OnyxTraining.swift:993` (`deltaTonnes`), `:1143` (`volumeDeltaTonnes`), `OnyxPerformance.swift:416` | No — three copies in one module | one helper | **RESOLVED** — collapsed to one. |
| 4 | A fixed-decimal reading | `Onyx/Features/Body/VitalMetrics.swift:72` (`VitalMetric.fixed`), `Packages/OnyxCore/.../Snapshot.swift:993` (`OnyxSnapshot.fixed`) | **Not duplicates.** `VitalMetric.fixed` appends a unit and rounds with `jsToFixed` (ties away from zero); `OnyxSnapshot.fixed` uses `String(format:)`, which rounds half to EVEN | both | **NO ACTION.** This audit called them identical and they are not — `VitalMetric.fixed`'s own doc comment names the rounding as the point. Collapsing them would move a vitals reading by a tenth on every exact tie. |
| 5 | Steps | `Onyx/Features/Today/TileSheets.swift:93` (`StepsSheetBody`, the hero with the goal journey) **and** `Onyx/Features/Today/DomainSheets.swift:486` (`MetricRow("Steps")`) — **twice inside the Today tab**, two shapes | No | `StepsSheetBody` | **RESOLVED** — the Vitals sheet's Steps row deleted; Active energy and Distance stay. |
| 6 | Stress — the index and the self-report | `Onyx/Features/Pulse/PulseSquares.swift:365` (`StressSquare`), `Onyx/Features/Week/WeekSections.swift:686` | **Two different quantities.** The square prints `StressDay.index` (0–100, with a band word); the week report prints `report.stressMean`, the mean of `stress_logs.level` (1–5, Calm…Swamped) | both | **NO ACTION.** This audit called the week report's `OnyxFormat.kg` a formatter bug. It is not: in `WeekSections` that function is the file's house drop-trailing-zeros decimal printer, used the same way for body fat, km, litres and DOMS severity at nine other call sites, and the value is a 1–5 mean, not an index. Printing it the square's way would truncate 2.6 to 2 and attach a band word from the wrong scale. |
| 7 | Water ml → litres | `NutritionModel.swift:555` (`NutritionFormat.litres`), `PulseTabView.swift:825`, `WeekSections.swift:585`, `Format.swift:26` (`Format.mlToL`), plus 7 × `String(format: "%.1f")` in OnyxUI | No — five | `NutritionFormat.litres` (Fuel owns hydration) | **PART** — `Format.mlToL` is UI-dead but covered by a golden vector, so it stays (deleting it is a spec change, §"Fixtures are spec"). The OnyxUI literals are one-liners inside fixed-width faces; folded into the density pass, not a deletion. |
| 8 | Session tonnage (the claim) | `LiveStatsView.swift:324`, `FinishSheet.swift:273`, `SessionDetailView.swift:568` | **Yes** — all three already on `OnyxFormat.volumeExact`, documented at `OnyxFormat.swift:48` | all three | **NO ACTION** — three surfaces, one claim, one formatter. This is the pattern the rest of the table is trying to reach. |
| 9 | Tonnage → string, display vs export | `Packages/OnyxCore/.../Format.swift:81` (`Format.volume`) vs `Packages/OnyxUI/.../OnyxFormat.swift:67` (`volumeExact`) | Look identical; **are not** | both | **NO ACTION, DELIBERATELY.** OnyxCore's is `jsRound` + hand-rolled grouping and feeds the locale-independent export; OnyxUI's is a locale-aware `NumberFormatter`. Collapsing them would put a comma-vs-period decision from the device's locale into an exported document the server has to parse. Recorded here so the next audit does not "fix" it. |
| 10 | Distance (km) | `TileSheets.swift:179`, `DomainSheets.swift:504`, `CardioLog.swift:210`/`:495` (`%.2f`), `WorkoutTabView.swift:1279` | No — five conversions, **two precisions**: a bout reads `0.37 km` in the logger and `0.4 km` on the tile | one helper | **OPEN** — the two precisions are a real disagreement, but the logger's second decimal is load-bearing for a short walk. Needs a founder call on which precision wins; not a silent collapse. |
| 11 | Readiness score | `TodayCards.swift:53` (`NowStrip.reading`), `PulseTabView.swift:536` (`NowStripPulse.scoreReading`), `OnyxDaily.swift:102`, `OnyxAccessory.swift:266` | Two hand-rolled strips, one shared `Stat` family | Pulse (owns "how am I") | **OPEN** — deleting Today's strip removes the only numeral above its grid and is a screen redesign, not a de-duplication. Both readings come from one `daily_scores` row, so they cannot disagree; the cost of leaving it is chrome, not a contradiction. |
| 12 | Recovery battery % | `TodayCards.swift:38` (36 pt ring), `PulseTabView.swift:499` (44 pt ring), `Packages/OnyxUI/.../OnyxPrimitives.swift:151` (`BatteryRing`, the real component, `internal`) | **Three ring implementations** | `BatteryRing`, made `public` | **OPEN** — with row 11, one change. Two 10-line `ZStack { Circle; Circle.trim }` blocks with different sizes and different animations. |
| 13 | Week tonnage / volume | `WorkoutTabView.swift:552`, `WeekSections.swift:186`, `WeeklyShareCard.swift:104`, `WeekDaysView.swift:582`/`:688`, `HistoryView.swift:323` | Four renderings, three formatters (`12,510` vs `12,510.0` vs `12.5 t`) | `OnyxStatCell` + `OnyxFormat.volume` for kg, `OnyxSnapshot.tonnes` for tiles | **OPEN** — the kg/tonne split is intentional (a tile has no room for five digits); the `12,510` vs `12,510.0` split is not. See row 9 for why this is not a one-line fix. |
| 14 | PR count | eight sites, **three different words** (`PRs`, `Records`, `N PR`) — `FinishSheet.swift:295`, `LiveStatsView.swift:889`, `SessionDetailView.swift:648`, `PulseWorkout.swift:77`, `WorkoutTabView.swift:838`, `HistoryView.swift:326`, `WeekDaysView.swift:828`, `OnyxTraining.swift:479` | No | `Records` on a page, `N PR` inside a totals line | **OPEN** — a vocabulary decision across eight surfaces. One word, no code deleted; belongs with row 15. |
| 15 | The session totals line (`3,108 kg · 12 sets · 2 PR · 48 min`) | `PulseWorkout.swift:75`, `WorkoutTabView.swift:836`, `HistoryView.swift:323`, `WeekDaysView.swift:800` | **Four hand-rolled string builders**, same four parts, same order | one `SessionTotals.line(…)` in OnyxCore | **OPEN** — the biggest single win left (`PulseWorkout.swift:64` already documents the `13,005.0` vs `13,005` drift this caused). Four call sites and a golden vector; a wave of its own, not a corner of this one. |
| 16 | Muscle distribution legend + counts | `MuscleDistributionSheet.swift:96`/`:117`, `AtlasSheet.swift:163`/`:480`, `TileSheets.swift:317`/`:490` (`MuscleFocusLegend`, already shared by Today and Trends) | Three sheets, one question; two of them hand-roll the shared component | `MuscleFocusLegend` | **OPEN** — ~120 lines of copy-paste. `TileSheets.swift:479` already names the failure mode ("a second list that agrees by inspection"). |
| 17 | Next session / today's plan day | `TodayCards.swift:63` (`sessionChip`) re-implements `OnyxLifestyle.swift:154` (`nextSessionText`), with a different word for a rest day (`Rest day` vs `Rest`) | No | `nextSessionText` (already public) | **RESOLVED** — the chip reads the shared text. |
| 18 | Week set count | `OnyxTraining.swift:594` (working sets, Int) vs `TileSheets.swift:290` (weighted, Double) — **a tile and its own sheet disagree by ~1.8×** | Two denominators, one label | both numbers, both labelled | **OPEN** — not a duplicate: two different facts wearing one word. The fix is a label, and the label is a founder call. |
| 19 | The five overnight vitals | `PulseVitals.swift:296` (`VitalCell`) / `:265` (`MetricRow` at AX5), `DomainSheets.swift:473` (Today's Vitals sheet), `VitalMetrics.swift:31` | `VitalSpec` and `MetricRow` genuinely shared; `VitalCell` and `VitalMetric` are two more | Pulse's grid | **OPEN** — Today's Vitals sheet is ~60 lines re-listing Pulse's grid. Deleting it removes a tile's destination, so it is a navigation change. |
| 20 | Targets (kcal · P/C/F · steps · water · sets) | `LeversView.swift:196` (editor), `PlanView.swift:129` (`consequences`), `NutritionSheets.swift:84`, `VolumeTargetsView.swift:33` | Three hand-rolled restatements | `LeversView` | **OPEN** — `PlanView.consequences` earns its place for an INACTIVE plan (it is a preview of a change) and is a second editor's-worth of restatement for the active one. |

**Ten rows resolved** (1, 2, 3, 5, 17, plus the five one-line duplications
folded into them — `OnyxPerformance.sessions`, `deltaTonnes`,
`tonnesThisWeek`/`tonnesLastWeek`, `delta(Double?,Double?)`,
`DayFormat.minutes`, `WeekDaysView.hours`, the Vitals sheet's Steps row);
ten recorded with the reason they were not.

**Two rows this audit got wrong, and the code said so.** Rows 4 and 6 were
written as duplicates from a survey of call sites and are not duplicates at
all — one is a rounding rule and one is a different quantity with the same
name. Both are left exactly as they were, and the reason is in the table
rather than in a commit message, because the next reader will notice the same
two similarities and reach for the same collapse.

---

## 2. Section headers that repeat the card beneath them

Resolved by the density pass (§3): each of these loses the header, not the card.

| Header | The card under it | File |
|---|---|---|
| `DaySheet("Soreness")` | `DayTile("Soreness", …)` 40 pt below it | `Onyx/Features/Pulse/PulseDoms.swift:374` → `:83` |
| `SquareShell("Soreness")` | `SquareReading(unit: "sore")` | `Onyx/Features/Pulse/PulseSquares.swift:436` |
| `Text("BODY")` | `figure("BODY FAT", …)` | `Onyx/Features/Week/WeekSections.swift:212` |
| `navigationTitle("Set water")` + `OnyxSectionHeader("Total for the day")` + `OnyxNumberRow("Water")` | **three labels, one field** | `Onyx/Features/Nutrition/NutritionSheets.swift:278`, `:259`, `:243` |
| `navigationTitle("Nutrients")` | pushed from a row that says `Nutrients` | `Onyx/Features/Nutrition/NutrientsView.swift:82` |
| `OnyxSectionHeader("The session")` | three tiles, all of them about the session | `Onyx/Features/Logger/FinishSheet.swift:246` |
| `Section("Activity")` | `Steps` / `Active energy` / `Distance` | `Onyx/Features/Today/DomainSheets.swift:485` |
| `OnyxChartCard("Recovery")` | inside `WeekRecoverySection`, empty state `WeekEmptyNote("RECOVERY")` | `Onyx/Features/Week/WeekSections.swift:621` |
| Three window captions, three spellings (`SEVEN NIGHTS`, `LAST N DAYS`, `last N bouts · minutes`) | — | `DomainSheets.swift:286`, `TileSheets.swift:213`, `WorkoutTabView.swift:1215` |

## 3. Cards over the house budget (one hero + ≤ 2 captions)

Now enforced by `LayoutGoldenTests.textNodesPerCard`, which counts the text
nodes each card in the preview catalogue draws and fails over the budget.

| Card | File | Over by |
|---|---|---|
| `GoalBoardRow` | `Onyx/Features/Today/TodayCards.swift:198` | 3 values + 3 labels + 3 sub-captions = **9 text nodes** |
| `NowStrip` | `TodayCards.swift:22` | 2 readings, 3 captions |
| `NowStripPulse` | `Onyx/Features/Pulse/PulseTabView.swift:487` | 2 numerals, 4 captions (the second numeral is a documented deliberate demotion) |
| `StepsSheetBody.supporting` | `Onyx/Features/Today/TileSheets.swift:175` | 4 values + 4 units + 4 labels |
| `MuscleFocusSheetBody.counts` | `TileSheets.swift:288` | **3 `.onyxHero()` numerals side by side** |
| `WeekVitalsRow` | `Onyx/Features/History/WeekDaysView.swift:668` | **8 value+label pairs in one card** |
| `VitalsGrid.grid` | `Onyx/Features/Pulse/PulseVitals.swift:275` | 8 `VitalCell`s, each name + value + unit + delta + sparkline |
| `FinishSheet.summary` | `Onyx/Features/Logger/FinishSheet.swift:244` | 6 figures, 7 captions |
| `SessionDetailView.metrics` | `.../SessionDetailView.swift:597` | 6 stat cells — **documented as deliberate**, a register not a card |
| `FatigueSquare` | `Onyx/Features/Pulse/PulseSquares.swift:664` | 1 reading, 6 captions in 139 pt |

A **register** — a grid built to be scanned, where no cell outranks another —
is exempt and says so in its own header. `WeekVitalsRow` and `VitalsGrid` are
registers. `GoalBoardRow` is not: it has three heroes competing.

## 4. The three day-log sheets

| Sheet | File | Entry points | Writes |
|---|---|---|---|
| Stress log | `Onyx/Features/Pulse/PulseStressLog.swift:102` | Pulse square, Pulse AX5 row, Today's Quick Log spoke, a widget deep link | ONE `stress_logs` row per save; N saves = N rows |
| Soreness / DOMS | `Onyx/Features/Pulse/PulseDoms.swift:370` | Pulse square, Pulse AX5 row, a VoiceOver rotor action. **No Quick Log spoke** | several rows, one per (muscle, side), written per tap, no Save |
| Water | `Onyx/Features/Nutrition/NutritionSheets.swift:228` | Fuel row **long-press** (tap adds a glass instead), Quick Log spoke, widget button, Control Centre, the watch | Save replaces the whole day (`setWaterOverride`); a glass appends one row |

Three sheets, three write shapes, three entry conventions. They are merged into
one **Log day** sheet with three segments, reached from one place on each tab —
which also gives soreness the Quick Log spoke it never had, and puts the water
sheet behind a visible control rather than a long-press nobody discovers.

The write shapes are NOT unified: a stress reading is an event, a soreness
rating is an upsert per muscle, and a water total is a replacement. One sheet,
three segments, three writes — merging the writes would be merging three
different facts.
