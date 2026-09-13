import Foundation

/// The ONE definition of "the night belonging to date D" — a port of
/// the web app's `lib/sleep/nightWindow.ts`. Window [prev(D) 12:00Z, D 12:00Z): half-open,
/// exactly 24 h, so consecutive nights TILE without overlapping.
public struct NightWindow: Codable, Sendable, Equatable {
    /// Inclusive lower bound — previous day 12:00Z.
    public var from: String
    /// EXCLUSIVE upper bound — this day 12:00Z.
    public var to: String
}

public enum Night {
    /// Previous calendar day. An unparseable date echoes the JS behaviour of the
    /// invalid-Date path only as far as the callers need: nil.
    public static func prevDayISO(_ dateISO: String) -> String? { ISODate.addDays(dateISO, -1) }
    public static func nextDayISO(_ dateISO: String) -> String? { ISODate.addDays(dateISO, 1) }

    /// The night that ENDS on the morning of `dateISO`.
    public static func window(_ dateISO: String) -> NightWindow? {
        guard let prev = prevDayISO(dateISO) else { return nil }
        return NightWindow(from: "\(prev)T12:00:00Z", to: "\(dateISO)T12:00:00Z")
    }

    /// Which date's night a bedtime belongs to: at or after noon is TOMORROW's.
    public static func nightOf(_ startTime: String) -> String {
        let day = String(startTime.prefix(10))
        let hourText = startTime.count >= 13 ? String(startTime.dropFirst(11).prefix(2)) : String(startTime.dropFirst(11))
        // `Number('')` is 0 in JS, so a bare date reads as hour 0 and keeps its day.
        let hour: Double? = hourText.isEmpty ? 0 : Double(hourText)
        if let h = hour, h.isFinite, h >= 12, let next = nextDayISO(day) { return next }
        return day
    }

    /// Where to stamp a session with no bed time — INSIDE its own window.
    public static func fallbackBedTime(_ dateISO: String) -> String? {
        guard let prev = prevDayISO(dateISO) else { return nil }
        return "\(prev)T23:00:00Z"
    }
}
