import Foundation

/// Cardio personal records — a port of the web app's `lib/cardio/cardioPrs.ts` and
/// `cardio/zone2.ts`. PURE and derived at read time: `cardio_logs` is the
/// ledger, the records are a view of it, and they can never disagree.
///
/// PACE IS A MINIMUM. Every other axis is a maximum.
public enum CardioAxis: String, CaseIterable, Codable, Sendable {
    case distance, duration, pace, calories

    public var label: String {
        switch self {
        case .distance: return "Distance"
        case .duration: return "Duration"
        case .pace: return "Pace"
        case .calories: return "Calories"
        }
    }

    /// Lower is better on pace; higher on everything else.
    public var isMin: Bool { self == .pace }
}

/// One `cardio_logs` row as the record engine needs it.
public struct CardioRow: Codable, Sendable, Equatable {
    public var id: String
    public var kind: String
    public var distanceM: Double?
    public var durationMin: Double?
    public var kcal: Double?
    public var activeKcal: Double?
    public var date: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, kcal, date
        case distanceM = "distance_m"
        case durationMin = "duration_min"
        case activeKcal = "active_kcal"
    }

    public init(id: String, kind: String, distanceM: Double?, durationMin: Double?, kcal: Double? = nil, activeKcal: Double? = nil, date: String? = nil) {
        self.id = id; self.kind = kind; self.distanceM = distanceM; self.durationMin = durationMin
        self.kcal = kcal; self.activeKcal = activeKcal; self.date = date
    }

    /// `active_kcal ?? kcal` — the legacy column is the fallback.
    public var activeKcalOf: Double? { activeKcal ?? kcal }
}

/// The value that won an axis, and the row that set it.
public struct CardioRecord: Codable, Sendable, Equatable {
    public var axis: CardioAxis
    public var value: Double
    public var id: String
    public var date: String?
}

public enum CardioPrs {
    /// A pace record needs real distance behind it.
    public static let minPaceDistanceM: Double = 1000

    /// Axis value for one row, or nil when the row cannot compete on that axis.
    public static func axisValue(_ row: CardioRow, _ axis: CardioAxis) -> Double? {
        switch axis {
        case .distance:
            guard let d = row.distanceM, d.isFinite, d > 0 else { return nil }
            return d
        case .duration:
            guard let m = row.durationMin, m.isFinite, m > 0 else { return nil }
            return m
        case .calories:
            guard let k = row.activeKcalOf, k.isFinite, k > 0 else { return nil }
            return k
        case .pace:
            guard let d = row.distanceM, d >= minPaceDistanceM else { return nil }
            return CardioMetrics.paceMinPerKm(distanceM: d, durationMin: row.durationMin)
        }
    }

    /// Standing records for ONE activity kind. Ties keep the EARLIER row.
    public static func records(_ rows: [CardioRow], kind: String) -> [CardioAxis: CardioRecord] {
        let mine = rows.filter { $0.kind == kind }
        var out: [CardioAxis: CardioRecord] = [:]
        for axis in CardioAxis.allCases {
            for row in mine {
                guard let v = axisValue(row, axis) else { continue }
                if let held = out[axis], axis.isMin ? !(v < held.value) : !(v > held.value) { continue }
                out[axis] = CardioRecord(axis: axis, value: v, id: row.id, date: row.date)
            }
        }
        return out
    }

    /// Which axes a row currently HOLDS — the standing record, not "was a record when logged".
    public static func axesHeld(by rowId: String, in rows: [CardioRow]) -> [CardioAxis] {
        guard let row = rows.first(where: { $0.id == rowId }) else { return [] }
        let held = records(rows, kind: row.kind)
        return CardioAxis.allCases.filter { held[$0]?.id == rowId }
    }
}

/// What Zone 2 means in this app — a COUNT of sessions, never a minute total.
public enum Zone2 {
    public static let weeklyTarget = 2
    public static let minMinutes: Double = 20

    public static func isZone2(_ durationMin: Double?) -> Bool {
        guard let m = durationMin else { return false }
        return m >= minMinutes
    }
}
