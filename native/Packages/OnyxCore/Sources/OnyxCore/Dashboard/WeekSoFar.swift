import Foundation

// The Week So Far card's arithmetic — the web app's `lib/dashboard/weekSoFar.ts`.
//
// One change worth naming, chosen by relative size, so the card says what
// actually moved rather than leading with the same metric every week.

public struct WeekTotals: Codable, Sendable, Equatable {
    public var volumeKg: Double
    public var sessions: Int
    public var sleepMin: Double?
    public var score: Double?

    public init(volumeKg: Double, sessions: Int, sleepMin: Double?, score: Double?) {
        self.volumeKg = volumeKg
        self.sessions = sessions
        self.sleepMin = sleepMin
        self.score = score
    }

    public static let empty = WeekTotals(volumeKg: 0, sessions: 0, sleepMin: nil, score: nil)
}

public struct WeekChange: Codable, Sendable, Equatable {
    public enum Direction: String, Codable, Sendable { case up, down }
    public var label: String
    public var text: String
    public var direction: Direction
    /// Whether the direction is good — sleep down is bad, tonnage down is bad.
    public var good: Bool

    public init(label: String, text: String, direction: Direction, good: Bool) {
        self.label = label; self.text = text; self.direction = direction; self.good = good
    }
}

public enum WeekSoFar {
    /// Percent change, guarding the divide — a week from zero has no percentage.
    static func pct(_ cur: Double, _ prev: Double) -> Double? {
        prev > 0 ? jsRound((cur - prev) / prev * 100) : nil
    }

    /// The ONE change worth naming. Ranked by |%|; sessions rank flat at 1 so a
    /// count only wins a week in which nothing else changed. Ties keep builder
    /// order — tonnage, sleep, score, sessions — as JavaScript's stable sort does.
    public static func biggestChange(_ cur: WeekTotals, _ prev: WeekTotals) -> WeekChange? {
        var candidates: [(WeekChange, Double)] = []

        if let vol = pct(cur.volumeKg, prev.volumeKg), vol != 0 {
            candidates.append((WeekChange(
                label: "Tonnage", text: "\(vol > 0 ? "+" : "")\(Int(vol))%",
                direction: vol > 0 ? .up : .down, good: vol > 0), abs(vol)))
        }

        if let c = cur.sleepMin, let p = prev.sleepMin {
            let d = jsRound(c - p)
            if abs(d) >= 10 {
                candidates.append((WeekChange(
                    label: "Sleep", text: "\(d > 0 ? "+" : "−")\(Format.sleep(abs(d)))",
                    direction: d > 0 ? .up : .down, good: d > 0), abs(pct(c, p) ?? 0)))
            }
        }

        if let c = cur.score, let p = prev.score {
            let d = jsRound(c - p)
            if d != 0 {
                candidates.append((WeekChange(
                    label: "Daily score", text: "\(d > 0 ? "+" : "−")\(Int(abs(d)))",
                    direction: d > 0 ? .up : .down, good: d > 0), abs(pct(c, p) ?? 0)))
            }
        }

        let s = cur.sessions - prev.sessions
        if s != 0 {
            candidates.append((WeekChange(
                label: "Sessions", text: "\(s > 0 ? "+" : "−")\(abs(s))",
                direction: s > 0 ? .up : .down, good: s > 0), 1))
        }

        guard !candidates.isEmpty else { return nil }
        // Stable: equal ranks stay in builder order.
        return candidates.enumerated()
            .sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }
            .first!.element.0
    }
}
