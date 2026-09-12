import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// "Export Week" — a dense, DRY-DATA payload of one training week. A port of
// the web app's `lib/reports/weeklyExport.ts`, byte for byte.
//
// EXPORT v4, THE DOCUMENT. The week is written DAY BY DAY: everything the app
// knows about Monday sits under `## DAY 2 · Mon · 2026-08-31`, in the order the
// day happened. A gap is NAMED — `no data` for a reading, `none` for a list,
// and a row with nothing in it at all is dropped and listed in that day's
// closing `Not recorded:` line. A computed figure says so where it sits: a
// day-major document has no fence to put one behind.
//
// Lines inside a day end in TWO SPACES. That is a markdown hard break, and
// without it every row of a day renders as one run-on paragraph.
//
// Deterministic and pure. Every number is one the app measured; the only
// derived figures live under `## DERIVED`, below every measurement they are
// built from, behind a heading that says so. Pace is the one exception in the
// raw body: arithmetic over two exported facts, and the unit a run is read in.
//
// `setDetail`, `nutrientLine` and `sparkline` are v2's prose renderers, kept
// because the golden vectors pin them. `markdownTable` carries the four tables
// v4 allows: the programme ledger, sets by muscle, body composition and the
// weekly micronutrient average.
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

    static func cardioLabel(_ kind: String) -> String {
        kind.isEmpty ? "Cardio" : kind.prefix(1).uppercased() + kind.dropFirst()
    }

    static func weekdayOf(_ date: String, _ days: [ExportDay]) -> String {
        days.first { $0.date == date }?.weekdayLabel ?? ""
    }

    /// en-GB short month names as Node prints them ("Sept", not "Sep"). v3
    /// prints no month name; `Format.dayAndMonth` is the one reader left.
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec"]

    static func month(_ iso: String) -> String {
        guard iso.count >= 7, let m = Int(iso.dropFirst(5).prefix(2)), (1...12).contains(m) else { return "" }
        return months[m - 1]
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

    static func directionGlyph(_ cur: Double?, _ prev: Double?) -> String {
        guard let cur, let prev else { return dash }
        let d = cur - prev
        return abs(d) < 1e-9 ? "→" : d > 0 ? "↑" : "↓"
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

    /// One data line. Nil/empty renders `—`; `0` renders `0`, which is a fact.
    static func fields(_ cells: [String?]) -> String {
        cells.map { $0 == nil || $0!.isEmpty ? dash : $0! }.joined(separator: sep)
    }

    /// A list field: items joined by `;`. Empty renders `—`.
    static func items(_ xs: [String]) -> String { xs.isEmpty ? dash : xs.joined(separator: ";") }

    /// Minutes, whole. EVERY duration in v3 is minutes — one unit, no suffixes.
    static func minutes(_ v: Double?) -> String { n(v, 0) }

    /// Metres → km, 2 dp.
    static func kmOf(_ m: Double?) -> String {
        guard let m, m.isFinite else { return dash }
        return n(m / 1000, 2)
    }

    /// Millilitres → litres, 2 dp.
    static func litresOf(_ ml: Double?) -> String {
        guard let ml, ml.isFinite else { return dash }
        return n(ml / 1000, 2)
    }

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

    /// A markdown hard break. Every row inside a day block ends with one.
    static let br = "  "
    /// What the document says instead of a blank. Never `0`, never an empty cell.
    static let noData = "no data"
    /// What it says for an empty LIST, which is a different fact from no reading.
    static let none = "none"

    /// Three letters, not four: `months` above spells September "Sept" for the
    /// ledger's own label, and a date inside a sentence reads better short.
    static let monthAbbr = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "30 Aug" from `2026-08-30`. Echoes anything it cannot parse.
    static func dayOfMonth(_ date: String) -> String {
        let p = date.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), m >= 1, m <= 12 else { return date }
        return "\(d) \(monthAbbr[m - 1])"
    }

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

    /// `HRV 61.5 ms`, or `HRV no data`. The label travels with the value
    /// because these lines are read left to right rather than zipped against a
    /// legend — which is the whole difference between v4 and v3.
    static func stat(_ label: String, _ v: Double?, _ unit: String = "", _ digits: Int = 0) -> String {
        guard let x = val(v, digits) else { return "\(label) \(noData)" }
        return "\(label) \(x)\(unit)"
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

    /// One labelled row of a day, or nil when it has nothing to say. The nil is
    /// load-bearing: a caller collects the names of the rows that came back nil
    /// and prints them in the day's closing `Not recorded:` line.
    static func dayRow(_ label: String, _ body: String) -> String? {
        body.isEmpty ? nil : "**\(label)** \(body)\(br)"
    }

    /// A row that prints the readings it HAS and names the ones it LACKS, once.
    ///
    /// A gap must never be omitted silently — that is how a missing weigh-in
    /// reads as a zero. But `Body` has sixteen compartments, and a day carrying
    /// two of them rendered as fourteen consecutive `no data`s is not stating a
    /// gap: it is burying the two real numbers in it. So the gap is stated ONCE,
    /// by name, in a trailing clause.
    static func partialRow(_ label: String, _ entries: [(String, String?)]) -> String? {
        let have = entries.compactMap { $0.1 }
        guard !have.isEmpty else { return nil }
        let lack = entries.filter { $0.1 == nil }.map { $0.0 }
        let tail = lack.isEmpty ? "" : " — not measured: \(lack.joined(separator: ", "))"
        return dayRow(label, have.joined(separator: sep) + tail)
    }

    /// True when at least one of these readings exists.
    static func some(_ vs: [Double?]) -> Bool { vs.contains { $0?.isFinite == true } }

    // MARK: - v4 · sets

    static func setValue(_ s: ExportSet, _ timed: Bool) -> String {
        if timed { return "\(grp(exact(s.reps))) sec" }
        if SetFormat.isUnloaded(s.weightKg) { return "\(grp(exact(s.reps))) reps" }
        return "\(grp(exact(s.weightKg))) kg × \(grp(exact(s.reps)))"
    }

    /// One side of a set: the value, its effort, then its tags.
    ///
    /// The effort rides DIRECTLY on the value because it is a property of that
    /// set's numbers. Everything else follows one em dash and is comma-separated
    /// — `·` cannot serve, since it already separates the two halves of a
    /// unilateral pair on this same line.
    static func setSide(_ s: ExportSet, _ timed: Bool, _ anyRated: Bool) -> String {
        var effort = ""
        if let r = s.rpe, r.isFinite { effort = " @ \(js(r)) \(Effort.rpeLabel(r))" }
        var tags: [String] = []
        if effort.isEmpty && anyRated && !s.isWarmup && !s.isGhost { tags.append("RPE not reported") }
        if s.isWarmup { tags.append("warm-up") }
        if s.isGhost { tags.append("ghost") }
        if s.dropset == true { tags.append("drop set") }
        // RPE 10 IS the top of the ladder — "Failure, to failure" states one
        // fact twice, so the tag is suppressed when the rating carries the word.
        if s.failure && !s.isWarmup && Effort.rpeLabel(s.rpe).lowercased() != "failure" { tags.append("to failure") }
        if let q = s.quality, let named = SetTags.quality[q] { tags.append(named.label.lowercased()) }
        let tail = tags.isEmpty ? "" : " — \(tags.joined(separator: ", "))"
        return "\(setValue(s, timed))\(effort)\(tail)"
    }

    static func setLine(_ row: SetRow, _ ordinal: String, _ timed: Bool, _ anyRated: Bool) -> String {
        if let s = row.single { return "`\(ordinal)` \(setSide(s, timed, anyRated))" }
        let sides = [
            row.left.map { "L \(setSide($0, timed, anyRated))" },
            row.right.map { "R \(setSide($0, timed, anyRated))" },
        ].compactMap { $0 }
        // The scored figure only where there are genuinely two sides to
        // reconcile. A lone side is a set as logged, and restating it is noise.
        var scored = ""
        if let l = row.left, let r = row.right {
            var weaker = l
            weaker.weightKg = min(l.weightKg, r.weightKg)
            weaker.reps = min(l.reps, r.reps)
            scored = " → scores \(setValue(weaker, timed))"
        }
        return "`\(ordinal)` \(sides.joined(separator: sep))\(scored)"
    }

    /// Every set of one exercise, in order. Warm-ups and ghosts consume no
    /// ordinal — `S1` is the first WORKING set, the rule the app counts by.
    static func exerciseLines(_ ex: ExportExercise) -> [String] {
        let timed = TimedExercise.isTimed(ex.name)
        let anyRated = ex.sets.contains { !$0.isWarmup && !$0.isGhost && $0.rpe?.isFinite == true }
        var working = 0
        return toSetRows(ex.sets).map { row in
            let sides = [row.single, row.left, row.right].compactMap { $0 }
            let warm = sides.contains { $0.isWarmup }
            let ghost = !warm && sides.contains { $0.isGhost }
            var ordinal = "G"
            if warm { ordinal = "W" } else if !ghost { working += 1; ordinal = "S\(working)" }
            return "\(setLine(row, ordinal, timed, anyRated))\(br)"
        }
    }

    /// How a session's sets divide, counted the way each figure is counted.
    struct SetTally { var working = 0; var warmup = 0; var ghost = 0; var failure = 0 }

    static func tallySets(_ session: ExportSession) -> SetTally {
        var t = SetTally()
        for ex in session.exercises {
            for row in toSetRows(ex.sets) {
                let sides = [row.single, row.left, row.right].compactMap { $0 }
                if sides.isEmpty { continue }
                if sides.contains(where: { $0.isWarmup }) { t.warmup += 1; continue }
                if sides.contains(where: { $0.isGhost }) { t.ghost += 1; continue }
                t.working += 1
                // A pair counts once here as everywhere: one side reaching
                // failure is the set reaching failure.
                if sides.contains(where: { $0.failure }) { t.failure += 1 }
            }
        }
        return t
    }

    // MARK: - v4 · readiness, micros, the stack

    /// `Arms/Biceps left`, `Quadriceps` — the soreness name, spelled for a reader.
    static func domsReadable(_ d: ExportDoms) -> String {
        let sub = (d.subRegion?.isEmpty == false) ? "/\(d.subRegion!)" : ""
        let side = d.side == "left" ? " left" : d.side == "right" ? " right" : ""
        return "\(d.muscle)\(sub)\(side)"
    }

    /// `Knee left`, `Wrist right: tight after pressing`.
    ///
    /// The note hangs off a COLON and not an em dash: the readiness row already
    /// divides its three clauses with ` — `, so a note carrying one would end
    /// the joints clause halfway through itself.
    static func jointReadable(_ j: ExportJoint) -> String {
        let side = j.side == "left" ? " left" : j.side == "right" ? " right" : ""
        let note = phrase(j.note)
        return note.isEmpty ? "\(j.joint)\(side)" : "\(j.joint)\(side): \(note)"
    }

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

    static func microExceptions(_ day: ExportDay) -> [String] {
        var out: [String] = []
        for t in NutrientTargets.all {
            let f = day.nutrientsFood?[t.key]
            let k = day.nutrientsStack?[t.key]
            if f == nil && k == nil { continue }
            let fv = (f?.isFinite == true && f! > 0) ? f! : 0
            let kv = (k?.isFinite == true && k! > 0) ? k! : 0
            let total = fv + kv
            let bad = t.kind == .ceiling ? total > t.target : (t.target > 0 && total < t.target)
            let flag = implausible(t, food: fv, stack: kv)
            if !bad && !flag { continue }
            let over = t.kind == .ceiling ? " (ceiling)" : ""
            let mark = flag ? "⚠ " : ""
            // A doubted figure names the app that wrote most of it — see the
            // TS twin and `dominantSource`.
            let blame = flag ? dominantSource(day.nutrientsFood, t.key) : nil
            let tail = flag ? " — implausible\(blame == nil ? "" : ", \(blame!)")" : ""
            out.append("\(t.label) \(mark)\(grp(exact(total))) / \(grp(exact(t.target))) \(t.unit)\(over)\(tail)")
        }
        return out
    }

    /// A stack item's NAME from the key its log row carries. An item whose key
    /// matches nothing in the protocol falls back to the key rather than
    /// vanishing — the dose still happened.
    static func supplementName(_ protocolItems: [ExportSupplement]?, _ key: String) -> String {
        protocolItems?.first { $0.key == key }?.name ?? key
    }

    /// The muscles a session trained, as a bracketed tag list.
    ///
    /// `[Chest, Upper back, *Triceps*]` — direct work upright, indirect in
    /// italics, because the two are not the same claim: a bench press trains
    /// chest, and it involves triceps. Flattening them would let three sessions
    /// of pressing read as triceps volume.
    ///
    /// Ordered by the CANONICAL landmark order rather than by first appearance,
    /// so two sessions that trained the same muscles tag them in the same order.
    static func sessionTags(_ s: ExportSession) -> String {
        let order = LandmarkMuscle.allCases.map(\.displayName)
        func rank(_ m: String) -> Int { order.firstIndex(of: m) ?? order.count }
        var primary = Set<String>(), secondary = Set<String>()
        for ex in s.exercises {
            for m in ex.primaryMuscles ?? [] { primary.insert(m) }
            for m in ex.secondaryMuscles ?? [] { secondary.insert(m) }
        }
        // A muscle trained directly anywhere in the session is direct for the
        // session, however many other movements only assisted it.
        secondary.subtract(primary)
        let tags = primary.sorted { rank($0) < rank($1) }
            + secondary.sorted { rank($0) < rank($1) }.map { "*\($0)*" }
        return tags.isEmpty ? "" : "[\(tags.joined(separator: ", "))]"
    }

    // MARK: - v4 · the legend and the notes

    static func legendLines() -> [String] {
        let ladder = Effort.ladder.map { "\(js($0.value)) \($0.label) *(\($0.hint))*" }.joined(separator: sep)
        return [
            "## LEGEND",
            "",
            "**RPE** — how many reps were left at the end of the set.\(br)",
            "\(ladder)\(br)",
            "Session sRPE uses Borg CR10, the same scale at session level: "
                + "1 Very light, 5 Hard, 7 Very hard, 10 Maximal.",
            "",
            "**Set counts** — `sets logged` includes warm-ups and ghosts; `working` excludes both. "
                + "Tonnage INCLUDES warm-ups and EXCLUDES ghosts — a warm-up is work that was done and "
                + "a ghost is work that was not. Set numbers skip both: `S1` is the first working set.",
            "",
            "**Set marks** — `W` warm-up · `G` ghost, planned and not performed · `drop set` · "
                + "`to failure` · a trailing word is the reported set quality.",
            "",
            "**Muscle tags** — a session heading names the landmarks it trained: upright for direct "
                + "work, *italic* for a muscle the movement only assists.\(br)",
            "A movement outside the exercise dictionary contributes no tag rather than its own name.",
            "",
            "**rest** — `120 s plan` is the prescription. `(avg 118 s actual)` is MEASURED: the mean "
                + "gap between committing that movement's sets, recorded by the logger on the phone.\(br)",
            "It is absent on every session logged before the measurement existed, and on anything "
                + "committed from the web — which has no stopwatch.",
            "",
            "**(order: logged sequence)** — the movements are printed in the order they were logged "
                + "because the session carried no deck index.\(br)",
            "Usually the order they were performed in; not guaranteed, which is why it is marked.",
            "",
            "**Sets by muscle** — a set credits 1.0 to each muscle the movement trains directly and "
                + "0.5 to each it assists. Per-muscle tonnage does NOT sum to the week’s total: a "
                + "compound lift is counted once against every muscle it trains.",
            "",
            "**Soreness** — 0–3, logged per muscle and per side, with the session it is attributed to.\(br)",
            "**Stress** — self-reported psychological stress, 1 Relaxed to 5 Swamped, with what it was about.\(br)",
            "**Fatigue** — 1–5, three times a day. Reported, never scored.",
            "",
            "**Derived** — computed by Onyx, not measured. tdee = BMR (from the scale, carried across "
                + "gaps) + Apple Watch active energy + intake × \(js(Energy.tefFactor)). load = session RPE × minutes. "
                + "acwr = EWMA 7:28 of load. strainZ = z of Foster strain against your own rolling normal. "
                + "wellness = mean of the answered Hooper items, 0–1.",
            "",
            "**\"\(noData)\" / \"\(none)\"** — the reading was never recorded. It is never a zero.\(br)",
            "A row states the readings it has and names the rest after **not measured:**. A row with "
                + "nothing in it at all is dropped, and named in that day’s closing **Not recorded:** line. "
                + "Nothing is ever silently omitted.",
        ]
    }

    /// Verbatim, and last. Each is a fact about how a number was ARRIVED AT,
    /// which no single line can carry and which a reader who has not been told
    /// gets wrong in a specific, predictable way. Asserted byte for byte by
    /// `export-layout.test.ts`.
    public static let notes: [String] = [
        "Note: Unilateral (single-arm / single-leg) work is logged per side and scored ONCE at the WEAKER side: min(weight) × min(reps). ‘L 5 kg × 10 · R 5 kg × 14’ is 50 kg of volume, not 70 and not 100 — crediting the strong side’s extra reps to the weak one would inflate the trend without the work being there, and doubling it would make the same physical set weigh twice as much purely for having been recorded per side. Each side keeps its own failure tag, and the pair counts as ONE set.",
        "Note: every ‘1RM’ here is an ESTIMATE from the Epley formula (weight × (1 + reps/30)), not a lift that was performed. Hevy estimates it differently, so the two will not agree exactly. Unloaded work has no 1RM estimate at all and shows none.",
        "Note: Heart rate, calories, and steps data are sourced from the Apple Watch and may not be entirely accurate.",
        "Note: Week 7 report is provided manually for reference and comparison.",
    ]

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

    /// `Knee@L` or `Wrist@R:tight after pressing`. Absence is the "no".
    static func jointToken(_ j: ExportJoint) -> String {
        let side = j.side == "left" ? "@L" : j.side == "right" ? "@R" : ""
        let note = phrase(j.note)
        return note.isEmpty ? "\(j.joint)\(side)" : "\(j.joint)\(side):\(note)"
    }

    /// `s.replace(/:+$/, '')` — a DOMS token drops the parts nothing filled.
    static func stripTrailingColons(_ s: String) -> String {
        var t = Substring(s)
        while t.last == ":" { t = t.dropLast() }
        return String(t)
    }

    // MARK: - The document

    public static func build(_ input: WeeklyExportInput) -> String {
        let days = input.days
        let sessions = input.sessions
        let cardio = input.cardio ?? []
        let bodyComp = input.bodyComp ?? []
        var L: [String] = []

        // ── HEADER ────────────────────────────────────────────────────────────
        let rawLabel = input.weekLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = rawLabel.isEmpty ? "WEEK" : rawLabel
        let phase = input.phaseLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        L.append("# ONYX · \(label.uppercased())")
        L.append(line([
            "\(input.weekStart) → \(input.weekEnd)",
            input.programLabel,
            phase.isEmpty ? nil : phase,
            sessions.isEmpty ? "no sessions" : "\(sessions.count) session\(sessions.count == 1 ? "" : "s")",
            "\(days.count) day\(days.count == 1 ? "" : "s")",
        ]))

        // ── THE WEEK ──────────────────────────────────────────────────────────
        let periods = input.targetPeriods ?? []
        let totals = trendTotals(days: days, sessions: sessions, cardio: cardio)
        let weekly = summary(input)
        let energy = energyBalance(days)
        let weights = days.compactMap { $0.weightKg?.isFinite == true ? $0.weightKg : nil }

        func rungGoals(_ p: TargetPeriod) -> String {
            let g = p.goals
            return line([
                "\(val(g.calorie) ?? noData) kcal",
                "\(val(g.protein) ?? noData) P / \(val(g.carbs) ?? noData) C / \(val(g.fat) ?? noData) F",
                "\(val(g.steps) ?? noData) steps",
            ])
        }

        L.append("")
        L.append("## THE WEEK")
        L.append("")
        // A week under ONE rung states it here, numbers and all — a bulleted
        // list of a single item repeats the line above it. A week under more
        // than one cannot: naming one would be a claim about the days the other
        // governed, so the count goes here and the runs below.
        let leverCell: String
        if periods.count == 1 {
            leverCell = "**Lever** \(periods[0].label) — \(rungGoals(periods[0]))"
        } else if periods.count > 1 {
            leverCell = "**Levers** \(periods.count) rungs this week"
        } else {
            leverCell = "**Lever** \(noData)"
        }
        L.append(line([
            "**Plan** \(input.programLabel)",
            "**Phase** \(phase.isEmpty ? noData : phase)",
            leverCell,
        ]) + br)
        if periods.count > 1 {
            for p in periods {
                let span = p.dates.isEmpty ? noData
                    : "\(dayOfMonth(p.dates[0])) → \(dayOfMonth(p.dates[p.dates.count - 1]))"
                L.append("- **\(p.label)** — \(line([rungGoals(p), span]))")
            }
        }
        L.append("")
        L.append("**Standing goals** " + line([
            val(input.calorieGoal).map { "\($0) kcal" } ?? "\(noData) kcal",
            "\(val(input.proteinGoalG) ?? noData) P",
            "\(val(input.stepsGoal) ?? noData) steps",
            "\(val(input.sleepGoalHours, 1) ?? noData) h sleep",
            "\(val(input.waterGoalMl) ?? noData) ml water",
        ]))

        L.append("")
        L.append("**Training** " + line([
            "\(valExact(totals.totalVolumeKg) ?? noData) kg",
            "\(weekly.workingSets) working sets, \(weekly.ratedSets) rated",
            "\(sessions.count) session\(sessions.count == 1 ? "" : "s")",
            weekly.avgSessionRpe == nil ? "sRPE not reported"
                : "sRPE \(val(weekly.avgSessionRpe, 1) ?? noData) avg over \(weekly.ratedSessions)",
        ]) + br)
        /* The week's training at a glance, one session per entry.
           Answering "what did this week actually train" meant reading seven day
           blocks and collecting the headings out of them. The index states it
           once, in session order, with the same tags each header carries.

           The tags ride on their label with a SPACE and `·` separates one
           session from the next: joining both with `·` made the line ambiguous,
           and a session with no tags read as a stray label. */
        if !sessions.isEmpty {
            L.append("**Sessions** " + sessions.map { s -> String in
                let tags = sessionTags(s)
                let number = s.sessionNumber == nil ? "" : "#\(n(s.sessionNumber)) "
                return "\(number)\(s.label)" + (tags.isEmpty ? "" : " \(tags)")
            }.joined(separator: sep) + br)
        }
        L.append("**Cardio** " + (cardio.isEmpty ? none : line([
            "\(val(weekly.cardioMinutes, 1) ?? noData) min",
            "\(val(weekly.cardioActiveKcal) ?? noData) kcal",
            "\(weekly.cardioSessions) bout\(weekly.cardioSessions == 1 ? "" : "s")",
        ])) + br)
        L.append("**Intake** " + line([
            val(totals.avgKcal).map { "\($0) kcal/day" } ?? "\(noData) kcal/day",
            "\(val(meanOf(days.map { $0.proteinG })) ?? noData) P",
            "\(val(meanOf(days.map { $0.carbsG })) ?? noData) C",
            "\(val(meanOf(days.map { $0.fatG })) ?? noData) F",
            "\(val(totals.avgWaterMl.map { $0 / 1000 }, 2) ?? noData) L water",
        ]) + br)
        L.append("**Activity** " + (val(totals.avgSteps).map { "\($0) steps/day" } ?? "steps \(noData)") + br)
        L.append("**Sleep** " + line([
            weekly.avgSleepMin == nil ? noData : "\(hm(weekly.avgSleepMin)!)/day",
            stat("RHR", weekly.avgRestingHr, "", 1),
            stat("HRV", weekly.avgHrvMs, " ms", 1),
        ]) + br)
        if weights.isEmpty {
            L.append("**Body** no weigh-in this week")
        } else {
            L.append("**Body** " + line([
                "\(val(totals.avgWeightKg, 2) ?? noData) kg avg",
                weights.count > 1
                    ? "\(val(weights[0], 1)!) → \(val(weights[weights.count - 1], 1)!) kg (\(signed(weights[weights.count - 1] - weights[0], 2)!) kg)"
                    : "one weigh-in",
            ]))
        }

        // ── ENERGY BALANCE ────────────────────────────────────────────────────
        // Labelled as computed ON THE LINE. v3 kept a document-level fence;
        // day-major layout cannot, so the marker travels with the figure.
        L.append("")
        if energy.daysCounted > 0 {
            let excluded = days.map { $0.date }.filter { !energy.countedDates.contains($0) }
            L.append("**Energy balance** " + line([
                "\(signed(energy.balanceKcal, 0) ?? noData) kcal over the week",
                "\(signed(energy.avgBalanceKcal, 0) ?? noData) kcal/day",
            ]) + " — *computed by Onyx, an estimate*" + br)
            L.append(line([
                "TDEE \(val(energy.expenditureKcal.map { $0 / Double(energy.daysCounted) }) ?? noData)/day"
                    + " = BMR \(val(energy.avgBmrKcal) ?? noData)"
                    + " + Apple Watch active \(val(energy.avgActiveKcal) ?? noData)"
                    + " + TEF \(val(energy.avgTefKcal) ?? noData) (intake × \(js(Energy.tefFactor)))",
                "\(energy.daysCounted) day\(energy.daysCounted == 1 ? "" : "s") counted",
                energy.bmrCarried ? "BMR carried across the days with no weigh-in" : nil,
                excluded.isEmpty ? nil : "excluded \(excluded.joined(separator: ", "))",
            ]))
        } else {
            L.append("**Energy balance** \(noData) — no day carried both an intake and an expenditure.")
        }

        // ── SETS BY MUSCLE ────────────────────────────────────────────────────
        if !input.volumeByMuscle.isEmpty || !(input.tonnageByMuscle ?? []).isEmpty {
            var tonnage: [String: TonnageByMuscle] = [:]
            for t in input.tonnageByMuscle ?? [] where tonnage[t.muscle] == nil { tonnage[t.muscle] = t }
            var muscles: [String] = []
            for v in input.volumeByMuscle where !muscles.contains(v.muscle) { muscles.append(v.muscle) }
            for t in input.tonnageByMuscle ?? [] where !muscles.contains(t.muscle) { muscles.append(t.muscle) }
            L.append("")
            L.append("### Sets by muscle")
            L.append("")
            let body: [[String]] = muscles.map { muscle in
                let v = input.volumeByMuscle.first { $0.muscle == muscle }
                let t = tonnage[muscle]
                // No target is not a target of zero: `Adductors` genuinely
                // carries 0 on a cut, and a muscle the plan never named carries
                // none at all.
                let delta = (v != nil && v!.target > 0) ? (signed(v!.sets - v!.target, 1) ?? dash) : dash
                let target = v == nil ? dash : (v!.target > 0 ? (val(v!.target, 1) ?? dash) : "none")
                return [
                    muscle,
                    val(v?.sets, 1) ?? dash,
                    target,
                    delta,
                    val(v?.directSets, 1) ?? dash,
                    val(v?.indirectSets, 1) ?? dash,
                    valExact(t?.volumeKg) ?? dash,
                ]
            }
            L.append(contentsOf: markdownTable(
                header: ["Muscle", "Sets", "Target", "Δ", "Direct", "Indirect", "Tonnage kg"],
                body: body,
                align: [.left, .right, .right, .right, .right, .right, .right]))
        }

        // ── BODY COMPOSITION ──────────────────────────────────────────────────
        // Every compartment in ABSOLUTE kg beside its percentage. A percentage
        // of a falling bodyweight can rise while the tissue shrinks.
        if !bodyComp.isEmpty {
            L.append("")
            L.append("### Body composition")
            L.append("")
            let body: [[String]] = bodyComp.map { b in
                [
                    dayOfMonth(b.date),
                    val(b.weightKg, 1) ?? dash, val(b.bmi, 1) ?? dash,
                    val(b.bodyFatPct, 1) ?? dash, val(b.fatMassKg, 1) ?? dash,
                    val(b.musclePercent, 1) ?? dash, val(b.muscleMassKg, 1) ?? dash,
                    val(b.skeletalMuscleMassKg, 1) ?? dash, val(b.fatFreeMassKg, 1) ?? dash,
                    val(b.waterPercent, 1) ?? dash, val(b.waterMassKg, 1) ?? dash,
                    val(b.proteinPercent, 1) ?? dash, val(b.proteinMassKg, 1) ?? dash,
                    val(b.boneMineralKg, 2) ?? dash, val(b.visceralFat, 1) ?? dash,
                    val(b.bmr) ?? dash, val(b.estimatedWaistToHipRatio, 2) ?? dash,
                ]
            }
            L.append(contentsOf: markdownTable(
                header: ["Date", "Weight", "BMI", "Fat %", "Fat kg", "Muscle %", "Muscle kg", "SMM", "FFM",
                         "Water %", "Water kg", "Protein %", "Protein kg", "Bone kg", "Visceral", "BMR", "WHR"],
                body: body,
                align: [.left] + Array(repeating: Align.right, count: 16)))
            let noWeighIn = days.filter { d in !bodyComp.contains { $0.date == d.date } }
            if !noWeighIn.isEmpty {
                L.append("")
                L.append("*No weigh-in: " + noWeighIn
                    .map { "\(dayOfMonth($0.date)) — \(WeighIn.skipReason($0.weighInSkipReason))" }
                    .joined(separator: sep) + ".*")
            }
        }

        // ── MICRONUTRIENTS ────────────────────────────────────────────────────
        let micros = weeklyNutrients(days)
        if !micros.isEmpty {
            L.append("")
            L.append("### Micronutrients — weekly average vs target")
            L.append("")
            let body: [[String]] = micros.map { m in
                [
                    m.kind == .ceiling ? "\(m.label) (ceiling)" : m.label,
                    m.days == 0 ? dash : (val(m.food, microDp(m.food)) ?? dash),
                    m.days == 0 ? dash : (val(m.stack, microDp(m.stack)) ?? dash),
                    m.days == 0 ? dash : (val(m.total, microDp(m.total)) ?? dash),
                    "\(valExact(m.target) ?? dash) \(m.unit)",
                    m.pct == nil ? dash : "\(val(m.pct) ?? dash) %",
                    // The denominator, and what was thrown out of it. `4 of 6`
                    // says more than `4` where two days were discarded.
                    m.excluded > 0 ? "\(m.days) of \(m.days + m.excluded) ⚠" : String(m.days),
                ]
            }
            L.append(contentsOf: markdownTable(
                header: ["Nutrient", "Food", "Stack", "Total", "Target", "%", "Days"],
                body: body,
                align: [.left, .right, .right, .right, .right, .right, .right]))
            L.append("")
            L.append("*Averaged over the days that carried a reading, not over seven. "
                + "A day whose figure the document judged implausible for the intake logged beside it "
                + "is EXCLUDED from the mean and counted after the ⚠ — it is treated as unmeasured, "
                + "not as a day that went badly.*")
        }

        // ── THE STACK ─────────────────────────────────────────────────────────
        // What the protocol ASKS for. What was taken rides on each day.
        let supps = consolidateSupplements(input.supplementProtocol ?? [])
        if !supps.isEmpty {
            L.append("")
            L.append("### The stack")
            L.append("")
            for s in supps { L.append("- \(s)") }
        }

        /* ── WEEK OVER WEEK IS GONE, DELIBERATELY (v4.1) ──────────────────
           v4 closed `THE WEEK` with a `### Week over week` table of every prior
           week and a `**vs the previous week**` delta paragraph. Both are
           removed: the document is now strictly about the week on its cover.

           Not because they were wrong — they were correct, and `Derived.week`
           still computes the deltas for the surfaces that show trends. Because
           this document has ONE consumer, a person pasting a week into a chat
           window, and a comparison table invites every reading of that week to
           be a reading of the trend instead. A −40 % volume line at the top of a
           deload reads as a collapse; the same week read alone reads as the
           deload it was planned to be.

           `Derived.week` is still called — the per-day battery and TDEE need it.
           `LedgerWeek` and `input.ledger` stay on the payload: `Derived` reads
           the ledger for the previous week's totals in the energy balance. */
        let derived = Derived.week(input)

        // ── ONE SESSION, WHEREVER IT BELONGS ──────────────────────────────────
        // Extracted because a session can land in two places: normally inside
        // its day, but a payload can carry one on a date the `days` array does
        // not cover, and a day-major document would then drop a whole workout.
        func pushSession(_ s: ExportSession) {
            let t = tallySets(s)
            L.append("")
            let tags = sessionTags(s)
            // The order the movements are printed in is a CLAIM, and only as
            // good as `exercise_order`. Where that was null the builder fell
            // back to logged sequence — usually right, not guaranteed.
            let orderNote = s.orderSource == "logged" ? " *(order: logged sequence)*" : ""
            L.append("### Session\(s.sessionNumber == nil ? "" : " #\(n(s.sessionNumber))") · \(s.label)"
                + (tags.isEmpty ? "" : " · \(tags)") + orderNote)
            L.append(line([
                (s.startedAt != nil || s.endedAt != nil)
                    ? "\(s.startedAt == nil ? noData : clock(s.startedAt)) → \(s.endedAt == nil ? noData : clock(s.endedAt))"
                    : "start \(noData)",
                val(s.durationMin).map { "\($0) min" } ?? "\(noData)",
                s.avgBpm == nil ? "avg HR \(noData)"
                    : "avg \(val(s.avgBpm) ?? noData) bpm\(s.avgBpmEstimated == true ? " *(estimated)*" : "")",
                s.caloriesBurned == nil ? "\(noData) kcal"
                    : "\(val(s.caloriesBurned) ?? noData) kcal\(s.caloriesEstimated == true ? " *(estimated)*" : "")",
                s.sessionRpe == nil ? "sRPE not reported"
                    : "sRPE \(js(s.sessionRpe!)) \(Effort.cr10Label(s.sessionRpe))",
            ]) + br)
            /* Every figure on this line comes from `tallySets`, over the same
               rows printed below it. `workout_sessions.set_count` counts
               committed rows INCLUDING warm-ups, which is right for the ledger
               and the wrong number to print above a list the reader can count —
               where the two disagree the document would state one total and
               then show another. The stored count is the fallback for a session
               that carries no exercises at all. */
            let logged = s.exercises.isEmpty ? Int(s.setCount ?? 0) : t.working + t.warmup + t.ghost
            L.append(line([
                "\(logged) sets logged",
                "\(t.working) working",
                t.warmup > 0 ? "\(t.warmup) warm-up" : nil,
                t.ghost > 0 ? "\(t.ghost) ghost" : nil,
                "\(t.failure) to failure",
                "\(valExact(s.volumeKg) ?? noData) kg tonnage",
                "\(s.prs.count) PR\(s.prs.count == 1 ? "" : "s")",
            ]))
            for ex in s.exercises {
                L.append("")
                let restCell: String
                // One parenthesis, never two. An overridden target reads as prose
                // so the measurement can keep the brackets to itself.
                let planCell: String? = ex.restTargetSec == nil ? nil
                    : (ex.restTargetSec == ex.restPlanSec
                        ? "rest \(val(ex.restTargetSec) ?? noData) s plan"
                        : "rest \(val(ex.restTargetSec) ?? noData) s plan, programme \(val(ex.restPlanSec) ?? noData)")
                let actualCell: String? = ex.restActualSec == nil
                    ? nil : "avg \(val(ex.restActualSec) ?? noData) s actual"
                if let planCell {
                    restCell = actualCell == nil ? planCell : "\(planCell) (\(actualCell!))"
                } else if let actualCell {
                    restCell = "rest no plan (\(actualCell))"
                } else {
                    restCell = "rest \(noData)"
                }
                let topCell: String
                if let top = ex.topKg {
                    topCell = SetFormat.isUnloaded(top) ? "bodyweight" : "top \(valExact(top) ?? noData) kg"
                } else {
                    topCell = "top \(noData)"
                }
                L.append("**\(ex.name)** · " + line([
                    (ex.repWindow?.isEmpty == false) ? "target \(ex.repWindow!) reps" : "target \(noData)",
                    restCell,
                    topCell,
                    ex.sets.isEmpty ? "**no sets logged**" : nil,
                ]) + (ex.sets.isEmpty ? "" : br))
                L.append(contentsOf: exerciseLines(ex))
            }
            if !s.prs.isEmpty {
                L.append("")
                L.append("**PRs**")
                for p in s.prs {
                    let lift: String
                    if TimedExercise.isTimed(p.name) {
                        lift = "\(grp(exact(p.reps))) sec"
                    } else if SetFormat.isUnloaded(p.weightKg) {
                        lift = "\(grp(exact(p.reps))) reps"
                    } else {
                        lift = "\(grp(exact(p.weightKg))) kg × \(grp(exact(p.reps)))"
                    }
                    L.append("- " + line([
                        "\(p.name) \(lift)",
                        p.axes.isEmpty ? nil : p.axes.map { PrEngine.axisLabel($0) }.joined(separator: ", "),
                        p.volumeKg == nil ? nil : "\(valExact(p.volumeKg) ?? noData) kg volume",
                        // An unloaded lift has no estimate at all, and says so
                        // rather than printing a dash a reader takes for a gap.
                        p.e1rmKg == nil ? "no 1RM estimate (unloaded)" : "e1RM \(valExact(p.e1rmKg) ?? noData) kg",
                    ]))
                }
            }
        }

        // ── THE DAYS ──────────────────────────────────────────────────────────
        var bodyByDate: [String: ExportBodyComp] = [:]
        for b in bodyComp where bodyByDate[b.date] == nil { bodyByDate[b.date] = b }
        var batteryByDate: [String: BatteryDay] = [:]
        for b in derived.battery where batteryByDate[b.date] == nil { batteryByDate[b.date] = b }
        let bmrs = bmrCarry(days)

        for (index, day) in days.enumerated() {
            let sessionsToday = sessions.filter { $0.date == day.date }
            let cardioToday = cardio.filter { $0.date == day.date }
            let bc = bodyByDate[day.date]

            L.append("")
            L.append("---")
            L.append("")
            /* The heading carries the WEEKDAY, the ISO DATE and what the day was
               for. The date is spelled in full rather than as "30 Aug": every
               other date in this document is ISO, and a friendly date with no
               year makes the reader infer one. */
            let what = day.isTrainingDay ? "TRAIN" : "REST"
            let labels = sessionsToday.isEmpty ? "" : " — " + sessionsToday.map { $0.label }.joined(separator: " + ")
            L.append("## DAY \(index + 1) · \(day.weekdayLabel) · \(day.date) · \(what)\(labels)")
            L.append("")

            var missing: [String] = []
            func put(_ name: String, _ row: String?) {
                if let row { L.append(row) } else { missing.append(name) }
            }

            // SLEEP
            // The two self-reported flags live INSIDE this row, and the row used
            // to be gated on a duration existing — so a night the watch missed
            // took the wearer's own "trouble falling asleep" down with it.
            let hasSleep = some([day.sleepMin, day.deepMin, day.remMin])
                || day.bedTime != nil || day.wakeTime != nil
                || day.sleepOnsetTrouble == true || day.sleepInaccurate == true
            put("sleep", hasSleep ? dayRow("Sleep", line([
                hm(day.sleepMin) ?? "no duration recorded",
                some([day.deepMin, day.remMin, day.coreMin, day.awakeMin])
                    ? "deep \(hm(day.deepMin) ?? noData) · REM \(hm(day.remMin) ?? noData)"
                        + " · core \(hm(day.coreMin) ?? noData) · awake \(hm(day.awakeMin) ?? noData)"
                    : nil,
                (day.bedTime != nil || day.wakeTime != nil)
                    ? "\(clock(day.bedTime)) → \(clock(day.wakeTime))" : nil,
                // Only the flag, never its absence — see the TS twin.
                day.sleepOnsetTrouble == true ? "trouble falling asleep" : nil,
                day.sleepInaccurate == true ? "⚠ the wearer disputes this night" : nil,
            ])) : nil)

            // VITALS
            put("vitals", partialRow("Vitals", [
                ("HRV", val(day.hrvMs, 1).map { "HRV \($0) ms" }),
                ("RHR", val(day.restingHr).map { "RHR \($0)" }),
                ("avg HR", val(day.avgHr).map { "avg HR \($0)" }),
                ("SpO₂", val(day.bloodOxygenPct).map { "SpO₂ \($0) %" }),
                ("respiratory rate", val(day.respiratoryRate, 1).map { "resp \($0) /min" }),
                // The SIGN is the finding: +0.2 °C and −0.2 °C are opposites.
                ("wrist temp", signed(day.wristTempDeltaC).map { "wrist temp \($0) °C" }),
                ("VO₂max", val(day.vo2max, 1).map { "VO₂max \($0)" }),
            ]))

            // BODY
            func both(_ word: String, _ pct: Double?, _ kg: Double?, _ dp: Int = 1) -> String? {
                if pct == nil && kg == nil { return nil }
                if pct == nil { return "\(word) \(val(kg, dp) ?? noData) kg" }
                if kg == nil { return "\(word) \(val(pct, 1) ?? noData) %" }
                return "\(word) \(val(pct, 1) ?? noData) % (\(val(kg, dp) ?? noData) kg)"
            }
            let bodyRowLine: String?
            if let bc {
                bodyRowLine = partialRow("Body", [
                    ("weight", (val(bc.weightKg, 1) ?? val(day.weightKg, 1)).map { "\($0) kg" }),
                    ("body fat", both("BF", bc.bodyFatPct, bc.fatMassKg)),
                    ("muscle", both("muscle", bc.musclePercent, bc.muscleMassKg)),
                    ("skeletal muscle", val(bc.skeletalMuscleMassKg, 1).map { "SMM \($0) kg" }),
                    ("fat-free mass", val(bc.fatFreeMassKg, 1).map { "FFM \($0) kg" }),
                    ("water", both("water", bc.waterPercent, bc.waterMassKg)),
                    ("protein", both("protein", bc.proteinPercent, bc.proteinMassKg)),
                    ("bone", val(bc.boneMineralKg, 2).map { "bone \($0) kg" }),
                    ("visceral fat", val(bc.visceralFat, 1).map { "visceral \($0)" }),
                    ("BMI", val(bc.bmi, 1).map { "BMI \($0)" }),
                    ("waist-to-hip", val(bc.estimatedWaistToHipRatio, 2).map { "WHR \($0)" }),
                    ("BMR", val(bc.bmr).map { "BMR \($0) kcal" }),
                ])
            } else if day.weightKg != nil {
                bodyRowLine = dayRow("Body", line(["\(val(day.weightKg, 1)!) kg", stat("BMR", day.bmrKcal, " kcal")]))
            } else {
                // The reason, not a blank. A skipped weigh-in with no stored
                // reason resolves to the protocol default, not to "unknown".
                let carried: String? = day.bmrKcal != nil
                    ? stat("BMR", day.bmrKcal, " kcal")
                    : (bmrs[index] != nil ? "BMR \(val(bmrs[index])!) kcal *(carried)*" : nil)
                bodyRowLine = dayRow("Body", line([
                    "no weigh-in — \(WeighIn.skipReason(day.weighInSkipReason))",
                    carried,
                ]))
            }
            put("body composition", bodyRowLine)

            // READINESS
            let fatigueCells = fatigueLabels(isTrainingDay: day.isTrainingDay).map { slot -> String in
                let hit = (input.fatigue ?? []).first { $0.date == day.date && $0.slot == slot }
                return "\(slot.lowercased()) \(hit == nil ? noData : "\(n(hit!.level)) \(hit!.label)")"
            }
            let domsCells = input.doms.filter { $0.date == day.date }.map { x -> String in
                var from = ""
                if let src = x.sourceLabel, !src.isEmpty {
                    let when = (x.sourceDate?.isEmpty == false) ? ", \(dayOfMonth(x.sourceDate!))" : ""
                    from = " *(from \(src)\(when))*"
                }
                return "\(domsReadable(x)) \(n(x.severity))\(from)"
            }
            let jointCells = (input.joints ?? []).filter { $0.date == day.date }.map(jointReadable)
            put("readiness", dayRow("Readiness", [
                "fatigue \(fatigueCells.joined(separator: sep))",
                "DOMS \(domsCells.isEmpty ? none : domsCells.joined(separator: sep))",
                "joints \(jointCells.isEmpty ? none : jointCells.joined(separator: sep))",
            ].joined(separator: " — ")))

            // HEAD
            let headCells = (input.stress ?? []).filter { $0.date == day.date }.map { h -> String in
                let tags = (h.tags?.isEmpty == false) ? " — \(h.tags!.joined(separator: ", "))" : ""
                let note = phrase(h.note)
                return "\(h.slot) \(n(h.level)) \(h.label)\(tags)\(note.isEmpty ? "" : " — “\(note)”")"
            }
            put("stress", dayRow("Stress", headCells.isEmpty ? noData : headCells.joined(separator: sep)))

            // INTAKE
            // The rung in force ON THIS DAY, not the goal row as it stands
            // today: a lever pulled on Wednesday does not re-target Sunday.
            func goalOf(_ pick: (LeverGoals) -> Double?) -> Double? {
                guard let p = periods.first(where: { $0.dates.contains(day.date) }) else { return nil }
                return pick(p.goals)
            }
            // A macro the day was NOT graded on prints its figure and says so.
            // A target inherited from the rung would invent a miss out of a
            // restaurant meal.
            func macro(_ what: String, _ got: Double?, _ goal: Double?, _ tracked: Bool? = nil) -> String {
                if tracked == false { return "\(val(got) ?? noData) \(what) *(not tracked)*" }
                if goal == nil { return "\(val(got) ?? noData) \(what)" }
                return "\(val(got) ?? noData) / \(val(goal) ?? noData) \(what)"
            }
            let hasIntake = some([day.calories, day.proteinG, day.carbsG, day.fatG, day.waterMl])
            put("intake", hasIntake ? dayRow("Intake", line([
                macro("kcal", day.calories, goalOf { $0.calorie } ?? input.calorieGoal),
                macro("P", day.proteinG, goalOf { $0.protein } ?? input.proteinGoalG),
                macro("C", day.carbsG, goalOf { $0.carbs }, day.trackCarbs),
                macro("F", day.fatG, goalOf { $0.fat }, day.trackFat),
                "water \(val(day.waterMl.map { $0 / 1000 }, 2) ?? noData)"
                    + " / \(val(input.waterGoalMl.map { $0 / 1000 }, 2) ?? noData) L",
            ])) : nil)

            // MICROS — the exceptions only. The full picture is the table above.
            let hasMicros = !(day.nutrientsFood?.isEmpty ?? true) || !(day.nutrientsStack?.isEmpty ?? true)
            let exceptions = microExceptions(day)
            put("micronutrients", hasMicros
                ? dayRow("Micros", exceptions.isEmpty
                    ? "every logged key on or above target"
                    : exceptions.joined(separator: sep))
                : nil)

            // STACK
            let taken = (day.supplementsLog ?? []).map { s -> String in
                "\(supplementName(input.supplementProtocol, s.key))\(s.time == nil ? "" : " \(s.time!)")"
            }
            /* ── THE STACK, ON THREE LINES ────────────────────────────────
               v4 joined the count and both lists onto ONE row with ` — `, so a
               nine-item protocol produced a paragraph the reader had to parse to
               find the one item that was refused. Each clause is its own line
               now, the two lists indented under the count.

               The skipped line distinguishes the two kinds of refusal:
                 · `(planned)` — the protocol asked for it and it was declined.
                 · `(not scheduled this day — logged anyway)` — the day's
                   resolved schedule does not name it, but a refusal was logged.
                   A day swapped Train↔Rest after the fact, or an item archived
                   mid-week. v4 silently DROPPED these. */
            let skipped = day.supplementsSkipped ?? []
            let skippedOff = day.supplementsSkippedUnplanned ?? []
            let later = day.supplementsLater ?? []
            let countCell: String?
            if day.supplementsTaken != nil && day.supplementsPlanned != nil {
                countCell = line([
                    "\(val(day.supplementsTaken)!) of \(val(day.supplementsPlanned)!) scheduled",
                    // Omitted when zero, which for a closed week is always.
                    later.isEmpty ? nil : "\(later.count) still ahead",
                    (skipped.count + skippedOff.count) == 0
                        ? nil : "\(skipped.count + skippedOff.count) skipped",
                ])
            } else if day.supplementsPlanned != nil {
                countCell = "\(val(day.supplementsPlanned)!) planned, ticks \(noData)"
            } else if day.supplementsTaken != nil {
                countCell = "\(val(day.supplementsTaken)!) taken"
            } else {
                countCell = nil
            }
            let hasStack = some([day.supplementsTaken, day.supplementsPlanned])
                || !taken.isEmpty || !skipped.isEmpty || !skippedOff.isEmpty
            let skippedCell = (skipped.map { "\($0) (planned)" }
                + skippedOff.map { "\($0) (not scheduled this day — logged anyway)" })
            let stackRows: [String] = [
                countCell,
                // A missing `supplement_log` row means TAKEN, not skipped —
                // which is why an empty list here cannot say "none". It says
                // the per-item ticks were never written.
                "  **taken** \(taken.isEmpty ? "no per-item log" : taken.joined(separator: sep))",
                "  **skipped** \(skippedCell.isEmpty ? "none logged" : skippedCell.joined(separator: sep))",
            ].compactMap { $0 }
            put("stack", hasStack
                ? stackRows.enumerated().map { i, r in i == 0 ? (dayRow("Stack", r) ?? "") : "\(r)\(br)" }
                    .joined(separator: "\n")
                : nil)

            // ACTIVITY
            put("activity", partialRow("Activity", [
                ("steps", val(day.steps).map { "\($0) steps" }),
                ("distance", val(day.distanceM.map { $0 / 1000 }, 2).map { "\($0) km" }),
                ("exercise minutes", val(day.exerciseMin).map { "exercise \($0) min" }),
                // Two independent measurements, never one `12h58` token.
                ("stand ring", (day.standHours == nil && day.standMin == nil) ? nil
                    : "stand \(val(day.standHours) ?? noData) h (\(val(day.standMin) ?? noData) min)"),
                ("daylight", val(day.daylightMin).map { "daylight \($0) min" }),
                ("active energy", val(day.activeKcal).map { "active \($0) kcal" }),
                ("training minutes", val(day.trainingMin).map { "training \($0) min" }),
            ]))

            // SHAPE — what the day was ASKED for, and what it was not graded on.
            let shape = line([
                (day.targetProfile?.isEmpty == false) ? day.targetProfile! : nil,
                (day.nutritionException?.isEmpty == false) ? "\(day.nutritionException!) — excepted from grading" : nil,
                day.nutritionEstimated ? "intake is an estimate" : nil,
            ])
            // "standard day" is a claim about a day that was LOGGED. On a day
            // the app never heard from it would assert that nothing unusual
            // happened, which an empty record cannot say.
            let shapeBody = shape.isEmpty
                ? (some([day.calories, day.proteinG, day.steps, day.weightKg]) ? "standard day" : "")
                : shape
            put("shape", dayRow("Shape", shapeBody))

            // SESSIONS
            for s in sessionsToday { pushSession(s) }
            if sessionsToday.isEmpty { missing.append("training") }

            // CARDIO
            if !cardioToday.isEmpty {
                L.append("")
                L.append("**Cardio**")
                for c in cardioToday {
                    L.append("- " + line([
                        // A hand-typed row's `created_at` is the instant it was
                        // typed, not a start. Printing 21:00 for an 08:00 walk
                        // is the export inventing one.
                        c.source == "health" ? clock(c.startedAt) : "start \(noData)",
                        "**\(cardioLabel(c.kind))**",
                        "\(val(c.durationMin, 1) ?? noData) min",
                        c.distanceM == nil ? nil : "\(val(c.distanceM.map { $0 / 1000 }, 2) ?? noData) km",
                        c.distanceM == nil ? nil : {
                            let p = CardioMetrics.formatPace(CardioMetrics.paceMinPerKm(distanceM: c.distanceM, durationMin: c.durationMin))
                            return p.isEmpty || p == dash ? nil : p
                        }(),
                        c.elevationM == nil ? nil : "\(signed(c.elevationM, 0) ?? noData) m",
                        stat("avg HR", c.avgHr),
                        // Already inside the day's own active energy — never
                        // add it on top.
                        c.kcal == nil ? nil : "\(val(c.kcal) ?? noData) kcal active"
                            + (c.totalKcal == nil ? "" : " (\(val(c.totalKcal) ?? noData) total)"),
                        c.effort == nil ? nil : "CR10 \(js(c.effort!)) \(Effort.cr10Label(c.effort))",
                        c.source == "health" ? "Apple Watch" : "typed",
                    ]))
                }
            } else { missing.append("cardio") }

            // DERIVED — named as computed, because there is no fence here.
            let battery = batteryByDate[day.date]
            let tdee = Energy.tdee(bmr: bmrs[index], active: day.activeKcal, intakeKcal: day.calories)
            let derivedRow = line([
                stat("load", day.readiness?.load, "", 1),
                stat("ACWR", battery?.acwr ?? day.readiness?.acwr, "", 3),
                "strain z \(signed(battery?.strainZ ?? day.readiness?.strainZ, 2) ?? noData)",
                stat("wellness", battery?.wellness, "", 2),
                stat("TDEE", tdee, " kcal"),
            ])
            if some([day.readiness?.load, battery?.acwr, battery?.strainZ, battery?.wellness, tdee]) {
                L.append("")
                L.append("**Derived** *(computed by Onyx, not measured)* \(derivedRow)")
            } else { missing.append("derived figures") }

            if !missing.isEmpty {
                L.append("")
                L.append("*Not recorded: \(missing.joined(separator: ", ")).*")
            }
        }

        // ── WORK THE DAYS COULD NOT HOLD ──────────────────────────────────────
        // A session or a bout dated outside the `days` array. It should not
        // happen, but a day-major document that silently dropped a whole
        // workout would be strictly worse than v3, which printed every session
        // in one flat section and could not have this bug.
        let dayDates = Set(days.map { $0.date })
        let strandedSessions = sessions.filter { !dayDates.contains($0.date) }
        let strandedCardio = cardio.filter { !dayDates.contains($0.date) }
        if !strandedSessions.isEmpty || !strandedCardio.isEmpty {
            L.append("")
            L.append("---")
            L.append("")
            L.append("## OUTSIDE THE LOGGED DAYS")
            L.append("")
            L.append("*These fall on dates this week has no day record for. They are the "
                + "week’s work and are counted in every total above; they simply have no "
                + "day to sit under.*")
            var seen: [String] = []
            for s in strandedSessions where !seen.contains(s.date) { seen.append(s.date) }
            for date in seen {
                L.append("")
                L.append("**\(date)**\(br)")
                for s in strandedSessions where s.date == date { pushSession(s) }
            }
            for c in strandedCardio {
                L.append("")
                L.append("**\(c.date)** · \(cardioLabel(c.kind)) · \(val(c.durationMin, 1) ?? noData) min")
            }
        }

        // ── LEGEND AND NOTES ──────────────────────────────────────────────────
        L.append("")
        L.append("---")
        L.append("")
        L.append(contentsOf: legendLines())
        L.append("")
        L.append("## NOTES")
        L.append("")
        for note in notes { L.append("- \(note)") }

        return L.joined(separator: "\n")
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
