import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Reports — the weekly export, byte for byte, and everything it renders from.
// ─────────────────────────────────────────────────────────────────────────────

private struct Empty: Decodable {}

/// Drop every null (and every key holding one) so the TypeScript payload —
/// which writes `null` for a `x: number | null` field — compares structurally
/// with the Swift one, which omits an absent optional.
private func stripNulls(_ v: Any) -> Any {
    if let d = v as? [String: Any] {
        var out: [String: Any] = [:]
        for (k, x) in d where !(x is NSNull) { out[k] = stripNulls(x) }
        return out
    }
    if let a = v as? [Any] { return a.map(stripNulls) }
    return v
}

private func loadRaw(_ name: String) throws -> [[String: Any]] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else { throw GoldenError.missing(name) }
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    return root["cases"] as! [[String: Any]]
}

/// The first line on which two strings differ, for a readable failure.
private func firstDiff(_ a: String, _ b: String) -> String {
    let la = a.split(separator: "\n", omittingEmptySubsequences: false)
    let lb = b.split(separator: "\n", omittingEmptySubsequences: false)
    for (i, (x, y)) in zip(la, lb).enumerated() where x != y { return "line \(i + 1)\n  swift: \(x)\n  ts:    \(y)" }
    return la.count == lb.count ? "identical" : "length \(la.count) vs \(lb.count)"
}

@Suite("Week numbering")
struct WeekNumberGoldenTests {
    struct In: Decodable { let date: String; let startDay: Int }
    struct Out: Decodable { let weekStart: String; let weekNumber: Double; let label: String; let weekNumberForDate: Double }

    @Test("weekStartOf, weekNumberOf and weekLabelOf match")
    func matches() throws {
        let anchor = Week.anchor(planStartedOn: FounderTables.planStartISO)
        for c in try GoldenFixture<In, Out>.load("week-number").cases {
            let ws = Week.start(of: c.input.date, startDay: c.input.startDay)
            #expect(ws == c.expected.weekStart, "weekStartOf — \(c.name)")
            expectClose(Week.number(ofWeekStart: ws, anchor: anchor), c.expected.weekNumber, "weekNumberOf — \(c.name)")
            #expect(Week.label(ofWeekStart: ws, anchor: anchor, phases: FounderTables.phases) == c.expected.label, "weekLabelOf — \(c.name)")
            expectClose(Week.number(forDate: c.input.date, startDay: c.input.startDay, anchor: anchor), c.expected.weekNumberForDate, "weekNumberForDate — \(c.name)")
        }
    }
}

@Suite("Weekly export — the document")
struct WeeklyExportGoldenTests {
    struct Out: Decodable {
        let markdown: String; let summary: WeeklySummary; let totals: TrendTotals; let energy: EnergyBalance; let derived: DerivedWeek
    }

    @Test("every document matches byte for byte, and so do its aggregates")
    func documentsMatch() throws {
        let fixture = try GoldenFixture<WeeklyExportInput, Out>.load("weekly-export")
        #expect(fixture.cases.count >= 8)
        for c in fixture.cases {
            let md = WeeklyExport.build(c.input)
            #expect(md == c.expected.markdown, "markdown — \(c.name) — \(firstDiff(md, c.expected.markdown))")
            #expect(WeeklyExport.summary(c.input) == c.expected.summary, "weeklySummary — \(c.name)")
            #expect(WeeklyExport.trendTotals(days: c.input.days, sessions: c.input.sessions, cardio: c.input.cardio ?? []) == c.expected.totals, "trendTotals — \(c.name)")
            #expect(WeeklyExport.energyBalance(c.input.days) == c.expected.energy, "energyBalance — \(c.name)")
            #expect(Derived.week(c.input) == c.expected.derived, "derivedWeek — \(c.name)")
        }
    }

    // The machine-readable payload test went with `WeekJson`. The document was
    // never a second serialisation of itself: nothing read the JSON fence, and
    // the cross-language check it provided is already covered by `derivedWeek`,
    // which this suite compares field for field above.

    /// v5's SHAPE, which the byte comparison above cannot state.
    ///
    /// A snapshot test fails when the document changes and says nothing about
    /// whether the change was allowed. These are the rules of the schema
    /// itself: seven sections, in this order, nothing else between them, no
    /// figure this app formed an opinion with, and short enough to paste.
    @Test("every document is seven sections, in order, and nothing else")
    func grammarHolds() throws {
        let sections = [
            "## 1 · WEEK", "## 2 · WEEK AGGREGATES", "## 3 · BODY COMPOSITION",
            "## 4 · DAILY ROWS", "## 5 · SESSIONS", "## 6 · SETS BY MUSCLE", "## 7 · ANOMALIES",
        ]
        // `Score` and `Battery` are this app's OPINION of a week. The audit
        // reading this document is here to form its own, and a number it cannot
        // recompute from the rows beside it is one it has to either trust or
        // ignore. Banned outright rather than merely unused, so a later wave
        // cannot reintroduce one by helpfulness.
        let banned = try NSRegularExpression(pattern: #"\b(score|batter(y|ies))\b"#, options: .caseInsensitive)

        for c in try GoldenFixture<WeeklyExportInput, Out>.load("weekly-export").cases {
            let md = WeeklyExport.build(c.input)
            let lines = md.components(separatedBy: "\n")
            #expect(lines.filter { $0.hasPrefix("## ") } == sections, "sections — \(c.name)")
            // A `#` heading of any other depth is a section by another name.
            #expect(!lines.contains { $0.hasPrefix("# ") || $0.hasPrefix("### #") }, "stray heading — \(c.name)")
            let ns = md as NSString
            #expect(banned.firstMatch(in: md, range: NSRange(location: 0, length: ns.length)) == nil,
                    "a Score or a Battery reached the document — \(c.name)")
            // The budget is 400 for a normal week; a fixture is smaller still,
            // and the number is here so a wave that doubles the document has to
            // change the rule on purpose.
            #expect(lines.count < 400, "\(lines.count) lines — \(c.name)")
            // The one field of §1 that is required.
            #expect(md.contains("\(c.input.weekStart) → \(c.input.weekEnd)"), "date_range — \(c.name)")
            // And the §2 rows the schema marks required, which print even with
            // nothing behind them.
            for required in ["\nwater ", "\nsteps ", "\nvitals ", "\ntraining ", "\nPRs ", "\ncardio ", "\nfatigue "] {
                let row = required == "\nwater " ? "water " : required
                #expect(md.contains(row), "required row \(row.trimmingCharacters(in: .whitespacesAndNewlines)) — \(c.name)")
            }
            #expect(md.contains("nights_deep_ge_60"), "required sleep field — \(c.name)")
            #expect(md.contains("flagged_days"), "required vitals field — \(c.name)")
        }
    }

    /// §6's grade is ASYMMETRIC, and the rule is `VolumeZone`'s, not this
    /// document's. A muscle is UNDER only if even its total falls short; only
    /// DIRECT work can earn an OVER. Graded symmetrically, a muscle that
    /// reached its number purely by assisting other movements printed OVER, and
    /// the reader was told to cut work that was never being done.
    @Test("a muscle is graded UNDER on its total and OVER on its direct sets alone")
    func setsByMuscleGradesAsymmetrically() throws {
        // 12 direct against a target of 10 is 1.2 — inside the 1.3 ceiling.
        #expect(VolumeZone.of(weeklySets: 12, target: 10, directSets: 12) == .optimal)
        // 14 direct against 10 is 1.4, and only direct work can reach it.
        #expect(VolumeZone.of(weeklySets: 14, target: 10, directSets: 14) == .over)
        // The case the symmetric grade got wrong: a total over the ceiling that
        // is mostly assistance stays ON, because the direct work is 0.6×.
        #expect(VolumeZone.of(weeklySets: 14, target: 10, directSets: 6) == .optimal)
        // And a total short of the target is UNDER even where direct is high.
        #expect(VolumeZone.of(weeklySets: 7.5, target: 10, directSets: 7.5) == .building)

        let rich = try #require(try GoldenFixture<WeeklyExportInput, Out>
            .load("weekly-export").cases.first { $0.name.hasPrefix("the rich week — every section lit") })
        let md = WeeklyExport.build(rich.input)
        #expect(md.contains("| Quadriceps |   12.0 |      0.0 |  12.0 |   10.0 | ON        |"))
        #expect(md.contains("| Side delts |   14.0 |        — |  14.0 |   10.0 | OVER      |"))
        // A muscle the plan never named is neither over nor under it.
        #expect(md.contains("| Adductors  |      — |        — |   2.0 |   none | no target |"))
    }
}

@Suite("Weekly export — the small renderers")
struct ExportRenderersGoldenTests {
    struct ValuesIn: Decodable { let values: [Double?] }

    @Test("sparkline matches")
    func sparklineMatches() throws {
        for c in try GoldenFixture<ValuesIn, String>.load("sparkline").cases {
            #expect(WeeklyExport.sparkline(c.input.values) == c.expected, "sparkline — \(c.name)")
        }
    }

    struct TableIn: Decodable { let header: [String]; let body: [[String]]; let align: [WeeklyExport.Align] }

    @Test("markdownTable matches")
    func tableMatches() throws {
        for c in try GoldenFixture<TableIn, [String]>.load("markdown-table").cases {
            #expect(WeeklyExport.markdownTable(header: c.input.header, body: c.input.body, align: c.input.align) == c.expected, "markdownTable — \(c.name)")
        }
    }

    struct PaceIn: Decodable { let distanceM: Double?; let durationMin: Double? }
    struct PaceOut: Decodable { let pace: Double?; let formatted: String }

    @Test("pace matches")
    func paceMatches() throws {
        for c in try GoldenFixture<PaceIn, PaceOut>.load("pace").cases {
            let pace = CardioMetrics.paceMinPerKm(distanceM: c.input.distanceM, durationMin: c.input.durationMin)
            expectClose(pace, c.expected.pace, "paceMinPerKm — \(c.name)")
            #expect(CardioMetrics.formatPace(pace) == c.expected.formatted, "formatPace — \(c.name)")
        }
    }

    struct SetFmtIn: Decodable { let weightKg: Double?; let reps: Double?; let timed: Bool; let bare: Bool; let unit: String? }
    struct SetFmtOut: Decodable { let text: String; let unloaded: Bool }

    @Test("formatSet and isUnloadedSet match")
    func setFormatMatches() throws {
        for c in try GoldenFixture<SetFmtIn, SetFmtOut>.load("set-format").cases {
            #expect(SetFormat.format(weightKg: c.input.weightKg, reps: c.input.reps, timed: c.input.timed, unit: c.input.unit ?? "kg", bare: c.input.bare) == c.expected.text, "formatSet — \(c.name)")
            #expect(SetFormat.isUnloaded(c.input.weightKg) == c.expected.unloaded, "isUnloadedSet — \(c.name)")
        }
    }

    struct CardioFmtIn: Decodable { let durationSec: Double?; let distanceKm: Double?; let incline: Double?; let elevationM: Double? }

    @Test("formatCardioSet matches")
    func cardioSetFormatMatches() throws {
        for c in try GoldenFixture<CardioFmtIn, String?>.load("cardio-set-format").cases {
            #expect(
                SetFormat.cardio(
                    durationSec: c.input.durationSec, distanceKm: c.input.distanceKm,
                    incline: c.input.incline, elevationM: c.input.elevationM
                ) == c.expected,
                "formatCardioSet — \(c.name)"
            )
        }
        // Not in the vector: `JSON.stringify` writes NaN as null, so a fixture
        // cannot ask this question across the two languages.
        #expect(SetFormat.cardio(durationSec: .nan, distanceKm: .nan, incline: .nan, elevationM: .nan) == nil)
        #expect(SetFormat.cardio(durationSec: .infinity, distanceKm: 1, incline: nil, elevationM: .infinity) == "1 km")
    }

    struct StoredIn: Decodable { let stored: String? }
    struct SkipOut: Decodable { let reason: String; let isDefault: Bool }

    @Test("the weigh-in skip reason matches")
    func skipMatches() throws {
        for c in try GoldenFixture<StoredIn, SkipOut>.load("weigh-in-skip").cases {
            #expect(WeighIn.skipReason(c.input.stored) == c.expected.reason, "weighInSkipReason — \(c.name)")
            #expect(WeighIn.isDefaultSkipReason(c.input.stored) == c.expected.isDefault, "isDefaultSkipReason — \(c.name)")
        }
    }

    @Test("the nutrient targets table equals the TypeScript")
    func targetsMatch() throws {
        let e = try #require(try GoldenFixture<Empty, [NutrientTarget]>.load("nutrient-targets").cases.first).expected
        #expect(NutrientTargets.all == e)
    }

    struct ZoneIn: Decodable { let sets: Double; let target: Double; let direct: Double }

    @Test("volumeZone matches")
    func zoneMatches() throws {
        for c in try GoldenFixture<ZoneIn, VolumeZone>.load("volume-zone").cases {
            #expect(VolumeZone.of(weeklySets: c.input.sets, target: c.input.target, directSets: c.input.direct) == c.expected, "volumeZone — \(c.name)")
        }
    }

    struct NutrientIn: Decodable { let food: [String: Double]?; let stack: [String: Double]? }
    struct NutrientOut: Decodable { let line: String; let flagged: [String] }

    @Test("nutrientLine and flaggedNutrients match")
    func nutrientsMatch() throws {
        for c in try GoldenFixture<NutrientIn, NutrientOut>.load("nutrient-line").cases {
            #expect(WeeklyExport.nutrientLine(food: c.input.food, stack: c.input.stack) == c.expected.line, "nutrientLine — \(c.name)")
            let day = ExportDay(date: "2026-09-01", weekdayLabel: "Tue", isTrainingDay: false, nutrientsFood: c.input.food, nutrientsStack: c.input.stack, nutritionEstimated: false)
            #expect(WeeklyExport.flaggedNutrients([day]) == c.expected.flagged, "flaggedNutrients — \(c.name)")
        }
    }

    struct DetailIn: Decodable { let sets: [ExportSet]; let exerciseName: String? }

    @Test("setDetail matches, line for line")
    func detailMatches() throws {
        for c in try GoldenFixture<DetailIn, [String]>.load("set-detail").cases {
            #expect(WeeklyExport.setDetail(c.input.sets, exerciseName: c.input.exerciseName) == c.expected, "setDetail — \(c.name)")
        }
    }

    struct ProtocolIn: Decodable { let `protocol`: [ExportSupplement] }

    @Test("consolidateSupplements matches")
    func supplementsMatch() throws {
        for c in try GoldenFixture<ProtocolIn, [String]>.load("supplements-consolidate").cases {
            #expect(WeeklyExport.consolidateSupplements(c.input.`protocol`) == c.expected, "consolidateSupplements — \(c.name)")
        }
    }

    /* `trendLedger` and its `trend-ledger` vectors retired in v4.1 with the
       `### Week over week` block they proved. The renderer no longer has the
       function, so there is nothing left to hold to a vector. `LedgerWeek` and
       `WeeklyExportInput.ledger` remain on the payload — `Derived` reads them
       for the energy balance — and `derivedMatches` below still covers that. */

    struct NotesOut: Decodable {
        let training: [String]; let rest: [String]; let slots: [String]
        let supplements: [WeeklyExport.SupplementRow]
    }

    /// The two fatigue triples, and the deduped stack both renderers read. The
    /// four standing closing notes retired with export v2.
    @Test("the standing strings match")
    func notesMatch() throws {
        let e = try #require(try GoldenFixture<Empty, NotesOut>.load("report-notes").cases.first).expected
        #expect(WeeklyExport.fatigueLabels(isTrainingDay: true) == e.training)
        #expect(WeeklyExport.fatigueLabels(isTrainingDay: false) == e.rest)
        #expect(WeeklyExport.fatigueSlotLabels == e.slots)
        // The vector's stack is the rich week's own, so it is read from there
        // rather than restated — one payload, one source of truth.
        let rich = try #require(try GoldenFixture<WeeklyExportInput, WeeklyExportGoldenTests.Out>
            .load("weekly-export").cases.first { $0.name.hasPrefix("the rich week — every section lit") })
        #expect(WeeklyExport.supplementRows(rich.input.supplementProtocol ?? []) == e.supplements)
    }
}
