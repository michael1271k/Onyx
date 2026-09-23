import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The day page's small pure modules — step marks, the fatigue scale, the
// supplement stack and the sleep-debt bank — replayed from `npm run golden`.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Step marks — the waypoints on the steps track")
struct StepMarksGoldenTests {
    struct In: Decodable { let goal: Int }

    @Test("stepMarks matches on every goal, including the degenerate ones")
    func marksMatch() throws {
        let fixture = try GoldenFixture<In, [Int]>.load("step-marks")
        #expect(fixture.cases.count > 20)
        for c in fixture.cases {
            #expect(StepMarks.marks(goal: c.input.goal) == c.expected, "stepMarks — \(c.name)")
        }
    }

    @Test("stepMarks always ends with the goal and is strictly increasing")
    func endsWithGoalAndIncreases() {
        for goal in stride(from: -1000, through: 30000, by: 1) {
            let marks = StepMarks.marks(goal: goal)
            #expect(marks.last == goal, "goal \(goal): the goal must be the last mark")
            #expect(zip(marks, marks.dropFirst()).allSatisfy { $0 < $1 }, "goal \(goal): \(marks) is not strictly increasing")
            #expect(marks.count <= 5)
        }
    }
}

@Suite("Fatigue — the slots, the legacy fold and the readings")
struct FatigueGoldenTests {
    struct In: Decodable { let fn: String; let raw: String?; let isTraining: Bool?; let rows: [FatigueRow]?; let day: FatigueDay?; let value: Int? }
    struct Tables: Decodable {
        let slots: [FatigueSlot]; let rest: [FatigueSlot]; let training: [FatigueSlot]; let labels: [String: String]
        let levels: [FatigueLevel]; let forTraining: [FatigueSlot]; let forRest: [FatigueSlot]
    }
    struct Out: Decodable {
        let slot: FatigueSlot?; let day: FatigueDay?; let delta: Int?; let latest: FatigueReading?; let level: FatigueLevel?; let tables: Tables?
    }

    @Test("every fatigue function matches — both day types, both fold orders")
    func fatigueMatches() throws {
        let fixture = try GoldenFixture<In, Out>.load("fatigue-slots")
        #expect(fixture.cases.count > 90)
        for c in fixture.cases {
            let i = c.input, e = c.expected
            switch i.fn {
            case "tables":
                let t = try #require(e.tables)
                #expect(Fatigue.slots == t.slots)
                #expect(Fatigue.restSlots == t.rest)
                #expect(Fatigue.trainingSlots == t.training)
                #expect(Fatigue.slotsForDay(isTraining: true) == t.forTraining)
                #expect(Fatigue.slotsForDay(isTraining: false) == t.forRest)
                #expect(Dictionary(uniqueKeysWithValues: FatigueSlot.allCases.map { ($0.rawValue, $0.label) }) == t.labels)
                #expect(Fatigue.levels == t.levels)
            case "normalizeSlot":
                #expect(Fatigue.normalizeSlot(i.raw!, isTraining: i.isTraining!) == e.slot, "\(c.name)")
            case "fold":
                #expect(Fatigue.foldRows(i.rows!, isTraining: i.isTraining!) == e.day, "\(c.name)")
            case "delta":
                #expect(Fatigue.delta(i.day!) == e.delta, "\(c.name)")
            case "latest":
                #expect(Fatigue.latest(i.day!) == e.latest, "\(c.name)")
            case "level":
                #expect(Fatigue.level(i.value) == e.level, "\(c.name)")
            default:
                Issue.record("unknown fn \(i.fn)")
            }
        }
    }

    @Test("both day types read forwards through the vocabulary — the property `latest` depends on")
    func vocabularyIsOrderedForBothDayTypes() {
        let index = Dictionary(uniqueKeysWithValues: Fatigue.slots.enumerated().map { ($1, $0) })
        for slots in [Fatigue.trainingSlots, Fatigue.restSlots] {
            let positions = slots.map { index[$0]! }
            #expect(positions == positions.sorted())
        }
    }
}

@Suite("Supplements — the seed, the DB grouping and the clock rules")
struct SupplementGoldenTests {
    struct In: Decodable {
        let fn: String; let isTraining: Bool?; let weekday: Int?; let dbSlots: [SupplementSlot]?; let hhmm: String?; let nowMinutes: Int?
        let customs: [CustomSupplement]?; let custom: CustomSupplement?
    }
    struct Out: Decodable { let slots: [SupplementSlot]?; let count: Int?; let passed: Bool?; let text: String? }

    @Test("every supplement function matches — every weekday, both day types, every fallback")
    func supplementsMatch() throws {
        let fixture = try GoldenFixture<In, Out>.load("supplement-stack")
        #expect(fixture.cases.count > 60)
        for c in fixture.cases {
            let i = c.input, e = c.expected
            switch i.fn {
            case "tables", "protocolForDate":
                // The protocol seed is `supplements` rows since W2; the package
                // holds no copy to compare or to resolve a weekday against.
                continue
            case "stackForDate", "count" where i.dbSlots!.isEmpty:
                // With no rows the old answer was the seed; an empty table is
                // an empty stack now.
                continue
            case "stackForDate":
                #expect(Supplements.stackForDate(i.dbSlots!, isTraining: i.isTraining!, weekday: i.weekday!) == e.slots, "\(c.name)")
            case "count":
                #expect(Supplements.count(isTraining: i.isTraining!, dbSlots: i.dbSlots!) == e.count, "\(c.name)")
            case "slotTimePassed":
                #expect(Supplements.slotTimePassed(i.hhmm!, nowMinutes: i.nowMinutes!) == e.passed, "\(c.name)")
            case "customSlotsForDate":
                #expect(Supplements.customSlotsForDate(i.customs!, on: "2026-01-01", weekday: i.weekday!, isTraining: i.isTraining!) == e.slots, "\(c.name)")
            case "customDoseFor":
                #expect(Supplements.customDose(i.custom!, isTraining: i.isTraining!) == e.text, "\(c.name)")
            case "supplementKeyOf":
                #expect(Supplements.key(of: i.custom!) == e.text, "\(c.name)")
            default:
                Issue.record("unknown fn \(i.fn)")
            }
        }
    }
}

@Suite("Sleep debt — the bank")
struct SleepDebtGoldenTests {
    struct In: Decodable { let nights: [SleepDebtNight]; let goalHours: Double; let weekAgo: String }

    @Test("computeSleepDebt matches with the clock pinned")
    func debtMatches() throws {
        let fixture = try GoldenFixture<In, SleepDebt>.load("sleep-debt")
        #expect(fixture.cases.count > 15)
        for c in fixture.cases {
            let d = SleepDebt.compute(nights: c.input.nights, goalHours: c.input.goalHours, weekAgo: c.input.weekAgo)
            expectClose(d.debtHours, c.expected.debtHours, "debtHours — \(c.name)")
            #expect(d.nights == c.expected.nights, "nights — \(c.name)")
            expectClose(d.worstNightMin, c.expected.worstNightMin, "worstNightMin — \(c.name)")
            expectClose(d.goalHours, c.expected.goalHours, "goalHours — \(c.name)")
        }
        #expect(SleepDebt.windowDays == 14)
        #expect(SleepDebt.weeklyDecay == 0.75)
    }

    @Test("debt is never negative: surplus repays but never banks credit")
    func neverNegative() {
        for mins in stride(from: 0.0, through: 900, by: 30) {
            let d = SleepDebt.compute(nights: [SleepDebtNight(date: "2026-09-01", sleepMinutes: mins)], goalHours: 8, weekAgo: "2026-08-27")
            #expect(d.debtHours >= 0)
        }
    }
}
