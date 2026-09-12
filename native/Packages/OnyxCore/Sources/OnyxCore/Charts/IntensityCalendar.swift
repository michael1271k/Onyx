import Foundation

/// The Intensity Calendar model — a port of the web app's `lib/charts/intensityCalendar.ts`.
/// Days after today are ABSENT, not rest; `avgLoad` divides by elapsed days.
public struct CalendarCell: Codable, Sendable, Equatable {
    public var date: String
    /// Volume as a fraction of the window's heaviest day, 0 when untrained.
    public var t: Double
    /// False for dates after `today`.
    public var elapsed: Bool
}

public struct CalendarStats: Codable, Sendable, Equatable {
    public struct Hardest: Codable, Sendable, Equatable { public var date: String; public var volume: Double }
    public var activeDays: Int
    public var hardest: Hardest?
    public var avgLoad: Double
    public var streak: Int
}

public struct CalendarModel: Codable, Sendable, Equatable {
    public var weeks: [[CalendarCell]]
    public var stats: CalendarStats
}

public enum IntensityCalendar {
    /// `volumeByDate` is the Map as ordered (date, kg) pairs.
    public static func build(volumeByDate: [(String, Double)], days: Int, todayISO: String) -> CalendarModel? {
        guard !volumeByDate.isEmpty, let todayN = ISODate.dayNumber(todayISO), let tw = ISODate.weekday(todayISO) else { return nil }
        var lookup: [String: Double] = [:]
        for (d, v) in volumeByDate { lookup[d] = v }

        let maxV = max(volumeByDate.map(\.1).max() ?? 1, 1)
        let nWeeks = min(16, max(1, Int((Double(days) / 7).rounded(.up))))
        let thisSunday = todayN - tw

        var weeks: [[CalendarCell]] = []
        for w in stride(from: nWeeks - 1, through: 0, by: -1) {
            var col: [CalendarCell] = []
            for d in 0..<7 {
                let n = thisSunday - w * 7 + d
                let date = ISODate.iso(dayNumber: n)
                col.append(CalendarCell(date: date, t: (lookup[date] ?? 0) / maxV, elapsed: n <= todayN))
            }
            weeks.append(col)
        }

        let first = weeks[0][0].date
        let inWindow = volumeByDate
            .filter { $0.1 > 0 && $0.0 >= first && $0.0 <= todayISO }
            .sorted { $0.0 < $1.0 }

        let firstN = ISODate.dayNumber(first) ?? todayN
        let elapsedDays = max(1, todayN - firstN + 1)
        let total = inWindow.reduce(0.0) { $0 + $1.1 }

        var streak = 0, best = 0
        var prevN: Int? = nil
        for (d, _) in inWindow {
            let n = ISODate.dayNumber(d) ?? Int.min
            streak = (prevN != nil && n - prevN! == 1) ? streak + 1 : 1
            if streak > best { best = streak }
            prevN = n
        }

        var heaviest: (String, Double)? = nil
        for e in inWindow {
            if let h = heaviest { if e.1 > h.1 { heaviest = e } } else { heaviest = e }
        }

        return CalendarModel(
            weeks: weeks,
            stats: CalendarStats(
                activeDays: inWindow.count,
                hardest: heaviest.map { CalendarStats.Hardest(date: $0.0, volume: $0.1) },
                avgLoad: total / Double(elapsedDays),
                streak: best
            )
        )
    }
}
