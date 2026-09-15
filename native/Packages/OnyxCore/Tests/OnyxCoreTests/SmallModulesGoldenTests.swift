import Foundation
import Testing
@testable import OnyxCore

// MARK: - A small JSON value, for the fixtures whose shape is not one struct

indirect enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var number: Double? { if case .number(let n) = self { return n } else { return nil } }
    var array: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    var isNull: Bool { if case .null = self { return true } else { return false } }

    /// `typeof v === 'number' && Number.isInteger(v)` and the layout's weekday range — as `Any?` for `ScheduleLayout.parse`.
    var any: Any? {
        switch self {
        case .null: return nil
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a
        case .object(let o): return o
        }
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: try JSONEncoder().encode(self))
    }
}

private func pairs(_ v: [[JSONValue]]) -> [(String, Int)] { v.map { ($0[0].string!, Int($0[1].number!)) } }

@Suite("Item #10 — cardio records, Zone 2")
struct CardioPrsGoldenTests {
    struct In: Decodable { let rows: [CardioRow]; let kind: String; let rowId: String }
    struct AxisValues: Decodable { let id: String; let values: [Double?] }
    struct Out: Decodable { let records: [String: CardioRecord]; let held: [String]; let axisValues: [AxisValues] }

    @Test("records, trophies and axis values match")
    func records() throws {
        for c in try GoldenFixture<In, Out>.load("cardio-prs").cases {
            let recs = CardioPrs.records(c.input.rows, kind: c.input.kind)
            var byName: [String: CardioRecord] = [:]
            for (k, v) in recs { byName[k.rawValue] = v }
            #expect(Set(byName.keys) == Set(c.expected.records.keys), "record axes — \(c.name)")
            for (k, e) in c.expected.records {
                let a = byName[k]
                #expect(a?.id == e.id && a?.date == e.date && a?.axis == e.axis, "record \(k) — \(c.name)")
                expectClose(a?.value, e.value, "record value \(k) — \(c.name)")
            }
            #expect(CardioPrs.axesHeld(by: c.input.rowId, in: c.input.rows).map(\.rawValue) == c.expected.held, "held — \(c.name)")
            for (row, e) in zip(c.input.rows, c.expected.axisValues) {
                #expect(row.id == e.id)
                for (axis, ev) in zip(CardioAxis.allCases, e.values) {
                    expectClose(CardioPrs.axisValue(row, axis), ev, "\(axis) of \(row.id) — \(c.name)")
                }
            }
        }
    }

    struct Z2In: Decodable { let durationMin: Double?; let minMinutes: Double; let weeklyTarget: Int }
    @Test("the Zone-2 rule")
    func zone2() throws {
        for c in try GoldenFixture<Z2In, Bool>.load("zone2").cases {
            #expect(Zone2.isZone2(c.input.durationMin) == c.expected, "\(c.name)")
            #expect(Zone2.minMinutes == c.input.minMinutes && Zone2.weeklyTarget == c.input.weeklyTarget)
        }
        #expect(CardioAxis.distance.label == "Distance" && CardioAxis.pace.label == "Pace")
    }
}

@Suite("Item #10 — the night window")
struct NightWindowGoldenTests {
    struct In: Decodable { let dateISO: String?; let startTime: String? }
    struct Out: Decodable { let prev: String?; let next: String?; let window: NightWindow?; let fallback: String?; let nightOf: String? }

    @Test("window, inverse and fallback match")
    func windows() throws {
        for c in try GoldenFixture<In, Out>.load("night-window").cases {
            if let d = c.input.dateISO {
                #expect(Night.prevDayISO(d) == c.expected.prev, "prev — \(c.name)")
                #expect(Night.nextDayISO(d) == c.expected.next, "next — \(c.name)")
                #expect(Night.window(d) == c.expected.window, "window — \(c.name)")
                #expect(Night.fallbackBedTime(d) == c.expected.fallback, "fallback — \(c.name)")
            }
            if let t = c.input.startTime {
                #expect(Night.nightOf(t) == c.expected.nightOf, "nightOf — \(c.name)")
            }
        }
    }
}

// MARK: - Schedule

private let onyx5 = FounderTables.deck

private func dayOf(_ key: String) -> ScheduleDay? {
    onyx5.days.first { $0.key == key }.map { ScheduleDay(label: $0.label, sub: $0.sub, dayKey: $0.key) }
}

/// The app's layering, rebuilt exactly as the exporter did: overrides, then the layout, then rest.
private func resolver(_ overrides: [String: String]) -> @Sendable (String, DayLayout) -> ScheduleDay? {
    { dateISO, layout in
        if let o = overrides[dateISO] {
            if o == Schedule.restOverride { return nil }
            if o.hasPrefix("label:") { return ScheduleDay(label: String(o.dropFirst(6))) }
            return dayOf(o)
        }
        guard let w = ISODate.weekday(dateISO), let key = ScheduleLayout.dayKeyForWeekday(onyx5, layout, w) else { return nil }
        return dayOf(key)
    }
}

@Suite("Item #10 — schedule swaps")
struct ScheduleSwapGoldenTests {
    struct Rest: Decodable { let dateISO: String; let horizon: Int? }
    struct SwapIn: Decodable { let dateISO: String; let dayKey: String; let naturalDate: String? }
    struct Block: Decodable { let dateISO: String; let dayKey: String; let logged: [LoggedDay]; let sourceDate: String? }
    struct Permanent: Decodable { let dayKey: String; let weekday: Int; let todayISO: String; let logged: [LoggedDay] }
    struct In: Decodable { let overrides: [String: String]; let layout: [String: Int]; let rest: Rest?; let swap: SwapIn?; let block: Block?; let permanent: Permanent? }
    struct RestOut: Decodable { let writes: [ScheduleWrite]; let moved: ScheduleDay?; let movedTo: String?; let sameWeek: Bool; let outcome: RestOutcome; let sentence: String }
    struct BlockOut: Decodable { let block: SwapBlock?; let sentence: String? }
    struct PermOut: Decodable { let layout: [String: Int]?; let writes: [ScheduleWrite]; let pinned: [String]; let block: SwapBlock? }
    struct Out: Decodable { let rest: RestOut?; let swap: [ScheduleWrite]?; let block: BlockOut?; let permanent: PermOut? }

    @Test("rest-day plans, swaps, blocks and permanent moves match")
    func swaps() throws {
        let labelFor: (String?) -> String = { key in key.flatMap { dayOf($0)?.label ?? $0 } ?? "Rest" }
        for c in try GoldenFixture<In, Out>.load("schedule-swap").cases {
            let layout = c.input.layout
            let resolveWith = resolver(c.input.overrides)
            let resolve: ResolveDay = { resolveWith($0, layout) }
            if let r = c.input.rest {
                let p = r.horizon.map { Swap.planRestDay(r.dateISO, resolve: resolve, horizon: $0) } ?? Swap.planRestDay(r.dateISO, resolve: resolve)
                let e = c.expected.rest!
                #expect(p == RestDayPlan(writes: e.writes, moved: e.moved, movedTo: e.movedTo, sameWeek: e.sameWeek, outcome: e.outcome), "rest plan — \(c.name)")
                #expect(Swap.describeRestPlan(p) == e.sentence, "rest sentence — \(c.name)")
            }
            if let s = c.input.swap {
                #expect(Swap.planDaySwap(s.dateISO, dayKey: s.dayKey, resolve: resolve, naturalDate: s.naturalDate) == c.expected.swap, "swap — \(c.name)")
            }
            if let b = c.input.block {
                let block = Swap.blockForPlacement(b.dateISO, dayKey: b.dayKey, logged: b.logged, sourceDate: b.sourceDate)
                #expect(block == c.expected.block!.block, "block — \(c.name)")
                #expect(block.map { Swap.describeBlock($0, labelFor: labelFor) } == c.expected.block!.sentence, "block sentence — \(c.name)")
            }
            if let p = c.input.permanent {
                let plan = Swap.planPermanentMove(program: onyx5, layout: layout, dayKey: p.dayKey, weekday: p.weekday, todayISO: p.todayISO, logged: p.logged, resolveWith: resolveWith)
                let e = c.expected.permanent!
                #expect(plan.layout == e.layout, "permanent layout — \(c.name)")
                #expect(plan.writes == e.writes && plan.pinned == e.pinned && plan.block == e.block, "permanent writes — \(c.name)")
            }
        }
    }

    struct WeekIn: Decodable { let dateISO: String }
    struct WeekOut: Decodable { let week: [String]; let forWeekday: [String]; let label: String; let weekLabels: [String] }
    @Test("Sunday-anchored week helpers and the en-GB short label")
    func week() throws {
        for c in try GoldenFixture<WeekIn, WeekOut>.load("schedule-week").cases {
            #expect(Swap.weekDatesOf(c.input.dateISO) == c.expected.week, "week — \(c.name)")
            #expect((0..<7).map { Swap.dateForWeekday(c.input.dateISO, $0) } == c.expected.forWeekday, "forWeekday — \(c.name)")
            #expect(Swap.shortDayLabel(c.input.dateISO) == c.expected.label, "label — \(c.name)")
            #expect(c.expected.week.map(Swap.shortDayLabel) == c.expected.weekLabels, "weekLabels — \(c.name)")
        }
    }
}

// MARK: - Charts

@Suite("Item #10 — charts")
struct ChartsGoldenTests {
    struct CalIn: Decodable { let volume: [[JSONValue]]; let days: Int; let todayISO: String }
    @Test("the intensity calendar matches")
    func calendar() throws {
        for c in try GoldenFixture<CalIn, CalendarModel?>.load("intensity-calendar").cases {
            let model = IntensityCalendar.build(volumeByDate: c.input.volume.map { ($0[0].string!, $0[1].number!) }, days: c.input.days, todayISO: c.input.todayISO)
            guard let e = c.expected else { #expect(model == nil, "\(c.name)"); continue }
            guard let m = model else { Issue.record("nil model — \(c.name)"); continue }
            #expect(m.weeks.count == e.weeks.count, "weeks — \(c.name)")
            for (wa, we) in zip(m.weeks, e.weeks) {
                for (a, x) in zip(wa, we) {
                    #expect(a.date == x.date && a.elapsed == x.elapsed, "cell \(x.date) — \(c.name)")
                    expectClose(a.t, x.t, "t \(x.date) — \(c.name)")
                }
            }
            #expect(m.stats.activeDays == e.stats.activeDays && m.stats.streak == e.stats.streak && m.stats.hardest == e.stats.hardest, "stats — \(c.name)")
            expectClose(m.stats.avgLoad, e.stats.avgLoad, "avgLoad — \(c.name)")
        }
    }

    // `aggregate()` tested `MuscleAggregator`, deleted in W3 along with its
    // `muscle-aggregate.json` and the `muscle-map.json` table case it read.
    // What replaced it is `family()` in the widget suite below: one
    // accumulator, checked at the landmark grain it now counts in.

    struct Nice: Decodable { let padPct: Double?; let zeroBased: Bool?; let hardMin: Double? }
    struct Tight: Decodable { let padPct: Double?; let hardMin: Double?; let minSpanPct: Double? }
    struct Axis: Decodable { let value: Double?; let span: Double }
    struct ScaleIn: Decodable { let values: [Double?]; let nice: Nice?; let tight: Tight?; let compact: Double?; let axis: Axis? }
    struct ScaleOut: Decodable { let nice: [Double]?; let tight: [Double]?; let compact: String?; let axis: String? }
    @Test("axis scaling matches")
    func scale() throws {
        for c in try GoldenFixture<ScaleIn, ScaleOut>.load("chart-scale").cases {
            if let n = c.input.nice {
                let d = ChartScale.niceDomain(c.input.values, padPct: n.padPct ?? 0.1, zeroBased: n.zeroBased ?? false, hardMin: n.hardMin)
                expectClose(d.0, c.expected.nice![0], "nice lo — \(c.name)"); expectClose(d.1, c.expected.nice![1], "nice hi — \(c.name)")
            }
            if let t = c.input.tight {
                let d = ChartScale.tightDomain(c.input.values, padPct: t.padPct ?? 0.06, hardMin: t.hardMin, minSpanPct: t.minSpanPct ?? 0.005)
                expectClose(d.0, c.expected.tight![0], "tight lo — \(c.name)"); expectClose(d.1, c.expected.tight![1], "tight hi — \(c.name)")
            }
            if c.expected.compact != nil { #expect(ChartScale.compactKg(c.input.compact) == c.expected.compact, "compact — \(c.name)") }
            if let a = c.input.axis { #expect(ChartScale.axisBound(a.value, span: a.span) == c.expected.axis, "axis — \(c.name)") }
        }
    }
}

// MARK: - Widget

@Suite("Item #10 — widget derivations")
struct WidgetGoldenTests {
    struct Shift: Decodable { let date: String; let days: Int }
    struct SeriesIn: Decodable { let rows: [DatedValue]; let limit: Int; let combine: WidgetDerive.Combine?; let from: String?; let to: String?; let todayISO: String?; let shift: Shift? }
    struct SeriesOut: Decodable { let trend: [TrendPoint]; let daily: [TrendPoint]?; let mean: Double?; let latest: LatestDelta; let vital: VitalBlock?; let shifted: String? }

    @Test("series helpers match")
    func series() throws {
        for c in try GoldenFixture<SeriesIn, SeriesOut>.load("widget-series").cases {
            let i = c.input
            let trend = WidgetDerive.trendPoints(i.rows, limit: i.limit)
            #expect(trend == c.expected.trend, "trend — \(c.name)")
            if let cmb = i.combine { #expect(WidgetDerive.dailySeries(i.rows, limit: i.limit, combine: cmb) == c.expected.daily, "daily — \(c.name)") }
            if let f = i.from, let t = i.to { expectClose(WidgetDerive.meanBetween(trend, from: f, to: t), c.expected.mean, "mean — \(c.name)") }
            #expect(WidgetDerive.latestDelta(trend) == c.expected.latest, "latest — \(c.name)")
            if let today = i.todayISO { #expect(WidgetDerive.vitalBlock(i.rows, todayISO: today, trendLimit: i.limit) == c.expected.vital, "vital — \(c.name)") }
            if let s = i.shift { #expect(ISODate.addDays(s.date, s.days) == c.expected.shifted, "shift — \(c.name)") }
        }
    }

    /// Swift-only: no TS twin, because it is the window a SCREEN asks for and
    /// nothing on the wire changes. Three facts — the window is always `limit`
    /// long, a missing day is nil rather than absent or zero, and a reading
    /// outside the window is dropped rather than folded onto the edge.
    @Test("paddedWindow fills the calendar without inventing zeroes")
    func padded() {
        let series = [
            TrendPoint(d: "2026-09-01", v: 420), TrendPoint(d: "2026-09-03", v: 465),
            // One reading each side of the window. BOTH must be dropped — the
            // later one is the case that actually happens (a clock ahead, a
            // timezone-skewed HealthKit sample) and the one an "edge" bug would
            // fold onto 2026-09-04.
            TrendPoint(d: "2026-08-20", v: 999), TrendPoint(d: "2026-09-06", v: 111),
        ]
        let window = WidgetDerive.paddedWindow(series, endingOn: "2026-09-04", limit: 7)
        #expect(window.count == 7)
        #expect(window.map(\.date) == ["2026-08-29", "2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04"])
        #expect(window.map(\.value) == [nil, nil, nil, 420, nil, 465, nil])

        // An empty series is a window of SEVEN nils, not an empty array — the
        // count is the half of this that a `.allSatisfy` alone cannot see.
        let empty = WidgetDerive.paddedWindow([], endingOn: "2026-09-04", limit: 7)
        #expect(empty.count == 7)
        #expect(empty.allSatisfy { $0.value == nil })

        // Duplicate dates resolve last-wins rather than trapping the initialiser.
        let duplicated = WidgetDerive.paddedWindow(
            [TrendPoint(d: "2026-09-04", v: 1), TrendPoint(d: "2026-09-04", v: 2)],
            endingOn: "2026-09-04", limit: 1)
        #expect(duplicated.map(\.value) == [2])

        // All or nothing: no window at all beats half a window.
        #expect(WidgetDerive.paddedWindow(series, endingOn: "2026-09-04", limit: 0).isEmpty)
        #expect(WidgetDerive.paddedWindow(series, endingOn: "not-a-day", limit: 7).isEmpty)
    }

    struct CalIn: Decodable { let days: [String]; let sessions: [CalendarSession]; let schedule: [String: ScheduledDay]; let todayISO: String; let weekStartDay: Int; let limit: Int }
    struct CalOut: Decodable { let calendar: [CalendarDay]; let streak: StreakResult; let programDay: Int; let weekly: [TrendPoint] }
    @Test("calendar, streak, program day and weekly volume match")
    func calendar() throws {
        for c in try GoldenFixture<CalIn, CalOut>.load("widget-calendar").cases {
            let i = c.input
            let cal = WidgetDerive.calendarDays(i.days, sessions: i.sessions) { i.schedule[$0] ?? ScheduledDay(dayKey: nil, scheduled: false) }
            #expect(cal == c.expected.calendar, "calendar — \(c.name)")
            #expect(Streak.from(cal.map { StreakDay(d: $0.d, scheduled: $0.scheduled, logged: $0.logged) }, todayISO: i.todayISO) == c.expected.streak, "streak — \(c.name)")
            #expect(Streak.programDayCount(i.todayISO, startISO: FounderTables.planStartISO) == c.expected.programDay, "programDay — \(c.name)")
            #expect(WidgetDerive.weeklyVolume(i.sessions, weekStartOfDate: { Week.start(of: $0, startDay: i.weekStartDay) }, limit: i.limit) == c.expected.weekly, "weekly — \(c.name)")
        }
    }

    struct CardioOpts: Decodable { let today: String; let weekStart: String; let zone2MinMinutes: Double; let weekTarget: Int; let trendDays: Int }
    struct CardioIn: Decodable { let rows: [WidgetCardioRow]; let opts: CardioOpts }
    @Test("the cardio block matches")
    func cardio() throws {
        for c in try GoldenFixture<CardioIn, CardioBlock>.load("widget-cardio").cases {
            let o = c.input.opts
            let b = WidgetDerive.cardioBlock(c.input.rows, today: o.today, weekStart: o.weekStart, zone2MinMinutes: o.zone2MinMinutes, weekTarget: o.weekTarget, paceOf: { CardioMetrics.paceMinPerKm(distanceM: $0, durationMin: $1) }, trendDays: o.trendDays)
            #expect(b.weekSessions == c.expected.weekSessions && b.weekTarget == c.expected.weekTarget && b.weekMinutes == c.expected.weekMinutes && b.trend == c.expected.trend, "block — \(c.name)")
            #expect(b.last?.kind == c.expected.last?.kind && b.last?.date == c.expected.last?.date && b.last?.distanceM == c.expected.last?.distanceM && b.last?.durationMin == c.expected.last?.durationMin, "last — \(c.name)")
            expectClose(b.last?.paceMinPerKm, c.expected.last?.paceMinPerKm, "pace — \(c.name)")
        }
    }

    struct RecIn: Decodable { let rows: [LedgerRow]; let limit: Int? }
    struct Floor: Decodable { let key: String; let floor: PrFloor? }
    struct RecOut: Decodable { let records: [WidgetRecord]; let floors: [Floor] }
    @Test("top records match and the floors agree with the founder's floor rows")
    func records() throws {
        for c in try GoldenFixture<RecIn, RecOut>.load("widget-records").cases {
            // `topRecords` used to drop rows under `PrTruth.floor`; the floors
            // are `personal_records` rows the store nets out before the widget
            // reads, so the test plays the store on the vector's input.
            let rows = c.input.rows.filter { r in
                guard let v = r.value, let f = FounderTables.floors[r.exerciseKey]?.value(axis: r.axis) else { return true }
                return v >= f
            }
            let r = c.input.limit.map { WidgetDerive.topRecords(rows, limit: $0) } ?? WidgetDerive.topRecords(rows)
            #expect(r == c.expected.records, "records — \(c.name)")
            for f in c.expected.floors { #expect(FounderTables.floors[f.key] == f.floor, "floor \(f.key)") }
        }
    }

    struct E1In: Decodable { let sets: [WidgetSetRow]; let asOf: String; let windowDays: Int?; let limit: Int? }

    /// ── THE KILOGRAMS ARE EXEMPT, THE SELECTION IS NOT ──────────────────────
    /// The estimates in this fixture were computed under Epley; the app reports
    /// Brzycki since 2026-09-15. What the vector pins and what has NOT changed
    /// is the SELECTION around them: which exercises make the tile and in what
    /// order (most recently trained first, heaviest breaking the tie), the
    /// limit, the per-day best fold, the working-set filter, and the shape of
    /// the trend. So the file is not regenerated — see `GoldenVector`.
    private func withoutKg(_ rows: [WidgetE1rm]) -> [(String, Int, Bool)] {
        rows.map { ($0.exercise, $0.trend.count, $0.deltaKg != nil) }
    }

    @Test("estimated 1RM trends match, the kilograms aside")
    func e1rm() throws {
        for c in try GoldenFixture<E1In, [WidgetE1rm]>.load("widget-e1rm").cases {
            let i = c.input
            let r = WidgetDerive.e1rmTrends(i.sets, asOf: i.asOf, windowDays: i.windowDays ?? 28, limit: i.limit ?? 3)
            let got = withoutKg(r), want = withoutKg(c.expected)
            #expect(got.map(\.0) == want.map(\.0), "e1rm exercises — \(c.name)")
            #expect(got.map(\.1) == want.map(\.1), "e1rm trend length — \(c.name)")
            #expect(got.map(\.2) == want.map(\.2), "e1rm delta presence — \(c.name)")
        }
    }

    struct FamIn: Decodable { let muscle: String }
    struct CreditIn: Decodable { let sets: [WidgetSetRow] }
    struct CreditOut: Decodable { let landmarks: [String: Double]; let families: [String: Double] }
    @Test("the family fold and the one accumulator match")
    func family() throws {
        for c in try GoldenFixture<FamIn, String>.load("muscle-family").cases {
            #expect(MuscleFamily.of(LandmarkMuscle(rawValue: c.input.muscle)!).rawValue == c.expected, "\(c.name)")
        }
        for c in try GoldenFixture<CreditIn, CreditOut>.load("widget-family").cases {
            let got = MuscleCredit.weightedSets(
                exerciseNames: c.input.sets.filter { $0.setType != "ghost" }.map(\.exercise)
            )
            let named = Dictionary(got.map { ($0.key.rawValue, $0.value) }, uniquingKeysWith: { a, _ in a })
            #expect(named.count == c.expected.landmarks.count, "credit keys — \(c.name)")
            for (muscle, sets) in c.expected.landmarks {
                expectClose(named[muscle], sets, "\(muscle) — \(c.name)")
            }
            // …and the eight-family rollup the payload computes from exactly
            // these sixteen. One accumulator, two grains: the pair is the claim.
            let rolled = Dictionary(
                OnyxSnapshot.familyRollup(named.map {
                    OnyxSnapshot.MuscleVolume(muscle: $0.key, sets: $0.value, target: 0)
                }).map { ($0.family.rawValue, $0.sets) },
                uniquingKeysWith: { a, _ in a }
            )
            #expect(rolled.count == c.expected.families.count, "family keys — \(c.name)")
            for (family, sets) in c.expected.families {
                expectClose(rolled[family], sets, "\(family) — \(c.name)")
            }
        }
    }

    struct CadenceOut: Decodable { let schedule: [[Int]]; let failureMinutes: Int; let perHour: [Int]; let perDay: Double }
    @Test("the refresh cadence table agrees")
    func cadence() throws {
        let e = try GoldenFixture<JSONValue?, CadenceOut>.load("widget-cadence").cases[0].expected
        #expect(WidgetCadence.schedule.map { [$0.0, $0.1] } == e.schedule)
        #expect(WidgetCadence.failureMinutes == e.failureMinutes)
        #expect((0..<24).map(WidgetCadence.minutes(forHour:)) == e.perHour)
        expectClose(WidgetCadence.refreshesPerDay(), e.perDay, "perDay")
    }
}

// MARK: - Exercises

@Suite("Item #10 — exercise flags and the muscle dictionary")
struct ExerciseGoldenTests {
    struct In: Decodable { let name: String?; let stored: [String] }
    struct Out: Decodable {
        let bodyweight: Bool; let unloaded: Bool; let loadable: Bool; let unilateral: Bool; let timed: Bool; let icon: String
        let muscles: MoverTokens?; let groups: [String]?; let movers: MoverTokens; let moversStored: MoverTokens
    }

    @Test("every flag matches over the catalogue and free-typed names")
    func flags() throws {
        let fixture = try GoldenFixture<In, Out>.load("exercise-flags")
        #expect(fixture.cases.count > 120)
        for c in fixture.cases {
            let n = c.input.name
            #expect(BodyweightExercise.isBodyweight(n) == c.expected.bodyweight, "bodyweight — \(c.name)")
            #expect(BodyweightExercise.isUnloaded(n) == c.expected.unloaded, "unloaded — \(c.name)")
            #expect(BodyweightExercise.isLoadableBodyweight(n) == c.expected.loadable, "loadable — \(c.name)")
            #expect(UnilateralExercise.isUnilateral(n) == c.expected.unilateral, "unilateral — \(c.name)")
            #expect(TimedExercise.isTimed(n) == c.expected.timed, "timed — \(c.name)")
            #expect(ExerciseIcon.label(for: n) == c.expected.icon, "icon — \(c.name)")
            if let name = n {
                #expect(MuscleMap.movers(name) == c.expected.muscles, "muscles — \(c.name)")
                #expect(MuscleMap.muscleGroups(name) == c.expected.groups, "groups — \(c.name)")
                #expect(MuscleMap.resolveMovers(name) == c.expected.movers, "movers — \(c.name)")
                #expect(MuscleMap.resolveMovers(name, stored: c.input.stored) == c.expected.moversStored, "moversStored — \(c.name)")
            }
        }
    }

    struct TokenIn: Decodable { let token: String }
    @Test("the dictionary and the landmark token fold agree")
    func dictionary() throws {
        let dict = try GoldenFixture<JSONValue?, [MuscleMap.Entry]>.load("muscle-dict").cases[0].expected
        #expect(MuscleMap.dict == dict)
        for c in try GoldenFixture<TokenIn, String?>.load("landmark-token").cases {
            #expect(LandmarkMuscle.from(token: c.input.token)?.rawValue == c.expected, "\(c.name)")
        }
    }
}

// MARK: - Formatters

@Suite("Item #10 — small formatters and measures")
struct FormatGoldenTests {
    struct In: Decodable { let kind: String; let value: Double?; let text: String? }
    struct Out: Decodable { let text: String?; let long: String?; let text2: String?; let number: Double? }

    @Test("sleep, litres, durations, weight, volume and SpO2 match")
    func formatters() throws {
        for c in try GoldenFixture<In, Out>.load("utils-format").cases {
            let i = c.input, e = c.expected
            switch i.kind {
            case "sleep":
                #expect(Format.sleep(i.value) == e.text && Format.sleepLong(i.value) == e.long, "\(c.name)")
            case "ml":
                #expect(Format.mlToL(i.value) == e.text && Format.mlToL(i.value, digits: 2) == e.text2, "\(c.name)")
            case "duration":
                #expect(Format.parseDurationMin(i.text).map(Double.init) == e.number, "\(c.name)")
            case "weight":
                #expect(Format.validWeight(i.value) == e.number, "\(c.name)")
            case "volume":
                #expect(Format.volume(i.value) == e.text, "\(c.name)")
            case "spo2":
                expectClose(Format.normalizeSpO2(i.value), e.number, "\(c.name)")
            default:
                Issue.record("unknown kind \(i.kind)")
            }
        }
    }

    struct RelIn: Decodable { let now: String; let iso: String? }
    @Test("relative time under the pinned clock")
    func relative() throws {
        for c in try GoldenFixture<RelIn, String>.load("relative-time").cases {
            #expect(Format.relativeTime(c.input.iso, nowMs: ISODate.parseMillis(c.input.now)!) == c.expected, "\(c.name)")
        }
    }
}
