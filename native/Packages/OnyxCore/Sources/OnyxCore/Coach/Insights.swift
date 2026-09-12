import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The Intellectual Insight Coach — deterministic, zero-model analytics that
// mine real correlations from the recent metrics. A port of
// the web app's `lib/coach/insights.ts`: same data → same insights, strict English, no
// network, no randomness, and every builder stays silent rather than invent a
// pattern from too little data.
// ─────────────────────────────────────────────────────────────────────────────

public struct DayPoint: Codable, Equatable, Sendable {
    public var date: String
    public var sleepMin: Double?
    public var restHr: Double?
    public var respiratory: Double?
    public var weightKg: Double?
    public var calories: Double?
    public var calorieGoal: Double?
    public var carbsG: Double?
    public var steps: Double?
    public var waterMl: Double?
    /// A declared nutrition exception — read by the adherence builder alone.
    public var exception: String?

    public init(date: String, sleepMin: Double? = nil, restHr: Double? = nil, respiratory: Double? = nil, weightKg: Double? = nil, calories: Double? = nil, calorieGoal: Double? = nil, carbsG: Double? = nil, steps: Double? = nil, waterMl: Double? = nil, exception: String? = nil) {
        self.date = date; self.sleepMin = sleepMin; self.restHr = restHr; self.respiratory = respiratory
        self.weightKg = weightKg; self.calories = calories; self.calorieGoal = calorieGoal; self.carbsG = carbsG
        self.steps = steps; self.waterMl = waterMl; self.exception = exception
    }
}

public struct SessionPoint: Codable, Equatable, Sendable {
    public var date: String
    public var volumeKg: Double

    public init(date: String, volumeKg: Double) { self.date = date; self.volumeKg = volumeKg }
}

public enum InsightTone: String, Codable, Sendable { case positive, caution, neutral }

public struct Insight: Codable, Equatable, Sendable {
    public var id: String
    public var headline: String
    public var detail: String
    public var tone: InsightTone
    /// 0–1, used to rank which insights surface.
    public var confidence: Double

    public init(id: String, headline: String, detail: String, tone: InsightTone, confidence: Double) {
        self.id = id; self.headline = headline; self.detail = detail; self.tone = tone; self.confidence = confidence
    }
}

/// `Number.prototype.toLocaleString()` in the en-US default: thousands grouped
/// with commas. The coach only ever formats whole numbers this way.
func jsLocaleString(_ v: Double) -> String {
    let negative = v < 0
    let whole = abs(v).rounded(.towardZero)
    var digits = String(Int64(whole))
    var grouped = ""
    while digits.count > 3 {
        grouped = "," + String(digits.suffix(3)) + grouped
        digits = String(digits.dropLast(3))
    }
    let fraction = abs(v) - whole
    let fractionText = fraction > 0 ? String(jsIntegerString(jsRound(fraction * 1000) / 1000).dropFirst()) : ""
    return (negative ? "-" : "") + digits + grouped + fractionText
}

public enum Insights {
    // MARK: - Math

    /// Mean; 0 for an empty list.
    public static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    /// Pearson correlation, or nil under 4 pairs or with zero variance.
    public static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        let n = Swift.min(xs.count, ys.count)
        if n < 4 { return nil }
        let mx = mean(Array(xs[0..<n])), my = mean(Array(ys[0..<n]))
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<n {
            let a = xs[i] - mx, b = ys[i] - my
            num += a * b; dx += a * a; dy += b * b
        }
        if dx == 0 || dy == 0 { return nil }
        return num / (dx * dy).squareRoot()
    }

    /// Least-squares slope per index, or nil under 3 points.
    public static func linregSlope(_ ys: [Double]) -> Double? {
        let n = ys.count
        if n < 3 { return nil }
        let mx = Double(n - 1) / 2
        let my = mean(ys)
        var num = 0.0, den = 0.0
        for i in 0..<n {
            let a = Double(i) - mx
            num += a * (ys[i] - my); den += a * a
        }
        return den == 0 ? nil : num / den
    }

    static func round(_ n: Double, _ d: Int = 0) -> Double {
        let f = pow(10.0, Double(d))
        return jsRound(n * f) / f
    }

    static func js(_ v: Double) -> String { jsIntegerString(v) }

    /// `Array.prototype.slice(start, end)` with negative indices.
    static func slice<T>(_ a: [T], _ start: Int, _ end: Int? = nil) -> [T] {
        let n = a.count
        func norm(_ i: Int) -> Int { i < 0 ? Swift.max(0, n + i) : Swift.min(i, n) }
        let s = norm(start), e = end.map(norm) ?? n
        return e > s ? Array(a[s..<e]) : []
    }

    /// 7-day rolling average series (oldest → newest).
    public static func rollingAverage(_ values: [Double], window: Int = 7) -> [Double] {
        guard values.count >= window else { return [] }
        return (window - 1..<values.count).map { i in mean(Array(values[(i - window + 1)...i])) }
    }

    // MARK: - Builders

    /// Days since the most recent session, or nil with no sessions at all.
    public static func daysSinceLastSession(_ sessions: [SessionPoint], todayISO: String) -> Double? {
        guard let first = sessions.first else { return nil }
        let last = sessions.dropFirst().reduce(first.date) { $1.date > $0 ? $1.date : $0 }
        guard let a = ISODate.dayNumber(todayISO), let b = ISODate.dayNumber(last) else { return nil }
        return Double(a - b)
    }

    /// Data-gap awareness: a week without training suppresses the volume builders and says so.
    public static func trainingGap(_ sessions: [SessionPoint], todayISO: String) -> Insight? {
        guard let gap = daysSinceLastSession(sessions, todayISO: todayISO) else {
            return Insight(id: "training-gap", headline: "No training history in this window",
                           detail: "Volume and PR comparisons are paused until your first logged session — nothing here is being estimated or invented.",
                           tone: .neutral, confidence: 0.95)
        }
        if gap < 7 { return nil }
        let g = js(gap)
        return Insight(id: "training-gap", headline: "\(g) days since your last session",
                       detail: "Training comparisons are paused — a \(g)-day gap makes week-over-week volume math meaningless. Expect the first session back to feel ~10% heavier than it is; start at re-entry loads and the numbers return within two sessions.",
                       tone: .neutral, confidence: 0.95)
    }

    /// Sleep the night of a session vs that session's training volume.
    static func sleepVsVolume(_ days: [DayPoint], _ sessions: [SessionPoint]) -> Insight? {
        var sleepByDate: [String: Double] = [:]
        for d in days { if let s = d.sleepMin { sleepByDate[d.date] = s } }
        let pairs: [(sleep: Double, vol: Double)] = sessions.compactMap { s in
            guard let sleep = sleepByDate[s.date], s.volumeKg > 0 else { return nil }
            return (sleep, s.volumeKg)
        }
        if pairs.count < 4 { return nil }
        let r = pearson(pairs.map(\.sleep), pairs.map(\.vol))
        let low = pairs.filter { $0.sleep < 390 }
        let high = pairs.filter { $0.sleep >= 450 }
        if low.count >= 2 && high.count >= 2 {
            let lowAvg = mean(low.map(\.vol)), highAvg = mean(high.map(\.vol))
            if highAvg > 0 && lowAvg < highAvg {
                let drop = round((1 - lowAvg / highAvg) * 100)
                if drop >= 8 {
                    return Insight(id: "sleep-volume", headline: "Short sleep is costing you volume",
                                   detail: "After nights under 6.5h you averaged \(jsLocaleString(round(lowAvg))) kg vs \(jsLocaleString(round(highAvg))) kg following 7.5h+ — a \(js(drop))% drop across \(pairs.count) sessions.",
                                   tone: .caution, confidence: Swift.min(0.95, 0.5 + drop / 100))
                }
            }
        }
        if let r, abs(r) >= 0.4 {
            return Insight(id: "sleep-volume", headline: r > 0 ? "Sleep is fuelling your lifts" : "Inverse sleep–volume pattern",
                           detail: "Sleep duration and training volume correlate at r=\(js(round(r, 2))) over \(pairs.count) sessions.",
                           tone: r > 0 ? .positive : .caution, confidence: abs(r))
        }
        return nil
    }

    /// Resting HR (and respiratory rate) trend vs baseline — an early fatigue signal.
    static func recoveryDrift(_ days: [DayPoint]) -> Insight? {
        let hr = days.compactMap(\.restHr)
        if hr.count < 5 { return nil }
        let recent = slice(hr, -3), baseline = slice(hr, 0, -3)
        if baseline.count < 2 { return nil }
        let recentAvg = mean(recent), baseAvg = mean(baseline)
        if baseAvg <= 0 { return nil }
        let pct = round((recentAvg / baseAvg - 1) * 100)

        var respNote = ""
        let resp = days.compactMap(\.respiratory)
        if resp.count >= 5 {
            let rRecent = mean(slice(resp, -3)), rBase = mean(slice(resp, 0, -3))
            if rBase > 0 && rRecent / rBase - 1 >= 0.05 {
                respNote = " Respiratory rate is up too (\(js(round(rBase, 1)))→\(js(round(rRecent, 1))) br/min) — both point the same way."
            }
        }
        if pct >= 4 {
            return Insight(id: "recovery-drift", headline: "Resting HR is creeping up",
                           detail: "Your last 3 days average \(js(round(recentAvg))) bpm vs a \(js(round(baseAvg))) bpm baseline (+\(js(pct))%) — often an early fatigue or under-recovery signal.\(respNote)",
                           tone: .caution, confidence: Swift.min(0.9, 0.5 + pct / 30))
        }
        if pct <= -4 {
            return Insight(id: "recovery-drift", headline: "Recovery is trending well",
                           detail: "Resting HR dropped to \(js(round(recentAvg))) bpm vs a \(js(round(baseAvg))) bpm baseline (\(js(pct))%) — a sign your system is well-recovered.",
                           tone: .positive, confidence: Swift.min(0.85, 0.45 + abs(pct) / 30))
        }
        return nil
    }

    static let adherenceMinDays = 7 - 2

    /// Calorie adherence, this week vs last — only when BOTH windows hold ≥ 5 real days; exceptions drop out first.
    static func calorieAdherence(_ days: [DayPoint]) -> Insight? {
        let ok: [(calories: Double, goal: Double)] = days.compactMap { d in
            guard !ExceptionDay.isException(d.exception), let c = d.calories, c > 0, let g = d.calorieGoal, g != 0, g > 0 else { return nil }
            return (c, g)
        }
        let recent = slice(ok, -7), prior = slice(ok, -14, -7)
        if recent.count < adherenceMinDays || prior.count < adherenceMinDays { return nil }
        func onTarget(_ d: (calories: Double, goal: Double)) -> Bool { abs(d.calories - d.goal) / d.goal <= 0.1 }
        let rPct = round(Double(recent.filter(onTarget).count) / Double(recent.count) * 100)
        let pPct = round(Double(prior.filter(onTarget).count) / Double(prior.count) * 100)
        let delta = rPct - pPct
        if abs(delta) < 12 { return nil }
        return Insight(id: "calorie-adherence", headline: delta > 0 ? "Nutrition discipline is climbing" : "Calorie adherence eased off",
                       detail: "\(js(rPct))% of your last \(recent.count) logged days landed within 10% of your calorie goal, vs \(js(pPct))% over the prior \(prior.count) (\(delta > 0 ? "+" : "")\(js(delta)) percentage points of adherence — an observation, not a score change).",
                       tone: delta > 0 ? .positive : .caution, confidence: Swift.min(0.85, 0.4 + abs(delta) / 100))
    }

    /// The 7-day rolling average, week over week — single days carry no authority.
    static func weightTrend(_ days: [DayPoint], _ sessions: [SessionPoint], contextMode: String?) -> Insight? {
        let w = days.filter { $0.weightKg != nil }
        if w.count < 8 { return nil }
        let weights = w.map { $0.weightKg! }
        let thisWeek = mean(slice(weights, -7))
        let lastWeek = mean(slice(weights, -14, -7))
        if lastWeek == 0 { return nil }
        let wow = round(thisWeek - lastWeek, 2)

        // `days.findLast(d => d.calorieGoal)?.calorieGoal ?? days.at(-1)?.calorieGoal ?? null`
        let goal: Double? = days.last(where: { ($0.calorieGoal ?? 0) != 0 })?.calorieGoal ?? days.last?.calorieGoal
        let phase: String? = goal.map { $0 <= 2050 ? "cut" : $0 < 2450 ? "maintenance" : "bulk" }

        let last3 = Set(slice(w, -3).map(\.date))
        let flagged = contextMode == "travel" || sessions.contains { last3.contains($0.date) && $0.volumeKg > 0 }
        let lastDelta = weights.count >= 2 ? weights[weights.count - 1] - weights[weights.count - 2] : 0
        if flagged && lastDelta > 0 && lastDelta <= 1.5 && wow >= 0 && phase == "cut" {
            return Insight(id: "weight-trend", headline: "Scale spike auto-flagged — not fat",
                           detail: "+\(js(round(lastDelta, 1))) kg within 72h of a heavy session/travel is water + glycogen noise. The 7-day average (\(js(round(thisWeek, 1))) kg) stays the only number with decision authority.",
                           tone: .neutral, confidence: 0.6)
        }
        if phase == "maintenance" && wow >= 0.5 && wow <= 1.2 {
            return Insight(id: "weight-trend", headline: "Glycogen rebound — expected, not fat gain",
                           detail: "The 7-day average is up \(js(wow)) kg entering maintenance — textbook glycogen + water refill (+0.5–1.2 kg band). Hold the protocol.",
                           tone: .positive, confidence: 0.75)
        }
        if phase == "cut" && w.count >= 21 && !flagged {
            let rolling = rollingAverage(weights)
            let win = slice(rolling, -14)
            if win.count == 14 && win[13] >= win[0] - 0.05 {
                return Insight(id: "weight-trend", headline: "Cut stall detected (14-day plateau)",
                               detail: "The 7-day average has been flat or rising for 14 consecutive days with no flagged event — a true stall by v5.1 rules. Consider a small deficit or step adjustment.",
                               tone: .caution, confidence: 0.85)
            }
        }
        let band: (Double, Double)? = phase == "cut" ? (-0.5, -0.4) : phase == "bulk" ? (0.2, 0.25) : nil
        if let band {
            let inBand = wow >= band.0 - 0.05 && wow <= band.1 + 0.05
            return Insight(id: "weight-trend",
                           headline: inBand ? "On-target \(phase!) rate" : "\(phase == "cut" ? "Cut" : "Bulk") rate off target",
                           detail: "7-day average moved \(wow > 0 ? "+" : "")\(js(wow)) kg week-over-week (target \(js(band.0)) to \(js(band.1))). Rolling average only — single days carry zero authority.",
                           tone: inBand ? .positive : .caution, confidence: inBand ? 0.7 : 0.75)
        }
        return Insight(id: "weight-trend",
                       headline: abs(wow) < 0.15 ? "Weight is holding steady" : wow < 0 ? "Downward weekly trend" : "Upward weekly trend",
                       detail: "7-day rolling average: \(js(round(lastWeek, 1))) → \(js(round(thisWeek, 1))) kg (\(wow > 0 ? "+" : "")\(js(wow)) kg week-over-week).",
                       tone: .neutral, confidence: 0.4)
    }

    /// Fuel → Force: day-before carbs vs next-day volume, median-split.
    public static func fuelVsForce(_ days: [DayPoint], _ sessions: [SessionPoint]) -> Insight? {
        var carbsByDate: [String: Double] = [:]
        for d in days { if let c = d.carbsG { carbsByDate[d.date] = c } }
        let pairs: [(carbs: Double, vol: Double)] = sessions.compactMap { s in
            guard let prev = ISODate.addDays(s.date, -1), let carbs = carbsByDate[prev] else { return nil }
            return (carbs, s.volumeKg)
        }
        if pairs.count < 8 { return nil }
        let sorted = pairs.enumerated().sorted { a, b in a.element.carbs != b.element.carbs ? a.element.carbs < b.element.carbs : a.offset < b.offset }.map(\.element)
        let half = sorted.count / 2
        let low = Array(sorted[0..<half]), high = Array(sorted[(sorted.count - half)...])
        if low.count < 4 || high.count < 4 { return nil }
        let lowVol = mean(low.map(\.vol)), highVol = mean(high.map(\.vol))
        if lowVol <= 0 { return nil }
        let diffPct = jsRound(((highVol - lowVol) / lowVol) * 100)
        if abs(diffPct) < 5 { return nil }
        let carbCut = jsRound(mean([low[low.count - 1].carbs, high[0].carbs]))
        if diffPct > 0 {
            return Insight(id: "fuel-force", headline: "Carbs the day before are worth +\(js(diffPct))% volume",
                           detail: "Sessions after a \(js(carbCut))g+ carb day averaged \(js(diffPct))% more volume than after lower-carb days (\(pairs.count) sessions). Front-load carbs the evening before training days.",
                           tone: .positive, confidence: Swift.min(0.9, 0.5 + abs(diffPct) / 40))
        }
        return Insight(id: "fuel-force", headline: "Prior-day carbs aren't driving your volume",
                       detail: "Higher-carb days preceded \(js(abs(diffPct)))% LESS volume (\(pairs.count) sessions) — your output is currently limited by something other than fuel (likely sleep or recovery).",
                       tone: .neutral, confidence: Swift.min(0.75, 0.4 + abs(diffPct) / 50))
    }

    /// STALL PROTOCOL — a true 14-day plateau of the rolling average, no heavy session in 72 h, ONE lever.
    public static func stallProtocol(_ days: [DayPoint], _ sessions: [SessionPoint]) -> Insight? {
        let w = days.filter { $0.weightKg != nil }
        if w.count < 21 { return nil }
        let rolling = rollingAverage(w.map { $0.weightKg! })
        let win = slice(rolling, -14)
        if win.count < 14 { return nil }
        if win[13] < win[0] - 0.05 { return nil }
        let last3 = Set(slice(w, -3).map(\.date))
        if sessions.contains(where: { last3.contains($0.date) && $0.volumeKg > 0 }) { return nil }

        let recent = slice(w, -7)
        let avgSteps = mean(recent.map { $0.steps ?? 0 }.filter { $0 > 0 })
        let avgCarbs = mean(recent.map { $0.carbsG ?? 0 }.filter { $0 > 0 })
        let lever: String
        if avgSteps > 0 && avgSteps < 8000 {
            lever = "Add 1,500 steps/day (you're averaging \(jsLocaleString(jsRound(avgSteps)))). Cheapest lever — it costs no recovery."
        } else if avgCarbs >= 150 {
            lever = "Drop 100 kcal of carbs (−25 g, currently ~\(js(jsRound(avgCarbs))) g/day). Keep protein and training identical."
        } else {
            lever = "Cut one set per muscle this week. Steps and carbs are already tight, so the limiter is systemic fatigue masking the loss."
        }
        return Insight(id: "stall-protocol", headline: "True 14-day stall — pull ONE lever",
                       detail: "The 7-day rolling average has been flat or rising for 14 straight days (\(js(round(win[0], 1))) → \(js(round(win[13], 1))) kg) with no heavy session in the last 72h, so this is not water. Change ONE thing only, then hold it 10–14 days before judging: \(lever)",
                       tone: .caution, confidence: 0.88)
    }

    /// The ranked insight set — up to `limit`, highest confidence first, builder order on a tie.
    public static func compute(days: [DayPoint], sessions: [SessionPoint], contextMode: String? = nil, todayISO: String, limit: Int = 3) -> [Insight] {
        let gap = daysSinceLastSession(sessions, todayISO: todayISO)
        let gapped = gap == nil || gap! >= 7
        let stall = stallProtocol(days, sessions)
        let builders: [Insight?] = [
            gapped ? trainingGap(sessions, todayISO: todayISO) : sleepVsVolume(days, sessions),
            recoveryDrift(days),
            calorieAdherence(days),
            stall ?? weightTrend(days, sessions, contextMode: contextMode),
            gapped ? nil : fuelVsForce(days, sessions),
        ]
        let ranked = builders.compactMap { $0 }.enumerated()
            .sorted { a, b in a.element.confidence != b.element.confidence ? a.element.confidence > b.element.confidence : a.offset < b.offset }
            .map(\.element)
        return Array(ranked.prefix(Swift.max(0, limit)))
    }
}
