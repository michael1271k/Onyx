import Foundation

/// The widget payload — every tile draws from this and nothing else.
///
/// Lifted verbatim from the web-shell app's `OnyxSnapshot.swift` (Wave 5), minus
/// the HTTP client: the extension now reads the App Group GRDB file through
/// `WidgetSnapshotBuilder` in OnyxData and builds one of these locally. The
/// shape is unchanged so the tile drawing code is unchanged. Every field is
/// optional on purpose: rendering "—" is correct, rendering an invented number
/// is not.

// MARK: - Model

/// Which slice of the payload to ask for.
///
/// The two composite widgets read disjoint halves and an extension is measured
/// in hundreds of milliseconds against a hard memory cap. The scope only ever
/// trims the OPTIONAL extras — every non-optional property below arrives in
/// every scope, because a decode failure renders as "can't reach ONYX", which
/// would blame the network for what is really a shape mismatch.
public enum OnyxScope: String, Codable, Sendable {
  case lifestyle
  case performance
  case training
  case body
  case full
}

/// Mirrors the web app's `WidgetSnapshot`. Every field is
/// optional on purpose: rendering "—" is correct, rendering a stale or invented
/// number is not.
public struct OnyxSnapshot: Codable, Sendable, Equatable {
  /// One dated reading. Short keys — this crosses the wire thousands of times.
  public struct Point: Codable, Sendable, Equatable, Identifiable {
    public let d: String
    public let v: Double
    public var id: String { d }
    public init(d: String, v: Double) {
      self.d = d
      self.v = v
    }
  }

  public struct Sleep: Codable, Sendable, Equatable {
    public let minutes: Int?
    public let deepMin: Int?
    public let remMin: Int?
    /// Stage TOTALS, not a timeline. Nothing here may be drawn against a CLOCK
    /// axis: the ordering a real hypnogram implies is not in this data, and
    /// `sleep_sessions` is the only table the builder reads (sample-level
    /// stages would need `sleep_samples`, which does not exist — W6's stated
    /// ceiling). W6's depth strip therefore lays the four stages out by DEPTH
    /// and scales them by SHARE OF NIGHT, and says so on its own axis.
    public let coreMin: Int?
    public let awakeMin: Int?
    public let score: Int?
    public let startTime: String?
    public let endTime: String?
    /// The user's own target, in minutes. The sleep face hardcoded 480, so a
    /// seven-hour goal was graded against someone else's eight.
    public let goalMin: Int?
    /// Seven nights of duration, oldest first. Body scope. One night is a
    /// reading; seven is the thing worth changing a bedtime over.
    public let trend: [Point]?
    /// "23:30" — the usual bedtime, as a LOCAL clock time, over the fortnight
    /// before tonight.
    ///
    /// ── WHY A STRING AND NOT A NUMBER ─────────────────────────────────────
    /// The store holds this as minutes past the night window's UTC noon
    /// (`bedtimeOffsets`), which is the only form that does not wrap around
    /// midnight and the only form the regularity term can take a median of. It
    /// is also unreadable: 690 is half past eleven and nothing about it says
    /// so. The conversion needs the device's zone, and the builder is the one
    /// place that has one — a face converting it would be a second timezone
    /// decision on the same fact, which is how a bedtime reads three hours
    /// wrong on a phone in Jerusalem (see `clockTime`).
    ///
    /// Nil under five nights: `median` refuses a baseline it cannot call
    /// usual, and this is that same refusal with a clock on it.
    public let medianBedtime: String?
    public init(minutes: Int? = nil, deepMin: Int? = nil, remMin: Int? = nil, coreMin: Int? = nil, awakeMin: Int? = nil, score: Int? = nil, startTime: String? = nil, endTime: String? = nil, goalMin: Int? = nil, trend: [Point]? = nil, medianBedtime: String? = nil) {
      self.minutes = minutes
      self.deepMin = deepMin
      self.remMin = remMin
      self.coreMin = coreMin
      self.awakeMin = awakeMin
      self.score = score
      self.startTime = startTime
      self.endTime = endTime
      self.goalMin = goalMin
      self.trend = trend
      self.medianBedtime = medianBedtime
    }
  }
  public struct Weight: Codable, Sendable, Equatable {
    public let kg: Double?
    public let deltaKg: Double?
    public let measuredOn: String?
    public let targetKg: Double?
    /// Last week's mean — the dotted baseline the fortnight is read against.
    /// Nil, never zero: a 0 kg baseline would draw an ordinary fortnight as a
    /// catastrophic gain.
    public let prevWeekMeanKg: Double?
    public let trend: [Point]?
    public init(kg: Double? = nil, deltaKg: Double? = nil, measuredOn: String? = nil, targetKg: Double? = nil, prevWeekMeanKg: Double? = nil, trend: [Point]? = nil) {
      self.kg = kg
      self.deltaKg = deltaKg
      self.measuredOn = measuredOn
      self.targetKg = targetKg
      self.prevWeekMeanKg = prevWeekMeanKg
      self.trend = trend
    }
  }
  public struct Macros: Codable, Sendable, Equatable {
    public let kcal: Double?
    public let kcalGoal: Double?
    public let proteinG: Double?
    public let proteinGoalG: Double?
    public let carbsG: Double?
    public let carbsGoalG: Double?
    public let fatG: Double?
    public let fatGoalG: Double?
    /// Seven days of intake, oldest first. Lifestyle scope.
    public let kcalTrend: [Point]?
    /// The day's micronutrients furthest from target, furthest first
    /// (`KeyMicro.top`, overhaul B2). Optional ON THE WIRE so a payload written
    /// before it decodes — synthesized `Codable` only tolerates a missing key
    /// for an Optional — and read through `micros`, which is never nil.
    public let keyMicros: [KeyMicro]?
    public var micros: [KeyMicro] { keyMicros ?? [] }
    public init(kcal: Double? = nil, kcalGoal: Double? = nil, proteinG: Double? = nil, proteinGoalG: Double? = nil, carbsG: Double? = nil, carbsGoalG: Double? = nil, fatG: Double? = nil, fatGoalG: Double? = nil, kcalTrend: [Point]? = nil, keyMicros: [KeyMicro]? = nil) {
      self.keyMicros = keyMicros
      self.kcal = kcal
      self.kcalGoal = kcalGoal
      self.proteinG = proteinG
      self.proteinGoalG = proteinGoalG
      self.carbsG = carbsG
      self.carbsGoalG = carbsGoalG
      self.fatG = fatG
      self.fatGoalG = fatGoalG
      self.kcalTrend = kcalTrend
    }
  }
  public struct Water: Codable, Sendable, Equatable {
    public let ml: Double?
    public let goalMl: Double?
    /// Seven days of intake, oldest first. Lifestyle scope — without it a Water
    /// face above Small has one number and a goal, which is a Small's worth of
    /// content however much room it is given.
    public let trend: [Point]?
    public init(ml: Double? = nil, goalMl: Double? = nil, trend: [Point]? = nil) {
      self.ml = ml
      self.goalMl = goalMl
      self.trend = trend
    }
  }
  public struct Steps: Codable, Sendable, Equatable {
    public let count: Int?
    public let goal: Int?
    public let distanceM: Double?
    public let activeKcal: Double?
    public let trend: [Point]?
    public init(count: Int? = nil, goal: Int? = nil, distanceM: Double? = nil, activeKcal: Double? = nil, trend: [Point]? = nil) {
      self.count = count
      self.goal = goal
      self.distanceM = distanceM
      self.activeKcal = activeKcal
      self.trend = trend
    }
  }
  public struct Workout: Codable, Sendable, Equatable {
    public let label: String
    public let dayKey: String?
    public let logged: Bool
    public let isRestDay: Bool
    /// What the PLAN asks of today, phase-resolved server-side. Optional so a
    /// build talking to an older deployment still decodes; nil renders as "—",
    /// never as a zero, because on a training day a zero reads as "nothing to
    /// do".
    public let plannedExercises: Int?
    public let plannedSets: Int?
    /// Tonnage the last time this same `dayKey` was trained — the number the
    /// due state is chasing.
    public let lastVolumeKg: Double?
    /// The landmark muscles the day's DECK is built on, in deck order, each
    /// named once. `LandmarkMuscle.rawValue`s — the payload carries strings so
    /// a widget built against an older vocabulary decodes rather than throws.
    ///
    /// ── WHY IT IS ON `workout` AND NOT ON `today` (W6) ──────────────────────
    /// The brief said `today.muscles`. `today` is nil until a session is
    /// logged, and the face that wants this is the DUE state — the wash exists
    /// to say what the session in front of you is about, hours before there is
    /// a session to summarise. On `workout` it is the same fact in both
    /// states, because a deck's muscles do not change when you finish it.
    ///
    /// Nil on a rest day and on a day the program cannot name: a wash with no
    /// hues draws nothing, which is the honest picture of "nothing is planned"
    /// (`PulseTabView.muscleWash` makes the same choice for the same reason).
    public let muscles: [String]?
    public init(label: String, dayKey: String? = nil, logged: Bool, isRestDay: Bool, plannedExercises: Int? = nil, plannedSets: Int? = nil, lastVolumeKg: Double? = nil, muscles: [String]? = nil) {
      self.label = label
      self.dayKey = dayKey
      self.logged = logged
      self.isRestDay = isRestDay
      self.plannedExercises = plannedExercises
      self.plannedSets = plannedSets
      self.lastVolumeKg = lastVolumeKg
      self.muscles = muscles
    }

    /// The deck's muscles as landmarks, unknown tokens dropped.
    public var landmarks: [LandmarkMuscle] {
      (muscles ?? []).compactMap(LandmarkMuscle.init(rawValue:))
    }
  }
  public struct Week: Codable, Sendable, Equatable {
    public let sessions: Int
    /// Nil, never 0, when the week holds no sessions at all.
    ///
    /// This one field broke the file's own rule — "nil renders as '—'; an
    /// invented zero renders as a lie" — for the whole of Phase 2. It was
    /// non-optional, the builder summed an empty array, and every volume
    /// surface read "0.0 t": on Monday morning, on a fresh install, and
    /// throughout the casing bug that hid every synced session from the query.
    /// "0 kg" is a claim that you lifted nothing. "—" is the truth, which is
    /// that there is nothing to total yet.
    ///
    /// `sessions`, `prs` and `sets` stay non-optional on purpose: a count of
    /// occurrences genuinely is zero when none occurred.
    public let volumeKg: Double?
    public let prs: Int
    public let sets: Int
    /// How many training days the plan schedules — "3 sessions" needs a
    /// denominator to mean anything at a glance.
    public let sessionTarget: Int?
    public init(sessions: Int, volumeKg: Double?, prs: Int, sets: Int, sessionTarget: Int? = nil) {
      self.sessions = sessions
      self.volumeKg = volumeKg
      self.prs = prs
      self.sets = sets
      self.sessionTarget = sessionTarget
    }
  }
  /// Last week's totals. No `sessionTarget`: the plan may have changed since,
  /// and a denominator from this week's plan over last week's count is a
  /// comparison of two different things.
  public struct WeekTotals: Codable, Sendable, Equatable {
    public let sessions: Int
    /// Nil, never 0, when the week holds no sessions — see `Week.volumeKg`.
    public let volumeKg: Double?
    public let prs: Int
    public let sets: Int
    public init(sessions: Int, volumeKg: Double?, prs: Int, sets: Int) {
      self.sessions = sessions
      self.volumeKg = volumeKg
      self.prs = prs
      self.sets = sets
    }
  }
  public struct Record: Codable, Sendable, Equatable, Identifiable {
    public let exercise: String
    public let axis: String
    public let value: Double
    public let reps: Int?
    public let achievedOn: String
    /// The standing mark this record CLEARED — `personal_records.floor_value`.
    ///
    /// ── WHY IT IS THE FLOOR AND NOT "THE PREVIOUS RECORD" (W6) ──────────────
    /// W6's brief asked for the record before this one. There is no such row:
    /// `personal_records` has a UNIQUE natural key on
    /// `(user_id, exercise_key, axis)`, so the table holds ONE standing record
    /// per lift per axis and a beaten record is overwritten, not kept. The
    /// history is not thrown away by accident — `PrRecorder.carryFloor` keeps
    /// the bar that was cleared in `floor_value` precisely because the row
    /// replacing it would otherwise take the floor with it.
    ///
    /// So the margin is "how far past the bar this is", not "how much better
    /// than last time". On a lift with three successive records that is the
    /// distance from where the book opened, which is a true and more useful
    /// statement than a delta against a row that no longer exists. Deriving the
    /// previous record from `workout_sets` instead would be a second
    /// implementation of PR eligibility — working sets, rep windows, the pair
    /// rule — beside `PrRecorder`, which is the one thing this project has
    /// learned not to do with records.
    ///
    /// Nil when nothing stood before it, and nil rather than an equal value: a
    /// record that cleared nothing has no margin, and "+0.0 kg" under a trophy
    /// claims a gain that did not happen. The face renders it "first on the
    /// board".
    public let previous: Double?
    public var id: String { "\(exercise)-\(axis)" }
    public init(exercise: String, axis: String, value: Double, reps: Int? = nil, achievedOn: String, previous: Double? = nil) {
      self.exercise = exercise
      self.axis = axis
      self.value = value
      self.reps = reps
      self.achievedOn = achievedOn
      self.previous = previous
    }

    /// How far past the mark it cleared this record stands, in the axis's own
    /// units. Nil when it cleared nothing, and nil when it did not actually
    /// improve on it — a compiled floor ABOVE a logged record must not report a
    /// negative gain.
    public var margin: Double? {
      guard let previous, previous < value else { return nil }
      return value - previous
    }
  }
  public struct E1rm: Codable, Sendable, Equatable, Identifiable {
    public let exercise: String
    public let kg: Double
    /// Nil when the lift has no session old enough to compare against — which
    /// is a different statement from "no change", and must not render as +0.
    public let deltaKg: Double?
    /// The per-DAY best estimate over the window, oldest first. The chip says
    /// the lift moved; the shape says whether it climbed or spiked once and gave
    /// it back, and those two want opposite decisions next session.
    public let trend: [Point]?
    public var id: String { exercise }
    public init(exercise: String, kg: Double, deltaKg: Double? = nil, trend: [Point]? = nil) {
      self.exercise = exercise
      self.kg = kg
      self.deltaKg = deltaKg
      self.trend = trend
    }
  }
  /// One LANDMARK's week: weighted sets against the phase's target.
  ///
  /// The payload's muscle grain since W3, and the only one — the eight-family
  /// figures the bars draw are rolled up from these (`volumeByFamily`), so a
  /// tile cannot disagree with the sheet it opens about how much work a session
  /// was. Decision 4: charts group by eight, the atlas paints sixteen; one array
  /// is what makes those the same reading at two grains.
  public struct MuscleVolume: Codable, Sendable, Equatable, Identifiable {
    /// `LandmarkMuscle.rawValue` — the display spelling the atlas keys on.
    public let muscle: String
    /// Fractional by design: a secondary mover earns half a set.
    public let sets: Double
    /// The `plan_phase_volume` row for this muscle and phase. Zero is a real
    /// answer: Adductors is 0 on a cut, and a muscle with no target is not
    /// behind, it is unasked-for.
    public let target: Int
    public var id: String { muscle }
    public init(muscle: String, sets: Double, target: Int) {
      self.muscle = muscle
      self.sets = sets
      self.target = target
    }
    public var landmark: LandmarkMuscle? { LandmarkMuscle(rawValue: muscle) }
  }

  /// A family's week — the sum of its landmarks', in the same currency.
  ///
  /// ── WHY A SUM AND NOT A SET COUNT ──────────────────────────────────────────
  /// A leg press credits quads in full and glutes and hamstrings at a half, so
  /// one physical set rolls up to 2.0 weighted sets of Legs. That is not double
  /// counting: it is what the muscles were asked for, and the TARGET rolls up
  /// the same way (quads 10 + hams 8 + glutes 8 + adductors 0 + calves 6 = 32),
  /// so the ratio the bar draws is the ratio the programme is written in.
  public struct FamilyVolume: Codable, Sendable, Equatable, Identifiable {
    /// The family itself, not its name. It is built from `MuscleFamily.allCases`
    /// and only ever read to pick a colour and a label, so a `String` bought
    /// nothing and cost every reader a `MuscleFamily(rawValue:) ?? .chest` —
    /// which turns a typo into chest-red rather than into a compile error.
    public let family: MuscleFamily
    /// Fractional by design: a secondary mover earns half a set.
    public let sets: Double
    public let target: Int
    public var id: String { family.rawValue }
    public init(family: MuscleFamily, sets: Double, target: Int) {
      self.family = family
      self.sets = sets
      self.target = target
    }
    /// 0…1 against the target, or nil when the plan asks for nothing — a rail
    /// that sits full or empty at random says less than no rail.
    public var progress: Double? {
      target > 0 ? Swift.min(1, sets / Double(target)) : nil
    }
  }

  /// TODAY's logged session — distinct from `workout`, which is what the PLAN
  /// says. Null until something has actually been logged, which is exactly the
  /// difference the Today face is drawing.
  public struct Today: Codable, Sendable, Equatable {
    public let durationMin: Int?
    public let sessionRpe: Double?
    public let volumeKg: Double?
    public let setCount: Int?
    public let prCount: Int?
    /// What the session cost, as `workout_sessions.calories_burned` holds it.
    ///
    /// Summed across the day's sessions, like volume: two sessions cost what
    /// they both cost. Nil — never zero — when nothing measured or estimated
    /// one, because a training day that reads `0 kcal` is a claim.
    public let caloriesKcal: Double?
    /// Mean heart rate over the session, `workout_sessions.avg_bpm`.
    ///
    /// Taken from the LONGEST session and never averaged across two, for the
    /// reason duration and RPE are: the mean of two means is a number that
    /// describes neither bout.
    public let avgBpm: Int?
    public init(durationMin: Int? = nil, sessionRpe: Double? = nil, volumeKg: Double? = nil, setCount: Int? = nil, prCount: Int? = nil, caloriesKcal: Double? = nil, avgBpm: Int? = nil) {
      self.durationMin = durationMin
      self.sessionRpe = sessionRpe
      self.volumeKg = volumeKg
      self.setCount = setCount
      self.prCount = prCount
      self.caloriesKcal = caloriesKcal
      self.avgBpm = avgBpm
    }
  }

  /// One day of the training calendar.
  ///
  /// `dayKey` is the PLAN's key for that date, resolved server-side through
  /// `serverScheduleContext` so a swap moves it — and it is what tints the ring
  /// (`Onyx.day`). `logged` is whether a session actually landed. The two
  /// disagreeing is the whole point of the surface.
  public struct CalendarDay: Codable, Sendable, Equatable, Identifiable {
    public let d: String
    public let dayKey: String?
    /// The plan's own name for the day — "Legs & Core B". Nil on a rest day.
    /// A colour identifies a session; it cannot name one.
    public let label: String?
    /// False on a scheduled rest day.
    public let scheduled: Bool
    public let logged: Bool
    public let volumeKg: Double?
    public var id: String { d }
    public init(d: String, dayKey: String? = nil, label: String? = nil, scheduled: Bool, logged: Bool, volumeKg: Double? = nil) {
      self.d = d
      self.dayKey = dayKey
      self.label = label
      self.scheduled = scheduled
      self.logged = logged
      self.volumeKg = volumeKg
    }
  }

  /// Cardio: the last session, and how the week stands against Zone 2.
  ///
  /// ── ZONE 2 IS A COUNT OF SESSIONS ──────────────────────────────────────────
  /// `weekSessions` counts sessions at or over 20 minutes, against `weekTarget`
  /// (2). It is NOT a minute total, and `weekMinutes` beside it is deliberately
  /// labelled as minutes so the two can never be confused. The app draws one pip
  /// per session in the CardioLogger; a widget counting minutes under the same
  /// words would disagree with it on the same phone, which is the failure the
  /// streak already taught this project once.
  public struct Cardio: Codable, Sendable, Equatable {
    public struct Session: Codable, Sendable, Equatable {
      public let kind: String
      public let date: String
      public let distanceM: Double?
      public let durationMin: Double?
      /// Minutes per kilometre, computed SERVER-side. Pace there is a minimum
      /// with a 1 km floor; recomputing it here would be a second chance to get
      /// that wrong.
      public let paceMinPerKm: Double?
      public init(kind: String, date: String, distanceM: Double? = nil, durationMin: Double? = nil, paceMinPerKm: Double? = nil) {
        self.kind = kind
        self.date = date
        self.distanceM = distanceM
        self.durationMin = durationMin
        self.paceMinPerKm = paceMinPerKm
      }
    }
    public let last: Session?
    public let weekSessions: Int
    public let weekTarget: Int
    public let weekMinutes: Int
    public let trend: [Point]?
    public init(last: Session? = nil, weekSessions: Int, weekTarget: Int, weekMinutes: Int, trend: [Point]? = nil) {
      self.last = last
      self.weekSessions = weekSessions
      self.weekTarget = weekTarget
      self.weekMinutes = weekMinutes
      self.trend = trend
    }
  }

  /// The program day, twice.
  ///
  /// `current` is days elapsed since the cut opened (2026-07-15), both ends
  /// counted — a figure that only rises. `best` carries the same number: the
  /// shape predates the redefinition and a monotonic count has no separate
  /// record, so reporting them as equal is the honest answer rather than an
  /// omission. See `lib/training/streak.ts` for why the consecutive-days walk
  /// is still derived and no longer rendered.
  public struct Streak: Codable, Sendable, Equatable {
    public let current: Int
    public let best: Int
    public init(current: Int, best: Int) {
      self.current = current
      self.best = best
    }
  }

  /// One overnight reading, with the normal it is read against.
  ///
  /// `baseline` is computed SERVER-side over a fortnight, excluding today. A
  /// widget that averaged its own seven-point trend would be a second
  /// definition of "normal" and would disagree with the app the first time the
  /// windows differed by a day — the same class of split the streak taught this
  /// project once already.
  public struct Vital: Codable, Sendable, Equatable {
    public let value: Double?
    public let baseline: Double?
    public let trend: [Point]?

    /// How far tonight sits from your own normal, or nil when either is missing.
    public var delta: Double? {
      guard let value, let baseline else { return nil }
      return value - baseline
    }
    public init(value: Double? = nil, baseline: Double? = nil, trend: [Point]? = nil) {
      self.value = value
      self.baseline = baseline
      self.trend = trend
    }
  }

  /// The five readings a watch takes overnight.
  ///
  /// Steps and sleep are deliberately absent: they have their own blocks with
  /// their own goals, and the Vitals faces read those. Duplicating them here
  /// would be two payload fields that must agree and one day would not.
  public struct Vitals: Codable, Sendable, Equatable {
    public let hrvMs: Vital?
    public let restingBpm: Vital?
    public let wristTempDeltaC: Vital?
    public let bloodOxygenPct: Vital?
    public let respiratoryRate: Vital?
    public init(hrvMs: Vital? = nil, restingBpm: Vital? = nil, wristTempDeltaC: Vital? = nil, bloodOxygenPct: Vital? = nil, respiratoryRate: Vital? = nil) {
      self.hrvMs = hrvMs
      self.restingBpm = restingBpm
      self.wristTempDeltaC = wristTempDeltaC
      self.bloodOxygenPct = bloodOxygenPct
      self.respiratoryRate = respiratoryRate
    }
  }

  /// The five sub-scores behind the composite.
  ///
  /// `Double`, not `Int`: these are `numeric` columns read straight out of
  /// `daily_scores`, and a single 82.4 in the payload makes an Int decoder throw
  /// — which surfaces as "can't reach ONYX", blaming the network for a type.
  public struct Scores: Codable, Sendable, Equatable {
    public let sleep: Double?
    public let nutrition: Double?
    public let activity: Double?
    public let workout: Double?
    public let recovery: Double?
    public init(sleep: Double? = nil, nutrition: Double? = nil, activity: Double? = nil, workout: Double? = nil, recovery: Double? = nil) {
      self.sleep = sleep
      self.nutrition = nutrition
      self.activity = activity
      self.workout = workout
      self.recovery = recovery
    }
  }

  /// Today's readiness verdict, as `computeReadiness` grades it. `color` is a
  /// hex string from the same palette — parsed, never guessed at.
  public struct Readiness: Codable, Sendable, Equatable {
    public let level: String
    public let label: String
    public let color: String
    public let reason: String
    /// Set only when the watch was off the wrist AND a wrist signal went
    /// missing with it (App Store W6). Optional, so a payload an older build
    /// parked in the App Group still decodes.
    public let offWrist: OffWristNote?
    public init(level: String, label: String, color: String, reason: String, offWrist: OffWristNote? = nil) {
      self.level = level
      self.label = label
      self.color = color
      self.reason = reason
      self.offWrist = offWrist
    }
  }

  /// Body composition beyond the scale weight.
  ///
  /// Three DIFFERENT measurements, never interchangeable: `smmKg` is skeletal
  /// muscle (~27 kg, entered by hand), `muscleKg` is lean soft tissue (~50 kg,
  /// and must be LABELLED as such), `ffmKg` is fat-free mass (~53 kg, derived).
  public struct Body: Codable, Sendable, Equatable {
    public let fatPct: Double?
    public let muscleKg: Double?
    public let smmKg: Double?
    public let ffmKg: Double?
    /// Movement since the previous DIFFERENT reading of that field. The table
    /// carries values forward, so a row-to-row delta would be 0.0 on every day
    /// between weigh-ins — "held steady" where the truth is "not measured".
    public let fatPctDelta: Double?
    public let muscleKgDelta: Double?
    public let smmKgDelta: Double?
    public let ffmKgDelta: Double?
    public let fatTrend: [Point]?
    public init(fatPct: Double? = nil, muscleKg: Double? = nil, smmKg: Double? = nil, ffmKg: Double? = nil, fatPctDelta: Double? = nil, muscleKgDelta: Double? = nil, smmKgDelta: Double? = nil, ffmKgDelta: Double? = nil, fatTrend: [Point]? = nil) {
      self.fatPct = fatPct
      self.muscleKg = muscleKg
      self.smmKg = smmKg
      self.ffmKg = ffmKg
      self.fatPctDelta = fatPctDelta
      self.muscleKgDelta = muscleKgDelta
      self.smmKgDelta = smmKgDelta
      self.ffmKgDelta = ffmKgDelta
      self.fatTrend = fatTrend
    }
  }

  /// One day of the week's three rings.
  ///
  /// ── WHY THREE BOOLEANS AND NOT THREE PERCENTAGES ────────────────────────
  /// The tile draws seven columns of three marks in about 150 pt. A column of
  /// three part-filled arcs at that size is three greys; a column of three
  /// marks that are either on or off is a week you read in one look, which is
  /// the only reading this shape can carry. The percentages already have tiles
  /// of their own — Day Rings for today, the Fuel and Sleep faces for the
  /// number — and this one answers a different question: how many of the
  /// seven.
  ///
  /// ── AND WHY A MISSED DAY AND AN UNLOGGED ONE ARE THE SAME `false` ───────
  /// This breaks the file's own "missing is nil" rule on purpose and it is the
  /// only place that does. The rule exists so a reading is never INVENTED — a
  /// zero standing in for a number nobody took. A ring is not a reading: it is
  /// whether the day's goal was met, and a day with no food logged did not
  /// meet its calorie target however good the eating was. "Not hit" is the
  /// honest answer to the question the mark asks, and a third state would be a
  /// third mark in a column that has room for three.
  public struct WeekRingDay: Codable, Sendable, Equatable, Identifiable {
    /// `YYYY-MM-DD`.
    public let date: String
    /// A session landed. Not "was scheduled" — `consistency` is the tile that
    /// grades against the plan, and two tiles disagreeing about a Tuesday is
    /// the split this payload's one-accumulator rule exists to prevent.
    public let trained: Bool
    /// Intake was logged and landed within a tenth of that day's calorie
    /// target — the day's own target, phase- and lever-resolved, not today's.
    public let fuelHit: Bool
    /// The night that ended that morning reached the sleep goal.
    public let sleepHit: Bool
    public var id: String { date }
    public init(date: String, trained: Bool, fuelHit: Bool, sleepHit: Bool) {
      self.date = date
      self.trained = trained
      self.fuelHit = fuelHit
      self.sleepHit = sleepHit
    }
  }

  /// One sore LANDMARK, at the severity its group was rated.
  ///
  /// ── THE GROUP IS RATED, THE LANDMARK IS DRAWN ───────────────────────────
  /// `doms_logs.muscle_group` is one of ten words a user can tap ("a sore arm
  /// is a sore arm"); the atlas paints sixteen. The expansion is
  /// `DomsMuscles.landmarks`, one vocabulary in one generated file, so the
  /// tile's figure and the Pulse sheet's figure light the same shapes. The
  /// payload carries the expanded form because the tile is in OnyxUI and the
  /// map is in OnyxCore — a face that expanded it itself would be the second
  /// implementation this project has already paid for once.
  public struct SorenessRegion: Codable, Sendable, Equatable, Identifiable {
    /// `LandmarkMuscle.rawValue` — the display spelling the atlas keys on,
    /// exactly as `MuscleVolume.muscle` carries it.
    public let landmark: String
    /// 1…3 — Mild, Moderate, Severe. A rating of None is not carried: the
    /// array is what is SORE, and a zero in it would draw a lit muscle.
    public let level: Int
    public var id: String { landmark }
    public init(landmark: String, level: Int) {
      self.landmark = landmark
      self.level = level
    }
    public var muscle: LandmarkMuscle? { LandmarkMuscle(rawValue: landmark) }
  }

  /// The stress index and the fortnight behind it.
  ///
  /// `index` is nil on a day nothing was answered — never a 50, which is the
  /// centre of the scale and would read as an ordinary day. `series14` is
  /// exactly fourteen days ending today, oldest first, a day with no reading
  /// present and empty (`StressSeries`' own rule), so the sparkline draws a
  /// gap rather than a dive to the floor.
  public struct StressFace: Codable, Sendable, Equatable {
    public let index: Double?
    public let series14: [StressDay]
    public init(index: Double? = nil, series14: [StressDay] = []) {
      self.index = index
      self.series14 = series14
    }
    /// Calm … Overreached, or nil with no reading. Derived rather than
    /// carried: `Stress.band` is a pure function of the index and a second
    /// copy of it in the payload is a second thing that can disagree.
    public var band: StressBand? { index.map(Stress.band) }
  }

  /// A declared context, as the server writes it: the vocabulary key and the
  /// label to draw. The label comes down rather than being mapped here so the
  /// two sides cannot disagree about what "refeed" is called.
  /// One day of the energy ledger: what intake minus TDEE came to, or nil on a
  /// day with a hole in it.
  ///
  /// Nil and never zero — `Energy.tdee` refuses a day missing BMR, active
  /// energy or intake, because a missing sync counted as zero reports a ~400
  /// kcal larger deficit in the same direction every time it happens
  /// (`DeficitLedger.swift`'s header). A bar that is absent says so; a bar at
  /// the axis says the day broke even.
  public struct DayBalance: Codable, Sendable, Equatable, Identifiable {
    public let d: String
    public let kcal: Double?
    public var id: String { d }
    public init(d: String, kcal: Double? = nil) {
      self.d = d
      self.kcal = kcal
    }
  }

  public struct DayContext: Codable, Sendable, Equatable {
    public let mode: String
    public let label: String
    public init(mode: String, label: String) {
      self.mode = mode
      self.label = label
    }
  }

  public let date: String
  public let generatedAt: String
  /// Echoed by the server so a cache can be keyed on it. Optional so a build
  /// talking to an older deployment still decodes.
  public let scope: String?
  public let battery: Int?
  public let score: Int?
  public let sleep: Sleep
  public let weight: Weight
  public let macros: Macros
  /// `var`, alone among the blocks: the widget extension adds the glasses
  /// Control Center has queued and the app has not yet drained (W5,
  /// `PendingWater`), so the Water face reads the optimistic figure without
  /// every water reader learning about the queue.
  public var water: Water
  public let steps: Steps
  public let workout: Workout
  public let week: Week
  public let weekPrev: WeekTotals?
  public let records: [Record]?
  public let e1rm: [E1rm]?
  /// The week's weighted sets per landmark, against this phase's targets.
  /// Named `volumeByFamily` until W3, when the grain moved down to the sixteen
  /// and the eight became a rollup of it rather than a second count.
  public let muscleFocus: [MuscleVolume]?

  // ── Added with the four configurable families ──────────────────────────────
  // Every one is OPTIONAL, including `today`, which the server sends in all
  // scopes as `null` on a day with no session. A build talking to a deployment
  // from before these existed still decodes; the faces render "—", which is
  // what they do for a missing reading anyway.
  public let today: Today?
  public let streak: Streak?
  /// The day's declared context (Illness, Travel, Refeed…), or nil for an
  /// ordinary day. A widget that presents a sick day as a normal one is the
  /// surface most likely to be believed and least able to explain itself.
  public let context: DayContext?
  public let cardio: Cardio?
  public let calendar: [CalendarDay]?
  public let volumeTrend: [Point]?
  public let body: Body?
  public let scores: Scores?
  public let readiness: Readiness?
  /// Lifestyle scope. Absent on an older deployment; every face treats that as
  /// "no readings", which is the same thing it renders for a night off-wrist.
  public let vitals: Vitals?

  // ── The W12 series ─────────────────────────────────────────────────────────
  //
  // Five blocks, each the whole output of one builder in `OnyxCore/Charts`
  // rather than a flattened handful of numbers. The flattening is what the
  // faces would otherwise do twice — once in `WidgetSnapshotBuilder` for the
  // Home Screen and once in the app's own model for the Today grid — and two
  // flattenings of one series is how a tile and a screen come to disagree.
  //
  // Optional like everything else here: a build talking to a payload written
  // before them decodes, and the faces draw `OnyxChartEmpty` rather than a
  // zero. `Charts` is a peer module of `Widget` inside OnyxCore, so this costs
  // no new dependency.

  /// Training scope. Planned against done, eight weeks.
  public let consistency: Consistency?
  /// Lifestyle scope. The energy ledger against the scale.
  public let deficit: DeficitLedger?
  /// Body scope. The smoothed weight line and the board behind it.
  public let trajectory: Trajectory?
  /// Body scope. The v9 battery, taken apart, a fortnight of it.
  public let batteryStack: [BatteryStackDay]?
  /// Body scope. Four composition metrics and their own spans.
  public let bodyComp: [BodyCompMetric]?

  // ── The W7 sentence ────────────────────────────────────────────────────────
  //
  /// The Mega Widget's line — `CoachSentence.sentence`, resolved by the
  /// builder rather than by the face.
  ///
  /// ── WHY THE STRING AND NOT ITS INPUTS ──────────────────────────────────────
  /// The rule table is pure and lives in `Coach/CoachSentence.swift`, and
  /// `CoachSentence.Inputs` is one `Codable` struct, so carrying the inputs
  /// instead would cost one field rather than four and a face could fold them
  /// at render time. It would also be wrong, and the failure is quiet.
  ///
  /// The rules read four dimensions and every one of them is optional, because
  /// "in band" and "never looked at" are different facts and the table says so
  /// — nothing known at all is its own branch. Only the BUILDER knows which it
  /// is. Two of the four come from a `stressInputs` read that runs at one scope
  /// (`wantsBody`), so a payload built at a narrower one would carry a perfectly
  /// well-formed `Inputs` with the battery present and the load and stress
  /// absent — and a face folding that would print "Battery 72 % and nothing is
  /// behind. Train hard." from two readings nobody consulted. Resolving where
  /// the reads happen is the only place that distinction survives.
  ///
  /// Nil on a payload built before W7, and on any scope that does not resolve
  /// the battery. The face draws nothing rather than a blank line — which is
  /// also what a scoped render of the Mega tile would get, though nothing does
  /// that today: `.daily` is a dashboard tile and the grid builds at `.full`.
  public let coach: String?

  // ── The sprint's W4 faces ──────────────────────────────────────────────────
  //
  // Three blocks for the three new WidgetIds that need one; `bedtime` needs no
  // field of its own because it draws `sleep.medianBedtime` beside the night
  // `sleep` already carries. Filled at `.full` and `.body` — the two scopes
  // that already pay for the day's scoring reads — and nil everywhere else,
  // which every face renders as "—" like any other missing reading.

  /// The last seven days, one row each. `.full` and `.body`.
  public let weekRings: [WeekRingDay]?
  /// TODAY's soreness, expanded onto the atlas's landmarks. Only what is sore:
  /// an empty array is a day nothing hurts, which is a real answer, and nil is
  /// a payload that did not ask.
  public let soreness: [SorenessRegion]?
  /// The stress index and its fortnight. `.full` and `.body`.
  public let stress: StressFace?

  // ── W6 ─────────────────────────────────────────────────────────────────────

  /// The last SEVEN days of the energy ledger, oldest first — one signed
  /// balance a day, a hole left as nil.
  ///
  /// ── WHY IT IS NOT A FIELD ON `DeficitLedger` ───────────────────────────────
  /// It belongs there by shape and cannot go there by test: `deficit-ledger.json`
  /// compares the whole built `DeficitLedger` against a hand-computed expected
  /// value with `==`, so a new field — even an optional one — fails all ten
  /// cases on a difference that is not a difference in the arithmetic. The
  /// sprint's rule is that goldens are hand-edited only when the NUMBERS moved;
  /// they have not. `DeficitLedgerSeries.dayBalanceKcal` is public and is the
  /// one rule both surfaces call, so this is the same arithmetic in a second
  /// window, not a second implementation of it.
  ///
  /// Lifestyle scope, beside `deficit` itself.
  public let deficitDays: [DayBalance]?

  public init(date: String, generatedAt: String, scope: String? = nil, battery: Int? = nil, score: Int? = nil, sleep: Sleep, weight: Weight, macros: Macros, water: Water, steps: Steps, workout: Workout, week: Week, weekPrev: WeekTotals? = nil, records: [Record]? = nil, e1rm: [E1rm]? = nil, muscleFocus: [MuscleVolume]? = nil, today: Today? = nil, streak: Streak? = nil, context: DayContext? = nil, cardio: Cardio? = nil, calendar: [CalendarDay]? = nil, volumeTrend: [Point]? = nil, body: Body? = nil, scores: Scores? = nil, readiness: Readiness? = nil, vitals: Vitals? = nil, consistency: Consistency? = nil, deficit: DeficitLedger? = nil, trajectory: Trajectory? = nil, batteryStack: [BatteryStackDay]? = nil, bodyComp: [BodyCompMetric]? = nil, coach: String? = nil, weekRings: [WeekRingDay]? = nil, soreness: [SorenessRegion]? = nil, stress: StressFace? = nil, deficitDays: [DayBalance]? = nil) {
    self.date = date
    self.generatedAt = generatedAt
    self.scope = scope
    self.battery = battery
    self.score = score
    self.sleep = sleep
    self.weight = weight
    self.macros = macros
    self.water = water
    self.steps = steps
    self.workout = workout
    self.week = week
    self.weekPrev = weekPrev
    self.records = records
    self.e1rm = e1rm
    self.muscleFocus = muscleFocus
    self.today = today
    self.streak = streak
    self.context = context
    self.cardio = cardio
    self.calendar = calendar
    self.volumeTrend = volumeTrend
    self.body = body
    self.scores = scores
    self.readiness = readiness
    self.vitals = vitals
    self.consistency = consistency
    self.deficit = deficit
    self.trajectory = trajectory
    self.batteryStack = batteryStack
    self.bodyComp = bodyComp
    self.coach = coach
    self.weekRings = weekRings
    self.soreness = soreness
    self.stress = stress
    self.deficitDays = deficitDays
  }
}

extension OnyxSnapshot {
  /// The eight families, rolled up from the sixteen landmarks.
  ///
  /// Computed and not stored: two arrays that must agree is precisely the
  /// disease W3 cured (F7 — three accumulators, three currencies). In
  /// `MuscleFamily.allCases` order, which is the legend's order, and families
  /// the week never touched AND the plan never asked for are dropped — a bar of
  /// zero against a target of zero is a row that says nothing.
  public var volumeByFamily: [FamilyVolume] { Self.familyRollup(muscleFocus ?? []) }

  /// The rollup itself, so a test can check it without building a whole payload.
  public static func familyRollup(_ rows: [MuscleVolume]) -> [FamilyVolume] {
    let byMuscle = Dictionary(
      rows.compactMap { row in row.landmark.map { ($0, row) } },
      uniquingKeysWith: { a, _ in a }
    )
    return MuscleFamily.allCases.compactMap { family in
      let owned = family.members.compactMap { byMuscle[$0] }
      let sets = owned.reduce(0) { $0 + $1.sets }
      let target = owned.reduce(0) { $0 + $1.target }
      guard sets > 0 || target > 0 else { return nil }
      return FamilyVolume(family: family, sets: (sets * 10).rounded() / 10, target: target)
    }
  }

  /// Landmark → 0…1 for the atlas. `MuscleCredit.worked(sets:targets:)` states
  /// the rule; this is the payload's spelling of the same call the Today sheet
  /// and the Trends card make.
  public var muscleWorked: [String: Double] {
    let rows = (muscleFocus ?? []).compactMap { row in row.landmark.map { ($0, row) } }
    let worked = MuscleCredit.worked(
      sets: Dictionary(rows.map { ($0.0, $0.1.sets) }, uniquingKeysWith: { a, _ in a }),
      targets: Dictionary(rows.map { ($0.0, $0.1.target) }, uniquingKeysWith: { a, _ in a })
    )
    return Dictionary(worked.map { ($0.key.rawValue, $0.value) }, uniquingKeysWith: { a, _ in a })
  }

  /// Landmark → 0…1 for the atlas, from SORENESS rather than from work done.
  ///
  /// The same shape `muscleWorked` returns and read by the same figure, so the
  /// Soreness tile and the Muscle Focus tile are one drawing with two inputs.
  /// Severity over `DomsMuscles.maxSeverity`, which is the intensity the Pulse
  /// figure has always used (`DomsMap.worked`) — the atlas paints AMOUNT and
  /// passes no verdicts, so a severe quad is a strong tint, not a red one.
  public var soreWorked: [String: Double] {
    var out: [String: Double] = [:]
    for region in soreness ?? [] where region.level > 0 {
      let intensity = min(1, max(0, Double(region.level) / Double(DomsMuscles.maxSeverity)))
      out[region.landmark] = max(out[region.landmark] ?? 0, intensity)
    }
    return out
  }

  /// One composition metric out of the W12 series, or nil when the payload
  /// predates it. Every face reads it through here so a missing series is one
  /// `nil` rather than four spellings of the same lookup.
  public func metric(_ key: BodyMetricKey) -> BodyCompMetric? {
    bodyComp?.first { $0.key == key }
  }

  /// "over 24 d" — the span a delta ACTUALLY covers, when the series knows it.
  ///
  /// A face that captions its chip with the window's nominal length is claiming
  /// a month for two readings nine days apart. Nil when there is no delta to
  /// caption, which is also when there is nothing to overstate.
  public static func spanCaption(_ metric: BodyCompMetric?) -> String? {
    guard let days = metric?.deltaDays, days > 0, metric?.delta != nil else { return nil }
    return "over \(days) d"
  }

  /// kcal left against the goal — the small widget's headline. Nil when unknown.
  public var caloriesRemaining: Int? {
    guard let kcal = macros.kcal, let goal = macros.kcalGoal else { return nil }
    return Int((goal - kcal).rounded())
  }

  /// "8h27m" for a minute count, or "—".
  public static func formatSleep(_ minutes: Int?) -> String {
    guard let m = minutes, m > 0 else { return "—" }
    return "\(m / 60)h\(String(format: "%02d", m % 60))m"
  }

  /// Fractional progress toward a goal, clamped to 0...1 (nil when unknown).
  public static func progress(_ value: Double?, _ goal: Double?) -> Double? {
    guard let v = value, let g = goal, g > 0 else { return nil }
    return min(1, max(0, v / g))
  }

  /// A tonne figure for a kilogram total: "38.4 t". Nil stays nil.
  public static func tonnes(_ kg: Double?) -> String? {
    guard let kg else { return nil }
    return String(format: "%.1f t", kg / 1000)
  }

  /// "+2.5" / "−1.2" / nil. The minus is U+2212, which is the same width as the
  /// plus in a tabular face; a hyphen is not, and the column jitters.
  /// A reading at a fixed number of decimals, or nil.
  ///
  /// `String(format:)` and not a `NumberFormatter`: the vitals faces call this
  /// once per row per redraw, and a formatter allocated per call is real cost
  /// inside an extension's memory cap for output that never varies by locale —
  /// these are all monospaced-digit readings, not prose.
  public static func fixed(_ v: Double?, decimals: Int) -> String? {
    guard let v, v.isFinite else { return nil }
    return String(format: "%.\(max(0, decimals))f", v)
  }

  public static func signed(_ v: Double?, decimals: Int = 1) -> String? {
    guard let v else { return nil }
    let magnitude = String(format: "%.\(decimals)f", abs(v))
    if abs(v) < 0.05 { return magnitude }
    return (v > 0 ? "+" : "−") + magnitude
  }

  /// "3d ago" / "today" / "12 Aug" for a `YYYY-MM-DD`. Nil for an unparseable one.
  public static func relativeDay(_ iso: String?, from now: Date = Date()) -> String? {
    guard let iso, let then = dayFormatter.date(from: iso) else { return nil }
    let days = Calendar.current.dateComponents([.day], from: then, to: now).day ?? 0
    switch days {
    case ..<0:  return "today"
    case 0:     return "today"
    case 1:     return "yesterday"
    case 2...6: return "\(days)d ago"
    default:    return shortDayFormatter.string(from: then)
    }
  }

  /// "21:48" from an ISO timestamp, in the DEVICE's timezone. Bedtime read in
  /// UTC on a phone in Jerusalem is three hours wrong, every night.
  public static func clockTime(_ iso: String?) -> String? {
    guard let iso, let date = isoFormatter.date(from: iso) else { return nil }
    return clockFormatter.string(from: date)
  }

  /// An ISO timestamp → a `Date`, tolerating a missing fractional-seconds part.
  ///
  /// `generatedAt` is written by `new Date().toISOString()`, which ALWAYS
  /// carries milliseconds — but the strict formatter this file already uses
  /// rejects a timestamp without them, and Postgres-sourced values elsewhere in
  /// the payload arrive both ways. One parser that accepts both is the
  /// difference between a staleness tag that works and one that silently never
  /// fires, which is the failure mode this whole helper exists to end.
  public static func timestamp(_ iso: String?) -> Date? {
    guard let iso else { return nil }
    return isoFormatter.date(from: iso) ?? plainIsoFormatter.date(from: iso)
  }

  /// A payload age as a caption: "4m", "2h", "3d". Nil below a minute — a widget
  /// announcing it is forty seconds old is noise, not information.
  public static func shortAge(_ seconds: TimeInterval?) -> String? {
    guard let seconds, seconds >= 60 else { return nil }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    return "\(hours / 24)d"
  }

  // ── Calendar helpers ───────────────────────────────────────────────────────
  //
  // ── WHY WEEKDAYS ARE DERIVED AND NEVER ASSUMED ───────────────────────────────
  // The calendar payload is a rolling window ENDING TODAY, so its first cell is
  // whatever weekday today happens to be minus forty-one. The old grid chunked it
  // seven at a time and printed a hardcoded "S M T W T F S" over the result, so
  // every column was mislabelled by however far today sat from a Sunday. These
  // read the weekday out of the DATE, which is right whatever the window start —
  // and stays right if the server later aligns the window.

  /// 0 = Sunday … 6 = Saturday, for a `YYYY-MM-DD`. Nil for an unparseable one.
  public static func weekdayIndex(_ iso: String?) -> Int? {
    guard let iso, let date = dayFormatter.date(from: iso) else { return nil }
    return Calendar.current.component(.weekday, from: date) - 1
  }

  /// "S" / "M" / "T" … for a `YYYY-MM-DD`. Empty string when undatable, so a
  /// header cell holds its column rather than collapsing the grid.
  public static func weekdayInitial(_ iso: String?) -> String {
    guard let index = weekdayIndex(iso) else { return "" }
    return ["S", "M", "T", "W", "T", "F", "S"][max(0, min(6, index))]
  }

  /// The day of the month — the number that goes INSIDE a calendar ring, and
  /// which the grid drew none of.
  public static func dayOfMonth(_ iso: String?) -> Int? {
    guard let iso, let date = dayFormatter.date(from: iso) else { return nil }
    return Calendar.current.component(.day, from: date)
  }

  /// "AUG" on the first of a month, nil otherwise. What turns six undifferentiated
  /// rows of numbers into a calendar you can find a date in.
  public static func monthMarker(_ iso: String?) -> String? {
    guard dayOfMonth(iso) == 1, let date = dayFormatter.date(from: iso ?? "") else { return nil }
    return monthFormatter.string(from: date).uppercased()
  }

  /// "August" for any date in it — the calendar grid's own title.
  ///
  /// Distinct from `monthMarker`, which is a marker INSIDE a rolling grid and is
  /// deliberately nil on every day but the first. This one always answers, and
  /// it is what let the Calendar face stop captioning a month "THIS WEEK".
  public static func monthName(_ iso: String?) -> String? {
    guard let iso, let date = dayFormatter.date(from: iso) else { return nil }
    return fullMonthFormatter.string(from: date)
  }

  /// Whether a day belongs to the same calendar month as `reference`.
  ///
  /// String prefixes, not `Calendar` — `d` is `YYYY-MM-DD` and the first seven
  /// characters ARE the month, with no parsing to get a timezone wrong in.
  public static func sameMonth(_ iso: String, as reference: String?) -> Bool {
    guard let reference, reference.count >= 7 else { return true }
    return iso.hasPrefix(reference.prefix(7))
  }
}

private let dayFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "yyyy-MM-dd"
  f.timeZone = TimeZone.current
  return f
}()

private let shortDayFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "d MMM"
  return f
}()

private let monthFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "MMM"
  return f
}()

/// "August" — the grid's title, where `monthFormatter` gives the "AUG" marker.
private let fullMonthFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "MMMM"
  return f
}()

private let clockFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "HH:mm"
  return f
}()

nonisolated(unsafe) private let isoFormatter: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  // Postgres timestamps arrive with fractional seconds; the default parser
  // rejects them outright and every bedtime would silently read as "—".
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f
}()

/// The same thing WITHOUT fractional seconds. `ISO8601DateFormatter` is strict
/// in both directions — a parser configured for milliseconds rejects a timestamp
/// that has none — so the two are tried in turn by `timestamp(_:)`.
nonisolated(unsafe) private let plainIsoFormatter: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime]
  return f
}()

