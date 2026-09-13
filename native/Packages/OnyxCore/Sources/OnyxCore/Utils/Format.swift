import Foundation

/// Small formatters and measures — ports of the web app's `lib/utils/{format,duration,measure}.ts`.
public enum Format {
    /// 457 → "7h 37m" · 420 → "7h" · 45 → "45m" · nil/0 → "—".
    public static func sleep(_ min: Double?) -> String {
        guard let min = min, min.isFinite, min > 0 else { return "—" }
        let total = Int(jsRound(min))
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    /// 457 → "7 hours 37 minutes".
    public static func sleepLong(_ min: Double?) -> String {
        guard let min = min, min.isFinite, min > 0 else { return "—" }
        let total = Int(jsRound(min))
        let h = total / 60, m = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) \(h == 1 ? "hour" : "hours")") }
        if m > 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        return parts.joined(separator: " ")
    }

    /// Millilitres → litres. 2500 → "2.5".
    public static func mlToL(_ ml: Double?, digits: Int = 1) -> String {
        guard let ml = ml, ml.isFinite else { return "—" }
        return jsToFixed(ml / 1000, digits)
    }

    /// "just now" · "12m ago" · "3h ago" · "2d ago" · then "6 Aug" (en-IL, UTC).
    public static func relativeTime(_ input: String?, nowMs: Double) -> String {
        guard let s = input, !s.isEmpty, let t = ISODate.parseMillis(s) else { return "—" }
        let sec = jsRound((nowMs - t) / 1000)
        if sec < 45 { return "just now" }
        let min = jsRound(sec / 60)
        if min < 60 { return "\(jsIntegerString(min))m ago" }
        let hr = jsRound(min / 60)
        if hr < 24 { return "\(jsIntegerString(hr))h ago" }
        let day = jsRound(hr / 24)
        if day < 7 { return "\(jsIntegerString(day))d ago" }
        let dayNumber = Int((t / 86_400_000).rounded(.down))
        let iso = ISODate.iso(dayNumber: dayNumber)
        let dom = Int(iso.dropFirst(8).prefix(2)) ?? 0
        return "\(dom) \(WeeklyExport.month(iso))"
    }

    // MARK: durations

    static func capture(_ pattern: String, _ text: String) -> [String?]? {
        let re = try! NSRegularExpression(pattern: pattern)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : String(text[Range(r, in: text)!])
        }
    }

    /// "1h 20", "1:20", "80m", "80" → minutes; nil when unparseable.
    public static func parseDurationMin(_ raw: String?) -> Int? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let m = capture(#"(\d+)\s*h(?:ours?)?\s*(\d+)?"#, s) { return Int(m[0]!)! * 60 + (m[1].flatMap { Int($0) } ?? 0) }
        if let m = capture(#"^(\d+):(\d+)$"#, s) { return Int(m[0]!)! * 60 + Int(m[1]!)! }
        if let m = capture(#"(\d+)\s*m"#, s) { return Int(m[0]!)! }
        if let m = capture(#"^(\d+)$"#, s) { return Int(m[0]!)! }
        return nil
    }

    // MARK: measures

    /// Any reading under 50 kg is a scale/ingest artifact.
    public static let minValidWeightKg: Double = 50

    public static func validWeight(_ kg: Double?) -> Double? {
        guard let kg = kg, kg.isFinite, kg >= minValidWeightKg else { return nil }
        return kg
    }

    /// Volume to exactly one decimal with thousands separators: "12,102.5".
    public static func volume(_ value: Double?) -> String {
        guard let v = value, v.isFinite else { return "0.0" }
        let r = jsRound(v * 10) / 10
        let fixed = jsToFixed(r, 1)                    // "-12102.5"
        let negative = fixed.hasPrefix("-")
        let body = negative ? String(fixed.dropFirst()) : fixed
        let parts = body.split(separator: ".", maxSplits: 1).map(String.init)
        var digits = parts[0]
        var grouped = ""
        while digits.count > 3 {
            grouped = "," + String(digits.suffix(3)) + grouped
            digits = String(digits.dropLast(3))
        }
        return (negative ? "-" : "") + digits + grouped + "." + (parts.count > 1 ? parts[1] : "0")
    }

    /// Blood-oxygen unit coercion: anything ≤ 1.5 is a fraction and scales to percent.
    public static func normalizeSpO2(_ v: Double?) -> Double? {
        guard let v = v, v.isFinite else { return nil }
        return v <= 1.5 ? jsRound(v * 1000) / 10 : v
    }
}
