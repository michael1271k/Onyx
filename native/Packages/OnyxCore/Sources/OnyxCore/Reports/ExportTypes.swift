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
    /// A label import's ingredients the nutrient table has no key for
    /// (`custom_supplements.other_ingredients`, overhaul C3 → W5.3) — kept by
    /// name so the stack is described whole. Nil for a hand-added item.
    public var otherIngredients: [String]?
}

public struct SupplementLogEntry: Codable, Equatable, Sendable {
    public var key: String
    public var time: String?
    /// The dose in force ON THAT DAY (`Supplements.doseAt`), not the dose on
    /// the row today. Nil on a payload built before 7.13.0.
    public var dose: String?
}

/// A dose that changed on the day it is filed under — the day the NEW dose
/// started. `from` is what was taken until the day before.
public struct ExportDoseChange: Codable, Equatable, Sendable {
    public var name: String
    public var from: String
    public var to: String

    public init(name: String, from: String, to: String) {
        self.name = name; self.from = from; self.to = to
    }
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
    /// Minutes of the night window the watch was off the wrist (W6) — the
    /// battery input `wrist_coverage` holds. Absent unless measured.
    public var offWristMin: Double?
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
    /// Doses that changed on this day. Absent on every day nothing changed.
    public var supplementDoseChanges: [ExportDoseChange]?
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
    /// The night's SLEEP LATENCY in minutes — bed to first asleep sample
    /// (`sleep_sessions.onset_time − start_time`). Nil on a night written
    /// before v31 and on one the watch never sampled an onset for.
    public var sleepOnsetMin: Double?
    /// `sleep_sessions.awakenings` — merged awake intervals of five minutes or
    /// more, counted AFTER onset.
    public var awakenings: Double?
    /// Whether `hrvMs` is the mean of the samples inside the night's BED
    /// WINDOW, or the calendar day's mean.
    ///
    /// ── THE TWO ARE NOT COMPARABLE, AND THE COLUMN HELD BOTH ────────────────
    /// Overnight SDNN runs far above the waking figure — on this athlete ~100 ms
    /// against ~60 — so a week in which the night resolved on Thursday and not
    /// on Wednesday put two different measurements in one column, and
    /// `VitalsGate.hrvArtifact` judged the overnight reading against a median
    /// of daytime ones and called the good night an artifact. Carried so the
    /// document can say which reading it is holding.
    public var hrvOvernight: Bool?
    /// When the row carrying this HRV was last written — `daily_logs.updated_at`
    /// in the athlete's own zone. Printed beside a FLAGGED reading only: a
    /// reading the watch filed hours after the night it describes is the first
    /// thing to check, and the stamp is the only evidence of it the document
    /// can carry.
    public var hrvSyncedAt: String?
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
    /// `health` | `import` | `manual`. Optional only so a fixture written
    /// before this field existed still decodes; the builder always supplies it.
    ///
    /// ── WHY `import` HAD TO BECOME ITS OWN WORD ─────────────────────────────
    /// `cardio_logs` has no start column — `created_at` is the only timestamp
    /// it has ever had — and on a row the CURRENT ingest filed it is the bout's
    /// start, by that ingest's own rule. On a row imported before `hk_uuid`
    /// existed it is the instant of the IMPORT, and the two are
    /// indistinguishable by value: a Tuesday walk taken at 18:58 exported as
    /// `from 21:11`, which is when the batch ran. A row Health filed with no
    /// key is therefore `import`, and the document says `imported HH:MM` — the
    /// moment the ledger learned of the bout, which is a fact, rather than a
    /// start it cannot prove.
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
    // `restActualSec` (the mean commit-to-commit gap) was removed in the
    // overhaul (decision Q16): the rest is the plan's, and the ±15 s timer
    // nudges are visual only. A decoder still reading an old payload ignores
    // the key.
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

/// `3 × 8–12 @ 40 kg` — what the athlete is being asked for, never a
/// back-formed average.
///
/// ── TWO SOURCES, AND THE ROW SAYS WHICH ─────────────────────────────────────
/// `source: "prescription"` is a dated instruction from `prescriptions`, the
/// CURRENT version in force on the session's day. `source: "plan"` is
/// `ProgramExercise.wk1Kg` — the July blueprint the program was compiled with,
/// which is what this field carried alone until v6 and why every `load Δ` was
/// drawn against a number nobody had worked to since the block began.
public struct ExportPrescription: Codable, Equatable, Sendable {
    /// Optional since v6: a prescription may state a load and a window and
    /// leave the count to the plan, and a fabricated `3` is a claim.
    public var sets: Double?
    /// The window as it is written: `"8–12"`, `"55s"`. Never parsed on the way
    /// in — a spelling this app cannot read still reaches the document intact.
    public var reps: String?
    public var loadKg: Double?
    /// The ceiling the set was not meant to pass. A set rated ABOVE it is
    /// flagged on its movement's line: the prescription was not followed, and
    /// that is a different finding from a missed rep.
    public var rpeCap: Double?
    /// `STRAIGHT` | `TOPSET_BACKOFF` — `Prescription.Structure`.
    public var structure: String?
    /// Per-set loads, top set first, on a `TOPSET_BACKOFF`. A ladder cannot be
    /// said with one number and an average of it describes a session nobody
    /// performed.
    public var setLoads: [Double]?
    /// `ALTERNATE` | `LEFT` | `RIGHT` | `NONE` — `Prescription.LeadRule`.
    public var leadRule: String?
    public var notes: String?
    /// The day this version came into force, and its ordinal. Printed so the
    /// audit can see that a load moved and when, rather than only that it is
    /// where it is.
    public var effectiveFrom: String?
    public var version: Double?
    /// `prescription` | `plan`.
    public var source: String?

    public init(
        sets: Double? = nil, reps: String? = nil, loadKg: Double? = nil, rpeCap: Double? = nil,
        structure: String? = nil, setLoads: [Double]? = nil, leadRule: String? = nil,
        notes: String? = nil, effectiveFrom: String? = nil, version: Double? = nil,
        source: String? = nil
    ) {
        self.sets = sets; self.reps = reps; self.loadKg = loadKg; self.rpeCap = rpeCap
        self.structure = structure; self.setLoads = setLoads; self.leadRule = leadRule
        self.notes = notes; self.effectiveFrom = effectiveFrom; self.version = version
        self.source = source
    }

    /// The load a comparison is drawn against — the TOP SET on a ladder, which
    /// is the load the session is built around. Comparing the day's heaviest
    /// set to a back-off would report progress for doing less.
    public var referenceLoadKg: Double? {
        if structure == Prescription.Structure.topsetBackoff.rawValue, let first = setLoads?.first { return first }
        return loadKg
    }
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

/// One night the insomnia tracker names.
///
/// The three qualifying conditions are ORed and each is a different complaint:
/// a long latency is trouble getting to sleep, a long awake total is trouble
/// staying there, and the tag is the athlete saying so regardless of what the
/// watch measured. A night can meet more than one.
public struct ExportInsomniaNight: Codable, Equatable, Sendable {
    public var date: String
    /// The wall clock the athlete actually fell asleep at.
    public var onsetLocal: String?
    /// Minutes from getting into bed to the first asleep sample.
    public var onsetMin: Double?
    public var awakeMin: Double?
    public var durationMin: Double?
    /// `daily_logs.sleep_onset_trouble` — ticked by hand.
    public var tag: Bool

    public init(date: String, onsetLocal: String? = nil, onsetMin: Double? = nil,
                awakeMin: Double? = nil, durationMin: Double? = nil, tag: Bool = false) {
        self.date = date; self.onsetLocal = onsetLocal; self.onsetMin = onsetMin
        self.awakeMin = awakeMin; self.durationMin = durationMin; self.tag = tag
    }
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
    /// Every night in the TRAILING EIGHT WEEKS that met one of the insomnia
    /// conditions, oldest first — the exported week included.
    ///
    /// The window and not the week, because the running count is the finding:
    /// two bad nights is a fortnight, two bad nights every week for eight is a
    /// pattern, and the rows are the same rows either way. The renderer prints
    /// the ones inside the week in full and counts the rest, so the count
    /// cannot disagree with the list it was taken over.
    public var insomnia: [ExportInsomniaNight]?
}
