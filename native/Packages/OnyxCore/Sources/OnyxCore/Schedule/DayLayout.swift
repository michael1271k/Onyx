import Foundation

/// The permanent weekday layout of a plan — a port of the web app's `lib/schedule/layout.ts`.
///
/// ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
/// `ProgramDay.weekday` is a constant, and `schedule_overrides` is strictly
/// per-date. So "Delts & Arms moves off Tuesday FOREVER" had nowhere to be
/// recorded. A layout is `dayKey → weekday`; an absent key means "wherever the
/// deck put it", so a partial layout is meaningful and deleting the row restores
/// the plan exactly as authored.
///
/// It is ONE jsonb row because a swap is an EXCHANGE, and an exchange is atomic
/// or it is corruption — per-day rows with a unique-weekday constraint collide
/// with themselves mid-statement.
///
/// No clock, no database. Pure functions over a `[String: Int]`.
public typealias DayLayout = [String: Int]

public enum ScheduleLayout {

    /// Weekdays a layout may name. Anything else is a corrupt row, not a rest day.
    static func isValidWeekday(_ n: Int) -> Bool { (0...6).contains(n) }

    /// Read a stored payload (a `JSONSerialization` value) into a layout,
    /// dropping anything malformed. TOTAL by design: this runs behind the
    /// schedule rule, and a bad row must degrade to the authored plan.
    ///
    /// ── KEY ORDER, AND WHY IT IS JSONB'S ─────────────────────────────────────
    /// A duplicate weekday is dropped rather than allowed to shadow — the FIRST
    /// key wins. The TypeScript reads "first" as object insertion order, and the
    /// only object it ever reads is a `program_day_layout.layout` jsonb value,
    /// which Postgres hands back with keys sorted by length then bytewise. A
    /// Swift `Dictionary` has no order at all, so this walks the keys in that
    /// same jsonb order; the two implementations then see the same "first" for
    /// the same stored row.
    public static func parseLayout(_ raw: Any?) -> DayLayout {
        guard let dict = raw as? [String: Any] else { return [:] }
        var out: DayLayout = [:]
        var taken = Set<Int>()
        let keys = dict.keys.sorted { a, b in
            a.utf8.count != b.utf8.count ? a.utf8.count < b.utf8.count : Array(a.utf8).lexicographicallyPrecedes(b.utf8)
        }
        for key in keys {
            // `typeof n === 'number' && Number.isInteger(n) && 0 ≤ n ≤ 6`. A
            // boolean bridges to NSNumber and is not a number to JavaScript.
            guard !key.isEmpty, let n = Dashboard.jsNumber(dict[key]),
                  n == n.rounded(.towardZero), let wd = Int(exactly: n), isValidWeekday(wd),
                  !taken.contains(wd)
            else { continue }
            out[key] = wd
            taken.insert(wd)
        }
        return out
    }

    /// Where a day actually sits: the layout's answer, else the authored weekday.
    public static func effectiveWeekday(_ day: ProgramDay, _ layout: DayLayout) -> Int {
        if let mapped = layout[day.key], isValidWeekday(mapped) { return mapped }
        return day.weekday
    }

    /// Which day owns a weekday under this layout, or nil when that day rests.
    public static func dayKeyForWeekday(_ program: Program, _ layout: DayLayout, _ weekday: Int) -> String? {
        program.days.first { effectiveWeekday($0, layout) == weekday }?.key
    }

    /// The COMPLETE layout a plan is currently running — every day named
    /// explicitly. Stored layouts are sparse; every mutation starts from this
    /// and the result is stored whole, so the row describes the week on its own.
    public static func fullLayout(_ program: Program, _ layout: DayLayout) -> DayLayout {
        var out: DayLayout = [:]
        for d in program.days { out[d.key] = effectiveWeekday(d, layout) }
        return out
    }

    /// Move `dayKey` to `weekday`, as an EXCHANGE.
    ///
    /// If another day already sits there, the two trade slots — which keeps the
    /// layout a bijection and the week the same set of sessions in a different
    /// order. If the target weekday is free (a rest day), the day simply moves
    /// and its old slot becomes rest. No session is destroyed either way.
    public static func moveDay(_ program: Program, _ layout: DayLayout, _ dayKey: String, _ weekday: Int) -> DayLayout {
        var next = fullLayout(program, layout)
        guard isValidWeekday(weekday), let from = next[dayKey], from != weekday else { return next }
        // `Object.keys(next).find(...)` — key order does not matter here: a
        // valid layout has at most one occupant per weekday.
        let occupant = program.days.map(\.key).first { $0 != dayKey && next[$0] == weekday }
        next[dayKey] = weekday
        if let occupant { next[occupant] = from }   // the exchange
        return next
    }

    /// True when the layout says nothing the authored plan doesn't already say.
    public static func isAuthoredLayout(_ program: Program, _ layout: DayLayout) -> Bool {
        program.days.allSatisfy { effectiveWeekday($0, layout) == $0.weekday }
    }

    /// Key-order-independent serialisation, for idempotency checks — byte for
    /// byte what `JSON.stringify(Object.keys(layout).sort().map(k => [k, layout[k]]))`
    /// prints. `JSON.stringify` is NOT usable against a stored jsonb value:
    /// Postgres reorders the keys, and a string comparison then reports a
    /// difference that does not exist.
    ///
    /// `.sort()` on keys is UTF-16 code-unit order; for the ASCII day keys this
    /// app writes that is bytewise order, which is what is used here.
    public static func canonicalLayout(_ layout: DayLayout) -> String {
        let pairs = layout.keys.sorted { Array($0.utf16).lexicographicallyPrecedes($1.utf16) }
            .map { "[\(jsonString($0)),\(layout[$0]!)]" }
        return "[" + pairs.joined(separator: ",") + "]"
    }

    /// `programDayIn` — the one place the remap is applied. nil = rest.
    public static func programDayIn(_ program: Program, _ layout: DayLayout, _ weekday: Int) -> ProgramDay? {
        program.days.first { effectiveWeekday($0, layout) == weekday }
    }

    /// `JSON.stringify` of one string. Day keys are plain identifiers, but a
    /// stored key is user-shaped data and the escape rule costs nothing.
    private static func jsonString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s])
        let text = String(decoding: data, as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }
}
