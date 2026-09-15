# Stress index v1 — a report-only index over the readiness signals

**Status: shipped 2026-09-08 (Phase 3 E3, Track E).** Implemented twice and proven equal: `src/lib/scoring/stress.ts` + `src/lib/charts/stressSeries.ts` on the web, `native/Packages/OnyxCore/Sources/OnyxCore/Scoring/Stress.swift` + `Charts/StressSeries.swift` on the phone. The `stress-breakdown`, `stress-constants`, `stress-fragmentation`, `stress-series` and `stress-battery-isolation` golden vectors (`npm run golden`) are the specification; `npm test` and `npm run swift:core` replay them. A number in this document that disagrees with a vector is a documentation bug.

Founder decision 2 (2026-09-06): **report-only**. The index is a Pulse tile, a Trends series and (from E5) one line of the export's `DERIVED` footer. It is not a battery input, it has no mood question, and it stores no column.

## 1. What it answers

The battery answers "how much is left today". Its five drains say *where the charge went*, but the two things that make a day feel heavy without spending much charge — a night broken by wakings, and a whole day spent at "Heavy" — are read by the battery as one small wellness item or not at all. The index reads them, alongside the autonomic and load signals readiness already computes, and says how far from *your own normal* the day sits.

Daily `S ∈ [10, 90]`. **50 is your normal.** Band words on the reachable range:

| Band | S |
|---|---|
| Calm | < 30 |
| Baseline | 30 – 50 |
| Elevated | 50 – 62 |
| High | 62 – 75 |
| Overreached | > 75 |

Each upper edge is inclusive — 50 is Baseline, 62 is Elevated, 75 is High — except Calm's, so that your normal is never one rounding step from "Elevated". A vector reaches every band from real inputs (`stress-breakdown.json`: 28 · 48 · 59 · 70 · 88, and the floor 10).

## 2. The grammar — the same as readiness v9

Personal z-scores against your own baseline, SWC-gated, clamped ±2; **missing terms neutral, answered terms renormalised**; **load never negative**. Every z below is either a `Readiness.signals` output or built with the same `zSignal` (7-day rolling mean vs the 42 days before it, smallest worthwhile change 0.5 × SD as the dead-band, ±2 clamp — Plews 2013, Buchheit 2014; see `READINESS_MODEL.md` §2).

```
z_auto  = mean of answered { −hrvZ, rhrZ }
z_sleep = mean of answered { fragZ, onset }
            fragZ = z( awake_min / asleep_min  vs the 42-day baseline, SWC 0.5·SD ), clamped ±2
                    MISSING for a duration-only row (awake = deep = rem = 0)
            onset = 1 if sleep_onset_trouble else 0        one-sided: a calm night does not de-stress
z_self  = mean of answered { clamp(fatigueDayMean − 3, −2, 2), clamp(stressDayMean − 3, −2, 2) }
            fatigueDayMean = the DAY's fatigue slots, ALL of them, not the latest (1–5)
            stressDayMean  = the DAY's stress_logs levels, all of them (1–5; W2, decision 3)
z_load  = clamp( ½ · ( max(0, strainZ) + 2 · max(0, min(ACWR, 2.0) − 1.3) / 0.7 ), 0, 2 )

S       = round( clamp( 50 + 20 · Σ wᵢ zᵢ / Σ wᵢ  over ANSWERED terms, 10, 90 ) )
w       = { auto 0.35, sleep 0.25, self 0.25, load 0.15 }
```

**Answered.** A term is answered when at least one of its inputs is a finite number (or, for onset, a readable boolean — `false` is an answer). An unanswered term contributes to neither sum; the rest are renormalised. So one term alone at +2 reads 90 whichever term it is, and a term at exactly zero *does* dilute — that is what answered means. **Nothing answered → no reading** (`index = null`), never a 50 standing in: the tile draws a gap, as the battery stack does for an unscored day.

**No second smoothing.** The z inputs are already rolling means against a baseline. The sparkline draws S itself.

### 2.1 Autonomic — Plews 2013, Buchheit 2014

`hrvZ` and `rhrZ` are `Readiness.signals.hrv.z` and `.rhr.z` exactly: ln(HRV) and raw resting HR, 7-day rolling vs 42-day baseline, SWC-gated, ±2. HRV enters negated (suppressed HRV is stress), resting HR as-is (elevated is stress). The mean of the two that answered; one alone stands for the term.

### 2.2 Sleep — Ohayon 2017 (fragmentation), Hooper 1995 (onset)

Ohayon et al. (2017), the National Sleep Foundation's consensus on sleep-quality indicators, rate **wake after sleep onset** and the **number of awakenings** as the two strongest markers of poor sleep quality in adults, ahead of stage architecture. Onyx has one of them per night — `sleep_sessions.awake_min`, the union of HealthKit's awake samples — and reads it as a **fraction of time asleep**, so the same twenty awake minutes weigh more in a five-hour night than an eight-hour one. The ratio series goes through `zSignal` raw (it is already a proportion; no log), rolling 7 vs baseline 42, SWC-gated. It is your fragmentation against your own weeks, not against a population figure.

A **duration-only row** — the Shortcut-era and manual web nights, and any night whose `awake = deep = rem = 0` — carries no stage data. Its zero awake minutes are an absence, not a perfectly still night, so the night is a **hole** in the series (`fragmentationRatio` → null), and the history builder nulls `awakeMin` for it on both platforms (`readinessHistoryFor`, `AppDatabase.readinessHistory`). A night with stages and genuinely zero awake minutes is a real zero.

**Onset** is the `daily_logs.sleep_onset_trouble` flag — the one Hooper item the battery already reads as a wellness complaint — and it is **one-sided**: `1` when the night was hard to fall into, `0` otherwise, never negative. Falling asleep easily is the absence of a stressor, not a de-stressor; letting it pull S below 50 would make the index reward every unremarkable night. `false` is still an answer, so the sleep term's weight stays in Σw on a calm night with no fragmentation data.

### 2.3 Self-report — Hooper 1995

Hooper & Mackinnon (1995) found that athletes' daily ratings of fatigue, sleep, stress and soreness track overtraining ahead of the physiology. Onyx's fatigue scale is five words with definitions (Fresh · Fine · Worn · Heavy · Empty, stored 1–5), logged up to three times a day. The battery reads the **latest** slot, the tracker's rule for the day's one figure. The index reads the **day mean of every slot logged** (`fatigueDayMean` / `Fatigue.dayMean`): how heavy the whole day felt, which is the question stress asks. "Worn" (3) is neutral; the scale's own range is exactly ±2, so the clamp is a guard, not a shape.

**Since W2 the term has a second input — psychological stress.** `stress_logs` (founder decision 3, 2026-09-10) holds a 1 (calm) … 5 (overwhelmed) level per slot per day with optional tag chips; the index reads the **day mean of every row** (`stressDayMean`), centred on 3 and clamped exactly as fatigue is, and the term is the **mean of the two that answered**. Hooper treats fatigue and stress as one self-report, so the weights are unchanged (self stays 0.25): a day with only fatigue logged reads exactly as it did before the table existed, and a day with both averages them rather than doubling the self-report's say. `answered` on the term is 0, 1 or 2. Psych stress is NOT a Battery input — `ScoringInputs` still carries no stress field (§3, §7). Three hand-computed vectors in `stress-breakdown.json` pin the arithmetic.

**W4 gave it a writer, and W1 (Live UX) made it an event log.** `stress_logs` holds one row per `logStress` call (`PulseHead.swift`), each stamped with `logged_at`; a day holds any number of rows, not three, and re-answering adds a row rather than replacing one (`deleteStress` removes one). The slot — `morning` (before 12:00), `midday` (before 18:00), `evening` — is derived from that timestamp, never chosen by the user; a day that has already passed derives `evening`. The `self` term's `stressDayMean` is unchanged: the flat mean of every row logged that day. The words are **Relaxed · Okay · Tense · Strained · Swamped** (`PsychStress.levels`): "Calm" is deliberately not one of them, because `StressBand.calm` already prints that word on the computed tile directly above the row. Tags and the note are report-only and reach no term.

### 2.4 Load — Foster 1998, Williams 2017

Both inputs are `Readiness.signals.load`'s: the EWMA acute:chronic ratio (Williams 2017) and this week's Foster strain against your own rolling strains (Foster 1998; see `READINESS_MODEL.md` §3). The term rises from an ACWR of 1.3 (the top of the "sweet spot") to saturation at 2.0 and reads any positive strain z; both pieces are floored at zero and the sum halved into the ±2 grammar. **A light week de-stresses nothing** — the same drain-only argument the battery makes — so `z_load ≥ 0` always, and the term is unanswered only when both inputs are missing.

The term reads the load drain's **inputs**, not the drain value, so the tile and the battery stack cannot disagree about the same fact at two rounding points.

## 3. Collinearity with the battery — stated plainly

Three of the four terms are built from scalars the battery reads: `hrvZ` and `rhrZ` (the charge's `hrvQ`/`rhrQ`), `acwr` and `strainZ` (the load drain), `sleep_onset_trouble` (a wellness item). Fatigue is the same source at a different summary (mean vs latest). **The index will co-move with `BatteryStackSeries` by construction**, and a founder reading both tiles should expect it: on a day the battery is low because the week was hard, the index will be Elevated for the same week. That is not a second measurement; it is the same signals arranged around a different question — *how far from normal* rather than *how much is left* — and the two surfaces are kept from disagreeing by sharing inputs rather than by pretending independence.

What is genuinely new to the index is **fragmentation** and **the day's whole fatigue curve**. Those are the reason it exists.

**The battery does not read the index, and the index does not change the battery.** `ScoringInputs` carries no stress field; `Battery.breakdown` is untouched by this wave; the drain budget is still 35 + 12 + 32 + 8 + 6 = **93**. `stress-battery-isolation.json` computes the battery breakdown alongside the index at every extreme and expects the same breakdown in every case; `InvariantTests` (Swift) and `stress.test.ts` assert it, and that `MAX_TOTAL_DRAIN == 93`.

## 4. Inputs and where they come from

| Term | Input | Web | Phone |
|---|---|---|---|
| auto | `hrvZ`, `rhrZ` | `computeReadinessSignals(readinessHistoryFor(...))` | `Readiness.signals(readinessHistory(...))` |
| sleep | `fragZ` | `fragmentationZ(history.awakeMin, history.asleepMin)` — the 49-day series `readinessHistoryFor` lays from `sleep_sessions` (longest row per night window, filed under `nightOf(start_time)`) | `Stress.fragmentationZ` over the same two series from `AppDatabase.readinessHistory` |
| sleep | `onset` | `daily_logs.sleep_onset_trouble` | `DailyLogRow.sleepOnsetTrouble` |
| self | `fatigueDayMean` | `fatigueDayMean(foldFatigueRows(rows))` | `Fatigue.dayMean(Fatigue.foldRows(rows))` |
| self | `stressDayMean` | — (web has no stress log; dies with W6) | mean of `stress_logs.level` for the day (`StressInputsBuilder`) |
| load | `acwr`, `strainZ` | `signals.load` | `signals.load` |

`fetchReadinessHistory` gained one narrow select (`sleep_sessions.start_time, duration_min, deep_min, rem_min, awake_min` over the union of the 49 night windows); `ReadinessHistoryBuilder` gained the same two arrays. `ReadinessHistory.awakeMin`/`asleepMin` are optional on both sides — the battery never reads them and the `readiness-signals` vectors predate them.

## 5. Series

`stressSeries` / `StressSeries.build` — `BatteryStackSeries`' shape: exactly `limit` (default 14) consecutive days ending on `endingOn`, oldest first; a day with no reading is present and `empty`. Each day carries the index, the band, and each term's z to one decimal (null where unanswered), for the breakdown sheet. Vector: `stress-series.json`.

## 6. Storage — none in v1

Computed on read, on both platforms. The phone's `AppDatabase.stressBreakdown(userId:date:)` and `stressSeries(userId:endingOn:limit:)` build each day's inputs from the local store; the web computes it where it draws it. Documented upgrade if the widget budget or the Trends read ever complains: `daily_scores.stress_index int` + `stress_breakdown jsonb`, written beside `battery_pct` by the same scorer, with the cascade rewriting both. Nothing here depends on that column existing.

## 7. Invariants (asserted on both sides)

1. Missing terms neutral: a term with no finite input is excluded from Σw; nothing answered → `index = null`.
2. `z_load ∈ [0, 2]` for every ACWR and strain z; a light week reads 0, never below.
3. `S ∈ [10, 90]`, an integer; 50 is Baseline; every band reachable from real inputs.
4. `Battery.breakdown(inputs)` is identical with and without any stress input, and `MAX_TOTAL_DRAIN == 93`.
5. Fragmentation: a duration-only night is a hole; a still night with stages is a real zero; the z is the unchanged readiness `zSignal`.

## 8. Known limits

- **One fragmentation marker, not two.** Ohayon 2017 rates awakenings-per-night alongside WASO; HealthKit's samples could count them, but `sleep_sessions` stores only the union minutes. A count would need a column (§6).
- **The self-report is optional.** On a day nothing was logged the term is unanswered and the index leans on the physiology — which is the renormalisation doing its job, and also why a run of un-logged days reads calmer than the athlete may feel.
- **Bands are Onyx's, not a paper's.** They partition the reachable range so that each z-band has a word; nothing in the literature names an "Elevated" stress at 0.5 SD. They are labels for a personal scale.
- **Sept 1–2 (illness) spot-check** is recorded in the E3 report, not here; the model is not tuned to it.

## References

- Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M. *Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring.* Sports Medicine 2013;43(9):773–781.
- Buchheit M. *Monitoring training status with HR measures: do all roads lead to Rome?* Frontiers in Physiology 2014;5:73.
- Foster C. *Monitoring training in athletes with reference to overtraining syndrome.* Medicine & Science in Sports & Exercise 1998;30(7):1164–1168.
- Williams S, West S, Cross MJ, Stokes KA. *Better way to determine the acute:chronic workload ratio?* British Journal of Sports Medicine 2017;51(3):209–210.
- Hooper SL, Mackinnon LT. *Monitoring overtraining in athletes: recommendations.* Sports Medicine 1995;20(5):321–327.
- Ohayon M, Wickwire EM, Hirshkowitz M, et al. *National Sleep Foundation's sleep quality recommendations: first report.* Sleep Health 2017;3(1):6–19.
