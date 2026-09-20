import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The weekly export's payload — `WeeklyExportInput` and its parts, as declared
// in the web app's `lib/reports/weeklyExport.ts`. Nil means "not recorded" throughout;
// the renderer prints `—` for it and never a zero.
// ─────────────────────────────────────────────────────────────────────────────

public struct ExportSupplement: Codable, Equatable, Sendable {
    /// "HH:MM", or nil for an unscheduled item.
    public var time: String?
    /// The `custom_supplements.schedule.key` each `supplement_log` row is
    /// written against. Carried so a day's "taken" list can print NAMES: the
    /// log holds keys, and `d3k2@07:00` is not a line a person reads.
    public var key: String?
    public var name: String
    public var dose: String
    public var trainingDose: String?
    public var restDose: String?
    public var trainingOnly: Bool?
    public var notes: String?
}

public struct SupplementLogEntry: Codable, Equatable, Sendable {
    public var key: String
    public var time: String?
}

/// Readiness v9's signals for one day, exactly as the scorer read them —
/// `ExportReadiness`. Every field nil when the history was too thin to answer.
public struct ExportReadiness: Codable, Equatable, Sendable {
    public var hrvZ: Double?
    public var rhrZ: Double?
    public var load: Double?
    public var acute: Double?
    public var chronic: Double?
    public var acwr: Double?
    public var weeklyLoad: Double?
    public var monotony: Double?
    public var strain: Double?
    public var strainZ: Double?

    public init(hrvZ: Double?, rhrZ: Double?, load: Double?, acute: Double?, chronic: Double?, acwr: Double?, weeklyLoad: Double?, monotony: Double?, strain: Double?, strainZ: Double?) {
        self.hrvZ = hrvZ; self.rhrZ = rhrZ; self.load = load; self.acute = acute; self.chronic = chronic
        self.acwr = acwr; self.weeklyLoad = weeklyLoad; self.monotony = monotony; self.strain = strain; self.strainZ = strainZ
    }

    /// `flattenReadiness` — the signals as the export carries them.
    public init(signals s: ReadinessSignals) {
        self.init(
            hrvZ: s.hrv.z, rhrZ: s.rhr.z,
            load: s.load.today, acute: s.load.acute, chronic: s.load.chronic, acwr: s.load.acwr,
            weeklyLoad: s.load.weeklyLoad, monotony: s.load.monotony, strain: s.load.strain, strainZ: s.load.strainZ
        )
    }
}

public struct ExportDay: Codable, Equatable, Sendable {
    public var date: String
    public var weekdayLabel: String
    public var isTrainingDay: Bool
    public var weightKg: Double?
    public var calories: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var steps: Double?
    public var distanceM: Double?
    public var trainingMin: Double?
    public var sleepMin: Double?
    public var deepMin: Double?
    public var remMin: Double?
    public var restingHr: Double?
    public var hrvMs: Double?
    public var wristTempDeltaC: Double?
    public var bloodOxygenPct: Double?
    public var avgHr: Double?
    public var respiratoryRate: Double?
    public var vo2max: Double?
    public var daylightMin: Double?
    public var exerciseMin: Double?
    public var standHours: Double?
    public var standMin: Double?
    public var coreMin: Double?
    public var awakeMin: Double?
    public var bedTime: String?
    public var wakeTime: String?
    public var sleepOnsetTrouble: Bool?
    /// The night the wearer says the watch got wrong. Absent on every payload
    /// that is not disputing one — the builder omits the key rather than
    /// writing `false` seven times a week.
    public var sleepInaccurate: Bool?
    /// The battery's inputs the raw body cannot show, and the stored
    /// `battery_pct`. Read only by the Derived section. The two seven-day
    /// baselines are v8's (the recovery score still reads them); `readiness`
    /// is what v9's battery reads. Nil on a payload built before each existed.
    public var restingHrBaseline: Double?
    public var hrvBaseline: Double?
    public var batteryPct: Double?
    public var readiness: ExportReadiness?
    public var waterMl: Double?
    public var supplementsTaken: Double?
    public var supplementsPlanned: Double?
    public var supplementsLog: [SupplementLogEntry]?
    /// Doses the protocol asked for and the wearer refused — a real miss.
    public var supplementsSkipped: [String]?
    /// Doses refused that the day's resolved schedule did not ask for. The log
    /// is the evidence and the schedule is only a projection of it; filtering
    /// one through the other used to DELETE a skip whenever the two drifted
    /// (a day swapped Train↔Rest, an item archived mid-week).
    public var supplementsSkippedUnplanned: [String]?
    /// Scheduled doses whose slot had not come round yet. Always empty for a
    /// closed week; the clause exists so a partial week cannot round a pending
    /// dose up into an adherence figure.
    public var supplementsLater: [String]?
    public var nutrientsFood: [String: Double]?
    public var nutrientsStack: [String: Double]?
    public var activeKcal: Double?
    public var bmrKcal: Double?
    public var weighInSkipReason: String?
    public var nutritionException: String?
    public var nutritionEstimated: Bool
    /// Why `VitalsGate.hrvArtifact` refused to believe the day's HRV, in its
    /// own words. Present ONLY when the reading is doubted — a nil is "the
    /// gate had no objection", which is every ordinary night.
    public var hrvFlag: String?
    public var targetProfile: String?
    public var trackCarbs: Bool?
    public var trackFat: Bool?
}

public struct ExportCardio: Codable, Equatable, Sendable {
    public var date: String
    public var kind: String
    public var distanceM: Double?
    public var durationMin: Double?
    public var kcal: Double?
    public var totalKcal: Double?
    public var avgHr: Double?
    public var effort: Double?
    /// The bout's own start on an imported row; the moment of typing on a
    /// manual one. `source` is what tells the two apart — see the TypeScript
    /// twin's doc comment for why the column carries both.
    public var startedAt: String?
    public var elevationM: Double?
    /// `health` | `manual`. Optional only so a fixture written before this
    /// field existed still decodes; the builder always supplies it.
    public var source: String?
}

public struct ExportSet: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var reps: Double
    public var rpe: Double?
    public var side: String?
    public var failure: Bool
    public var warmup: Bool?
    public var ghost: Bool?
    public var dropset: Bool?
    public var quality: String?
    public var pairId: String?
    /// A CARDIO set's own axes — `workout_sets.duration_sec / distance_km /
    /// incline`, the four columns `SessionHistoryStore` has always selected and
    /// the export's hand-rolled copy of that query never did.
    ///
    /// A treadmill warm-up carries `weight_kg 0, reps 0` and all of its real
    /// measurement in here, so an export that drops them renders `W 0 reps` —
    /// a row that reads as nothing having happened. Nil on every resistance
    /// set, which is what these being optional means.
    ///
    /// SPEED IS NOT STORED and is not a column: it is distance over duration,
    /// derived at the render boundary. A treadmill's pace rises through a
    /// warm-up, so the stored pair is the honest record and a single speed is
    /// the average of it.
    public var durationSec: Double?
    public var distanceKm: Double?
    public var inclinePct: Double?

    var isWarmup: Bool { warmup == true }
    var isGhost: Bool { ghost == true }
}

public struct ExportExercise: Codable, Equatable, Sendable {
    public var name: String
    public var sets: [ExportSet]
    public var restTargetSec: Double?
    public var restPlanSec: Double?
    /// The MEAN measured rest between this exercise's sets, in seconds —
    /// `workout_sets.actual_rest_sec`, written by the logger as the gap between
    /// committing one set and the next. Nil for every session logged before the
    /// column shipped and for every session committed from the web, where it
    /// means "not measured" and the renderer prints the plan alone.
    public var restActualSec: Double?
    /// The landmark muscles the movement trains, spelled for a reader.
    /// Resolved in the builder so `exercises.muscle_groups` is honoured.
    public var primaryMuscles: [String]?
    public var secondaryMuscles: [String]?
    public var topKg: Double?
    public var repWindow: String?
    /// `exercises.is_compound` / `ProgramExercise.isCompound`, carried so the
    /// week can count the compound sets taken past RPE 8.5. Never guessed from
    /// the name — see `Exercises/Tags.swift`.
    public var compound: Bool?
    /// What the ACTIVE PLAN asked for, as it stands. Nil for a movement the
    /// plan does not name (a substitution, an accessory added on the day).
    public var prescription: ExportPrescription?
    /// The best set of the last session that performed this movement, before
    /// this one. Nil the first time it is ever logged.
    public var previous: ExportPrevious?
}

/// `3 × 8–12 @ 40 kg` — the plan's own row, never a back-formed average.
public struct ExportPrescription: Codable, Equatable, Sendable {
    public var sets: Double
    /// The window as the plan writes it: `"8–12"`, `"55s"`.
    public var reps: String
    /// `ProgramExercise.wk1Kg`. Absent for bodyweight and for a plan row that
    /// never carried a load.
    public var loadKg: Double?
}

/// The previous best set of one movement — the comparison every ACTUAL line is
/// read against. Dated, because "last time" is a date and not a week.
public struct ExportPrevious: Codable, Equatable, Sendable {
    public var date: String
    public var weightKg: Double
    public var reps: Double
}

public struct ExportPr: Codable, Equatable, Sendable {
    public var name: String
    public var weightKg: Double
    public var reps: Double
    public var axes: [PrAxis]
    public var volumeKg: Double?
    public var e1rmKg: Double?

    /// Public so a PREVIEW can write one. Every real payload decodes or is
    /// assembled inside `OnyxData`; the weekly report's shot fixture is in the
    /// app module and cannot reach an internal memberwise init.
    public init(
        name: String, weightKg: Double, reps: Double, axes: [PrAxis],
        volumeKg: Double? = nil, e1rmKg: Double? = nil
    ) {
        self.name = name; self.weightKg = weightKg; self.reps = reps
        self.axes = axes; self.volumeKg = volumeKg; self.e1rmKg = e1rmKg
    }
}

public struct ExportSession: Codable, Equatable, Sendable {
    public var date: String
    public var startedAt: String?
    public var endedAt: String?
    public var sessionNumber: Double?
    public var label: String
    public var volumeKg: Double?
    public var setCount: Double?
    public var failureSets: Double?
    public var durationMin: Double?
    public var avgBpm: Double?
    public var caloriesBurned: Double?
    public var caloriesEstimated: Bool?
    public var avgBpmEstimated: Bool?
    public var sessionRpe: Double?
    /// Where the order of `exercises` came from — `"index"` when every movement
    /// carried `workout_sets.exercise_order`, `"logged"` when at least one did
    /// not and the list falls back to first-appearance in logged order. The
    /// renderer marks the fallback rather than presenting a guess as a record.
    public var orderSource: String?
    public var exercises: [ExportExercise]
    public var prs: [ExportPr]
}

public struct ExportFatigue: Codable, Equatable, Sendable {
    public var date: String
    public var slot: String
    public var level: Double
    public var label: String
}

/// One `stress_logs` row — one self-reported stress event.
///
/// Not a second fatigue scale: `ExportFatigue` asks what the BODY could do and
/// this asks what is on the mind, and the two answer differently on the same
/// day. See `Recovery/PsychStress.swift`, which owns the vocabulary.
public struct ExportStress: Codable, Equatable, Sendable {
    public var date: String
    /// `morning` / `midday` / `evening`, derived from the event's time, never chosen.
    public var slot: String
    /// `HH:mm` of the event in the user's own zone. Nil on a row written
    /// before stress was an event log; the document prints the slot instead.
    public var time: String?
    public var level: Double
    /// `PsychStress.levels`' own word — the number alone is not readable and
    /// the word alone cannot be compared.
    public var label: String
    /// Report-only: nothing scores a tag, and a reading with none is complete.
    public var tags: [String]?
    public var note: String?
}

public struct ExportDoms: Codable, Equatable, Sendable {
    public var date: String
    public var muscle: String
    public var severity: Double
    public var sourceLabel: String?
    public var sourceDate: String?
    /// Which side, and which part of the muscle. Both optional and both absent
    /// on every row written before 2026-09-12 — which is why the token for a
    /// whole-muscle bilateral rating is byte-identical to the one v1 produced.
    public var side: String?
    public var subRegion: String?
}

/// One joint or connective-tissue complaint. Binary: the row IS the flag.
///
/// Rides in the DAYS row beside `doms` rather than in a section of its own,
/// because it is a per-day list of short tokens and that is exactly what
/// `fatigue`, `doms` and `tags` already are. A section would need a parser.
public struct ExportJoint: Codable, Equatable, Sendable {
    public var date: String
    public var joint: String
    public var side: String?
    /// The wearer's own words. Sanitised at the render boundary — see `phrase`.
    public var note: String?
}

public struct ExportBodyComp: Codable, Equatable, Sendable {
    public var date: String
    public var weightKg: Double?
    public var bmi: Double?
    public var bodyFatPct: Double?
    public var musclePercent: Double?
    public var waterPercent: Double?
    public var visceralFat: Double?
    public var bmr: Double?
    public var boneMineral: Double?
    public var muscleMassKg: Double?
    public var fatFreeMassKg: Double?
    public var fatMassKg: Double?
    public var proteinMassKg: Double?
    public var boneMineralKg: Double?
    public var waterMassKg: Double?
    public var proteinPercent: Double?
    public var skeletalMuscleMassKg: Double?
    public var estimatedWaistToHipRatio: Double?
    /// THE ONE TAPE MEASUREMENT — `daily_logs.waist_cm`, entered in the InBody
    /// sheet beside the weight it was taken with (`v30.waistCm`, W3).
    ///
    /// It is NOT the waist-to-hip ratio and nothing derives one from the other:
    /// there is no hip measurement. `Body/Composition.swift` states the rule —
    /// the waist is stored and shown, and the arithmetic never reads it.
    public var waistCm: Double?
    /// Why the scan is not believed, in words — `bone 0.14 kg from the 14-day
    /// median`. The row is still PRINTED; it is excluded from every mean and
    /// from the trailing-four window. Nil is a valid scan.
    public var anomaly: String?
}

public struct VolumeByMuscle: Codable, Equatable, Sendable {
    public var muscle: String
    public var sets: Double
    public var target: Double
    public var directSets: Double?
    public var indirectSets: Double?
}

public struct TonnageByMuscle: Codable, Equatable, Sendable {
    public var muscle: String
    public var volumeKg: Double
    public var directKg: Double?
}

/// The six figures the week-over-week block compares.
public struct TrendTotals: Codable, Equatable, Sendable {
    public var avgKcal: Double?
    public var totalVolumeKg: Double?
    public var avgSteps: Double?
    public var cardioMinutes: Double?
    public var avgWaterMl: Double?
    public var avgWeightKg: Double?
}

public struct LedgerWeek: Codable, Equatable, Sendable {
    public var label: String
    public var weekStart: String
    public var totals: TrendTotals
}

public struct WeeklyExportInput: Codable, Equatable, Sendable {
    public var weekStart: String
    public var weekEnd: String
    public var weekLabel: String?
    public var programLabel: String
    public var calorieGoal: Double?
    public var proteinGoalG: Double?
    public var stepsGoal: Double?
    public var sleepGoalHours: Double?
    public var waterGoalMl: Double?
    public var phaseLabel: String?
    public var targetPeriods: [TargetPeriod]?
    public var days: [ExportDay]
    public var sessions: [ExportSession]
    public var volumeByMuscle: [VolumeByMuscle]
    public var tonnageByMuscle: [TonnageByMuscle]?
    public var doms: [ExportDoms]
    /// Flagged joints. Optional: a payload built before v2 simply has none.
    public var joints: [ExportJoint]?
    public var fatigue: [ExportFatigue]?
    /// Self-reported psychological stress — the stress log. Optional: a payload
    /// built by a surface that does not write `stress_logs` simply has none,
    /// and the day says `no data` rather than claiming a calm week.
    public var stress: [ExportStress]?
    public var bodyComp: [ExportBodyComp]?
    public var cardio: [ExportCardio]?
    public var supplementProtocol: [ExportSupplement]?
    public var ledger: [LedgerWeek]?
    /// The maintenance anchor every rung of the ladder is a step away from.
    /// Printed on the lever line so a target can be read as a deficit rather
    /// than as a bare number.
    public var leverBaselineKcal: Double?
    /// Everything the BUILDER corrected or refused on the way out, one clause
    /// each — a duplicate bout dropped, a sleep duration rebuilt from stages,
    /// a session whose stamps disagreed. The renderer adds what IT can see
    /// (doubted micros, flagged HRV, anomalous scans) and prints both under
    /// `## 7 · ANOMALIES`, which is the only place the document admits to
    /// having changed anything.
    public var anomalies: [String]?
    /// Free text the athlete keeps against the protocol, at most three lines.
    public var protocolNotes: [String]?
}
