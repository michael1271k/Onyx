// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import Foundation
import OnyxCore

// MARK: - The render gate's fixture
//
// One full-scope snapshot, every optional populated, frozen at a fixed date.
// The tiles are photographed from this (`PreviewHarness` → `widgets`) so a diff
// in `native/__screenshots__` is a diff of the DRAWING and never of the data.
// Previews and the package tests read the same value; nothing here is real.

public extension OnyxSnapshot {
  /// The moment `sample` was "generated". Build tile entries against this date
  /// rather than `Date()`, or every fixture renders as hours stale.
  static let sampleDate = OnyxSnapshot.timestamp("2026-09-03T08:15:00.000Z")!

  static let sample: OnyxSnapshot = {
    let today = "2026-09-03"
    func days(_ back: Int) -> String {
      let cal = Calendar(identifier: .gregorian)
      let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
      let base = f.date(from: today)!
      return f.string(from: cal.date(byAdding: .day, value: -back, to: base)!)
    }
    func series(_ values: [Double], step: Int = 1) -> [Point] {
      values.enumerated().map { i, v in Point(d: days((values.count - 1 - i) * step), v: v) }
    }

    // Six weeks of the Onyx-5 rotation ending today (a Wednesday session).
    let rotation: [(String, String)?] = [
      ("cb_a", "Chest & Back A"), ("legs_a", "Legs & Core A"), ("arms", "Delts & Arms"), nil,
      ("cb_b", "Chest & Back B"), ("legs_b", "Legs & Core B"), nil,
    ]
    let calendar: [CalendarDay] = (0..<42).reversed().map { back in
      let slot = rotation[(41 - back) % 7]
      let logged = slot != nil && back > 0 && back % 9 != 4
      return CalendarDay(
        d: days(back), dayKey: slot?.0, label: slot?.1,
        scheduled: slot != nil, logged: logged,
        volumeKg: logged ? 6200 + Double((41 - back) * 37 % 900) : nil)
    }

    // ── The W12 series ──────────────────────────────────────────────────────
    //
    // Built by CALLING the builders rather than by hand-writing their output.
    // A fixture typed out as a literal is a second implementation of the thing
    // it is meant to photograph — and the one place a tile's arithmetic could
    // be wrong without any vector noticing, because the fixture would be wrong
    // in the same way.

    // Eight weeks of the same rotation the calendar draws, so the dot grid and
    // the month grid tell one story. Every ninth scheduled day is missed, which
    // is what puts hollow rings on the tile.
    let consistencyDays: [ConsistencyDayIn] = (0..<56).reversed().map { back in
      let slot = rotation[(55 - back) % 7]
      return ConsistencyDayIn(
        date: days(back), dayKey: slot?.0,
        scheduled: slot != nil,
        logged: slot != nil && back > 0 && back % 9 != 4)
    }
    let consistency = ConsistencySeries.build(consistencyDays, endingOn: today, weeks: 8)

    // A cut that is working, with two days a week the sync missed — which is
    // what makes `daysCounted` worth printing.
    let ledgerDays: [DeficitDayIn] = (0..<56).reversed().map { back in
      let t = 55 - back
      let holed = t % 11 == 3
      return DeficitDayIn(
        date: days(back),
        intakeKcal: holed ? nil : 1950 + Double((t * 37) % 180) - 90,
        bmrKcal: 1540,
        activeKcal: holed ? nil : 520 + Double((t * 53) % 260),
        weightKg: t % 3 == 0 ? (66.4 - Double(t) * 0.021 * 10).rounded() / 10 : nil)
    }
    let deficit = DeficitLedgerSeries.build(ledgerDays, endingOn: today, weeks: 8)

    // Thirty mornings on the scale, every second one, drifting down through a
    // half-kilo of water noise — the shape the EWMA exists to see through.
    let scale: [GoalBoard.Reading] = (0..<30).reversed().map { back in
      let t = Double(29 - back)
      return GoalBoard.Reading(
        date: days(back),
        weightKg: back % 2 == 0 ? ((66.0 - t * 0.07 + 0.35 * sin(t / 2.3)) * 100).rounded() / 100 : nil)
    }
    let trajectory = TrajectorySeries.build(
      scale, today: today, targetWeightKg: 62, rateMinKgWk: -0.5, rateMaxKgWk: -0.4)

    // A fortnight of batteries: a good night, a short one, a heavy leg day, a
    // week with the load catching up, and one day the scorer never reached.
    let stackDays: [BatteryStackDayIn] = (0..<14).reversed().map { back in
      let t = 13 - back
      guard t != 6 else { return BatteryStackDayIn(date: days(back)) }
      // Every term annotated and hoisted: one `ScoringInputs(...)` literal of
      // thirty ternaries defeats the type checker outright.
      let hard: Bool = t % 5 == 0
      let day = Double(t)
      let sleepHours: Double = hard ? 6.1 : 7.4 + Double(t % 3) * 0.3
      let steps: Double = 8_200 + Double((t * 613) % 4_200)
      let activeCal: Double = 480 + Double((t * 137) % 380)
      var inputs = ScoringInputs(
        sleepHours: sleepHours,
        deepMinutes: hard ? 42 : 66,
        remMinutes: hard ? 61 : 94,
        steps: steps,
        activeCal: activeCal,
        workoutLogged: hard,
        isRestDay: !hard,
        sessionVolumeKg: hard ? 11_800 : 0,
        trailingAvgVolumeKg: 9_100)
      inputs.sessionRpe = hard ? 8.5 : nil
      inputs.sessionDayKey = hard ? "legs_a" : nil
      inputs.hrvZ = hard ? -0.9 : 0.4
      inputs.rhrZ = hard ? 0.8 : -0.3
      inputs.acwr = 1.05 + day * 0.03
      inputs.strainZ = day * 0.08 - 0.3
      inputs.fatigueLevel = hard ? 4 : 2
      inputs.domsSeverity = hard ? 2 : 0.5
      inputs.sleepOnsetTrouble = t % 7 == 2
      let breakdown = Battery.breakdown(inputs, hoursAwake: Battery.defaults.maxAwake)
      return BatteryStackDayIn(date: days(back), batteryPct: jsRound(breakdown.currentPct), breakdown: breakdown)
    }
    let batteryStack = BatteryStackSeries.build(stackDays, endingOn: today, limit: 14)

    // The scale's own composition columns, on the mornings it reported them.
    let compReadings: [BodyCompReadingIn] = (0..<30).reversed().compactMap { back in
      let t = Double(29 - back)
      guard back % 3 == 0 else { return nil }
      let weight = ((66.0 - t * 0.07) * 10).rounded() / 10
      let fat = ((16.4 - t * 0.035) * 10).rounded() / 10
      return BodyCompReadingIn(
        date: days(back), weightKg: weight, fatPct: fat,
        skeletalMuscleKg: ((26.6 + t * 0.006) * 10).rounded() / 10,
        leanSoftTissueKg: ((weight * (100 - fat) / 100) * 10).rounded() / 10,
        fatFreeMassKg: ((weight - weight * fat / 100) * 100).rounded() / 100)
    }
    let bodyComp = BodyCompSeries.build(compReadings, endingOn: today, days: 30)

    // ── The fortnight of stress, RUN and not typed ──────────────────────────
    //
    // Same argument as the W12 series above: a hand-written index is a second
    // implementation of `Stress.breakdown`, and it would go on photographing a
    // number the model had stopped producing. The inputs are the same shape
    // the battery stack's are — a hard day every fifth, one day nobody
    // answered — so the sparkline and the fatigue tile tell one story about
    // the same fortnight.
    let stressDays: [StressDayIn] = (0..<14).reversed().map { back in
      let t = 13 - back
      guard t != 6 else { return StressDayIn(date: days(back), breakdown: nil) }
      let hard = t % 5 == 0
      var inputs = StressInputs()
      inputs.hrvZ = hard ? -0.9 : 0.4
      inputs.rhrZ = hard ? 0.8 : -0.3
      inputs.fragZ = hard ? 0.7 : -0.2
      inputs.sleepOnsetTrouble = t % 7 == 2
      inputs.fatigueDayMean = hard ? 4 : 2.5
      inputs.stressDayMean = hard ? 4 : 2
      inputs.acwr = 1.05 + Double(t) * 0.03
      inputs.strainZ = Double(t) * 0.08 - 0.3
      return StressDayIn(date: days(back), breakdown: Stress.breakdown(inputs))
    }
    let stressSeries = StressSeries.build(stressDays, endingOn: today, limit: 14)

    // ── The week's rings ────────────────────────────────────────────────────
    //
    // The same rotation the calendar and the consistency grid draw, so the
    // three tiles agree about which days were training days. Two of the seven
    // miss their calorie band and one night falls short — a week with holes in
    // it is the week worth photographing, because a full board proves only
    // that the filled mark renders.
    let weekRings: [WeekRingDay] = (0..<7).reversed().map { back in
      let slot = rotation[(6 - back) % 7]
      return WeekRingDay(
        date: days(back),
        trained: slot != nil && back > 0,
        fuelHit: back % 3 != 1,
        sleepHit: back != 2 && back != 5)
    }

    return OnyxSnapshot(
      date: today,
      generatedAt: "2026-09-03T08:15:00.000Z",
      scope: "full",
      battery: 72,
      score: 81,
      sleep: Sleep(
        minutes: 437, deepMin: 68, remMin: 92, coreMin: 251, awakeMin: 26, score: 84,
        startTime: "2026-09-02T22:41:00.000Z", endTime: "2026-09-03T06:04:00.000Z",
        goalMin: 480, trend: series([412, 455, 398, 470, 431, 402, 437]),
        // Half an hour later than the usual — a night the regularity term has
        // something to say about, which a fixture at the median would not.
        //
        // ── AND IT WILL NOT AGREE WITH `startTime` ON THE CONTACT SHEET ─────
        // `startTime` is an ISO instant that every face renders in the DEVICE's
        // zone; `medianBedtime` is a clock string the BUILDER already rendered,
        // because the offsets it comes from are minutes past a UTC noon and a
        // face has no business converting those twice. So a fixture can make
        // the two agree in exactly one timezone, and the shot simulator's is
        // not UTC — 22:41Z draws as 01:41 on a +3 machine beside a flat
        // "Usually 23:12". Nothing is wrong with either number; the pair is
        // only readable together on a real device, where both came from the
        // same clock.
        medianBedtime: "23:12"),
      weight: Weight(
        kg: 64.3, deltaKg: -0.4, measuredOn: today, targetKg: 62, prevWeekMeanKg: 65.1,
        trend: series([66.1, 65.9, 65.8, 65.4, 65.5, 65.2, 64.9, 65.0, 64.8, 64.7, 64.6, 64.5, 64.7, 64.3])),
      macros: Macros(
        kcal: 1240, kcalGoal: 1955, proteinG: 128, proteinGoalG: 170, carbsG: 121, carbsGoalG: 195,
        fatG: 38, fatGoalG: 55, kcalTrend: series([1980, 1870, 2110, 1940, 1790, 1905, 1240])),
      water: Water(ml: 1900, goalMl: 3000, trend: series([2800, 3100, 2600, 3000, 2400, 2900, 1900])),
      steps: Steps(
        count: 7412, goal: 10000, distanceM: 5630, activeKcal: 412,
        trend: series([10200, 8600, 11400, 9100, 7300, 12100, 7412])),
      workout: Workout(
        label: "Delts & Arms", dayKey: "arms", logged: false, isRestDay: false,
        plannedExercises: 7, plannedSets: 21, lastVolumeKg: 5840),
      week: Week(sessions: 2, volumeKg: 13400, prs: 3, sets: 44, sessionTarget: 5),
      weekPrev: WeekTotals(sessions: 5, volumeKg: 31200, prs: 1, sets: 108),
      records: [
        Record(exercise: "Incline DB Press", axis: "weight", value: 32.5, reps: 8, achievedOn: days(1)),
        Record(exercise: "Hack Squat", axis: "e1rm", value: 148.2, reps: nil, achievedOn: days(2)),
        Record(exercise: "Neutral-Grip Lat Pulldown", axis: "volume", value: 780, reps: nil, achievedOn: days(2)),
        Record(exercise: "Hanging Knee Raise", axis: "reps", value: 18, reps: 18, achievedOn: days(4)),
      ],
      e1rm: [
        E1rm(exercise: "Incline DB Press", kg: 41.2, deltaKg: 1.6, trend: series([38.9, 39.4, 40.1, 40.6, 41.2], step: 6)),
        E1rm(exercise: "Hack Squat", kg: 148.2, deltaKg: 4.1, trend: series([141.0, 143.7, 144.2, 147.0, 148.2], step: 6)),
        E1rm(exercise: "Lat Pulldown", kg: 88.5, deltaKg: -0.8, trend: series([89.1, 90.0, 88.9, 89.3, 88.5], step: 6)),
        E1rm(exercise: "Shoulder Press", kg: 27.9, deltaKg: 0.0, trend: series([27.5, 27.9, 28.1, 27.7, 27.9], step: 6)),
      ],
      // A real Onyx-5 cut week at Thursday: the sixteen landmarks against the
      // founder's `plan_phase_volume` targets. Side delts is deliberately short
      // (the lateral raise lives on Upper B) — it is the reading F2 was hiding,
      // and every screenshot of this tile should show it behind.
      muscleFocus: [
        MuscleVolume(muscle: "Chest", sets: 12, target: 12),
        MuscleVolume(muscle: "Lats", sets: 10.5, target: 12),
        MuscleVolume(muscle: "Upper back", sets: 8, target: 10),
        MuscleVolume(muscle: "Lower back", sets: 3.5, target: 6),
        MuscleVolume(muscle: "Front delts", sets: 7.5, target: 6),
        MuscleVolume(muscle: "Side delts", sets: 3, target: 9),
        MuscleVolume(muscle: "Rear delts", sets: 4, target: 8),
        MuscleVolume(muscle: "Biceps", sets: 9, target: 10),
        MuscleVolume(muscle: "Triceps", sets: 11, target: 10),
        MuscleVolume(muscle: "Forearms", sets: 2.5, target: 4),
        MuscleVolume(muscle: "Quads", sets: 8, target: 10),
        MuscleVolume(muscle: "Hamstrings", sets: 6, target: 8),
        MuscleVolume(muscle: "Glutes", sets: 5.5, target: 8),
        MuscleVolume(muscle: "Adductors", sets: 0, target: 0),
        MuscleVolume(muscle: "Calves", sets: 4, target: 6),
        MuscleVolume(muscle: "Abs/core", sets: 6, target: 6),
      ],
      today: nil,
      streak: Streak(current: 51, best: 51),
      context: DayContext(mode: "travel", label: "Travel"),
      cardio: Cardio(
        last: Cardio.Session(kind: "walk", date: days(1), distanceM: 5200, durationMin: 52, paceMinPerKm: 10.0),
        weekSessions: 1, weekTarget: 2, weekMinutes: 52,
        trend: series([0, 35, 0, 0, 44, 0, 52])),
      calendar: calendar,
      volumeTrend: series([28100, 29400, 30200, 27800, 31000, 30100, 31200, 13400], step: 7),
      body: Body(
        fatPct: 14.8, muscleKg: 50.3, smmKg: 26.8, ffmKg: 53.1,
        fatPctDelta: -0.3, muscleKgDelta: 0.1, smmKgDelta: 0.0, ffmKgDelta: 0.2,
        fatTrend: series([15.9, 15.7, 15.8, 15.5, 15.4, 15.3, 15.1, 15.2, 15.0, 14.9, 15.0, 14.9, 14.8, 14.8])),
      scores: Scores(sleep: 84, nutrition: 76, activity: 71, workout: 90, recovery: 83),
      readiness: Readiness(level: "ready", label: "Ready to train", color: "#3DFFB0",
                           reason: "HRV above baseline and a full night's sleep."),
      vitals: Vitals(
        hrvMs: Vital(value: 54, baseline: 49, trend: series([47, 51, 46, 50, 52, 49, 54])),
        restingBpm: Vital(value: 52, baseline: 55, trend: series([56, 55, 57, 54, 55, 53, 52])),
        wristTempDeltaC: Vital(value: 0.12, baseline: -0.05, trend: series([-0.1, 0.0, -0.05, -0.08, 0.02, 0.05, 0.12])),
        bloodOxygenPct: Vital(value: 97.4, baseline: 97.1, trend: series([97.0, 97.3, 96.9, 97.2, 97.0, 97.5, 97.4])),
        respiratoryRate: Vital(value: 14.2, baseline: 14.6, trend: series([14.8, 14.5, 14.9, 14.4, 14.6, 14.3, 14.2]))),
      consistency: consistency,
      deficit: deficit,
      trajectory: trajectory,
      batteryStack: batteryStack,
      bodyComp: bodyComp,
      // RUN, never typed out. A hand-written sentence in the fixture is a
      // second author for the one string the Mega tile draws, and it would go
      // on photographing a line the rule table had stopped producing. The
      // inputs are the sample's own: a 72 % battery with three hours of sleep
      // debt behind it, which is the table's "the only thing behind" branch —
      // the most useful one to have a picture of, because it is the one that
      // has to fit two lines under the rings.
      coach: CoachSentence.sentence(CoachSentence.Inputs(batteryPct: 72, sleepDebtHours: 3.2)),
      weekRings: weekRings,
      // A leg day two days ago, still felt. Both a whole group rated (Quads)
      // and one that expands to three landmarks (Shoulders → the delts), so
      // the figure's group-to-landmark fan-out is exercised in the shot rather
      // than assumed.
      soreness: [
        SorenessRegion(landmark: "Quads", level: 3),
        SorenessRegion(landmark: "Glutes", level: 2),
        SorenessRegion(landmark: "Hamstrings", level: 2),
        SorenessRegion(landmark: "Front delts", level: 1),
        SorenessRegion(landmark: "Side delts", level: 1),
        SorenessRegion(landmark: "Rear delts", level: 1),
      ],
      stress: StressFace(index: stressSeries.last { $0.d == today }?.index, series14: stressSeries))
  }()

  /// The same fixture with every W12 series removed, and the muscle split with
  /// it.
  ///
  /// ── WHY AN EMPTY FIXTURE IS PART OF THE GATE ────────────────────────────
  /// A tile is reviewed twice: once for what it draws with data, and once for
  /// what it draws without. The second is the state a new device is in for its
  /// first week, and it is the one that goes unphotographed and ships as a
  /// stack of zeroes — which is the bug `OnyxChartEmpty` and the "nil is not
  /// zero" rule exist to prevent. Both shots, every tile (§W12's gate).
  static let sampleEmptySeries: OnyxSnapshot = {
    let s = sample
    return OnyxSnapshot(
      date: s.date, generatedAt: s.generatedAt, scope: s.scope, battery: s.battery, score: s.score,
      // ── THE NIGHT STAYS; THE FORTNIGHT BEHIND IT DOES NOT ────────────────
      // A first week has last night — it does not have a usual bedtime, which
      // `median` refuses under five nights. Carrying `sample.sleep` whole made
      // the "empty" Bedtime cell an exact copy of the populated one, so the
      // one branch that tile has ("No usual bedtime yet") was photographed by
      // nothing. Same argument as the series below, one field over.
      sleep: Sleep(
        minutes: s.sleep.minutes, deepMin: s.sleep.deepMin, remMin: s.sleep.remMin,
        coreMin: s.sleep.coreMin, awakeMin: s.sleep.awakeMin, score: s.sleep.score,
        startTime: s.sleep.startTime, endTime: s.sleep.endTime, goalMin: s.sleep.goalMin,
        trend: s.sleep.trend, medianBedtime: nil),
      weight: s.weight, macros: s.macros, water: s.water, steps: s.steps,
      workout: s.workout, week: s.week, weekPrev: s.weekPrev, records: s.records, e1rm: s.e1rm,
      muscleFocus: nil, today: s.today, streak: nil, context: s.context, cardio: s.cardio,
      calendar: s.calendar, volumeTrend: s.volumeTrend, body: nil, scores: s.scores,
      readiness: s.readiness, vitals: s.vitals,
      consistency: nil, deficit: nil, trajectory: nil, batteryStack: nil, bodyComp: nil)
  }()

  /// The same fixture with today's session FINISHED.
  ///
  /// ── WHY THE DONE STATE NEEDED A FIXTURE OF ITS OWN ──────────────────────
  /// `TodayFace` has three states and the shipped sample photographs one of
  /// them: a training day still due. The DONE state draws a completely
  /// different body — `TodayStats`, six figures over two rows — and it is
  /// therefore the half of that tile no contact sheet has ever shown. It is
  /// also where the session's calories and mean heart rate landed, so a layout
  /// fault in it would have shipped unseen. Same argument as
  /// `sampleEmptySeries` one property up, one axis over.
  static let sampleLogged: OnyxSnapshot = {
    let s = sample
    return OnyxSnapshot(
      date: s.date, generatedAt: s.generatedAt, scope: s.scope, battery: s.battery, score: s.score,
      sleep: s.sleep, weight: s.weight, macros: s.macros, water: s.water, steps: s.steps,
      workout: Workout(
        label: s.workout.label, dayKey: s.workout.dayKey, logged: true, isRestDay: false,
        plannedExercises: s.workout.plannedExercises, plannedSets: s.workout.plannedSets,
        lastVolumeKg: s.workout.lastVolumeKg),
      week: s.week, weekPrev: s.weekPrev, records: s.records, e1rm: s.e1rm,
      muscleFocus: s.muscleFocus,
      // A real Onyx-5 arms session: 68 minutes, an 8 on the ladder, 5.8 t, two
      // records, 412 kcal and a mean of 118. The last two are the readings
      // `workout_sessions` has carried since W2 and no face had ever drawn.
      today: Today(durationMin: 68, sessionRpe: 8, volumeKg: 5840, setCount: 21, prCount: 2,
                   caloriesKcal: 412, avgBpm: 118),
      streak: s.streak, context: s.context, cardio: s.cardio,
      calendar: s.calendar, volumeTrend: s.volumeTrend, body: s.body, scores: s.scores,
      readiness: s.readiness, vitals: s.vitals,
      consistency: s.consistency, deficit: s.deficit, trajectory: s.trajectory,
      batteryStack: s.batteryStack, bodyComp: s.bodyComp, coach: s.coach,
      weekRings: s.weekRings, soreness: s.soreness, stress: s.stress)
  }()
}

#endif
