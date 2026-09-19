import Foundation
import Testing
@testable import OnyxCore

private func lbOf(_ kg: Double) -> Double? { jsRound(kg * 2.20462 * 100) / 100 }
private func lbOrNil(_ kg: Double?) -> Double? { kg.map { jsRound($0 * 2.20462 * 100) / 100 } }
private func identity(_ kg: Double) -> Double? { kg }
private func identityOrNil(_ kg: Double?) -> Double? { kg }

@Suite("Item #11 — the deck rows")
struct DeckGoldenTests {
    struct In: Decodable { let sets: [DraftSet] }
    struct Out: Decodable { let groups: [SetGroup]; let statusLabels: [String: String]?; let valueLabels: [String: String]? }

    @Test("groupSets and the vocabularies match")
    func groups() throws {
        for c in try GoldenFixture<In, Out>.load("deck-groups").cases {
            #expect(Deck.groupSets(c.input.sets) == c.expected.groups, "groups — \(c.name)")
            if let labels = c.expected.statusLabels { #expect(Deck.statusLabels == labels) }
            if let labels = c.expected.valueLabels {
                for (mode, label) in labels { #expect(Deck.valueLabel(mode: mode) == label, "value label \(mode)") }
            }
        }
    }

    struct LadderIn: Decodable { let kind: String; let a: Double; let b: Double }
    struct LadderOut: Decodable { let number: Double?; let text: String?; let plate: Double; let fine: Double }
    @Test("the load ladder and the small formatters match")
    func ladder() throws {
        for c in try GoldenFixture<LadderIn, LadderOut>.load("deck-ladder").cases {
            #expect(Deck.plateStep == c.expected.plate && Deck.fineStep == c.expected.fine)
            switch c.input.kind {
            case "load":
                expectClose(Deck.nudgeLoad(c.input.a, c.input.b), c.expected.number, "nudgeLoad — \(c.name)")
                #expect(Deck.fmtKg(c.input.a) == c.expected.text, "fmtKg — \(c.name)")
            case "reps":
                expectClose(Deck.nudgeReps(c.input.a, c.input.b), c.expected.number, "nudgeReps — \(c.name)")
            case "trim":
                #expect(Deck.trimNum(c.input.a, digits: Int(c.input.b)) == c.expected.text, "trimNum — \(c.name)")
            default:
                Issue.record("unknown kind \(c.input.kind)")
            }
        }
    }
}

@Suite("Item #11 — muscle distribution and the progression scope")
struct MuscleDistributionGoldenTests {
    struct In: Decodable { let draft: SessionDraft? }
    struct Out: Decodable { let weighted: [String: Double]; let physical: Int }

    @Test("weighted and physical set counts match")
    func distribution() throws {
        for c in try GoldenFixture<In, Out>.load("muscle-distribution").cases {
            let w = MuscleDistribution.weightedSets(c.input.draft)
            var byName: [String: Double] = [:]
            for (m, v) in w { byName[m.rawValue] = v }
            #expect(Set(byName.keys) == Set(c.expected.weighted.keys), "weighted muscles — \(c.name)")
            for (k, e) in c.expected.weighted { expectClose(byName[k], e, "weighted \(k) — \(c.name)") }
            #expect(MuscleDistribution.physicalSets(c.input.draft) == c.expected.physical, "physical — \(c.name)")
        }
    }

    struct Alert: Decodable { let id: String; let dayKey: String? }
    struct ScopeIn: Decodable { let alerts: [Alert]; let dayKey: String?; let kind: String }
    @Test("scopeToDay matches")
    func scope() throws {
        for c in try GoldenFixture<ScopeIn, [String]>.load("scope-to-day").cases {
            #expect(ProgressionScope.toDay(c.input.alerts, dayKey: c.input.dayKey, key: \.dayKey).map(\.id) == c.expected, "\(c.name)")
        }
    }
}

@Suite("Item #11 — dashboard tiles")
struct TilesGoldenTests {
    struct In: Decodable {
        let kind: String; let series: [Double?]; let today: Double?; let goal: Double?; let have: Double?; let target: Double?
        let risk: String?; let weeks: Int?; let dateISO: String?; let todayISO: String?; let text: String?; let mins: Double?
    }
    struct Out: Decodable { let number: Double?; let numbers: [Double]?; let text: String? }

    @Test("the stats, marks, risks, windows and labels match")
    func stats() throws {
        for c in try GoldenFixture<In, Out>.load("tiles-stats").cases {
            let i = c.input, e = c.expected
            switch i.kind {
            case "baseline": expectClose(Tiles.vsBaseline(i.series, today: i.today), e.number, "\(c.name)")
            case "mean": expectClose(Tiles.mean(i.series), e.number, "\(c.name)")
            case "steps":
                let m = Tiles.stepMarks(goal: i.goal!)
                #expect(m.count == e.numbers!.count, "\(c.name)")
                for (a, x) in zip(m, e.numbers!) { expectClose(a, x, "\(c.name)") }
            case "risk": expectClose(Tiles.nutrientRisk(have: i.have, target: i.target!, ceiling: i.risk == "ceiling"), e.number, "\(c.name)")
            case "consistency": #expect(Tiles.consistencyWindow(weeks: i.weeks!, todayISO: i.todayISO!).map(Double.init) == e.number, "\(c.name)")
            case "daysAgo": #expect(Tiles.daysAgo(i.dateISO!, today: i.todayISO!) == e.text, "\(c.name)")
            case "parseMin": expectClose(Tiles.parseMin(i.text!), e.number, "\(c.name)")
            case "due": #expect(Tiles.dueLabel(i.mins!) == e.text, "\(c.name)")
            default: Issue.record("unknown kind \(i.kind)")
            }
        }
    }

    struct LedgerIn: Decodable { let todayISO: String; let floor: Int; let max: Int }
    @Test("the ledger window matches across the phase calendar")
    func ledger() throws {
        for c in try GoldenFixture<LedgerIn, LedgerWindow>.load("ledger-window").cases {
            #expect(Tiles.ledgerFloorDays == c.input.floor && Tiles.ledgerMaxDays == c.input.max)
            #expect(Tiles.ledgerWindow(c.input.todayISO, phases: FounderTables.phases) == c.expected, "\(c.name)")
        }
    }

    struct StackIn: Decodable { let slots: [StackDose]; let skipped: [String]; let minutes: Double }
    @Test("the stack schedule matches")
    func stack() throws {
        for c in try GoldenFixture<StackIn, StackSchedule>.load("stack-schedule").cases {
            #expect(Tiles.stackSchedule(c.input.slots, skipped: Set(c.input.skipped), minutes: c.input.minutes) == c.expected, "\(c.name)")
        }
    }
}

@Suite("Item #11 — the session report")
struct SessionDetailGoldenTests {
    struct RowsIn: Decodable { let sets: [DetailSet]; let prev: [HistorySet] }
    struct RowsOut: Decodable { let rows: [DetailRow]; let withPrev: [RowWithPrev]; let glyphs: [String?]? }

    @Test("ledger rows, previous alignment and glyphs match")
    func rows() throws {
        for c in try GoldenFixture<RowsIn, RowsOut>.load("detail-rows").cases {
            let rows = SessionDetail.toRows(c.input.sets)
            #expect(rows == c.expected.rows, "rows — \(c.name)")
            #expect(SessionDetail.rowsWithPrev(rows, prev: c.input.prev) == c.expected.withPrev, "withPrev — \(c.name)")
            if let g = c.expected.glyphs {
                let deltas: [Int??] = [nil, .some(nil), 1, 0, -1]
                #expect(deltas.map(SessionDetail.deltaGlyph) == g, "glyphs")
            }
        }
    }

    struct CueT: Decodable { let progression: CueProgression }
    struct CueIn: Decodable { let t: CueT?; let timed: Bool; let unit: String; let lb: Bool; let loadStep: Double }
    @Test("the progression cue matches")
    func cue() throws {
        for c in try GoldenFixture<CueIn, ProgressionCue?>.load("progression-cue").cases {
            #expect(Ceilings.loadStepKg == c.input.loadStep)
            let toDisplay: (Double) -> Double?; if c.input.lb { toDisplay = lbOf } else { toDisplay = identity }
            let cue = SessionDetail.progressionCue(c.input.t?.progression, timed: c.input.timed, unit: c.input.unit, toDisplay: toDisplay)
            #expect(cue == c.expected, "\(c.name)")
        }
    }

    struct HlIn: Decodable { let exercises: [DetailExercise]; let unit: String; let lb: Bool }
    struct HlOut: Decodable { let stats: [ExerciseStats]; let strongest: String?; let highlights: [Highlight] }
    @Test("the exercise strip and the highlights match")
    func highlights() throws {
        for c in try GoldenFixture<HlIn, HlOut>.load("session-highlights").cases {
            let stats = c.input.exercises.map(SessionDetail.exerciseStats)
            #expect(stats.count == c.expected.stats.count)
            for (a, e) in zip(stats, c.expected.stats) {
                #expect(a.totalReps == e.totalReps && a.topKg == e.topKg && a.topReps == e.topReps, "stats — \(c.name)")
                expectClose(a.avgRpe, e.avgRpe, "avgRpe — \(c.name)")
            }
            #expect(SessionDetail.strongest(c.input.exercises)?.name == c.expected.strongest, "strongest — \(c.name)")
            let toDisplay: (Double) -> Double?; if c.input.lb { toDisplay = lbOf } else { toDisplay = identity }
            let hl = SessionDetail.highlights(c.input.exercises, toDisplay: toDisplay, unit: c.input.unit)
            #expect(hl == c.expected.highlights, "highlights — \(c.name)")
        }
    }

    struct PctIn: Decodable { let metric: IntelMetric?; let i: Int }
    @Test("the metric delta matches")
    func pct() throws {
        for c in try GoldenFixture<PctIn, MetricPct?>.load("metric-pct").cases {
            #expect(SessionDetail.pct(of: c.input.metric) == c.expected, "\(c.name)")
        }
    }
}

@Suite("Item #11 — chart splits and body readings")
struct ReadingsGoldenTests {
    struct SplitIn: Decodable { let dateISO: String; let split: String; let era: String; let dayKey: String? }
    struct Tables: Decodable { let forEra: [String: [String]]; let dayKey: [String: String]; let labels: [String: String] }

    @Test("the volume chart buckets match")
    func splits() throws {
        let cases = try GoldenFixture<SplitIn, String>.load("volume-split").cases
        let tables = try JSONDecoder().decode(Tables.self, from: cases[0].expected.data(using: .utf8)!)
        for (era, splits) in tables.forEra { #expect(VolumeSplit.splits(forEra: era) == splits, "splits \(era)") }
        #expect(VolumeSplit.dayKeySplit == tables.dayKey)
        for (s, l) in tables.labels { #expect(VolumeSplit.label(s) == l, "label \(s)") }
        for c in cases.dropFirst() {
            #expect(VolumeSplit.resolve(dateISO: c.input.dateISO, split: c.input.split, era: c.input.era, dayKey: c.input.dayKey) == c.expected, "\(c.name)")
        }
    }

    struct MergeIn: Decodable { let trend: [BodyTrendRow]; let detail: [BodyDetailRow]; let lb: Bool }
    @Test("the body-composition merge matches")
    func merge() throws {
        for c in try GoldenFixture<MergeIn, [BodyCompositionPoint]>.load("body-merge").cases {
            let toDisplay: (Double?) -> Double?; if c.input.lb { toDisplay = lbOrNil } else { toDisplay = identityOrNil }
            let m = BodyReadings.merge(trend: c.input.trend, detail: c.input.detail, toDisplay: toDisplay)
            #expect(m.count == c.expected.count, "count — \(c.name)")
            for (a, e) in zip(m, c.expected) {
                #expect(a.date == e.date, "date — \(c.name)")
                expectClose(a.weight, e.weight, "weight \(e.date) — \(c.name)")
                expectClose(a.muscleMass, e.muscleMass, "muscleMass \(e.date) — \(c.name)")
                expectClose(a.fatFreeMass, e.fatFreeMass, "fatFreeMass \(e.date) — \(c.name)")
                expectClose(a.fatMass, e.fatMass, "fatMass \(e.date) — \(c.name)")
                expectClose(a.fatPct, e.fatPct, "fatPct \(e.date) — \(c.name)")
                expectClose(a.water, e.water, "water \(e.date) — \(c.name)")
                expectClose(a.musclePct, e.musclePct, "musclePct \(e.date) — \(c.name)")
                expectClose(a.visceral, e.visceral, "visceral \(e.date) — \(c.name)")
            }
        }
    }

    struct ScaleIn: Decodable { let log: [String: Double?]?; let i: Int; let keys: [String] }
    @Test("the scale-metrics test matches")
    func scale() throws {
        for c in try GoldenFixture<ScaleIn, Bool>.load("scale-metrics").cases {
            #expect(BodyReadings.scaleMetricKeys == c.input.keys)
            #expect(BodyReadings.hasScaleMetrics(c.input.log) == c.expected, "\(c.name)")
        }
    }
}
