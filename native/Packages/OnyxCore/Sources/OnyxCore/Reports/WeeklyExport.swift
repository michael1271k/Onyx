import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// "Export Week" — one training week as DRY DATA, for a coaching audit to read.
//
// EXPORT v5, THE DOCUMENT. Seven fixed sections, in this order, and nothing
// else between them:
//
//   1 · WEEK              the cover — dates, phase, the lever and its targets
//   2 · WEEK AGGREGATES   every weekly mean, one labelled row per domain
//   3 · BODY COMPOSITION  one row per scan, then T4WM and the clean means
//   4 · DAILY ROWS        one line per day
//   5 · SESSIONS          one block per session, in performed order
//   6 · SETS BY MUSCLE    direct, indirect, total, target, status
//   7 · ANOMALIES         everything the document corrected on the way out
//
// THE READER IS A MODEL, NOT A PERSON. v4 was written day-major for someone
// pasting a week into a chat window, and it explained itself as it went: a
// legend, four standing notes, a `Not recorded:` line under every day, a gap
// named in words. All of that is gone. The audit writes the prose; this supplies
// the numbers, and every field has to earn the tokens it costs.
//
// A FIELD WITH NOTHING BEHIND IT PRINTS NOTHING. Not a dash, not a zero, not
// "no data" — the key simply does not appear. The exception is the handful the
// schema marks required, where the absence IS the finding: the date range, the
// week's water, the steps floor and ceiling, `nights_deep_ge_60`, the flagged
// HRV days, the PR list, the cardio totals and the fatigue trace.
//
// NO SCORE AND NO BATTERY, anywhere. Both are this app's opinion of the week,
// and a number the reader cannot recompute from the rows beside it is one it has
// to either trust or ignore. `ReportsGoldenTests.grammarHolds` bans the words.
//
// Deterministic and pure. `setDetail`, `nutrientLine`, `sparkline` and
// `markdownTable` are older renderers the golden vectors still pin; `summary`,
// `trendTotals` and `energyBalance` are aggregates other surfaces read. The
// document itself uses `markdownTable` for its three tables and nothing else.
// ─────────────────────────────────────────────────────────────────────────────

public struct WeeklySummary: Codable, Equatable, Sendable {
    public struct PeakDoms: Codable, Equatable, Sendable { public var muscle: String; public var severity: Double; public var date: String }
    public var avgSleepMin: Double?
    public var avgRestingHr: Double?
    public var avgHrvMs: Double?
    public var cardioMinutes: Double?
    public var cardioActiveKcal: Double?
    public var cardioSessions: Int
    public var peakDoms: PeakDoms?
    public var avgSessionRpe: Double?
    public var ratedSessions: Int
    public var ratedSets: Int
    public var workingSets: Int
}

public struct EnergyBalance: Codable, Equatable, Sendable {
    public var daysCounted: Int
    public var intakeKcal: Double?
    public var expenditureKcal: Double?
    public var balanceKcal: Double?
    public var avgBalanceKcal: Double?
    public var avgBmrKcal: Double?
    public var avgActiveKcal: Double?
    public var avgTefKcal: Double?
    public var bmrCarried: Bool
    public var countedDates: [String]
}

public enum WeeklyExport {
    static let dash = "—"

    /// `v.toFixed(digits)`, or `—`.
    static func n(_ v: Double?, _ digits: Int = 0) -> String {
        guard let v, v.isFinite else { return dash }
        return jsToFixed(v, digits)
    }

    /// A number at FULL precision, snapped at 1e-6 against float noise.
    static func exact(_ v: Double?) -> String {
        guard let v, v.isFinite else { return dash }
        return jsIntegerString(jsRound(v * 1e6) / 1e6)
    }

    static func js(_ v: Double) -> String { jsIntegerString(v) }

    static func pad2(_ s: String) -> String { var t = s; while t.count < 2 { t = "0" + t }; return t }

    /// en-GB short month names as Node prints them ("Sept", not "Sep"). The
    /// document itself is all-ISO; `Format.dayAndMonth` is the one reader left.
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec"]

    static func month(_ iso: String) -> String {
        guard iso.count >= 7, let m = Int(iso.dropFirst(5).prefix(2)), (1...12).contains(m) else { return "" }
        return months[m - 1]
    }

    static func cardioLabel(_ kind: String) -> String {
        kind.isEmpty ? "Cardio" : kind.prefix(1).uppercased() + kind.dropFirst()
    }

    public static let fatigueSlotLabels = ["Waking", "Midday", "Before training", "After training", "Night"]
    public static let fatigueLabelsTraining = ["Waking", "Before training", "After training"]
    public static let fatigueLabelsRest = ["Waking", "Midday", "Night"]

    public static func fatigueLabels(isTrainingDay: Bool) -> [String] {
        isTrainingDay ? fatigueLabelsTraining : fatigueLabelsRest
    }

    private static let clockPattern = try! NSRegularExpression(pattern: #"T(\d{2}:\d{2})"#)

    /// "21:27" from a timestamp, in the log's own local wall clock. (The web
    /// falls back to a local-time `Date` parse for non-ISO strings; nothing
    /// this app stores is non-ISO, so that branch reads `—` here.)
    static func clock(_ ts: String?) -> String {
        guard let ts, !ts.isEmpty else { return dash }
        let ns = ts as NSString
        guard let m = clockPattern.firstMatch(in: ts, range: NSRange(location: 0, length: ns.length)) else { return dash }
        return ns.substring(with: m.range(at: 1))
    }

    // MARK: - Nutrients

    static let implausibleFloorMultiple = 2.5

    static func implausible(_ t: NutrientTarget, food: Double, stack: Double) -> Bool {
        if t.kind == .ceiling { return false }
        if stack > 0 { return false }
        return t.target > 0 && food > t.target * implausibleFloorMultiple
    }

    /// One micronutrient line: every target every day, provenance split only when both sides are non-zero.
    public static func nutrientLine(food: [String: Double]?, stack: [String: Double]?) -> String {
        NutrientTargets.all.map { t -> String in
            let f = food?[t.key], k = stack?[t.key]
            let hasF = f.map { $0.isFinite && $0 > 0 } ?? false
            let hasK = k.map { $0.isFinite && $0 > 0 } ?? false
            let total = (hasF ? f! : 0) + (hasK ? k! : 0)
            let tags = [t.kind == .ceiling ? "ceiling" : nil, t.fromStack && !hasF ? "stack" : nil].compactMap { $0 }.joined(separator: ", ")
            let suffix = tags.isEmpty ? "" : " (\(tags))"
            if !hasF && !hasK { return "\(t.label): \(dash)/\(exact(t.target)) \(t.unit)\(suffix)" }
            let split = hasF && hasK ? " (\(exact(f)) food + \(exact(k)) stack)" : ""
            let flag = implausible(t, food: hasF ? f! : 0, stack: hasK ? k! : 0) ? "⚠ " : ""
            return "\(t.label): \(flag)\(exact(total))/\(exact(t.target)) \(t.unit)\(suffix)\(split)"
        }.joined(separator: " · ")
    }

    /// Every "<Micro> <value> <unit> on <date>" the week flagged.
    public static func flaggedNutrients(_ days: [ExportDay]) -> [String] {
        var out: [String] = []
        for d in days {
            for t in NutrientTargets.all {
                let food = d.nutrientsFood?[t.key].map { $0 > 0 ? $0 : 0 } ?? 0
                let stack = d.nutrientsStack?[t.key].map { $0 > 0 ? $0 : 0 } ?? 0
                if implausible(t, food: food, stack: stack) { out.append("\(t.label) \(exact(food)) \(t.unit) on \(d.date)") }
            }
        }
        return out
    }

    // MARK: - Sets

    /// "RPE 8.5 — Hard".
    static func rpeText(_ rpe: Double) -> String { "RPE \(js(rpe)) — \(Effort.rpeLabel(rpe))" }

    /// One display row: a bilateral set, or the two halves of a unilateral one.
    struct SetRow { var left: ExportSet?; var right: ExportSet?; var single: ExportSet? }

    /// Group an exercise's rows for display, deciding PER SET.
    static func toSetRows(_ sets: [ExportSet]) -> [SetRow] {
        var rows: [SetRow] = []
        var byPair: [String: Int] = [:]
        for s in sets {
            if let p = s.pairId, !p.isEmpty {
                let idx: Int
                if let i = byPair[p] { idx = i } else { rows.append(SetRow()); idx = rows.count - 1; byPair[p] = idx }
                if s.side == "R" { rows[idx].right = s } else { rows[idx].left = s }
                continue
            }
            rows.append(SetRow(single: s))
        }
        return rows
    }

    /// Render one exercise's sets — ONE LINE PER SET.
    public static func setDetail(_ sets: [ExportSet], exerciseName: String? = nil) -> [String] {
        if sets.isEmpty { return [dash] }
        let anyRated = sets.contains { !$0.isWarmup && !$0.isGhost && $0.rpe != nil }
        let noneRated = !anyRated && sets.contains { !$0.isWarmup && !$0.isGhost }
        let notReported = "RPE not reported"
        let timed = TimedExercise.isTimed(exerciseName)

        func value(_ w: Double, _ reps: Double) -> String {
            timed ? "\(js(reps)) sec" : SetFormat.isUnloaded(w) ? "\(js(reps)) reps" : "\(js(w)) kg × \(js(reps))"
        }
        func notes(_ s: ExportSet) -> String {
            var bits: [String] = []
            if let r = s.rpe { bits.append(rpeText(r)) }
            else if anyRated && !s.isWarmup && !s.isGhost { bits.append(notReported) }
            if s.isWarmup { bits.append("warm-up") }
            else if s.failure && Effort.rpeLabel(s.rpe).lowercased() != "failure" { bits.append("to failure") }
            if s.dropset == true { bits.append("drop set") }
            if let q = s.quality, let quality = SetTags.quality[q] { bits.append("Set Quality: \(quality.label)") }
            return bits.isEmpty ? "" : " (\(bits.joined(separator: ", ")))"
        }

        var num = 0
        var lines: [String] = []
        for row in toSetRows(sets) {
            if let s = row.single {
                if s.isGhost { lines.append("Skipped: \(value(s.weightKg, s.reps)) (planned)"); continue }
                if s.isWarmup { lines.append("Warm-up: \(value(s.weightKg, s.reps))\(notes(s))"); continue }
                num += 1
                lines.append("Set \(num): \(value(s.weightKg, s.reps))\(notes(s))")
                continue
            }
            let halves = [
                row.left.map { "L \(value($0.weightKg, $0.reps))\(notes($0))" },
                row.right.map { "R \(value($0.weightKg, $0.reps))\(notes($0))" },
            ].compactMap { $0 }
            let lead = row.left ?? row.right
            if lead?.isGhost == true { lines.append("Skipped: \(halves.joined(separator: " · ")) (planned)"); continue }
            if lead?.isWarmup == true { lines.append("Warm-up: \(halves.joined(separator: " · "))"); continue }
            num += 1
            lines.append("Set \(num): \(halves.joined(separator: " · "))")
        }
        return noneRated ? lines + ["_(\(notReported) for any working set)_"] : lines
    }

    // MARK: - Aggregates

    public static func summary(_ input: WeeklyExportInput) -> WeeklySummary {
        let cardio = input.cardio ?? []
        var peak: WeeklySummary.PeakDoms?
        for d in input.doms where d.severity > 0 {
            if peak == nil || d.severity > peak!.severity { peak = .init(muscle: d.muscle, severity: d.severity, date: d.date) }
        }
        let rated = input.sessions.filter { $0.sessionRpe?.isFinite == true }
        // A UNILATERAL PAIR IS ONE SET HERE, as it is everywhere else — the
        // same `toSetRows` the token and prose renderers share, so the fourth
        // caller agrees by construction. A pair counts as RATED when EITHER
        // side carries a rating: the set was rated even if only one arm's
        // effort was recorded. A ghost is not an unrated working set.
        var ratedSets = 0, workingSets = 0
        for s in input.sessions { for ex in s.exercises { for row in toSetRows(ex.sets) {
            let sides = [row.single, row.left, row.right].compactMap { $0 }
            if sides.isEmpty { continue }
            if sides.contains(where: { $0.isWarmup || $0.isGhost }) { continue }
            workingSets += 1
            if sides.contains(where: { $0.rpe?.isFinite == true }) { ratedSets += 1 }
        } } }
        return WeeklySummary(
            avgSleepMin: meanOf(input.days.map(\.sleepMin)),
            avgRestingHr: meanOf(input.days.map(\.restingHr)),
            avgHrvMs: meanOf(input.days.map(\.hrvMs)),
            cardioMinutes: sumOf(cardio.map(\.durationMin)),
            cardioActiveKcal: sumOf(cardio.map(\.kcal)),
            cardioSessions: cardio.count,
            peakDoms: peak,
            avgSessionRpe: meanOf(rated.map(\.sessionRpe)),
            ratedSessions: rated.count,
            ratedSets: ratedSets,
            workingSets: workingSets
        )
    }

    static let sparkBars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    static let sparkGap = "·"

    /// An eight-level sparkline scaled from ZERO; a missing day is `·`.
    public static func sparkline(_ values: [Double?]) -> String {
        let present = values.compactMap { $0 }.filter(\.isFinite)
        if present.isEmpty { return "" }
        let max = Swift.max(present.max()!, 0)
        return values.map { v -> String in
            guard let v, v.isFinite else { return sparkGap }
            if max <= 0 { return sparkBars[0] }
            let i = Int(jsRound((v / max) * Double(sparkBars.count - 1)))
            return sparkBars[Swift.max(0, Swift.min(sparkBars.count - 1, i))]
        }.joined()
    }

    public static func trendTotals(days: [ExportDay], sessions: [ExportSession], cardio: [ExportCardio] = []) -> TrendTotals {
        TrendTotals(
            avgKcal: meanOf(days.map(\.calories)),
            totalVolumeKg: sumOf(sessions.map(\.volumeKg)),
            avgSteps: meanOf(days.map(\.steps)),
            cardioMinutes: sumOf(cardio.map(\.durationMin)),
            avgWaterMl: meanOf(days.map(\.waterMl)),
            avgWeightKg: meanOf(days.map(\.weightKg))
        )
    }

    /// The week's energy balance — an ESTIMATE. Both sides per day or neither;
    /// BMR carried across gaps forwards then backwards; TEF rides on the intake.
    public static func energyBalance(_ days: [ExportDay]) -> EnergyBalance {
        let empty = EnergyBalance(daysCounted: 0, intakeKcal: nil, expenditureKcal: nil, balanceKcal: nil, avgBalanceKcal: nil, avgBmrKcal: nil, avgActiveKcal: nil, avgTefKcal: nil, bmrCarried: false, countedDates: [])
        let measured: [Double?] = days.map { $0.bmrKcal?.isFinite == true ? $0.bmrKcal : nil }
        // `bmrCarry` is the ONE implementation of the carry; the `## DERIVED
        // tdee` row reads the same array, so the footer cannot disagree.
        let filled = bmrCarry(days)
        var intake = 0.0, burn = 0.0, bmrSum = 0.0, activeSum = 0.0, tefSum = 0.0
        var counted = 0
        var carried = false
        var countedDates: [String] = []
        for (i, d) in days.enumerated() {
            guard let kcal = d.calories, kcal.isFinite, let bmr = filled[i], let active = d.activeKcal, active.isFinite else { continue }
            if measured[i] == nil { carried = true }
            let tef = kcal * Energy.tefFactor
            intake += kcal
            burn += bmr + active + tef
            bmrSum += bmr; activeSum += active; tefSum += tef
            counted += 1
            countedDates.append(d.date)
        }
        if counted == 0 { return empty }
        let c = Double(counted)
        return EnergyBalance(
            daysCounted: counted, intakeKcal: jsRound(intake), expenditureKcal: jsRound(burn), balanceKcal: jsRound(intake - burn),
            avgBalanceKcal: jsRound((intake - burn) / c), avgBmrKcal: jsRound(bmrSum / c), avgActiveKcal: jsRound(activeSum / c),
            avgTefKcal: jsRound(tefSum / c), bmrCarried: carried, countedDates: countedDates
        )
    }

    public enum Align: String, Codable, Sendable { case left, right, center }

    /// A padded markdown table; widths count CODE POINTS.
    public static func markdownTable(header: [String], body: [[String]], align: [Align]) -> [String] {
        let all = [header] + body
        let width = header.indices.map { c in all.map { r in c < r.count ? r[c].unicodeScalars.count : 0 }.max() ?? 0 }
        func pad(_ s: String, _ c: Int) -> String {
            // A cell past the header's width has no column: the web pads it by
            // NaN, which is to say not at all.
            guard c < width.count else { return s }
            let gap = Swift.max(0, width[c] - s.unicodeScalars.count)
            switch align[c] {
            case .left: return s + String(repeating: " ", count: gap)
            case .right: return String(repeating: " ", count: gap) + s
            case .center:
                let left = gap / 2
                return String(repeating: " ", count: left) + s + String(repeating: " ", count: gap - left)
            }
        }
        func line(_ cells: [String]) -> String {
            "| " + cells.indices.map { pad(cells[$0], $0) }.joined(separator: " | ") + " |"
        }
        let rule = "|" + width.indices.map { c -> String in
            let dashes = String(repeating: "-", count: width[c])
            switch align[c] {
            case .left: return ":\(dashes)-"
            case .right: return "-\(dashes):"
            case .center: return ":\(dashes):"
            }
        }.joined(separator: "|") + "|"
        return [line(header), rule] + body.map(line)
    }

    /* `trendLedger` — DELETED in v4.1 with the `### Week over week` block it
     * rendered. The document is strictly about the week on its cover, so the
     * cumulative table has no reader. `LedgerWeek` and
     * `WeeklyExportInput.ledger` stay: `Derived` reads the ledger for the
     * previous week's totals in the energy balance, which is a calculation
     * and not a table. */

    // MARK: - v3, the dense token grammar

    /// Every data line is fields joined by this. No value may contain `·`.
    static let sep = " · "

    /// A signed weight change, 2 dp. ASCII `-`, like every other v3 figure —
    /// `n()` is `toFixed`, so the document spells one sign one way.

    /// BMR carried across the days that have none — ONE implementation, read by
    /// `energyBalance` and by the `## DERIVED tdee` row, so the document cannot
    /// disagree with its own footer.
    public static func bmrCarry(_ days: [ExportDay]) -> [Double?] {
        var filled: [Double?] = days.map { $0.bmrKcal?.isFinite == true ? $0.bmrKcal : nil }
        if filled.count > 1 {
            for i in 1..<filled.count where filled[i] == nil { filled[i] = filled[i - 1] }
            for i in stride(from: filled.count - 2, through: 0, by: -1) where filled[i] == nil { filled[i] = filled[i + 1] }
        }
        return filled
    }

    // MARK: - v4 · the document's own vocabulary
    /// What the document says instead of a blank. Never `0`, never an empty cell.
    static let noData = "no data"
    /// What it says for an empty LIST, which is a different fact from no reading.
    static let none = "none"

    /// Thousands separators on the INTEGER part only. Decimals are untouched:
    /// tonnage is a sum of quarter-kilogram microloads and its `.25` is real work.
    static func grp(_ s: String) -> String {
        var sign = ""
        var body = Substring(s)
        if let f = body.first, f == "-" || f == "−" || f == "+" { sign = String(f); body = body.dropFirst() }
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = String(parts[0])
        guard !whole.isEmpty, whole.allSatisfy({ $0.isNumber }) else { return s }
        var out = ""
        for (i, ch) in whole.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        let grouped = String(out.reversed())
        let frac = parts.count > 1 ? "." + String(parts[1]) : ""
        return sign + grouped + frac
    }

    /// A grouped fixed-dp number, or nil when there is nothing to print.
    static func val(_ v: Double?, _ digits: Int = 0) -> String? {
        guard let v, v.isFinite else { return nil }
        return grp(n(v, digits))
    }

    /// A grouped FULL-precision number — tonnage and loads. Nil when absent.
    static func valExact(_ v: Double?) -> String? {
        guard let v, v.isFinite else { return nil }
        return grp(exact(v))
    }

    /// A signed figure, where the sign IS the finding: `+0.2 °C`, `−0.1 °C`.
    static func signed(_ v: Double?, _ digits: Int = 1) -> String? {
        guard let v, v.isFinite else { return nil }
        let body = grp(n(abs(v), digits))
        return v < 0 ? "−\(body)" : "+\(body)"
    }

    /// Minutes as a person says them: `9 h 11 m`, `40 m`, `9 h`.
    static func hm(_ v: Double?) -> String? {
        guard let v, v.isFinite else { return nil }
        let total = Int(jsRound(v))
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) m" }
        return m == 0 ? "\(h) h" : "\(h) h \(pad2(String(m))) m"
    }

    /// The non-empty pieces of a line, joined by the document's one separator.
    static func line(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: sep)
    }

    /// True when at least one of these readings exists.
    static func some(_ vs: [Double?]) -> Bool { vs.contains { $0?.isFinite == true } }

    // MARK: - v4 · sets

    static func setValue(_ s: ExportSet, _ timed: Bool) -> String {
        if timed { return "\(grp(exact(s.reps))) sec" }
        if SetFormat.isUnloaded(s.weightKg) { return "\(grp(exact(s.reps))) reps" }
        return "\(grp(exact(s.weightKg))) kg × \(grp(exact(s.reps)))"
    }

    // MARK: - v4 · readiness, micros, the stack

    /// The week's micronutrients, averaged over the days that carried a reading.
    public struct WeeklyNutrient: Codable, Equatable, Sendable {
        public var key: String
        public var label: String
        public var unit: String
        public var kind: NutrientTarget.Kind
        public var food: Double
        public var stack: Double
        public var total: Double
        public var target: Double
        public var pct: Double?
        public var days: Int
        public var flagged: Bool
        /// How many days were EXCLUDED from the mean for being implausible.
        /// Stated rather than silently absorbed: a mean over four days where two
        /// were discarded is a different claim from a mean over six.
        public var excluded: Int
    }

    public static func weeklyNutrients(_ days: [ExportDay]) -> [WeeklyNutrient] {
        var out: [WeeklyNutrient] = []
        for t in NutrientTargets.all {
            var food = 0.0, stack = 0.0, counted = 0, flagged = false, excluded = 0
            for d in days {
                let f = d.nutrientsFood?[t.key]
                let k = d.nutrientsStack?[t.key]
                if f == nil && k == nil { continue }
                let fv = (f?.isFinite == true && f! > 0) ? f! : 0
                let kv = (k?.isFinite == true && k! > 0) ? k! : 0
                /* ── AN IMPLAUSIBLE DAY IS NOT AVERAGED ──────────────────────
                   It used to be flagged AND counted, so the week's calcium mean
                   read 2,012 mg against a 1,000 mg target — a figure produced
                   almost entirely by two days the same document says not to
                   believe. Marking a number untrustworthy and then letting it
                   set the average is having it both ways.

                   Dropped from BOTH numerator and denominator, which is the
                   rule this file already applies to a day with no reading: a
                   day the document does not believe did not carry one. */
                if implausible(t, food: fv, stack: kv) { flagged = true; excluded += 1; continue }
                food += fv; stack += kv; counted += 1
            }
            // Every reading excluded leaves no mean — but the key still appears,
            // so the row can say the week had readings and none survived.
            if counted == 0 && excluded == 0 { continue }
            let mf = counted == 0 ? 0 : food / Double(counted)
            let mk = counted == 0 ? 0 : stack / Double(counted)
            out.append(WeeklyNutrient(
                key: t.key, label: t.label, unit: t.unit, kind: t.kind,
                food: mf, stack: mk, total: mf + mk, target: t.target,
                pct: (t.target > 0 && counted > 0) ? ((mf + mk) / t.target) * 100 : nil,
                days: counted, flagged: flagged, excluded: excluded))
        }
        return out
    }

    /// Decimals a micronutrient average is worth printing at. A whole number
    /// prints whole: `0.0` mg of a supplement reads as a measured tenth.
    static func microDp(_ v: Double) -> Int {
        if v == v.rounded() && abs(v) < 1e15 { return 0 }
        return v < 10 ? 1 : 0
    }

    /// One day's micronutrients, reduced to what a reader has to act on: a
    /// floor missed, a ceiling exceeded, and anything the document doubts. The
    /// complete picture is the weekly table, which is where an average belongs.
    /// Which app contributed most of a nutrient, and how much — `mostly from
    /// MyFitnessPal (3,100 mg)`.
    ///
    /// Reads the `<key>@<source>` entries the HealthKit ingest writes beside
    /// the total. Nil when nothing was attributed, which is every day ingested
    /// before the split existed and every figure typed in by hand.
    static func dominantSource(_ food: [String: Double]?, _ key: String) -> String? {
        guard let food else { return nil }
        let prefix = "\(key)@"
        // Largest first, ties broken by NAME — a Swift dictionary has no order
        // and a JS object has insertion order, so "whichever came first" would
        // diverge between the two languages on equal contributors.
        // Built step by step: the fluent chain tripped "unable to type-check
        // this expression in reasonable time", which this file has hit before.
        var contenders: [(name: String, amount: Double)] = []
        for (k, v) in food {
            guard k.hasPrefix(prefix), v.isFinite, v > 0 else { continue }
            contenders.append((name: String(k.dropFirst(prefix.count)), amount: v))
        }
        contenders.sort { a, b in
            a.amount != b.amount ? a.amount > b.amount : a.name < b.name
        }
        guard let best = contenders.first else { return nil }
        return "mostly from \(best.name) (\(grp(exact(best.amount))))"
    }

    /// A stack item's NAME from the key its log row carries. An item whose key
    /// matches nothing in the protocol falls back to the key rather than
    /// vanishing — the dose still happened.
    static func supplementName(_ protocolItems: [ExportSupplement]?, _ key: String) -> String {
        protocolItems?.first { $0.key == key }?.name ?? key
    }

    // MARK: - Free text

    /// Free text entering a separator-sensitive document.
    ///
    /// ` · ` separates the readings on a row, so a note carrying one would
    /// split into things that look like data. It is stripped rather than
    /// escaped, because an escape needs a reader that knows about it and the
    /// only thing downstream of this document is a person reading plain text.
    ///
    /// v3 also stripped `;` and `:`, which both delimited list items inside a
    /// cell. v4 has no cells, and stripping them was the document editing the
    /// wearer's words: "barely slept; deadline" came out "barely slept deadline".
    ///
    /// A 1:1 port of `phrase` in the web app's `lib/reports/weeklyExport.ts`.
    static func phrase(_ text: String?, max: Int = 60) -> String {
        guard let text, !text.isEmpty else { return "" }
        let flat = text
            .components(separatedBy: CharacterSet(charactersIn: "·\r\n\t"))
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard flat.count > max else { return flat }
        return String(flat.prefix(max - 1)) + "…"
    }

    /// `muscle[/subRegion][@L|@R]` — the name half of a soreness token.
    ///
    /// `@` and `/` because neither can occur in a muscle or a sub-region name
    /// and neither is this column's separator. A leading `L`/`R` marker — how
    /// the SESSIONS section spells a unilateral set — is wrong here: `Lats` is
    /// a sub-region beginning with an L, so a prefix rule makes the token
    /// ambiguous to any parser.
    static func domsName(_ d: ExportDoms) -> String {
        let sub = (d.subRegion?.isEmpty == false) ? "/\(d.subRegion!)" : ""
        let side = d.side == "left" ? "@L" : d.side == "right" ? "@R" : ""
        return "\(d.muscle)\(sub)\(side)"
    }

    // MARK: - v5 · the vocabulary of the seven sections

    /// The maintenance anchor every rung of the lever ladder is a step away
    /// from, in kcal.
    ///
    /// It is a CONSTANT and not a lookup because the ladder cannot answer.
    /// `target_profiles.kind` is nullable locally and nothing in the app writes
    /// `deficit` or `release`, so `TargetProfile.init` defaults every row to
    /// `.day`, `NutritionLever.init?` drops every `.day`, `LeverLadder.rungs`
    /// comes back empty and every period is labelled `Custom`
    /// (`Levers.swift:271`). A custom rung carries a daily target with no
    /// anchor behind it, and a target with no anchor is unreadable: 1,999 kcal
    /// is a surplus or a deficit depending entirely on a number the document
    /// never showed. `WeeklyExportInput.leverBaselineKcal` overrides it.
    public static let leverBaselineKcal: Double = 1935

    /// A muscle is ON its target within this many sets either way. Weekly
    /// counts land on halves — an indirect set credits 0.5 — so an exact match
    /// almost never happens and a strict comparison prints UNDER or OVER for
    /// every muscle in the week, which tells the reader nothing.
    static let setTargetTolerance: Double = 1.0

    /// Sample standard deviation, `n − 1`: a week is a sample of days and not
    /// the population of them. Nil under two readings.
    static func sdOf(_ values: [Double?]) -> Double? {
        let xs = values.compactMap { $0 }.filter(\.isFinite)
        guard xs.count > 1 else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let ss = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        return (ss / Double(xs.count - 1)).squareRoot()
    }

    /// The wall clock of a timestamp, or nil — `clock` with the dash removed,
    /// so an absent reading drops out of a mean instead of poisoning it.
    static func clockOrNil(_ ts: String?) -> String? {
        let c = clock(ts)
        return c == dash ? nil : c
    }

    /// "23:41" → 1421. Nil for anything that is not a wall clock.
    static func minutesOfDay(_ hhmm: String?) -> Double? {
        guard let hhmm, hhmm.count >= 5 else { return nil }
        let p = hhmm.prefix(5).split(separator: ":")
        guard p.count == 2, let h = Double(p[0]), let m = Double(p[1]) else { return nil }
        return h * 60 + m
    }

    /// 1421 → "23:41", wrapping past midnight.
    static func clockOfMinutes(_ v: Double?) -> String? {
        guard let v, v.isFinite else { return nil }
        var t = Int(jsRound(v)) % 1440
        if t < 0 { t += 1440 }
        return "\(pad2(String(t / 60))):\(pad2(String(t % 60)))"
    }

    /// The mean of a set of BEDTIMES, which a plain average gets wrong.
    ///
    /// 23:50 and 00:10 average to 12:00 — the middle of the following day —
    /// where the answer a person wants is midnight. Anything before noon is
    /// read as belonging to the night before and carried past 24:00 before
    /// averaging, then wrapped back. Wake times never cross midnight and take
    /// the plain mean, which is what `wakeMean` is.
    static func onsetMean(_ times: [String?]) -> Double? {
        let mins = times.compactMap(minutesOfDay).map { $0 < 720 ? $0 + 1440 : $0 }
        guard !mins.isEmpty else { return nil }
        return mins.reduce(0, +) / Double(mins.count)
    }

    static func wakeMean(_ times: [String?]) -> Double? {
        let mins = times.compactMap(minutesOfDay)
        guard !mins.isEmpty else { return nil }
        return mins.reduce(0, +) / Double(mins.count)
    }

    /// A night's total sleep, rebuilt from the stages when the duration is
    /// missing.
    ///
    /// `daily_logs.sleep_minutes` is absent on most nights and `sleep_sessions`
    /// carries the four stages regardless, so a week averaged over the duration
    /// column alone was a mean of one night. AWAKE IS EXCLUDED: time in bed is
    /// not time asleep, and the three sleeping stages are what deep % and REM %
    /// are fractions of.
    public static func sleepMinutes(_ d: ExportDay) -> Double? {
        if let m = d.sleepMin, m.isFinite, m > 0 { return m }
        let stages = [d.deepMin, d.remMin, d.coreMin].compactMap { $0 }.filter { $0.isFinite && $0 > 0 }
        guard !stages.isEmpty else { return nil }
        return stages.reduce(0, +)
    }

    /// The day's doubted micronutrients, named — `calcium 3,142 mg`.
    static func doubtedNutrients(_ d: ExportDay) -> [String] {
        NutrientTargets.all.compactMap { t in
            let f = d.nutrientsFood?[t.key], k = d.nutrientsStack?[t.key]
            let fv = (f?.isFinite == true && f! > 0) ? f! : 0
            let kv = (k?.isFinite == true && k! > 0) ? k! : 0
            guard implausible(t, food: fv, stack: kv) else { return nil }
            let blame = dominantSource(d.nutrientsFood, t.key)
            return "\(t.label) \(grp(exact(fv + kv))) \(t.unit)\(blame == nil ? "" : " — \(blame!)")"
        }
    }

    // MARK: - v5 · sets

    /// `40 × 11 @8.5F` — one side of one set, as compact as it goes.
    ///
    /// The `F` rides ON the rating rather than after a comma: a set stopped at
    /// 9 that still could not complete another rep and a set that simply hit 10
    /// are different facts, and the reader needs both in one glance. RPE 10 IS
    /// the top of the ladder, so the marker is suppressed there rather than
    /// stating one fact twice.
    ///
    /// A cardio warm-up prints its own axes. SPEED IS DERIVED from the pair —
    /// distance over duration — because nothing stores one.
    /// True when the set carries a cardio measurement, which a NON-NIL ZERO is
    /// not. Both logger steppers write an explicit `0` when tapped down from
    /// empty, and a branch keyed on `!= nil` then produced an empty value — a
    /// line that was an ordinal and nothing else.
    static func isCardio(_ s: ExportSet) -> Bool {
        let axes = [s.durationSec, s.distanceKm, s.inclinePct]
        return axes.contains { $0.map { $0.isFinite && $0 != 0 } ?? false }
    }

    static func compactSide(_ s: ExportSet, _ timed: Bool) -> String {
        var value: String
        if isCardio(s) {
            var bits: [String] = []
            if let d = s.durationSec, d.isFinite, d > 0 {
                let total = Int(jsRound(d))
                bits.append("\(total / 60):\(pad2(String(total % 60)))")
                if let km = s.distanceKm, km.isFinite, km > 0 {
                    bits.append("\(grp(n(km / (d / 3600), 1))) km/h")
                }
            }
            if let km = s.distanceKm, km.isFinite, km > 0 { bits.append("\(grp(n(km, 2))) km") }
            // `exact`, so a whole percent prints whole — `SetFormat.cardio`'s
            // own convention, and 2 % is a treadmill setting rather than a
            // measurement to a tenth. `!= 0` and not `> 0`: a DECLINE is a real
            // setting and an unstated one is not.
            if let i = s.inclinePct, i.isFinite, i != 0 { bits.append("\(grp(exact(i)))%") }
            value = bits.joined(separator: " ")
        } else if timed {
            value = "\(grp(exact(s.reps))) s"
        } else if SetFormat.isUnloaded(s.weightKg) {
            value = "BW × \(grp(exact(s.reps)))"
        } else {
            value = "\(grp(exact(s.weightKg))) × \(grp(exact(s.reps)))"
        }
        if let r = s.rpe, r.isFinite { value += " @\(js(r))" }
        if s.failure && s.rpe != 10 { value += "F" }
        var flags: [String] = []
        if s.dropset == true { flags.append("drop") }
        if s.isGhost { flags.append("ghost") }
        if let q = s.quality, let named = SetTags.quality[q] { flags.append(named.label.lowercased()) }
        return flags.isEmpty ? value : "\(value) \(flags.joined(separator: " "))"
    }

    /// `S2 L 5 × 15 @10 · R 5 × 16 @9` — BOTH SIDES, ALWAYS.
    ///
    /// The weaker side is what the VOLUME is scored at (`SessionVolume`); it is
    /// not what the athlete did, and a document that prints only the scored
    /// side hides the asymmetry the audit is reading for.
    static func compactSet(_ row: SetRow, _ ordinal: String, _ timed: Bool) -> String {
        if let s = row.single { return "\(ordinal) \(compactSide(s, timed))" }
        let halves = [
            row.left.map { "L \(compactSide($0, timed))" },
            row.right.map { "R \(compactSide($0, timed))" },
        ].compactMap { $0 }
        return "\(ordinal) \(halves.joined(separator: sep))"
    }

    /// Every side of one display row.
    static func sides(_ row: SetRow) -> [ExportSet] {
        [row.single, row.left, row.right].compactMap { $0 }
    }

    /// A set reached failure when EITHER side did.
    ///
    /// ── WHY RPE 10 AND NOT `set_type` ──────────────────────────────────────
    /// `workout_sets.set_type = 'failure'` is a separate tick the logger offers
    /// and the athlete rarely uses; the RPE dial is on every set. A session with
    /// six sets rated 10 and no ticks reported `0 sets to failure` — a document
    /// contradicting its own set list two lines below it. The rating is the
    /// evidence and the tick is a second spelling of it, so either counts.
    ///
    /// A unilateral pair is examined PER SIDE and counted ONCE: one arm failing
    /// is the set failing, and counting both would let `failure_sets` exceed
    /// `working_sets` for a session of single-arm work.
    static func isFailure(_ row: SetRow) -> Bool {
        sides(row).contains { $0.rpe == 10 || $0.failure }
    }

    /// The set's own effort — the HARDER side of a pair. Both sides are printed
    /// beside each other; one number for the set has to be one of them, and the
    /// one that is true of the SET is the higher.
    static func setRpe(_ row: SetRow) -> Double? {
        sides(row).compactMap { $0.rpe }.filter(\.isFinite).max()
    }

    /// Working rows only — a warm-up and a ghost are neither.
    static func workingRows(_ ex: ExportExercise) -> [SetRow] {
        toSetRows(ex.sets).filter { row in
            let s = sides(row)
            return !s.isEmpty && !s.contains { $0.isWarmup || $0.isGhost }
        }
    }

    /// The heaviest working set of one movement — tonnage, ties to the heavier
    /// load. `dedupePrs`' own rule, so the "best set" this document prints and
    /// the set the PR engine picks are the same set.
    static func bestSet(_ ex: ExportExercise) -> ExportSet? {
        var best: ExportSet?
        for row in workingRows(ex) {
            for s in sides(row) {
                guard let cur = best else { best = s; continue }
                let a = s.weightKg * s.reps, b = cur.weightKg * cur.reps
                if a > b || (a == b && s.weightKg > cur.weightKg) { best = s }
            }
        }
        return best
    }

    // MARK: - The document

    /// EXPORT v5 — seven fixed sections, in this order, and nothing else.
    ///
    /// The consumer is a model auditing the week, not a person reading it, so
    /// every line is data and no line is prose. A field with nothing behind it
    /// prints NOTHING — not a dash, not a zero — except where the schema marks
    /// it required, which is where an absence is itself the finding. There are
    /// no Score and no Battery figures anywhere: both are this app's opinion of
    /// the week, and the audit is here to form its own.
    public static func build(_ input: WeeklyExportInput) -> String {
        let days = input.days
        let sessions = input.sessions
        let cardio = input.cardio ?? []
        let bodyComp = input.bodyComp ?? []
        let periods = input.targetPeriods ?? []
        var L: [String] = []
        /* Everything the document corrected or refused, collected as it renders
           and printed once at the end. The BUILDER's list leads: it saw the
           duplicate bouts and the rebuilt sleep durations, rows this renderer
           is never handed. */
        var anomalies: [String] = input.anomalies ?? []

        // ── 1 · WEEK ──────────────────────────────────────────────────────────
        L.append("## 1 · WEEK")
        let weekId = input.weekLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phase = input.phaseLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        L.append(line([
            weekId.isEmpty ? nil : "week_id \(weekId)",
            "\(input.weekStart) → \(input.weekEnd)",
            phase.isEmpty ? nil : "phase \(phase)",
        ]))

        let baseline = input.leverBaselineKcal ?? leverBaselineKcal
        func leverLine(_ p: TargetPeriod?) -> String {
            let g = p?.goals
            let span: String? = {
                guard let p, !p.dates.isEmpty, periods.count > 1 else { return nil }
                return "\(p.dates[0]) → \(p.dates[p.dates.count - 1])"
            }()
            return line([
                "lever \(p?.label ?? noData)",
                "baseline \(grp(n(baseline))) kcal",
                val(g?.calorie ?? input.calorieGoal).map { "\($0) kcal" },
                val(g?.protein ?? input.proteinGoalG).map { "\($0) P" },
                val(g?.carbs).map { "\($0) C" },
                val(g?.fat).map { "\($0) F" },
                val(g?.steps ?? input.stepsGoal).map { "\($0) steps" },
                val(input.waterGoalMl.map { $0 / 1000 }, 2).map { "\($0) L water" },
                val(input.sleepGoalHours, 1).map { "\($0) h sleep" },
                span,
            ])
        }
        if periods.isEmpty { L.append(leverLine(nil)) } else { for p in periods { L.append(leverLine(p)) } }

        let eventDays = days.filter { $0.nutritionException?.isEmpty == false }
        if !eventDays.isEmpty {
            L.append("event_days " + eventDays.map { d in
                "\(d.date) \(phrase(d.nutritionException))\(d.nutritionEstimated ? " (estimate)" : "")"
            }.joined(separator: sep))
        }
        for note in (input.protocolNotes ?? []).prefix(3) where !note.isEmpty {
            L.append("protocol_note \(phrase(note, max: 160))")
        }

        // ── 2 · WEEK AGGREGATES ───────────────────────────────────────────────
        L.append("")
        L.append("## 2 · WEEK AGGREGATES")

        let micros = weeklyNutrients(days)
        /// A micronutrient's weekly mean, with the denominator it was taken
        /// over. `(4 of 6 d)` where two days were thrown out says more than a
        /// mean that quietly absorbed them.
        func microMean(_ label: String, _ keys: [String]) -> String? {
            guard let m = micros.first(where: { keys.contains($0.key) && $0.days > 0 }) else { return nil }
            let denom = m.excluded > 0 ? "\(m.days) of \(m.days + m.excluded) d" : "\(m.days) d"
            return "\(label) \(val(m.total, microDp(m.total)) ?? noData) \(m.unit) (\(denom))"
        }
        L.append("intake " + line([
            val(meanOf(days.map(\.calories))).map { "kcal \($0)" },
            val(sdOf(days.map(\.calories))).map { "sd \($0)" },
            val(meanOf(days.map(\.proteinG))).map { "P \($0)" },
            val(meanOf(days.map(\.carbsG))).map { "C \($0)" },
            val(meanOf(days.map(\.fatG))).map { "F \($0)" },
            microMean("fiber", ["fiber"]),
            microMean("added_sugar", ["addedSugar", "added_sugar", "sugar"]),
            microMean("calcium", ["calcium"]),
            val(meanOf(days.map(\.waterMl)).map { $0 / 1000 }, 2).map { "water \($0) L" } ?? "water \(noData)",
        ]))

        let sessionDates = Set(sessions.map(\.date))
        func isGymDay(_ d: ExportDay) -> Bool { d.isTrainingDay || sessionDates.contains(d.date) }
        let allSteps = days.compactMap { $0.steps?.isFinite == true ? $0.steps : nil }
        L.append("steps " + line([
            val(meanOf(days.map(\.steps))).map { "mean \($0)" },
            val(meanOf(days.filter(isGymDay).map(\.steps))).map { "gym_day \($0)" },
            val(meanOf(days.filter { !isGymDay($0) }.map(\.steps))).map { "rest_day \($0)" },
            "min \(val(allSteps.min()) ?? noData)",
            "max \(val(allSteps.max()) ?? noData)",
        ]))

        let durations = days.map(sleepMinutes)
        let deepSum = days.compactMap(\.deepMin).reduce(0, +)
        let remSum = days.compactMap(\.remMin).reduce(0, +)
        let sleepSum = durations.compactMap { $0 }.reduce(0, +)
        L.append("sleep " + line([
            hm(meanOf(durations)).map { "duration \($0)" },
            val(meanOf(days.map(\.deepMin))).map { "deep \($0) m" },
            sleepSum > 0 ? "deep \(val(deepSum / sleepSum * 100, 1) ?? noData) %" : nil,
            sleepSum > 0 ? "REM \(val(remSum / sleepSum * 100, 1) ?? noData) %" : nil,
            clockOfMinutes(onsetMean(days.map { clockOrNil($0.bedTime) })).map { "onset_local \($0)" },
            clockOfMinutes(wakeMean(days.map { clockOrNil($0.wakeTime) })).map { "wake_local \($0)" },
            "nights_deep_ge_60 \(days.filter { ($0.deepMin ?? 0) >= 60 }.count)",
        ]))

        let flaggedDays = days.filter { $0.hrvFlag?.isEmpty == false }
        L.append("vitals " + line([
            val(meanOf(days.map(\.hrvMs)), 1).map { "HRV \($0) ms" },
            flaggedDays.isEmpty ? nil
                : "HRV_excl_flagged \(val(meanOf(days.filter { $0.hrvFlag == nil }.map(\.hrvMs)), 1) ?? noData) ms",
            val(meanOf(days.map(\.restingHr)), 1).map { "RHR \($0)" },
            "flagged_days \(flaggedDays.isEmpty ? none : flaggedDays.map(\.date).joined(separator: ", "))",
        ]))

        var workingSets = 0, failureSets = 0, compoundHard = 0
        var rpes: [Double] = []
        for s in sessions {
            for ex in s.exercises {
                for row in workingRows(ex) {
                    workingSets += 1
                    if isFailure(row) { failureSets += 1 }
                    if let r = setRpe(row) {
                        rpes.append(r)
                        if ex.compound == true && r > 8.5 { compoundHard += 1 }
                    }
                }
            }
        }
        L.append("training " + line([
            "sessions \(sessions.count)",
            "working_sets \(workingSets)",
            valExact(sumOf(sessions.map(\.volumeKg))).map { "tonnage \($0) kg" },
            val(sumOf(sessions.map(\.durationMin))).map { "minutes \($0)" },
            "failure_sets \(failureSets)",
            "compound_sets_over_8.5 \(compoundHard)",
            rpes.isEmpty ? nil : "mean_set_rpe \(val(rpes.reduce(0, +) / Double(rpes.count), 2) ?? noData)",
        ]))
        let allPrs = sessions.flatMap(\.prs)
        L.append("PRs " + (allPrs.isEmpty ? none : allPrs.map { p in
            // A timed movement's record is a DURATION. `BW × 60` for a 60-second
            // side plank reads as sixty repetitions of it.
            if TimedExercise.isTimed(p.name) { return "\(p.name) \(grp(exact(p.reps))) s" }
            if SetFormat.isUnloaded(p.weightKg) { return "\(p.name) BW × \(grp(exact(p.reps)))" }
            return "\(p.name) \(grp(exact(p.weightKg))) × \(grp(exact(p.reps)))"
        }.joined(separator: sep)))

        L.append("cardio " + line([
            "bouts \(cardio.count)",
            val(sumOf(cardio.map(\.durationMin)), 1).map { "minutes \($0)" },
            val(sumOf(cardio.map(\.kcal))).map { "kcal \($0)" },
        ]))

        /* The week's fatigue as ONE string — three slots a day, in the order
           the day happens in, days divided by the document's own separator. A
           slot nobody answered is `-`: a 0 on a 1–5 scale is a reading. */
        func fatigueTrace(_ d: ExportDay) -> String {
            /* `isGymDay`, not `d.isTrainingDay`. The BUILDER normalises a
               reading's slot with "a session logged on the day makes it a
               training day", and the Pulse screen writes under the same rule.
               Asking the calendar instead looked for `Waking / Midday / Night`
               on a rest day that was trained and found `Before training /
               After training`, printing `-/-/-` on a row this same renderer
               labels TRAIN. */
            fatigueLabels(isTrainingDay: isGymDay(d)).map { slot in
                let hit = (input.fatigue ?? []).first { $0.date == d.date && $0.slot == slot }
                return hit == nil ? "-" : n(hit!.level)
            }.joined(separator: "/")
        }
        L.append("fatigue " + (days.isEmpty ? none : days.map(fatigueTrace).joined(separator: sep)))

        if !input.doms.isEmpty {
            L.append("doms " + input.doms.map { "\($0.date) \(domsName($0)) \(n($0.severity))" }.joined(separator: sep))
        }
        if let stress = input.stress, !stress.isEmpty {
            L.append("stress " + stress.map { "\($0.date) \($0.slot) \(n($0.level))" }.joined(separator: sep))
        }

        // ── 3 · BODY COMPOSITION ──────────────────────────────────────────────
        L.append("")
        L.append("## 3 · BODY COMPOSITION")
        if bodyComp.isEmpty {
            L.append("no scan this week")
        } else {
            L.append("")
            L.append(contentsOf: markdownTable(
                header: ["date", "weight", "BF%", "fat kg", "lean kg", "SMM kg", "FFM kg",
                         "water kg", "water %", "protein kg", "bone kg", "visceral", "BMR", "valid"],
                body: bodyComp.map { b in
                    [
                        b.date,
                        val(b.weightKg, 2) ?? dash, val(b.bodyFatPct, 1) ?? dash, val(b.fatMassKg, 2) ?? dash,
                        val(b.muscleMassKg, 2) ?? dash, val(b.skeletalMuscleMassKg, 2) ?? dash,
                        val(b.fatFreeMassKg, 2) ?? dash,
                        val(b.waterMassKg, 2) ?? dash, val(b.waterPercent, 1) ?? dash,
                        val(b.proteinMassKg, 2) ?? dash, val(b.boneMineralKg, 2) ?? dash,
                        val(b.visceralFat, 1) ?? dash, val(b.bmr) ?? dash,
                        b.anomaly == nil ? "OK" : "ANOMALOUS",
                    ]
                },
                align: [.left] + Array(repeating: Align.right, count: 12) + [.left]))
            L.append("")

            for b in bodyComp where b.anomaly != nil {
                anomalies.append("anomalous body scan \(b.date) — \(b.anomaly!)")
            }
            /* THE TRAILING FOUR, AND WHERE IN THE WEEK THEY SAT.
               A first-to-last comparison of two weigh-ins is two numbers of
               water weight: 61.7 → 61.7 (+0.00) was the export's own reading of
               a week that moved. Four scans smooth the day-to-day swing; the
               sample CENTRE says which part of the week they came from, because
               a mean of four Sunday-to-Tuesday scans and a mean of four
               Thursday-to-Saturday scans are not comparable figures. An
               anomalous scan is printed above and excluded here. */
            let valid = bodyComp.filter { $0.anomaly == nil }
            // Weighed, THEN trailing four. A scan that recorded a muscle mass
            // and no weight is a valid scan and not a weigh-in; counting it
            // into the window printed four dates beside a mean of two.
            let t4 = Array(valid.filter { $0.weightKg?.isFinite == true }.suffix(4))
            let t4w = t4.compactMap(\.weightKg)
            if !t4w.isEmpty {
                let start = ISODate.dayNumber(input.weekStart)
                let centres = t4.compactMap { b -> Double? in
                    guard let start, let d = ISODate.dayNumber(b.date) else { return nil }
                    return Double(d - start) + 1
                }
                L.append(line([
                    "T4WM \(val(t4w.reduce(0, +) / Double(t4w.count), 2) ?? noData) kg",
                    "over \(t4w.count) valid scan\(t4w.count == 1 ? "" : "s")",
                    t4.map(\.date).joined(separator: ", "),
                    centres.isEmpty ? nil
                        : "T4WM_sample_centre \(val(centres.reduce(0, +) / Double(centres.count), 2) ?? noData)",
                ]))
            }
            if !valid.isEmpty {
                L.append("clean_scan_means " + line([
                    val(meanOf(valid.map(\.weightKg)), 2).map { "weight \($0)" },
                    val(meanOf(valid.map(\.bodyFatPct)), 1).map { "BF \($0) %" },
                    val(meanOf(valid.map(\.fatMassKg)), 2).map { "fat \($0) kg" },
                    val(meanOf(valid.map(\.muscleMassKg)), 2).map { "lean \($0) kg" },
                    val(meanOf(valid.map(\.skeletalMuscleMassKg)), 2).map { "SMM \($0) kg" },
                    val(meanOf(valid.map(\.fatFreeMassKg)), 2).map { "FFM \($0) kg" },
                    val(meanOf(valid.map(\.waterMassKg)), 2).map { "water \($0) kg" },
                    val(meanOf(valid.map(\.waterPercent)), 1).map { "water \($0) %" },
                    val(meanOf(valid.map(\.proteinMassKg)), 2).map { "protein \($0) kg" },
                    val(meanOf(valid.map(\.boneMineralKg)), 2).map { "bone \($0) kg" },
                    val(meanOf(valid.map(\.visceralFat)), 1).map { "visceral \($0)" },
                    val(meanOf(valid.map(\.bmr))).map { "BMR \($0)" },
                    "n \(valid.count)",
                ]))
            }
        }
        /* A day is a NO WEIGH-IN when nothing weighed it — not when it merely
           carried no full scan. `bodyComp` holds only dates with a compartment
           beyond bare weight, so filtering on it alone named four days that the
           daily rows show a weight for. */
        let weighed = Set(bodyComp.filter { $0.weightKg != nil }.map(\.date))
        let noWeighIn = days.filter { !weighed.contains($0.date) && $0.weightKg == nil }
        if !noWeighIn.isEmpty {
            L.append("no_weigh_in " + noWeighIn
                .map { "\($0.date) \(WeighIn.skipReason($0.weighInSkipReason))" }
                .joined(separator: sep))
        }

        // ── 4 · DAILY ROWS ────────────────────────────────────────────────────
        L.append("")
        L.append("## 4 · DAILY ROWS")
        for day in days {
            let today = sessions.filter { $0.date == day.date }
            let kind = day.nutritionException?.isEmpty == false ? "EVENT"
                : isGymDay(day) ? "TRAIN" : "REST"
            let domsCells = input.doms.filter { $0.date == day.date }
                .map { "\(domsName($0)) \(n($0.severity))" }
            let stressCells = (input.stress ?? []).filter { $0.date == day.date }
                .map { "\($0.slot) \(n($0.level))" }
            let skipped = (day.supplementsSkipped ?? []) + (day.supplementsSkippedUnplanned ?? [])
            let flags = [
                day.nutritionEstimated ? "estimate" : nil,
                day.sleepInaccurate == true ? "disputed sleep" : nil,
                day.hrvFlag == nil ? nil : "HRV flagged",
            ].compactMap { $0 }
            L.append(line([
                day.date,
                today.isEmpty ? kind : "\(kind) \(today.map(\.label).joined(separator: " + "))",
                val(day.calories).map { "\($0) kcal" },
                some([day.proteinG, day.carbsG, day.fatG])
                    ? "\(val(day.proteinG) ?? dash)/\(val(day.carbsG) ?? dash)/\(val(day.fatG) ?? dash)" : nil,
                val(day.nutrientsFood?["fiber"]).map { "fiber \($0)" },
                val(day.waterMl.map { $0 / 1000 }, 2).map { "water \($0) L" },
                val(day.steps).map { "\($0) steps" },
                hm(sleepMinutes(day)).map { "sleep \($0)" },
                val(day.deepMin).map { "deep \($0) m" },
                val(day.hrvMs, 1).map { "HRV \($0)" },
                val(day.restingHr).map { "RHR \($0)" },
                // A weigh-in or the REASON there is none — never a blank, which
                // a reader takes for a zero on the scale.
                val(day.weightKg, 2).map { "\($0) kg" }
                    ?? "no weigh-in (\(WeighIn.skipReason(day.weighInSkipReason)))",
                "fatigue \(fatigueTrace(day))",
                domsCells.isEmpty ? nil : "DOMS \(domsCells.joined(separator: ", "))",
                stressCells.isEmpty ? nil : "stress \(stressCells.joined(separator: ", "))",
                skipped.isEmpty ? nil : "skipped \(skipped.joined(separator: ", "))",
                flags.isEmpty ? nil : "flags \(flags.joined(separator: ", "))",
            ]))
        }

        // ── 5 · SESSIONS ──────────────────────────────────────────────────────
        L.append("")
        L.append("## 5 · SESSIONS")
        if sessions.isEmpty { L.append(none) }
        for s in sessions {
            var working = 0, failed = 0
            for ex in s.exercises {
                for row in workingRows(ex) { working += 1; if isFailure(row) { failed += 1 } }
            }
            L.append("")
            L.append("### " + line([
                s.label,
                s.date,
                {
                    // A dash with nothing after it reads as a rendering fault.
                    switch (clockOrNil(s.startedAt), clockOrNil(s.endedAt)) {
                    case let (a?, b?): return "\(a)–\(b)"
                    case let (a?, nil): return "from \(a)"
                    case let (nil, b?): return "until \(b)"
                    default: return nil
                    }
                }(),
                val(s.durationMin).map { "\($0) min" },
                s.sessionRpe.map { "sRPE \(js($0))" },
                "working_sets \(working)",
                "failure_sets \(failed)",
                valExact(s.volumeKg).map { "tonnage \($0) kg" },
                s.prs.isEmpty ? nil : "PRs \(s.prs.map(\.name).joined(separator: ", "))",
            ]))
            /* BOTH fallbacks are named. `index` is `workout_sets.exercise_order`,
               which is the DECK position and not a record of what was performed
               — a pulled session has no local event log and always lands here,
               so leaving it unmarked presents the deck as the session. */
            switch s.orderSource {
            case "logged":
                anomalies.append("no performed-order index \(s.date) \(s.label) — movements printed in logged order")
            case "index":
                anomalies.append("no performed-order index \(s.date) \(s.label) — movements printed in deck order")
            default: break
            }

            for ex in s.exercises {
                let timed = TimedExercise.isTimed(ex.name)
                L.append(line([
                    "**\(ex.name)**",
                    (ex.repWindow?.isEmpty == false) ? "target \(ex.repWindow!)" : nil,
                    ex.prescription.map { p in
                        "prescribed \(grp(exact(p.sets))) × \(p.reps)"
                            + (p.loadKg.map { " @ \(grp(exact($0))) kg" } ?? "")
                    },
                    ex.sets.isEmpty ? "no sets logged" : nil,
                ]))
                var num = 0
                for row in toSetRows(ex.sets) {
                    let ss = sides(row)
                    if ss.isEmpty { continue }
                    // Warm-ups are listed once per session, below, and consume
                    // no ordinal: `S1` is the first WORKING set.
                    if ss.contains(where: { $0.isWarmup }) { continue }
                    let ordinal: String
                    if ss.contains(where: { $0.isGhost }) { ordinal = "G" } else { num += 1; ordinal = "S\(num)" }
                    L.append(compactSet(row, ordinal, timed))
                }
                // What this movement did against the last time it was performed.
                // Absent on a movement being logged for the first time, which is
                // a fact and not a gap.
                // A cardio set has neither a load nor a rep count, so
                // `weightKg × reps` ranks every one of them at zero and the
                // line reads `best BW × 0 · load +0.00 kg`. Suppressed: the set
                // lines above already carry the duration and the speed.
                if let best = bestSet(ex), !isCardio(best) {
                    let lift = timed ? "\(grp(exact(best.reps))) s"
                        : SetFormat.isUnloaded(best.weightKg)
                        ? "BW × \(grp(exact(best.reps)))"
                        : "\(grp(exact(best.weightKg))) × \(grp(exact(best.reps)))"
                    if let prev = ex.previous {
                        L.append(line([
                            "best \(lift)",
                            "vs \(prev.date) \(grp(exact(prev.weightKg))) × \(grp(exact(prev.reps)))",
                            "load \(signed(best.weightKg - prev.weightKg, 2) ?? noData) kg",
                            "reps \(signed(best.reps - prev.reps, 0) ?? noData)",
                        ]))
                    } else {
                        L.append("best \(lift) · first time logged")
                    }
                }
            }

            let warmups = s.exercises.flatMap { ex -> [String] in
                toSetRows(ex.sets)
                    .filter { row in sides(row).contains { $0.isWarmup } }
                    .map { row in
                        let body = compactSet(row, "·", TimedExercise.isTimed(ex.name)).dropFirst(2)
                        return "\(ex.name) \(body)"
                    }
            }
            if !warmups.isEmpty { L.append("warm-ups " + warmups.joined(separator: sep)) }

            let cardioToday = cardio.filter { $0.date == s.date }
            if !cardioToday.isEmpty { L.append("cardio " + cardioLines(cardioToday, dated: false)) }
        }
        /* A bout on a day with no session still happened, and is already counted
           in the week's cardio total. Without this it would have nowhere to sit:
           §5 is the only section that carries a bout's own detail. */
        let sessionDays = Set(sessions.map(\.date))
        let looseCardio = cardio.filter { !sessionDays.contains($0.date) }
        if !looseCardio.isEmpty {
            L.append("")
            L.append("cardio_no_session " + cardioLines(looseCardio, dated: true))
        }

        // ── 6 · SETS BY MUSCLE ────────────────────────────────────────────────
        L.append("")
        L.append("## 6 · SETS BY MUSCLE")
        if input.volumeByMuscle.isEmpty { L.append(none) } else { L.append("") }
        L.append(contentsOf: input.volumeByMuscle.isEmpty ? [] : markdownTable(
            header: ["muscle", "direct", "indirect", "total", "target", "status"],
            body: input.volumeByMuscle.map { v in
                // No target is not a target of zero: `Adductors` genuinely
                // carries 0 on a cut, and a muscle the plan never named carries
                // none at all — neither can be UNDER.
                let status: String
                if v.target <= 0 { status = "ON" }
                else if v.sets < v.target - setTargetTolerance { status = "UNDER" }
                else if v.sets > v.target + setTargetTolerance { status = "OVER" }
                else { status = "ON" }
                return [
                    v.muscle,
                    val(v.directSets, 1) ?? dash,
                    val(v.indirectSets, 1) ?? dash,
                    val(v.sets, 1) ?? dash,
                    v.target > 0 ? (val(v.target, 1) ?? dash) : "none",
                    status,
                ]
            },
            align: [.left, .right, .right, .right, .right, .left]))

        // ── 7 · ANOMALIES ─────────────────────────────────────────────────────
        for d in days {
            if let why = d.hrvFlag { anomalies.append("HRV flagged \(d.date) — \(why)") }
            if d.sleepInaccurate == true { anomalies.append("disputed sleep \(d.date)") }
            for x in doubtedNutrients(d) { anomalies.append("implausible micro excluded \(d.date) \(x)") }
        }
        /* ── A NUTRIENT THE FOOD LOG NEVER REPORTED ─────────────────────────
           There is no food database in this app. Every food micronutrient
           arrives as a DAILY AGGREGATE from HealthKit, written by whichever
           food logger the athlete uses, and if that app's dairy and whey
           entries carry no calcium then no calcium is what HealthKit is handed
           and no calcium is what this document can show. Nothing here can add
           it back.

           What it can do is refuse to let the gap read as an intake. A calcium
           mean of 340 mg over three days is a different claim from a calcium
           mean of 340 mg over seven, and a day with food logged and no reading
           at all is neither a low day nor a zero — it is a day the source did
           not answer. Named once per nutrient, over the days that logged food.

           Only the floors FOOD is expected to supply: a stack nutrient absent
           from the food column is the ordinary case and says nothing. */
        let fedDays = days.filter { ($0.calories ?? 0) > 0 }
        if !fedDays.isEmpty {
            // Macros are excluded: fiber and protein have their own columns in
            // §2 and §4, and a second line saying they are missing is the same
            // gap twice. This clause exists for the minerals and vitamins,
            // which appear nowhere else if nothing reports them.
            for t in NutrientTargets.all where t.kind == .floor && !t.fromStack && t.group != "Macros" {
                let silent = fedDays.filter { ($0.nutrientsFood?[t.key] ?? 0) <= 0 }
                guard !silent.isEmpty else { continue }
                anomalies.append("\(t.label) not reported by the food source on "
                    + "\(silent.count) of \(fedDays.count) day\(fedDays.count == 1 ? "" : "s") with food logged")
            }
        }
        // A stamp that cannot be true says so rather than being quietly drawn.
        for s in sessions {
            guard let a = s.startedAt, let b = s.endedAt, !a.isEmpty, !b.isEmpty, b < a else { continue }
            anomalies.append("timestamp inconsistency \(s.date) \(s.label) — ended \(clock(b)) before it started \(clock(a))")
        }
        L.append("")
        L.append("## 7 · ANOMALIES")
        if anomalies.isEmpty { L.append("none") } else { L.append(contentsOf: anomalies) }

        return L.joined(separator: "\n")
    }

    /// One line per bout, bouts divided by `|` — `·` already separates a bout's
    /// own fields and a document cannot use one separator for both.
    static func cardioLines(_ bouts: [ExportCardio], dated: Bool) -> String {
        bouts.map { c in
            line([
                dated ? c.date : nil,
                cardioLabel(c.kind),
                // A hand-typed row's `created_at` is the instant it was typed,
                // not a start. Printing 21:00 for an 08:00 walk invents one.
                c.source == "health" ? clockOrNil(c.startedAt) : nil,
                val(c.durationMin, 1).map { "\($0) min" },
                val(c.distanceM.map { $0 / 1000 }, 2).map { "\($0) km" },
                val(c.kcal).map { "\($0) kcal" },
                val(c.avgHr).map { "avg HR \($0)" },
            ])
        }.joined(separator: " | ")
    }

        // MARK: - Supplements

    /// The stack, deduped and ordered — the shape BOTH renderers read. Nothing
    /// about any particular supplement is known here; every field arrives from
    /// `custom_supplements`.
    public struct SupplementRow: Codable, Equatable, Sendable {
        public var time: String
        public var name: String
        public var dose: String
        public var trainingDose: String?
        public var restDose: String?
        public var trainingOnly: Bool
        public var notes: String?
    }

    /// Deduped by NAME, ordered by the scheduled time — the order the day
    /// happens in. Ties keep insertion order, as JavaScript's stable sort does.
    public static func supplementRows(_ stack: [ExportSupplement]) -> [SupplementRow] {
        func trimmed(_ v: String?) -> String? {
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        var order: [String] = []
        var byName: [String: SupplementRow] = [:]
        for s in stack {
            let name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            let key = name.lowercased()
            if byName[key] != nil { continue }
            order.append(key)
            byName[key] = SupplementRow(
                time: trimmed(s.time) ?? dash,
                name: name,
                dose: s.dose.trimmingCharacters(in: .whitespacesAndNewlines),
                trainingDose: trimmed(s.trainingDose),
                restDose: trimmed(s.restDose),
                trainingOnly: s.trainingOnly == true,
                notes: trimmed(s.notes)
            )
        }
        return order.map { byName[$0]! }.enumerated()
            .sorted { a, b in
                let c = icuCompare(a.element.time, b.element.time)
                return c == 0 ? a.offset < b.offset : c < 0
            }
            .map(\.element)
    }

    /// The stack as ONE chronological list. A dose that differs by day is
    /// stated as the rule it is rather than arbitrarily picking one column.
    public static func consolidateSupplements(_ stack: [ExportSupplement]) -> [String] {
        supplementRows(stack).map { s in
            let dose: String
            if let t = s.trainingDose, let r = s.restDose, t != r {
                dose = "\(t) on training days / \(r) on rest days"
            } else {
                dose = s.dose
            }
            var parts = ["\(s.time) · \(s.name) — \(dose)"]
            if s.trainingOnly { parts.append("(training days only)") }
            if let notes = s.notes { parts.append("· \(notes)") }
            return parts.joined(separator: " ")
        }
    }
}
