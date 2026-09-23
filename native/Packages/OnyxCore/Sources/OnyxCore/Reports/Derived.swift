import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// DERIVED METRICS — the arithmetic, kept behind a wall. A port of
// the web app's `lib/reports/derived.ts`.
//
// Every input is a figure already printed in the raw body; nothing is invented
// to fill a gap (a metric with no evidence is nil); it is pure and
// deterministic. It computes; it does not advise.
// ─────────────────────────────────────────────────────────────────────────────

public struct WeekDelta: Codable, Equatable, Sendable {
    public var label: String
    public var unit: String
    public var current: Double?
    public var previous: Double?
    /// Absolute change. Nil when either side is missing — not 0.
    public var delta: Double?
    /// Percentage change. Nil when the previous value is missing OR zero.
    public var pct: Double?
    public var digits: Int
    /// Print at FULL precision instead (tonnage).
    public var exact: Bool
}

public struct QualityTally: Codable, Equatable, Sendable {
    public var key: String
    public var label: String
    public var count: Int
}

public struct ExerciseProgression: Codable, Equatable, Sendable {
    public var name: String
    public var firstKg: Double
    public var lastKg: Double
    public var deltaKg: Double
    public var sessions: Int
}

/// One day's battery v9 inputs, exactly as the scorer read them — `BatteryDay`.
public struct BatteryDay: Codable, Equatable, Sendable {
    public var date: String
    public var weekdayLabel: String
    /// `daily_scores.battery_pct`. Nil when the app never scored the day.
    public var appPct: Double?
    public var morningCharge: Double
    public var ratio: Double
    public var stagesQ: Double
    public var hrvQ: Double
    public var rhrQ: Double
    public var hrvZ: Double?
    public var rhrZ: Double?
    public var acwr: Double?
    public var monotony: Double?
    public var strain: Double?
    public var strainZ: Double?
    public var loadDrain: Double
    /// The Hooper-style index, 0...1. Nil when nothing was answered.
    public var wellness: Double?
    public var wellnessDrain: Double
    /// The latest fatigue reading's word, or nil when none was logged.
    public var fatigueLabel: String?
    /// Mean DOMS severity of the day's rows, 0...3. Nil when none was logged.
    public var soreness: Double?
    /// Nil when the question was never asked.
    public var onsetTrouble: Bool?
}

public struct DerivedWeek: Codable, Equatable, Sendable {
    public var deltas: [WeekDelta]
    public var battery: [BatteryDay]
    public var meanWorkingSetRpe: Double?
    public var ratedSets: Int
    public var workingSets: Int
    public var meanSetsPerSession: Double?
    public var meanVolumePerSessionKg: Double?
    public var failureSetShare: Double?
    public var quality: [QualityTally]
    public var flaggedSets: Int
    public var supplementsTaken: Double?
    public var supplementsPlanned: Double?
    public var fatigueReadings: Int
    public var fatigueSlots: Int
    public var domsDaysLogged: Int
    public var intakeDaysLogged: Int
    public var weighInDays: Int
    public var meanDeepPct: Double?
    public var meanRemPct: Double?
    public var meanAwakeMin: Double?
    public var progression: [ExerciseProgression]
    public var trainingDayKcal: Double?
    public var restDayKcal: Double?
}

/// Mean of the values that EXIST. Nil when none do — never 0.
func meanOf(_ xs: [Double?]) -> Double? {
    let ok = xs.compactMap { $0 }.filter(\.isFinite)
    return ok.isEmpty ? nil : ok.reduce(0, +) / Double(ok.count)
}

/// Sum of the values that exist. Nil when none do.
func sumOf(_ xs: [Double?]) -> Double? {
    let ok = xs.compactMap { $0 }.filter(\.isFinite)
    return ok.isEmpty ? nil : ok.reduce(0, +)
}

public enum Derived {
    /// The most recent EARLIER week in the ledger, anchored on the week's own start date.
    static func previousWeek(_ ledger: [LedgerWeek]?, weekStart: String) -> LedgerWeek? {
        guard let ledger, !ledger.isEmpty else { return nil }
        let earlier = ledger.filter { $0.weekStart < weekStart }
        guard let first = earlier.first else { return nil }
        return earlier.dropFirst().reduce(first) { $1.weekStart > $0.weekStart ? $1 : $0 }
    }

    static func deltaOf(_ label: String, _ unit: String, _ digits: Int, _ current: Double?, _ previous: Double?, exact: Bool = false) -> WeekDelta {
        let both = current?.isFinite == true && previous?.isFinite == true
        let c = current ?? 0, p = previous ?? 0
        return WeekDelta(
            label: label, unit: unit, current: current, previous: previous,
            delta: both ? c - p : nil,
            pct: both && p != 0 ? ((c - p) / abs(p)) * 100 : nil,
            digits: digits, exact: exact
        )
    }

    /// Top-set movement for the movements trained MORE THAN ONCE this week.
    static func progressionWithin(_ sessions: [ExportSession]) -> [ExerciseProgression] {
        var order: [String] = []
        var byName: [String: [(date: String, topKg: Double)]] = [:]
        for s in sessions {
            for e in s.exercises {
                let working = e.sets.filter { !$0.isWarmup && !$0.isGhost }
                guard let top = working.map(\.weightKg).max(), top.isFinite, top > 0 else { continue }
                if byName[e.name] == nil { order.append(e.name) }
                byName[e.name, default: []].append((s.date, top))
            }
        }
        var out: [ExerciseProgression] = []
        for name in order {
            let rows = byName[name]!
            if rows.count < 2 { continue }
            let sorted = rows.sorted { icuCompare($0.date, $1.date) < 0 }
            let firstKg = sorted[0].topKg, lastKg = sorted[sorted.count - 1].topKg
            out.append(ExerciseProgression(name: name, firstKg: firstKg, lastKg: lastKg, deltaKg: lastKg - firstKg, sessions: sorted.count))
        }
        return out.sorted { a, b in
            let da = abs(a.deltaKg), db = abs(b.deltaKg)
            if da != db { return da > db }
            return icuCompare(a.name, b.name) < 0
        }
    }

    /// `batteryDays` — the LATEST fatigue slot wins, by its position in the
    /// day. Soreness is the mean of the day's DOMS rows, zeros included.
    static func batteryDays(_ input: WeeklyExportInput) -> [BatteryDay] {
        func slotIndex(_ label: String) -> Int { FatigueSlot.allCases.firstIndex { $0.label == label } ?? -1 }
        return input.days.map { d in
            var latest: ExportFatigue?
            for f in (input.fatigue ?? []) where f.date == d.date {
                if latest == nil || slotIndex(f.slot) > slotIndex(latest!.slot) { latest = f }
            }
            // One number per RECOGNISED muscle — the max across its sides and
            // sub-regions — then the mean of those. It has to be the fold the
            // scorer applies (`DomsMuscles` / `foldDomsSeverity`), or the
            // export's recomputed battery would disagree with the stored one on
            // any day carrying a left/right pair.
            let soreness = Self.foldDomsSeverity(input.doms.filter { $0.date == d.date })
            let r = d.readiness
            let onsetTrouble: Bool? = d.sleepOnsetTrouble.map { $0 == true }
            let signals = ScoringInputs(
                sleepHours: (d.sleepMin ?? 0) / 60, deepMinutes: d.deepMin ?? 0, remMinutes: d.remMin ?? 0,
                sleepGoalHours: input.sleepGoalHours ?? 8,
                hrvZ: r?.hrvZ, rhrZ: r?.rhrZ, acwr: r?.acwr, strainZ: r?.strainZ,
                domsSeverity: soreness, sleepOnsetTrouble: onsetTrouble,
                fatigueLevel: latest?.level,
                // The scorer's off-wrist fact (W6), or this recompute and the
                // stored battery disagree on every night the watch never saw.
                offWristMin: d.offWristMin
            )
            let q = Battery.sleepQualityParts(signals)
            let load = Battery.loadParts(signals)
            let wellness = Battery.wellnessParts(signals)
            return BatteryDay(
                date: d.date, weekdayLabel: d.weekdayLabel,
                appPct: d.batteryPct,
                morningCharge: Battery.computeMorningCharge(sleepQuality: q.quality),
                ratio: q.ratio, stagesQ: q.stagesQ, hrvQ: q.hrvQ, rhrQ: q.rhrQ,
                hrvZ: r?.hrvZ, rhrZ: r?.rhrZ,
                acwr: r?.acwr, monotony: r?.monotony, strain: r?.strain, strainZ: r?.strainZ,
                loadDrain: load.drain,
                wellness: wellness.index, wellnessDrain: wellness.drain,
                fatigueLabel: latest.map { Fatigue.level(Int($0.level))?.label ?? jsIntegerString($0.level) },
                soreness: soreness,
                onsetTrouble: onsetTrouble
            )
        }
    }

    static func intakeOn(_ days: [ExportDay], training: Bool) -> Double? {
        meanOf(days.filter { $0.isTrainingDay == training }.map(\.calories))
    }

    public static func week(_ input: WeeklyExportInput) -> DerivedWeek {
        let days = input.days
        let sessions = input.sessions
        let p = previousWeek(input.ledger, weekStart: input.weekStart)?.totals

        let totalVolume = sumOf(sessions.map(\.volumeKg))
        let deltas = [
            deltaOf("Total volume", "kg", 2, totalVolume, p?.totalVolumeKg, exact: true),
            deltaOf("Intake (avg/day)", "kcal", 0, meanOf(days.map(\.calories)), p?.avgKcal),
            deltaOf("Steps (avg/day)", "steps", 0, meanOf(days.map(\.steps)), p?.avgSteps),
            deltaOf("Bodyweight (avg)", "kg", 2, meanOf(days.map(\.weightKg)), p?.avgWeightKg),
            deltaOf("Water (avg/day)", "ml", 0, meanOf(days.map(\.waterMl)), p?.avgWaterMl),
            deltaOf("Cardio", "min", 0, sumOf((input.cardio ?? []).map(\.durationMin)), p?.cardioMinutes),
        ]

        var rpes: [Double] = []
        var workingSets = 0, failureSets = 0, flaggedSets = 0
        var qualityOrder: [String] = []
        var qualityCount: [String: Int] = [:]
        for s in sessions {
            for e in s.exercises {
                for set in e.sets {
                    if set.isWarmup || set.isGhost { continue }
                    workingSets += 1
                    if let r = set.rpe, r.isFinite { rpes.append(r) }
                    if set.failure { failureSets += 1 }
                    if let q = set.quality, !q.isEmpty {
                        flaggedSets += 1
                        if qualityCount[q] == nil { qualityOrder.append(q) }
                        qualityCount[q, default: 0] += 1
                    }
                }
            }
        }
        let quality = qualityOrder
            .map { QualityTally(key: $0, label: SetTags.quality[$0]?.label ?? $0, count: qualityCount[$0]!) }
            .sorted { a, b in a.count != b.count ? a.count > b.count : icuCompare(a.key, b.key) < 0 }

        var deepPcts: [Double] = [], remPcts: [Double] = []
        for d in days {
            guard let sleep = d.sleepMin, sleep > 0 else { continue }
            if let deep = d.deepMin { deepPcts.append((deep / sleep) * 100) }
            if let rem = d.remMin { remPcts.append((rem / sleep) * 100) }
        }

        return DerivedWeek(
            deltas: deltas,
            battery: batteryDays(input),
            meanWorkingSetRpe: meanOf(rpes),
            ratedSets: rpes.count,
            workingSets: workingSets,
            meanSetsPerSession: sessions.isEmpty ? nil : Double(workingSets) / Double(sessions.count),
            meanVolumePerSessionKg: !sessions.isEmpty && totalVolume != nil ? totalVolume! / Double(sessions.count) : nil,
            failureSetShare: workingSets > 0 ? (Double(failureSets) / Double(workingSets)) * 100 : nil,
            quality: quality,
            flaggedSets: flaggedSets,
            supplementsTaken: sumOf(days.map(\.supplementsTaken)),
            supplementsPlanned: sumOf(days.map(\.supplementsPlanned)),
            fatigueReadings: (input.fatigue ?? []).count,
            fatigueSlots: days.count * 3,
            domsDaysLogged: Set(input.doms.map(\.date)).count,
            intakeDaysLogged: days.filter { $0.calories != nil }.count,
            weighInDays: days.filter { $0.weightKg != nil }.count,
            meanDeepPct: meanOf(deepPcts),
            meanRemPct: meanOf(remPcts),
            meanAwakeMin: meanOf(days.map(\.awakeMin)),
            progression: progressionWithin(sessions),
            trainingDayKcal: intakeOn(days, training: true),
            restDayKcal: intakeOn(days, training: false)
        )
    }

    /// Mean severity over DISTINCT RECOGNISED muscles, max within each.
    ///
    /// The same fold `ScoringInputsBuilder` and the web app's `lib/recovery/soreness.ts`
    /// apply. Max rather than mean within a muscle: "left quad severe, right
    /// quad fine" is a severe quad, and averaging it reports a day nobody had.
    static func foldDomsSeverity(_ rows: [ExportDoms]) -> Double? {
        var peak: [String: Double] = [:]
        for row in rows where DomsMuscles.recognised.contains(row.muscle) {
            peak[row.muscle] = Swift.max(peak[row.muscle] ?? 0, row.severity)
        }
        guard !peak.isEmpty else { return nil }
        return peak.values.reduce(0, +) / Double(peak.count)
    }
}

/// `String.prototype.localeCompare` as the web's ICU root collation orders the
/// strings this domain sorts: whitespace before punctuation before digits
/// before letters, letters compared case-insensitively first and lower-case
/// first on a tie. An approximation of ICU, sufficient for exercise names,
/// clock times and snake_case keys; anything exotic would need real ICU.
func icuCompare(_ a: String, _ b: String) -> Int {
    func cls(_ c: Character) -> (Int, String) {
        if c.isWhitespace { return (0, String(c)) }
        if c.isNumber { return (2, String(c)) }
        if c.isLetter { return (3, c.lowercased()) }
        return (1, String(c))
    }
    let ka = a.map(cls), kb = b.map(cls)
    for (x, y) in zip(ka, kb) where x != y {
        if x.0 != y.0 { return x.0 < y.0 ? -1 : 1 }
        return x.1 < y.1 ? -1 : 1
    }
    if ka.count != kb.count { return ka.count < kb.count ? -1 : 1 }
    // Tertiary: same letters, different case — lower-case first.
    for (x, y) in zip(a, b) where x != y {
        return x.isLowercase ? -1 : 1
    }
    return 0

}
