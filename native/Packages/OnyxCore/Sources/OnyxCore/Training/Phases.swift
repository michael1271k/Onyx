import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Training-phase anchors — the pure half of the web app's `lib/phases.ts`, over ROWS.
//
// A programme phase is a direction (`cut` / `bulk`), a polished end state
// (`peak`), or a bounded easing-off (`deload`). It is never a diet: the
// nutrition "maintenance week" is a LEVER (see `Levers`), and the one-week
// phase that used to duplicate it was deleted on 2026-08-30 after the two
// copies drifted apart.
//
// ── THE TABLE IS A PARAMETER (W2) ────────────────────────────────────────────
// `Phases.all` was the founder's eight dated blocks, compiled in. They are
// `plan_phases` rows now; every function below takes the rows it walks, in
// table order, and answers nothing for an empty table. The caller that has a
// `ScheduleContext` has the rows already (`ctx.phases`).
//
// Colours are not here. `PHASE_HEX` and friends are OnyxUI tokens.
// ─────────────────────────────────────────────────────────────────────────────

public enum PhaseKind: String, Codable, Sendable, CaseIterable { case cut, peak, bulk, deload }
/// Which programme an era belongs to. The raw values are a WIRE FORMAT, shared
/// with the golden fixtures and the `plan_phases.era` column.
///
/// ── THE CURRENT ERA WAS RENAMED ON THE WIRE (Expansion W1) ──────────────────
/// It carried the predecessor web app's name until 7.0.0, when the raw value
/// became `"onyx"` in the same release as `v32.onyxWire`, which rewrites every
/// stored row, and the server-side UPDATE the founder pasted alongside it. The
/// two halves ship together on purpose: a build that reads the new spelling
/// against un-migrated rows decodes `era` as nil and the era window loses its
/// tag. There are exactly TWO cases, which is what lets the migration find the
/// rows to rewrite without naming the retired brand — anything that is not
/// `ppl` is this era.
public enum PhaseEra: String, Codable, Sendable {
    case ppl
    case onyx
}

public struct PhaseDef: Codable, Equatable, Sendable {
    public var kind: PhaseKind
    public var name: String
    /// YYYY-MM-DD, a week start.
    public var start: String
    public var weeks: Int
    /// Append "Week N" per week.
    public var numbered: Bool?
    /// Compact override.
    public var short: String?
    /// Week numbering offset (blocks split around a deload).
    public var firstWeek: Int?
    /// Era-distinct tag (defaults to the name).
    public var eraTag: String?
    public var era: PhaseEra?
    /// `plan_phases.plan_id` — which plan the block belongs to. Optional so a
    /// fixture written before the column decodes; the store always fills it.
    public var planId: String?

    public init(kind: PhaseKind, name: String, start: String, weeks: Int, numbered: Bool? = nil, short: String? = nil, firstWeek: Int? = nil, era: PhaseEra? = nil, eraTag: String? = nil, planId: String? = nil) {
        self.kind = kind; self.name = name; self.start = start; self.weeks = weeks
        self.numbered = numbered; self.short = short; self.firstWeek = firstWeek; self.eraTag = eraTag; self.era = era
        self.planId = planId
    }

    /// The last day of the block, inclusive.
    public var endISO: String? { ISODate.addDays(start, weeks * 7 - 1) }
}

/// The phase for a week start.
public struct WeekPhase: Codable, Equatable, Sendable {
    public var kind: PhaseKind
    /// Full label, e.g. "Onyx Cut · Week 3".
    public var label: String
    /// Compact label, e.g. "Cut W3" / "Peak".
    public var short: String
    public var eraTag: String
    public var era: PhaseEra
    /// The phase on its own — "Cut", "Lean Bulk".
    public var name: String
    /// Week number within the phase, or nil on an unnumbered phase.
    public var n: Int?
}

public struct ProgramWeek: Codable, Equatable, Sendable {
    public var weekStart: String
    public var weekEnd: String
    public var kind: PhaseKind
    public var n: Int
    public var label: String
    public var eraTag: String
    public var era: PhaseEra
}

/// The phase a DATE falls in and how far into it that date is.
public struct PhaseSpan: Equatable, Sendable {
    public var def: PhaseDef
    public var start: String
    public var dayIndex: Int
}

public enum Phases {

    /// Rows in the order the walks below expect: by start date. The store
    /// hands rows over already sorted; this is the guard for a caller that
    /// built the array by hand.
    public static func sorted(_ table: [PhaseDef]) -> [PhaseDef] {
        table.sorted { $0.start < $1.start }
    }

    /// `phaseSpanFor` — first match in table order; nil between phases and for
    /// a date that does not parse.
    public static func span(for dateISO: String, in table: [PhaseDef]) -> PhaseSpan? {
        guard let t = ISODate.dayNumber(dateISO) else { return nil }
        for def in table {
            guard let start = ISODate.dayNumber(def.start) else { continue }
            let idx = t - start
            if idx >= 0 && idx < def.weeks * 7 { return PhaseSpan(def: def, start: def.start, dayIndex: idx) }
        }
        return nil
    }

    /// `getWeekPhase` — the phase for a week start, or nil.
    public static func weekPhase(weekStart: String, in table: [PhaseDef]) -> WeekPhase? {
        for p in table {
            guard let start = ISODate.dayNumber(p.start) else { continue }
            for i in 0..<p.weeks where ISODate.iso(dayNumber: start + i * 7) == weekStart {
                let era = p.era ?? .ppl
                let eraTag = p.eraTag ?? p.name
                if p.numbered == true {
                    let n = i + (p.firstWeek ?? 1)
                    return WeekPhase(kind: p.kind, label: "\(eraTag) · Week \(n)", short: "\(p.short ?? p.name) W\(n)", eraTag: eraTag, era: era, name: p.name, n: n)
                }
                return WeekPhase(kind: p.kind, label: eraTag, short: p.short ?? p.name, eraTag: eraTag, era: era, name: p.name, n: nil)
            }
        }
        return nil
    }

    /// `enumerateWeeks` — every week of the given kinds as a folder, NEWEST FIRST.
    public static func enumerateWeeks(_ kinds: [PhaseKind], in table: [PhaseDef]) -> [ProgramWeek] {
        var out: [ProgramWeek] = []
        for p in table where kinds.contains(p.kind) {
            guard let start = ISODate.dayNumber(p.start) else { continue }
            for i in 0..<p.weeks {
                let ws = start + i * 7
                let n = i + (p.firstWeek ?? 1)
                out.append(ProgramWeek(
                    weekStart: ISODate.iso(dayNumber: ws), weekEnd: ISODate.iso(dayNumber: ws + 6), kind: p.kind, n: n,
                    label: p.numbered == true ? "Week \(n)" : p.name, eraTag: p.eraTag ?? p.name, era: p.era ?? .ppl
                ))
            }
        }
        return out.reversed()
    }

    /// The plan a date belongs to, by the block that covers it — the first
    /// thing `Schedule.programForContext` asks before it falls back to the
    /// plans' start dates.
    public static func planId(owning dateISO: String, in table: [PhaseDef]) -> String? {
        span(for: dateISO, in: table)?.def.planId
    }
}
